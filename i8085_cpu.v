// i8085_cpu.v - Self-contained 8085 CPU with internal fetch FSM
// Combines CPU state, fetch FSM, and instruction decode
// Provides clean bus master interface to external memory controller
//
// Timing Optimizations (iCE40 UP5K, Yosys + nextpnr-ice40)
// ─────────────────────────────────────────────────────────
//
// 1. S_DECODE_OP Pipeline Stage
//    Problem:  Opcode arrives from SPRAM in S_WAIT_OP, and the decode
//              functions (inst_len, needs_hl_read, etc.) feed straight
//              into the FSM next-state mux — all in one cycle.
//    Fix:      Insert S_DECODE_OP between S_WAIT_OP and the fetch/exec
//              branch.  S_WAIT_OP latches fetched_op into a register;
//              S_DECODE_OP reads the registered value through the
//              combinational decode outputs, which are now stable.
//    Cost:     +1 cycle per instruction (fetch is 3 cycles instead of 2).
//    Result:   Moves decode logic off the critical path.
//
// 2. Registered Write Address/Data  (default; opt-out: ORIGINAL_EXECUTE_MEM_WR)
//    Problem:  In S_EXECUTE the XLS core produces mem_addr and mem_data
//              combinationally.  The old design drove bus_addr from those
//              signals in the same cycle, creating a deep path:
//              XLS core internals → bus_addr → memory controller address
//              decode → SPRAM write-enable.
//    Fix:      Register core_mem_addr and core_mem_data into r_bus_addr
//              and r_mem_data during S_EXECUTE.  The actual bus_wr
//              assertion happens one cycle later in S_WRITE_MEM.
//    Cost:     +1 cycle for memory-write instructions only.
//    Result:   ~200 fewer LUTs, ~50% higher Fmax (e.g. 17 → 25 MHz).
//              Compile with -DORIGINAL_EXECUTE_MEM_WR to revert.
//
// 3. Pre-computed PC+1 / PC+2
//    Problem:  In S_DECODE_OP, the mux feeding r_bus_addr includes
//              r_pc + 16'd1 for immediate fetches.  The 16-bit carry
//              chain sits after the opcode decode mux, adding ~5ns.
//    Fix:      Maintain r_pc_plus1 and r_pc_plus2 registers, computed
//              from the registered r_pc during S_FETCH_OP.  The adder
//              input is a clean register output (fast), and the result
//              has 2 cycles to settle before S_DECODE_OP reads it.
//              NOT computed from next_pc in S_EXECUTE (that would add
//              carry chain after deep XLS core combinational output).
//    Cost:     +32 FF, ~32 LUT4 (two 16-bit adders).
//    Result:   Removes carry chain from S_DECODE_OP critical path.

module i8085_cpu (
    input  wire        clk,
    input  wire        reset_n,

    // Memory Bus (master interface)
    output wire [15:0] bus_addr,
    output wire [7:0]  bus_data_out,
    output reg         bus_rd,
    output wire        bus_wr,
    input  wire [7:0]  bus_data_in,
    input  wire        bus_ready,

    // Stack Write Bus (separate for dual-port writes)
    output wire [15:0] stack_wr_addr,
    output wire [7:0]  stack_wr_data_lo,
    output wire [7:0]  stack_wr_data_hi,
    output wire        stack_wr,

    // I/O Bus
    output wire [7:0]  io_port,
    output wire [7:0]  io_data_out,
    input  wire [7:0]  io_data_in,
    output wire        io_rd,
    output wire        io_wr,

    // Bank registers (directly exposed for memory controller)
    output reg  [7:0]  rom_bank,
    output reg  [2:0]  ram_bank,

    // Interrupts
    input  wire        int_req,        // Interrupt request pending
    input  wire [15:0] int_vector,     // Vector address
    input  wire        int_is_trap,    // True for TRAP (NMI)
    output reg         int_ack,        // Acknowledge pulse

    // Hardware interrupt inputs (directly wired to core for RIM)
    input  wire        sid,
    input  wire        rst55_level,
    input  wire        rst65_level,

    // Status outputs
    output wire [15:0] pc,
    output wire [15:0] sp,
    output wire [7:0]  reg_a,
    output wire [7:0]  reg_b,
    output wire [7:0]  reg_c,
    output wire [7:0]  reg_d,
    output wire [7:0]  reg_e,
    output wire [7:0]  reg_h,
    output wire [7:0]  reg_l,
    output wire        halted,
    output wire        inte,
    output wire        flag_z,
    output wire        flag_c,

    // Interrupt mask outputs (for external interrupt controller)
    output wire        mask_55,
    output wire        mask_65,
    output wire        mask_75,
    output wire        rst75_pending,
    output wire        sod
);

    // I/O Ports for bank control
    localparam [7:0] PORT_ROM_BANK = 8'hF0;
    localparam [7:0] PORT_RAM_BANK = 8'hF1;

    // =========================================================================
    // FSM States
    // =========================================================================

    localparam S_FETCH_OP    = 4'd0;
    localparam S_WAIT_OP     = 4'd1;
    localparam S_DECODE_OP   = 4'd2;   // Decode pipeline stage - breaks critical path
    localparam S_FETCH_IMM1  = 4'd3;
    localparam S_WAIT_IMM1   = 4'd4;
    localparam S_FETCH_IMM2  = 4'd5;
    localparam S_WAIT_IMM2   = 4'd6;
    localparam S_READ_MEM    = 4'd7;
    localparam S_WAIT_MEM    = 4'd8;
    localparam S_READ_STK_LO = 4'd9;
    localparam S_WAIT_STK_LO = 4'd10;
    localparam S_READ_STK_HI = 4'd11;
    localparam S_WAIT_STK_HI = 4'd12;
    localparam S_EXECUTE     = 4'd13;
    localparam S_WRITE_MEM   = 4'd14;
    localparam S_HALTED      = 4'd15;

    reg [3:0] fsm_state;

    // =========================================================================
    // CPU State Registers
    // =========================================================================

    reg [7:0]  r_b, r_c, r_d, r_e, r_h, r_l, r_a;
    reg [15:0] r_sp, r_pc;
    reg [15:0] r_pc_plus1, r_pc_plus2;  // Pre-computed (timing opt #3)
    reg        f_sign, f_zero, f_aux, f_parity, f_carry;
    reg        r_halted, r_inte;
    reg        r_mask_55, r_mask_65, r_mask_75;
    reg        r_rst75_pending;
    reg        r_sod_latch;

    // Derived register pairs
    wire [15:0] hl = {r_h, r_l};
    wire [15:0] bc = {r_b, r_c};
    wire [15:0] de = {r_d, r_e};

    // =========================================================================
    // Instruction Fetch Registers
    // =========================================================================

    reg [7:0]  fetched_op;
    reg [7:0]  fetched_imm1;
    reg [7:0]  fetched_imm2;
    reg [7:0]  mem_rd_buf;
    reg [7:0]  stk_lo_buf, stk_hi_buf;
    reg [7:0]  io_rd_buf;
    reg        execute_pulse;
    reg        shld_second_wr;

    // =========================================================================
    // Instruction Decode
    // =========================================================================

    // Always decode from registered opcode - breaks critical path
    wire [7:0] decode_opcode = fetched_op;

    wire [1:0] dec_inst_len;
    wire       dec_needs_hl_read;
    wire       dec_needs_bc_read;
    wire       dec_needs_de_read;
    wire       dec_needs_direct_read;
    wire       dec_needs_stack_read;
    wire       dec_needs_io_read;

    i8085_decode decoder (
        .opcode(decode_opcode),
        .inst_len(dec_inst_len),
        .needs_hl_read(dec_needs_hl_read),
        .needs_bc_read(dec_needs_bc_read),
        .needs_de_read(dec_needs_de_read),
        .needs_direct_read(dec_needs_direct_read),
        .needs_stack_read(dec_needs_stack_read),
        .needs_io_read(dec_needs_io_read)
    );

    // =========================================================================
    // XLS Core Instance
    // =========================================================================

    // Pack state for core input (MSB-first to match XLS struct order)
    wire [99:0] core_state = {
        r_b, r_c, r_d, r_e, r_h, r_l, r_a,
        r_sp,
        r_pc,
        f_sign, f_zero, f_aux, f_parity, f_carry,
        r_halted,
        r_inte,
        r_mask_55, r_mask_65, r_mask_75,
        r_rst75_pending,
        r_sod_latch
    };

    wire [175:0] core_out;

    __i8085_core__execute_parity_opt core (
        .state(core_state),
        .opcode(fetched_op),
        .byte2(fetched_imm1),
        .byte3(fetched_imm2),
        .mem_read_data(mem_rd_buf),
        .stack_read_lo(stk_lo_buf),
        .stack_read_hi(stk_hi_buf),
        .io_read_data(io_rd_buf),
        .sid(sid),
        .rst55_level(rst55_level),
        .rst65_level(rst65_level),
        .out(core_out)
    );

    // Unpack core output - State (100 bits at MSB)
    wire [7:0]  next_b      = core_out[175:168];
    wire [7:0]  next_c      = core_out[167:160];
    wire [7:0]  next_d      = core_out[159:152];
    wire [7:0]  next_e      = core_out[151:144];
    wire [7:0]  next_h      = core_out[143:136];
    wire [7:0]  next_l      = core_out[135:128];
    wire [7:0]  next_a      = core_out[127:120];
    wire [15:0] next_sp     = core_out[119:104];
    wire [15:0] next_pc     = core_out[103:88];
    wire        next_f_sign = core_out[87];
    wire        next_f_zero = core_out[86];
    wire        next_f_aux  = core_out[85];
    wire        next_f_par  = core_out[84];
    wire        next_f_cry  = core_out[83];
    wire        next_halted = core_out[82];
    wire        next_inte   = core_out[81];
    wire        next_mask_55 = core_out[80];
    wire        next_mask_65 = core_out[79];
    wire        next_mask_75 = core_out[78];
    wire        next_rst75_pending = core_out[77];
    wire        next_sod_latch = core_out[76];

    // Unpack core output - MemBusOut (76 bits at LSB)
    wire [15:0] core_mem_addr     = core_out[75:60];
    wire [7:0]  core_mem_data     = core_out[59:52];
    wire        core_mem_wr       = core_out[51];
    wire [15:0] core_stack_addr   = core_out[50:35];
    wire [7:0]  core_stack_lo     = core_out[34:27];
    wire [7:0]  core_stack_hi     = core_out[26:19];
    wire        core_stack_wr     = core_out[18];
    wire [7:0]  core_io_port      = core_out[17:10];
    wire [7:0]  core_io_data      = core_out[9:2];
    wire        core_io_rd        = core_out[1];
    wire        core_io_wr        = core_out[0];

    // =========================================================================
    // Bus Interface Assignments
    // =========================================================================

    // Registered fetch address (set in FSM)
    reg [15:0] r_bus_addr;

`ifdef ORIGINAL_EXECUTE_MEM_WR
    // ORIGINAL: Combinational path from core outputs during S_EXECUTE writes
    // This creates a long critical path: XLS core → bus_addr
    // Use this only for debugging/comparison
    wire doing_mem_write = (fsm_state == S_EXECUTE) && core_mem_wr;
    wire doing_stk_write = (fsm_state == S_EXECUTE) && core_stack_wr;
    assign bus_addr = doing_mem_write ? core_mem_addr :
                      doing_stk_write ? core_stack_addr :
                      r_bus_addr;
    assign bus_wr = doing_mem_write;
    assign bus_data_out = core_mem_data;
`else
    // DEFAULT: Registered write path - breaks critical path from XLS core
    // Write address/data registered in S_EXECUTE, actual write in S_WRITE_MEM
    // Result: ~200 fewer LUTs, ~50% higher Fmax
    reg r_pending_mem_wr;
    reg [7:0] r_mem_data;

    assign bus_addr = r_bus_addr;
    assign bus_wr = (fsm_state == S_WRITE_MEM) && r_pending_mem_wr;
    assign bus_data_out = r_mem_data;
`endif

    assign stack_wr_addr = core_stack_addr;
    assign stack_wr_data_lo = core_stack_lo;
    assign stack_wr_data_hi = core_stack_hi;
    assign stack_wr = (fsm_state == S_EXECUTE) && core_stack_wr;

    assign io_port = core_io_port;
    assign io_data_out = core_io_data;
    assign io_rd = core_io_rd;
    assign io_wr = (fsm_state == S_EXECUTE) && core_io_wr;

    // =========================================================================
    // Status Outputs
    // =========================================================================

    assign pc = r_pc;
    assign sp = r_sp;
    assign reg_a = r_a;
    assign reg_b = r_b;
    assign reg_c = r_c;
    assign reg_d = r_d;
    assign reg_e = r_e;
    assign reg_h = r_h;
    assign reg_l = r_l;
    assign halted = r_halted;
    assign inte = r_inte;
    assign flag_z = f_zero;
    assign flag_c = f_carry;

    assign mask_55 = r_mask_55;
    assign mask_65 = r_mask_65;
    assign mask_75 = r_mask_75;
    assign rst75_pending = r_rst75_pending;
    assign sod = r_sod_latch;

    // =========================================================================
    // Direct Address Calculation
    // =========================================================================

    wire [15:0] direct_addr = {fetched_imm2, fetched_imm1};

    // =========================================================================
    // Main FSM + State Update
    // =========================================================================

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // FSM state
            fsm_state <= S_FETCH_OP;
            r_bus_addr <= 16'h0000;
            bus_rd <= 1'b0;
            int_ack <= 1'b0;

            // CPU registers
            r_b <= 8'h00; r_c <= 8'h00;
            r_d <= 8'h00; r_e <= 8'h00;
            r_h <= 8'h00; r_l <= 8'h00;
            r_a <= 8'h00;
            r_sp <= 16'hFFFF;
            r_pc <= 16'h0000;
            r_pc_plus1 <= 16'h0001;
            r_pc_plus2 <= 16'h0002;
            f_sign <= 1'b0; f_zero <= 1'b0;
            f_aux <= 1'b0; f_parity <= 1'b0; f_carry <= 1'b0;
            r_halted <= 1'b0;
            r_inte <= 1'b0;
            r_mask_55 <= 1'b1;
            r_mask_65 <= 1'b1;
            r_mask_75 <= 1'b1;
            r_rst75_pending <= 1'b0;
            r_sod_latch <= 1'b0;

            // Fetch state
            fetched_op <= 8'h00;
            fetched_imm1 <= 8'h00;
            fetched_imm2 <= 8'h00;
            mem_rd_buf <= 8'h00;
            stk_lo_buf <= 8'h00;
            stk_hi_buf <= 8'h00;
            io_rd_buf <= 8'h00;
            execute_pulse <= 1'b0;
            shld_second_wr <= 1'b0;

            // Bank registers
            rom_bank <= 8'h00;
            ram_bank <= 3'b000;

`ifndef ORIGINAL_EXECUTE_MEM_WR
            r_pending_mem_wr <= 1'b0;
            r_mem_data <= 8'h00;
`endif
        end else begin
            // Defaults
            bus_rd <= 1'b0;
            execute_pulse <= 1'b0;
            int_ack <= 1'b0;

            case (fsm_state)
                S_FETCH_OP: begin
                    if (r_halted) begin
                        // Check for interrupt to wake from halt
                        if (int_req) begin
                            int_ack <= 1'b1;
                            r_pc <= int_vector;
                            r_sp <= r_sp - 16'd2;
                            r_halted <= 1'b0;
                            if (!int_is_trap)
                                r_inte <= 1'b0;
                            // Stay in S_FETCH_OP; next cycle computes
                            // r_pc_plus1/2 from registered r_pc
                        end else begin
                            fsm_state <= S_HALTED;
                        end
                    end else begin
                        // Pre-compute PC+1/2 from registered r_pc (opt #3)
                        r_pc_plus1 <= r_pc + 16'd1;
                        r_pc_plus2 <= r_pc + 16'd2;
                        r_bus_addr <= r_pc;
                        bus_rd <= 1'b1;
                        fsm_state <= S_WAIT_OP;
                    end
                end

                S_WAIT_OP: begin
                    if (bus_ready) begin
                        fetched_op <= bus_data_in;
                        fsm_state <= S_DECODE_OP;  // Pipeline: latch then decode
                    end
                end

                S_DECODE_OP: begin
                    // Decode outputs now stable (based on registered fetched_op)
                    if (dec_inst_len >= 2'd2) begin
                        r_bus_addr <= r_pc_plus1;
                        bus_rd <= 1'b1;
                        fsm_state <= S_FETCH_IMM1;
                    end else if (dec_needs_hl_read) begin
                        r_bus_addr <= hl;
                        bus_rd <= 1'b1;
                        fsm_state <= S_READ_MEM;
                    end else if (dec_needs_bc_read) begin
                        r_bus_addr <= bc;
                        bus_rd <= 1'b1;
                        fsm_state <= S_READ_MEM;
                    end else if (dec_needs_de_read) begin
                        r_bus_addr <= de;
                        bus_rd <= 1'b1;
                        fsm_state <= S_READ_MEM;
                    end else if (dec_needs_stack_read) begin
                        r_bus_addr <= r_sp;
                        bus_rd <= 1'b1;
                        fsm_state <= S_READ_STK_LO;
                    end else begin
                        fsm_state <= S_EXECUTE;
                    end
                end

                S_FETCH_IMM1: fsm_state <= S_WAIT_IMM1;

                S_WAIT_IMM1: begin
                    if (bus_ready) begin
                        fetched_imm1 <= bus_data_in;
                        if (dec_inst_len >= 2'd3) begin
                            r_bus_addr <= r_pc_plus2;
                            bus_rd <= 1'b1;
                            fsm_state <= S_FETCH_IMM2;
                        end else if (dec_needs_io_read) begin
                            io_rd_buf <= 8'hFF;  // Will be updated by external I/O
                            fsm_state <= S_EXECUTE;
                        end else if (dec_needs_hl_read) begin
                            r_bus_addr <= hl;
                            bus_rd <= 1'b1;
                            fsm_state <= S_READ_MEM;
                        end else if (dec_needs_bc_read) begin
                            r_bus_addr <= bc;
                            bus_rd <= 1'b1;
                            fsm_state <= S_READ_MEM;
                        end else if (dec_needs_de_read) begin
                            r_bus_addr <= de;
                            bus_rd <= 1'b1;
                            fsm_state <= S_READ_MEM;
                        end else if (dec_needs_stack_read) begin
                            r_bus_addr <= r_sp;
                            bus_rd <= 1'b1;
                            fsm_state <= S_READ_STK_LO;
                        end else begin
                            fsm_state <= S_EXECUTE;
                        end
                    end
                end

                S_FETCH_IMM2: fsm_state <= S_WAIT_IMM2;

                S_WAIT_IMM2: begin
                    if (bus_ready) begin
                        fetched_imm2 <= bus_data_in;
                        if (dec_needs_direct_read) begin
                            r_bus_addr <= {bus_data_in, fetched_imm1};
                            bus_rd <= 1'b1;
                            fsm_state <= S_READ_MEM;
                        end else if (dec_needs_stack_read) begin
                            r_bus_addr <= r_sp;
                            bus_rd <= 1'b1;
                            fsm_state <= S_READ_STK_LO;
                        end else begin
                            fsm_state <= S_EXECUTE;
                        end
                    end
                end

                S_READ_MEM: fsm_state <= S_WAIT_MEM;

                S_WAIT_MEM: begin
                    if (bus_ready) begin
                        mem_rd_buf <= bus_data_in;
                        if (fetched_op == 8'h2A) begin
                            // LHLD: need second byte
                            r_bus_addr <= direct_addr + 16'd1;
                            bus_rd <= 1'b1;
                            fsm_state <= S_READ_STK_LO;
                        end else if (dec_needs_stack_read) begin
                            r_bus_addr <= r_sp;
                            bus_rd <= 1'b1;
                            fsm_state <= S_READ_STK_LO;
                        end else begin
                            fsm_state <= S_EXECUTE;
                        end
                    end
                end

                S_READ_STK_LO: fsm_state <= S_WAIT_STK_LO;

                S_WAIT_STK_LO: begin
                    if (bus_ready) begin
                        stk_lo_buf <= bus_data_in;
                        r_bus_addr <= r_bus_addr + 16'd1;
                        bus_rd <= 1'b1;
                        fsm_state <= S_READ_STK_HI;
                    end
                end

                S_READ_STK_HI: fsm_state <= S_WAIT_STK_HI;

                S_WAIT_STK_HI: begin
                    if (bus_ready) begin
                        stk_hi_buf <= bus_data_in;
                        fsm_state <= S_EXECUTE;
                    end
                end

                S_EXECUTE: begin
                    execute_pulse <= 1'b1;

                    // Update CPU state from core
                    r_b <= next_b; r_c <= next_c;
                    r_d <= next_d; r_e <= next_e;
                    r_h <= next_h; r_l <= next_l;
                    r_a <= next_a;
                    r_sp <= next_sp;
                    r_pc <= next_pc;
                    f_sign <= next_f_sign;
                    f_zero <= next_f_zero;
                    f_aux <= next_f_aux;
                    f_parity <= next_f_par;
                    f_carry <= next_f_cry;
                    r_halted <= next_halted;
                    r_inte <= next_inte;
                    r_mask_55 <= next_mask_55;
                    r_mask_65 <= next_mask_65;
                    r_mask_75 <= next_mask_75;
                    r_rst75_pending <= next_rst75_pending;
                    r_sod_latch <= next_sod_latch;

                    // Handle I/O writes to bank registers
                    if (core_io_wr) begin
                        if (core_io_port == PORT_ROM_BANK)
                            rom_bank <= core_io_data;
                        else if (core_io_port == PORT_RAM_BANK)
                            ram_bank <= core_io_data[2:0];
                    end

                    // Handle memory/stack writes
                    // Note: Stack writes use separate stack_wr interface, not bus_wr
                    if (core_stack_wr) begin
                        r_bus_addr <= core_stack_addr;
                        fsm_state <= S_WRITE_MEM;
                    end else if (core_mem_wr) begin
                        r_bus_addr <= core_mem_addr;
`ifndef ORIGINAL_EXECUTE_MEM_WR
                        r_pending_mem_wr <= 1'b1;
                        r_mem_data <= core_mem_data;
`endif
                        shld_second_wr <= (fetched_op == 8'h22);
                        fsm_state <= S_WRITE_MEM;
                    end else begin
                        fsm_state <= S_FETCH_OP;
                    end
                end

                S_WRITE_MEM: begin
                    // Memory controller handles the actual write
                    // This state gives it one cycle
`ifndef ORIGINAL_EXECUTE_MEM_WR
                    if (shld_second_wr) begin
                        // SHLD: first write (L) done, now write H to addr+1
                        r_bus_addr <= r_bus_addr + 16'd1;
                        r_mem_data <= r_h;
                        shld_second_wr <= 1'b0;
                        // r_pending_mem_wr stays 1 for the second write
                        fsm_state <= S_WRITE_MEM;
                    end else begin
                        r_pending_mem_wr <= 1'b0;
                        fsm_state <= S_FETCH_OP;
                    end
`else
                    fsm_state <= S_FETCH_OP;
`endif
                end

                S_HALTED: begin
                    if (int_req) begin
                        int_ack <= 1'b1;
                        r_pc <= int_vector;
                        r_sp <= r_sp - 16'd2;
                        r_halted <= 1'b0;
                        if (!int_is_trap)
                            r_inte <= 1'b0;
                        fsm_state <= S_FETCH_OP;
                    end
                end

                default: fsm_state <= S_FETCH_OP;
            endcase
        end
    end

endmodule
