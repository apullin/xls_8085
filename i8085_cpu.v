// i8085_cpu.v - Self-contained 8085 CPU with internal fetch FSM
// Combines CPU state, fetch FSM, and instruction decode
// Provides clean bus master interface to external memory controller
//
// Phase 2 of refactoring: moves fetch FSM from i8085sg.v into CPU

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
    localparam S_FETCH_IMM1  = 4'd2;
    localparam S_WAIT_IMM1   = 4'd3;
    localparam S_FETCH_IMM2  = 4'd4;
    localparam S_WAIT_IMM2   = 4'd5;
    localparam S_READ_MEM    = 4'd6;
    localparam S_WAIT_MEM    = 4'd7;
    localparam S_READ_STK_LO = 4'd8;
    localparam S_WAIT_STK_LO = 4'd9;
    localparam S_READ_STK_HI = 4'd10;
    localparam S_WAIT_STK_HI = 4'd11;
    localparam S_EXECUTE     = 4'd12;
    localparam S_WRITE_MEM   = 4'd13;
    localparam S_HALTED      = 4'd14;

    reg [3:0] fsm_state;

    // =========================================================================
    // CPU State Registers
    // =========================================================================

    reg [7:0]  r_b, r_c, r_d, r_e, r_h, r_l, r_a;
    reg [15:0] r_sp, r_pc;
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

    // =========================================================================
    // Instruction Decode
    // =========================================================================

    wire [7:0] decode_opcode = (fsm_state == S_WAIT_OP) ? bus_data_in : fetched_op;

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

    // bus_addr muxes between:
    // - Write address (core_mem_addr or core_stack_addr) during S_EXECUTE writes
    // - Registered fetch address (r_bus_addr) for reads
    wire doing_mem_write = (fsm_state == S_EXECUTE) && core_mem_wr;
    wire doing_stk_write = (fsm_state == S_EXECUTE) && core_stack_wr;
    assign bus_addr = doing_mem_write ? core_mem_addr :
                      doing_stk_write ? core_stack_addr :
                      r_bus_addr;

    assign bus_data_out = core_mem_data;
    assign bus_wr = doing_mem_write;

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

            // Bank registers
            rom_bank <= 8'h00;
            ram_bank <= 3'b000;
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
                        end else begin
                            fsm_state <= S_HALTED;
                        end
                    end else begin
                        r_bus_addr <= r_pc;
                        bus_rd <= 1'b1;
                        fsm_state <= S_WAIT_OP;
                    end
                end

                S_WAIT_OP: begin
                    if (bus_ready) begin
                        fetched_op <= bus_data_in;
                        if (dec_inst_len >= 2'd2) begin
                            r_bus_addr <= r_pc + 16'd1;
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
                end

                S_FETCH_IMM1: fsm_state <= S_WAIT_IMM1;

                S_WAIT_IMM1: begin
                    if (bus_ready) begin
                        fetched_imm1 <= bus_data_in;
                        if (dec_inst_len >= 2'd3) begin
                            r_bus_addr <= r_pc + 16'd2;
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
                    if (core_stack_wr) begin
                        r_bus_addr <= core_stack_addr;
                        fsm_state <= S_WRITE_MEM;
                    end else if (core_mem_wr) begin
                        r_bus_addr <= core_mem_addr;
                        fsm_state <= S_WRITE_MEM;
                    end else begin
                        fsm_state <= S_FETCH_OP;
                    end
                end

                S_WRITE_MEM: begin
                    // Memory controller handles the actual write
                    // This state gives it one cycle
                    fsm_state <= S_FETCH_OP;
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
