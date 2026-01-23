// Intel 8085A 40-DIP Compatible Wrapper
// Wraps XLS-generated core with proper bus timing and pinout
//
// This provides the classic 8085 bus interface:
// - Multiplexed AD0-7 bus with ALE timing
// - Active-low RD/WR strobes
// - IO/M, S0, S1 status signals
// - Interrupt inputs (TRAP, RST7.5, RST6.5, RST5.5, INTR)
// - Serial I/O (SID, SOD)
// - DMA support (HOLD, HLDA)
//
// Note: This is instruction-accurate, not cycle-accurate.
// Each instruction completes in fewer clocks than the original 8085.
// The T-state machine here provides compatible external timing.

module i8085_40dip (
    // Clock and Reset
    input  wire        clk,          // System clock
    input  wire        reset_n,      // RESIN (pin 36) - active low

    // Multiplexed Address/Data Bus
    inout  wire [7:0]  ad,           // AD0-AD7 (pins 12-19)
    output wire [7:0]  a_hi,         // A8-A15 (pins 21-28)

    // Bus Control
    output wire        ale,          // ALE (pin 30) - Address Latch Enable
    output wire        rd_n,         // RD (pin 32) - active low
    output wire        wr_n,         // WR (pin 31) - active low
    output wire        io_m_n,       // IO/M (pin 34) - high=IO, low=Memory

    // Status
    output wire        s0,           // S0 (pin 29)
    output wire        s1,           // S1 (pin 33)
    output wire        resout,       // RESOUT (pin 3) - active high during reset

    // Interrupts
    input  wire        trap,         // TRAP (pin 6) - NMI, edge+level triggered
    input  wire        rst75,        // RST7.5 (pin 7) - edge triggered
    input  wire        rst65,        // RST6.5 (pin 8) - level triggered
    input  wire        rst55,        // RST5.5 (pin 9) - level triggered
    input  wire        intr,         // INTR (pin 10) - general interrupt
    output wire        inta_n,       // INTA (pin 11) - interrupt acknowledge, active low

    // Serial I/O
    input  wire        sid,          // SID (pin 5) - Serial Input Data
    output wire        sod,          // SOD (pin 4) - Serial Output Data

    // DMA
    input  wire        hold,         // HOLD (pin 39) - DMA request
    output wire        hlda,         // HLDA (pin 38) - Hold Acknowledge

    // Wait State
    input  wire        ready         // READY (pin 35) - memory/IO ready
);

    // =========================================================================
    // FSM States
    // =========================================================================

    localparam [5:0]
        S_IDLE          = 6'd0,
        // Opcode fetch
        S_FETCH_ALE     = 6'd1,
        S_FETCH_RD      = 6'd2,
        S_FETCH_WAIT    = 6'd3,
        S_DECODE        = 6'd4,
        // Immediate byte fetch
        S_IMM1_ALE      = 6'd5,
        S_IMM1_RD       = 6'd6,
        S_IMM1_WAIT     = 6'd7,
        S_IMM2_ALE      = 6'd8,
        S_IMM2_RD       = 6'd9,
        S_IMM2_WAIT     = 6'd10,
        // Memory read (for MOV r,M, ADD M, LDA, LDAX, etc.)
        S_MEM_RD_ALE    = 6'd11,
        S_MEM_RD        = 6'd12,
        S_MEM_RD_WAIT   = 6'd13,
        // Memory read 2nd byte (for LHLD)
        S_MEM_RD2_ALE   = 6'd14,
        S_MEM_RD2       = 6'd15,
        S_MEM_RD2_WAIT  = 6'd16,
        // Stack read (for RET, POP)
        S_STK_RD_LO_ALE = 6'd17,
        S_STK_RD_LO     = 6'd18,
        S_STK_RD_LO_WAIT= 6'd19,
        S_STK_RD_HI_ALE = 6'd20,
        S_STK_RD_HI     = 6'd21,
        S_STK_RD_HI_WAIT= 6'd22,
        // I/O read (for IN)
        S_IO_RD_ALE     = 6'd23,
        S_IO_RD         = 6'd24,
        S_IO_RD_WAIT    = 6'd25,
        // Execute
        S_EXECUTE       = 6'd26,
        // Memory write (for MOV M,r, STA, STAX, etc.)
        S_MEM_WR_ALE    = 6'd27,
        S_MEM_WR        = 6'd28,
        S_MEM_WR_WAIT   = 6'd29,
        // Memory write 2nd byte (for SHLD)
        S_MEM_WR2_ALE   = 6'd30,
        S_MEM_WR2       = 6'd31,
        S_MEM_WR2_WAIT  = 6'd32,
        // Stack write (for CALL, PUSH, RST)
        S_STK_WR_HI_ALE = 6'd33,
        S_STK_WR_HI     = 6'd34,
        S_STK_WR_HI_WAIT= 6'd35,
        S_STK_WR_LO_ALE = 6'd36,
        S_STK_WR_LO     = 6'd37,
        S_STK_WR_LO_WAIT= 6'd38,
        // I/O write (for OUT)
        S_IO_WR_ALE     = 6'd39,
        S_IO_WR         = 6'd40,
        S_IO_WR_WAIT    = 6'd41,
        // Interrupt acknowledge (for INTR)
        S_INTA_ALE      = 6'd42,
        S_INTA          = 6'd43,
        S_INTA_WAIT     = 6'd44,
        // Halt
        S_HALT          = 6'd45,
        // Interrupt check and service
        S_INT_CHECK     = 6'd46,
        S_INT_PUSH_HI_ALE = 6'd47,
        S_INT_PUSH_HI   = 6'd48,
        S_INT_PUSH_HI_WAIT = 6'd49,
        S_INT_PUSH_LO_ALE = 6'd50,
        S_INT_PUSH_LO   = 6'd51,
        S_INT_PUSH_LO_WAIT = 6'd52;

    reg [5:0] state;

    // =========================================================================
    // Internal Signals
    // =========================================================================

    // CPU core interface registers
    reg  [7:0]  opcode_reg;
    reg  [7:0]  imm1_reg;
    reg  [7:0]  imm2_reg;
    reg  [7:0]  mem_read_data;
    reg  [7:0]  mem_read_data2;     // For LHLD 2nd byte
    reg  [7:0]  stack_lo, stack_hi;
    reg  [7:0]  io_read_data;
    reg         execute_pulse;

    // Address/data output registers
    reg [15:0] addr_out;
    reg [7:0]  data_out;
    reg        data_out_en;
    reg        ale_reg;
    reg        rd_reg;
    reg        wr_reg;
    reg        io_m_reg;           // 1=IO, 0=Memory
    reg        inta_reg;
    reg        s0_reg, s1_reg;     // Status signals

    // Core outputs
    wire [15:0] core_mem_addr;
    wire [7:0]  core_mem_data_out;
    wire        core_mem_wr;
    wire        core_mem_rd;
    wire [15:0] core_stack_wr_addr;
    wire [7:0]  core_stack_wr_lo;
    wire [7:0]  core_stack_wr_hi;
    wire        core_stack_wr;
    wire [7:0]  core_io_port;
    wire [7:0]  core_io_data_out;
    wire        core_io_rd;
    wire        core_io_wr;
    wire [15:0] core_pc;
    wire [15:0] core_sp;
    wire [7:0]  core_reg_a;
    wire [7:0]  core_reg_b;
    wire [7:0]  core_reg_c;
    wire [7:0]  core_reg_d;
    wire [7:0]  core_reg_e;
    wire [7:0]  core_reg_h;
    wire [7:0]  core_reg_l;
    wire        core_halted;
    wire        core_inte;
    wire        core_flag_z;
    wire        core_flag_c;
    // Interrupt mask/status from core
    wire        core_mask_55;
    wire        core_mask_65;
    wire        core_mask_75;
    wire        core_rst75_pending;
    wire        core_sod;

    // Latched core outputs after execute (for write phases)
    reg [15:0] latched_mem_addr;
    reg [7:0]  latched_mem_data;
    reg        latched_mem_wr;
    reg [15:0] latched_stack_addr;
    reg [7:0]  latched_stack_lo;
    reg [7:0]  latched_stack_hi;
    reg        latched_stack_wr;
    reg [7:0]  latched_io_port;
    reg [7:0]  latched_io_data;
    reg        latched_io_wr;

    // Computed memory address for reads
    reg [15:0] mem_rd_addr;

    // Interrupt service registers
    reg [15:0] int_vector;        // Vector address for current interrupt
    reg        int_is_trap;       // True if servicing TRAP (don't clear INTE)
    reg        int_is_intr;       // True if servicing INTR (need INTA cycle)
    reg [15:0] int_saved_pc;      // PC to push to stack
    reg [15:0] int_saved_sp;      // SP for stack push
    reg        int_ack;           // Pulse to acknowledge interrupt (update PC/SP/INTE)

    // =========================================================================
    // Instruction Decoders
    // =========================================================================

    function [1:0] get_inst_len;
        input [7:0] op;
        begin
            casez (op)
                // 3-byte instructions
                8'hCD, 8'hC4, 8'hCC, 8'hD4, 8'hDC,  // CALL, Ccond
                8'hE4, 8'hEC, 8'hF4, 8'hFC,
                8'hC3, 8'hC2, 8'hCA, 8'hD2, 8'hDA,  // JMP, Jcond
                8'hE2, 8'hEA, 8'hF2, 8'hFA,
                8'h01, 8'h11, 8'h21, 8'h31,         // LXI
                8'h22, 8'h2A,                       // SHLD, LHLD
                8'h32, 8'h3A,                       // STA, LDA
                8'hC6, 8'hCE, 8'hD6, 8'hDE,        // Immediate ALU
                8'hE6, 8'hEE, 8'hF6, 8'hFE:
                    get_inst_len = 2'd3;

                // 2-byte instructions
                8'h06, 8'h0E, 8'h16, 8'h1E,        // MVI
                8'h26, 8'h2E, 8'h36, 8'h3E,
                8'hDB, 8'hD3:                       // IN, OUT
                    get_inst_len = 2'd2;

                // All others are 1-byte
                default:
                    get_inst_len = 2'd1;
            endcase
        end
    endfunction

    // Does instruction need memory read from (HL)?
    function needs_hl_read;
        input [7:0] op;
        begin
            casez (op)
                8'b01???110: needs_hl_read = (op[5:3] != 3'b110); // MOV r,M (not HLT)
                8'b10???110: needs_hl_read = 1'b1;  // ADD/ADC/SUB/SBC/ANA/XRA/ORA/CMP M
                8'h34, 8'h35: needs_hl_read = 1'b1; // INR M, DCR M
                8'hE3: needs_hl_read = 1'b1;        // XTHL
                default: needs_hl_read = 1'b0;
            endcase
        end
    endfunction

    // Does instruction need memory read from (BC)?
    function needs_bc_read;
        input [7:0] op;
        begin
            needs_bc_read = (op == 8'h0A);  // LDAX B
        end
    endfunction

    // Does instruction need memory read from (DE)?
    function needs_de_read;
        input [7:0] op;
        begin
            needs_de_read = (op == 8'h1A);  // LDAX D
        end
    endfunction

    // Does instruction need memory read from direct address?
    function needs_direct_read;
        input [7:0] op;
        begin
            case (op)
                8'h3A: needs_direct_read = 1'b1;  // LDA
                8'h2A: needs_direct_read = 1'b1;  // LHLD (first byte)
                default: needs_direct_read = 1'b0;
            endcase
        end
    endfunction

    // Does instruction need 2-byte memory read? (LHLD)
    function needs_mem_read2;
        input [7:0] op;
        begin
            needs_mem_read2 = (op == 8'h2A);  // LHLD
        end
    endfunction

    // Does instruction need stack read?
    function needs_stack_read;
        input [7:0] op;
        begin
            casez (op)
                8'hC9: needs_stack_read = 1'b1;           // RET
                8'b11???000: needs_stack_read = 1'b1;     // Rcond
                8'b11??0001: needs_stack_read = 1'b1;     // POP (including PSW)
                8'hE3: needs_stack_read = 1'b1;           // XTHL
                default: needs_stack_read = 1'b0;
            endcase
        end
    endfunction

    // Does instruction need I/O read?
    function needs_io_read;
        input [7:0] op;
        begin
            needs_io_read = (op == 8'hDB);  // IN
        end
    endfunction

    wire [1:0] inst_len = get_inst_len(opcode_reg);
    wire op_needs_hl_read = needs_hl_read(opcode_reg);
    wire op_needs_bc_read = needs_bc_read(opcode_reg);
    wire op_needs_de_read = needs_de_read(opcode_reg);
    wire op_needs_direct_read = needs_direct_read(opcode_reg);
    wire op_needs_mem_read2 = needs_mem_read2(opcode_reg);
    wire op_needs_stack_read = needs_stack_read(opcode_reg);
    wire op_needs_io_read = needs_io_read(opcode_reg);

    wire op_needs_any_mem_read = op_needs_hl_read | op_needs_bc_read |
                                  op_needs_de_read | op_needs_direct_read;

    // =========================================================================
    // HOLD/DMA Logic
    // =========================================================================

    reg hold_ack;
    wire in_hold = hold & hold_ack;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            hold_ack <= 1'b0;
        else if (hold && (state == S_IDLE || state == S_HALT))
            hold_ack <= 1'b1;
        else if (!hold)
            hold_ack <= 1'b0;
    end

    assign hlda = hold_ack;

    // =========================================================================
    // Interrupt Edge Detection and Priority
    // =========================================================================

    reg trap_prev, rst75_prev;
    wire trap_edge = trap & ~trap_prev;
    wire rst75_edge = rst75 & ~rst75_prev;

    reg trap_pending;
    reg rst75_latch;  // Set on edge, cleared by SIM or service
    reg clear_trap, clear_rst75;  // Pulses to clear pending flags

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            trap_prev <= 1'b0;
            rst75_prev <= 1'b0;
            trap_pending <= 1'b0;
            rst75_latch <= 1'b0;
        end else begin
            trap_prev <= trap;
            rst75_prev <= rst75;

            // TRAP: edge + level triggered (NMI)
            if (trap_edge && trap)
                trap_pending <= 1'b1;
            else if (clear_trap)
                trap_pending <= 1'b0;

            // RST 7.5: edge triggered, latched
            // Set on rising edge, clear when serviced or via SIM R7.5 bit
            if (rst75_edge)
                rst75_latch <= 1'b1;
            else if (clear_rst75 || (!core_rst75_pending && rst75_latch))
                rst75_latch <= 1'b0;
        end
    end

    // Interrupt vectors (per 8085 datasheet)
    localparam [15:0] VEC_TRAP  = 16'h0024;
    localparam [15:0] VEC_RST75 = 16'h003C;
    localparam [15:0] VEC_RST65 = 16'h0034;
    localparam [15:0] VEC_RST55 = 16'h002C;

    // Interrupt conditions (active when should be serviced)
    wire int_trap_active = trap_pending & trap;  // Edge + level
    wire int_rst75_active = rst75_latch & ~core_mask_75 & core_inte;
    wire int_rst65_active = rst65 & ~core_mask_65 & core_inte;
    wire int_rst55_active = rst55 & ~core_mask_55 & core_inte;
    wire int_intr_active = intr & core_inte;

    // Any interrupt pending (in priority order)
    wire int_any_pending = int_trap_active | int_rst75_active |
                           int_rst65_active | int_rst55_active | int_intr_active;

    // =========================================================================
    // Main FSM
    // =========================================================================

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_IDLE;
            opcode_reg <= 8'h00;
            imm1_reg <= 8'h00;
            imm2_reg <= 8'h00;
            mem_read_data <= 8'h00;
            mem_read_data2 <= 8'h00;
            stack_lo <= 8'h00;
            stack_hi <= 8'h00;
            io_read_data <= 8'h00;
            execute_pulse <= 1'b0;
            addr_out <= 16'h0000;
            data_out <= 8'h00;
            data_out_en <= 1'b0;
            ale_reg <= 1'b0;
            rd_reg <= 1'b1;
            wr_reg <= 1'b1;
            io_m_reg <= 1'b0;
            inta_reg <= 1'b1;
            mem_rd_addr <= 16'h0000;
            latched_mem_addr <= 16'h0000;
            latched_mem_data <= 8'h00;
            latched_mem_wr <= 1'b0;
            latched_stack_addr <= 16'h0000;
            latched_stack_lo <= 8'h00;
            latched_stack_hi <= 8'h00;
            latched_stack_wr <= 1'b0;
            latched_io_port <= 8'h00;
            latched_io_data <= 8'h00;
            latched_io_wr <= 1'b0;
            // Interrupt service registers
            int_vector <= 16'h0000;
            int_is_trap <= 1'b0;
            int_is_intr <= 1'b0;
            int_saved_pc <= 16'h0000;
            int_saved_sp <= 16'h0000;
            int_ack <= 1'b0;
            clear_trap <= 1'b0;
            clear_rst75 <= 1'b0;
            // Status signals
            s0_reg <= 1'b0;
            s1_reg <= 1'b0;
        end else if (in_hold) begin
            // Tri-state bus during hold
            ale_reg <= 1'b0;
            rd_reg <= 1'b1;
            wr_reg <= 1'b1;
            data_out_en <= 1'b0;
        end else begin
            execute_pulse <= 1'b0;
            int_ack <= 1'b0;
            clear_trap <= 1'b0;
            clear_rst75 <= 1'b0;

            case (state)
                // =============================================================
                // IDLE - Start fetch or check halt
                // =============================================================
                S_IDLE: begin
                    if (core_halted) begin
                        s0_reg <= 1'b0; s1_reg <= 1'b0;  // Halt status
                        state <= S_HALT;
                    end else begin
                        // Start opcode fetch: S1=1, S0=1
                        addr_out <= core_pc;
                        ale_reg <= 1'b1;
                        io_m_reg <= 1'b0;
                        s0_reg <= 1'b1; s1_reg <= 1'b1;  // Opcode fetch
                        state <= S_FETCH_ALE;
                    end
                end

                // =============================================================
                // Opcode Fetch
                // =============================================================
                S_FETCH_ALE: begin
                    ale_reg <= 1'b0;
                    rd_reg <= 1'b0;
                    state <= S_FETCH_RD;
                end

                S_FETCH_RD: begin
                    state <= S_FETCH_WAIT;
                end

                S_FETCH_WAIT: begin
                    if (ready) begin
                        opcode_reg <= ad;
                        rd_reg <= 1'b1;
                        state <= S_DECODE;
                    end
                end

                // =============================================================
                // Decode - Determine what else needs fetching
                // =============================================================
                S_DECODE: begin
                    if (inst_len >= 2'd2) begin
                        // Need immediate byte(s) - memory read: S1=1, S0=0
                        addr_out <= core_pc + 16'd1;
                        ale_reg <= 1'b1;
                        s0_reg <= 1'b0; s1_reg <= 1'b1;
                        state <= S_IMM1_ALE;
                    end else if (op_needs_any_mem_read) begin
                        // 1-byte instruction needing memory read
                        // Compute address based on instruction type
                        if (op_needs_hl_read)
                            mem_rd_addr <= {core_reg_h, core_reg_l};
                        else if (op_needs_bc_read)
                            mem_rd_addr <= {core_reg_b, core_reg_c};
                        else if (op_needs_de_read)
                            mem_rd_addr <= {core_reg_d, core_reg_e};
                        addr_out <= op_needs_hl_read ? {core_reg_h, core_reg_l} :
                                   op_needs_bc_read ? {core_reg_b, core_reg_c} :
                                   {core_reg_d, core_reg_e};
                        ale_reg <= 1'b1;
                        io_m_reg <= 1'b0;
                        s0_reg <= 1'b0; s1_reg <= 1'b1;  // Memory read
                        state <= S_MEM_RD_ALE;
                    end else if (op_needs_stack_read) begin
                        addr_out <= core_sp;
                        ale_reg <= 1'b1;
                        s0_reg <= 1'b0; s1_reg <= 1'b1;  // Memory read (stack)
                        io_m_reg <= 1'b0;
                        state <= S_STK_RD_LO_ALE;
                    end else begin
                        // 1-byte instruction, execute directly
                        state <= S_EXECUTE;
                    end
                end

                // =============================================================
                // Immediate Byte 1 Fetch
                // =============================================================
                S_IMM1_ALE: begin
                    ale_reg <= 1'b0;
                    rd_reg <= 1'b0;
                    state <= S_IMM1_RD;
                end

                S_IMM1_RD: begin
                    state <= S_IMM1_WAIT;
                end

                S_IMM1_WAIT: begin
                    if (ready) begin
                        imm1_reg <= ad;
                        rd_reg <= 1'b1;
                        if (inst_len == 2'd3) begin
                            addr_out <= core_pc + 16'd2;
                            ale_reg <= 1'b1;
                            s0_reg <= 1'b0; s1_reg <= 1'b1;  // Memory read
                            state <= S_IMM2_ALE;
                        end else if (op_needs_io_read) begin
                            // IN instruction - do I/O read: S1=1, S0=0
                            addr_out <= {ad, ad};  // Port on both A0-7 and A8-15
                            ale_reg <= 1'b1;
                            io_m_reg <= 1'b1;
                            s0_reg <= 1'b0; s1_reg <= 1'b1;  // I/O read
                            state <= S_IO_RD_ALE;
                        end else begin
                            state <= S_EXECUTE;
                        end
                    end
                end

                // =============================================================
                // Immediate Byte 2 Fetch
                // =============================================================
                S_IMM2_ALE: begin
                    ale_reg <= 1'b0;
                    rd_reg <= 1'b0;
                    state <= S_IMM2_RD;
                end

                S_IMM2_RD: begin
                    state <= S_IMM2_WAIT;
                end

                S_IMM2_WAIT: begin
                    if (ready) begin
                        imm2_reg <= ad;
                        rd_reg <= 1'b1;

                        if (op_needs_direct_read) begin
                            // LDA or LHLD - read from direct address
                            addr_out <= {ad, imm1_reg};
                            mem_rd_addr <= {ad, imm1_reg};
                            ale_reg <= 1'b1;
                            io_m_reg <= 1'b0;
                            s0_reg <= 1'b0; s1_reg <= 1'b1;  // Memory read
                            state <= S_MEM_RD_ALE;
                        end else if (op_needs_stack_read) begin
                            // CALL variants that need stack read? No, CALL writes
                            // This is for RET with immediate - doesn't exist
                            state <= S_EXECUTE;
                        end else begin
                            state <= S_EXECUTE;
                        end
                    end
                end

                // =============================================================
                // Memory Read
                // =============================================================
                S_MEM_RD_ALE: begin
                    ale_reg <= 1'b0;
                    rd_reg <= 1'b0;
                    state <= S_MEM_RD;
                end

                S_MEM_RD: begin
                    state <= S_MEM_RD_WAIT;
                end

                S_MEM_RD_WAIT: begin
                    if (ready) begin
                        mem_read_data <= ad;
                        rd_reg <= 1'b1;

                        if (op_needs_mem_read2) begin
                            // LHLD needs second byte
                            addr_out <= mem_rd_addr + 16'd1;
                            ale_reg <= 1'b1;
                            s0_reg <= 1'b0; s1_reg <= 1'b1;  // Memory read
                            state <= S_MEM_RD2_ALE;
                        end else begin
                            state <= S_EXECUTE;
                        end
                    end
                end

                // =============================================================
                // Memory Read 2nd Byte (LHLD)
                // =============================================================
                S_MEM_RD2_ALE: begin
                    ale_reg <= 1'b0;
                    rd_reg <= 1'b0;
                    state <= S_MEM_RD2;
                end

                S_MEM_RD2: begin
                    state <= S_MEM_RD2_WAIT;
                end

                S_MEM_RD2_WAIT: begin
                    if (ready) begin
                        mem_read_data2 <= ad;
                        rd_reg <= 1'b1;
                        state <= S_EXECUTE;
                    end
                end

                // =============================================================
                // Stack Read (RET, POP)
                // =============================================================
                S_STK_RD_LO_ALE: begin
                    ale_reg <= 1'b0;
                    rd_reg <= 1'b0;
                    state <= S_STK_RD_LO;
                end

                S_STK_RD_LO: begin
                    state <= S_STK_RD_LO_WAIT;
                end

                S_STK_RD_LO_WAIT: begin
                    if (ready) begin
                        stack_lo <= ad;
                        rd_reg <= 1'b1;
                        // Read high byte
                        addr_out <= core_sp + 16'd1;
                        ale_reg <= 1'b1;
                        s0_reg <= 1'b0; s1_reg <= 1'b1;  // Memory read (stack)
                        state <= S_STK_RD_HI_ALE;
                    end
                end

                S_STK_RD_HI_ALE: begin
                    ale_reg <= 1'b0;
                    rd_reg <= 1'b0;
                    state <= S_STK_RD_HI;
                end

                S_STK_RD_HI: begin
                    state <= S_STK_RD_HI_WAIT;
                end

                S_STK_RD_HI_WAIT: begin
                    if (ready) begin
                        stack_hi <= ad;
                        rd_reg <= 1'b1;
                        state <= S_EXECUTE;
                    end
                end

                // =============================================================
                // I/O Read (IN)
                // =============================================================
                S_IO_RD_ALE: begin
                    ale_reg <= 1'b0;
                    rd_reg <= 1'b0;
                    state <= S_IO_RD;
                end

                S_IO_RD: begin
                    state <= S_IO_RD_WAIT;
                end

                S_IO_RD_WAIT: begin
                    if (ready) begin
                        io_read_data <= ad;
                        rd_reg <= 1'b1;
                        io_m_reg <= 1'b0;
                        state <= S_EXECUTE;
                    end
                end

                // =============================================================
                // Execute
                // =============================================================
                S_EXECUTE: begin
                    execute_pulse <= 1'b1;

                    // Latch core outputs for write phases
                    latched_mem_addr <= core_mem_addr;
                    latched_mem_data <= core_mem_data_out;
                    latched_mem_wr <= core_mem_wr;
                    latched_stack_addr <= core_stack_wr_addr;
                    latched_stack_lo <= core_stack_wr_lo;
                    latched_stack_hi <= core_stack_wr_hi;
                    latched_stack_wr <= core_stack_wr;
                    latched_io_port <= core_io_port;
                    latched_io_data <= core_io_data_out;
                    latched_io_wr <= core_io_wr;

                    // Determine next state based on what writes are needed
                    if (core_mem_wr) begin
                        addr_out <= core_mem_addr;
                        ale_reg <= 1'b1;
                        io_m_reg <= 1'b0;
                        s0_reg <= 1'b1; s1_reg <= 1'b0;  // Memory write
                        state <= S_MEM_WR_ALE;
                    end else if (core_stack_wr) begin
                        // Stack push: write high byte first (to SP-1), then low (to SP-2)
                        addr_out <= core_stack_wr_addr;  // SP-1
                        ale_reg <= 1'b1;
                        io_m_reg <= 1'b0;
                        s0_reg <= 1'b1; s1_reg <= 1'b0;  // Memory write (stack)
                        state <= S_STK_WR_HI_ALE;
                    end else if (core_io_wr) begin
                        addr_out <= {core_io_port, core_io_port};
                        ale_reg <= 1'b1;
                        io_m_reg <= 1'b1;
                        s0_reg <= 1'b1; s1_reg <= 1'b0;  // I/O write
                        state <= S_IO_WR_ALE;
                    end else begin
                        state <= S_INT_CHECK;
                    end
                end

                // =============================================================
                // Memory Write
                // =============================================================
                S_MEM_WR_ALE: begin
                    ale_reg <= 1'b0;
                    data_out <= latched_mem_data;
                    data_out_en <= 1'b1;
                    wr_reg <= 1'b0;
                    state <= S_MEM_WR;
                end

                S_MEM_WR: begin
                    state <= S_MEM_WR_WAIT;
                end

                S_MEM_WR_WAIT: begin
                    if (ready) begin
                        wr_reg <= 1'b1;
                        data_out_en <= 1'b0;

                        // Check for SHLD (needs 2nd write)
                        if (opcode_reg == 8'h22 && !latched_stack_wr) begin
                            // SHLD: wrote L, now write H
                            addr_out <= latched_mem_addr + 16'd1;
                            latched_mem_data <= core_reg_h;  // Write H to addr+1
                            ale_reg <= 1'b1;
                            s0_reg <= 1'b1; s1_reg <= 1'b0;  // Memory write
                            state <= S_MEM_WR2_ALE;
                        end else begin
                            state <= S_INT_CHECK;
                        end
                    end
                end

                // =============================================================
                // Memory Write 2nd Byte (SHLD)
                // =============================================================
                S_MEM_WR2_ALE: begin
                    ale_reg <= 1'b0;
                    data_out <= latched_mem_data;
                    data_out_en <= 1'b1;
                    wr_reg <= 1'b0;
                    state <= S_MEM_WR2;
                end

                S_MEM_WR2: begin
                    state <= S_MEM_WR2_WAIT;
                end

                S_MEM_WR2_WAIT: begin
                    if (ready) begin
                        wr_reg <= 1'b1;
                        data_out_en <= 1'b0;
                        state <= S_INT_CHECK;
                    end
                end

                // =============================================================
                // Stack Write (CALL, PUSH, RST)
                // Push order: high byte to SP-1, low byte to SP-2
                // =============================================================
                S_STK_WR_HI_ALE: begin
                    ale_reg <= 1'b0;
                    data_out <= latched_stack_hi;
                    data_out_en <= 1'b1;
                    wr_reg <= 1'b0;
                    state <= S_STK_WR_HI;
                end

                S_STK_WR_HI: begin
                    state <= S_STK_WR_HI_WAIT;
                end

                S_STK_WR_HI_WAIT: begin
                    if (ready) begin
                        wr_reg <= 1'b1;
                        data_out_en <= 1'b0;
                        // Now write low byte
                        addr_out <= latched_stack_addr - 16'd1;  // SP-2
                        ale_reg <= 1'b1;
                        s0_reg <= 1'b1; s1_reg <= 1'b0;  // Memory write (stack)
                        state <= S_STK_WR_LO_ALE;
                    end
                end

                S_STK_WR_LO_ALE: begin
                    ale_reg <= 1'b0;
                    data_out <= latched_stack_lo;
                    data_out_en <= 1'b1;
                    wr_reg <= 1'b0;
                    state <= S_STK_WR_LO;
                end

                S_STK_WR_LO: begin
                    state <= S_STK_WR_LO_WAIT;
                end

                S_STK_WR_LO_WAIT: begin
                    if (ready) begin
                        wr_reg <= 1'b1;
                        data_out_en <= 1'b0;
                        state <= S_INT_CHECK;
                    end
                end

                // =============================================================
                // I/O Write (OUT)
                // =============================================================
                S_IO_WR_ALE: begin
                    ale_reg <= 1'b0;
                    data_out <= latched_io_data;
                    data_out_en <= 1'b1;
                    wr_reg <= 1'b0;
                    state <= S_IO_WR;
                end

                S_IO_WR: begin
                    state <= S_IO_WR_WAIT;
                end

                S_IO_WR_WAIT: begin
                    if (ready) begin
                        wr_reg <= 1'b1;
                        data_out_en <= 1'b0;
                        io_m_reg <= 1'b0;
                        state <= S_INT_CHECK;
                    end
                end

                // =============================================================
                // Halt - Wait for interrupt or reset
                // =============================================================
                S_HALT: begin
                    // Check for any interrupt that can wake from halt
                    if (int_trap_active) begin
                        // TRAP wakes from halt
                        int_vector <= VEC_TRAP;
                        int_is_trap <= 1'b1;
                        int_is_intr <= 1'b0;
                        int_saved_pc <= core_pc;
                        int_saved_sp <= core_sp;
                        clear_trap <= 1'b1;
                        addr_out <= core_sp - 16'd1;
                        ale_reg <= 1'b1;
                        io_m_reg <= 1'b0;
                        s0_reg <= 1'b1; s1_reg <= 1'b0;  // Memory write (int push)
                        state <= S_INT_PUSH_HI_ALE;
                    end else if (int_rst75_active) begin
                        int_vector <= VEC_RST75;
                        int_is_trap <= 1'b0;
                        int_is_intr <= 1'b0;
                        int_saved_pc <= core_pc;
                        int_saved_sp <= core_sp;
                        clear_rst75 <= 1'b1;
                        addr_out <= core_sp - 16'd1;
                        ale_reg <= 1'b1;
                        io_m_reg <= 1'b0;
                        s0_reg <= 1'b1; s1_reg <= 1'b0;  // Memory write (int push)
                        state <= S_INT_PUSH_HI_ALE;
                    end else if (int_rst65_active) begin
                        int_vector <= VEC_RST65;
                        int_is_trap <= 1'b0;
                        int_is_intr <= 1'b0;
                        int_saved_pc <= core_pc;
                        int_saved_sp <= core_sp;
                        addr_out <= core_sp - 16'd1;
                        ale_reg <= 1'b1;
                        io_m_reg <= 1'b0;
                        s0_reg <= 1'b1; s1_reg <= 1'b0;  // Memory write (int push)
                        state <= S_INT_PUSH_HI_ALE;
                    end else if (int_rst55_active) begin
                        int_vector <= VEC_RST55;
                        int_is_trap <= 1'b0;
                        int_is_intr <= 1'b0;
                        int_saved_pc <= core_pc;
                        int_saved_sp <= core_sp;
                        addr_out <= core_sp - 16'd1;
                        ale_reg <= 1'b1;
                        io_m_reg <= 1'b0;
                        s0_reg <= 1'b1; s1_reg <= 1'b0;  // Memory write (int push)
                        state <= S_INT_PUSH_HI_ALE;
                    end else if (int_intr_active) begin
                        // INTR needs INTA cycle to get instruction
                        int_is_trap <= 1'b0;
                        int_is_intr <= 1'b1;
                        int_saved_pc <= core_pc;
                        int_saved_sp <= core_sp;
                        inta_reg <= 1'b0;  // Assert INTA
                        ale_reg <= 1'b1;
                        s0_reg <= 1'b1; s1_reg <= 1'b1;  // INTA
                        state <= S_INTA_ALE;
                    end
                    // Otherwise stay in HALT (s0=0, s1=0 already set)
                end

                // =============================================================
                // Interrupt Check - After instruction, check for pending IRQ
                // =============================================================
                S_INT_CHECK: begin
                    if (int_trap_active) begin
                        // TRAP has highest priority, is NMI
                        int_vector <= VEC_TRAP;
                        int_is_trap <= 1'b1;
                        int_is_intr <= 1'b0;
                        int_saved_pc <= core_pc;
                        int_saved_sp <= core_sp;
                        clear_trap <= 1'b1;
                        // Start push sequence
                        addr_out <= core_sp - 16'd1;  // SP-1 for high byte
                        ale_reg <= 1'b1;
                        io_m_reg <= 1'b0;
                        s0_reg <= 1'b1; s1_reg <= 1'b0;  // Memory write (int push)
                        state <= S_INT_PUSH_HI_ALE;
                    end else if (int_rst75_active) begin
                        int_vector <= VEC_RST75;
                        int_is_trap <= 1'b0;
                        int_is_intr <= 1'b0;
                        int_saved_pc <= core_pc;
                        int_saved_sp <= core_sp;
                        clear_rst75 <= 1'b1;
                        addr_out <= core_sp - 16'd1;
                        ale_reg <= 1'b1;
                        io_m_reg <= 1'b0;
                        s0_reg <= 1'b1; s1_reg <= 1'b0;  // Memory write (int push)
                        state <= S_INT_PUSH_HI_ALE;
                    end else if (int_rst65_active) begin
                        int_vector <= VEC_RST65;
                        int_is_trap <= 1'b0;
                        int_is_intr <= 1'b0;
                        int_saved_pc <= core_pc;
                        int_saved_sp <= core_sp;
                        addr_out <= core_sp - 16'd1;
                        ale_reg <= 1'b1;
                        io_m_reg <= 1'b0;
                        s0_reg <= 1'b1; s1_reg <= 1'b0;  // Memory write (int push)
                        state <= S_INT_PUSH_HI_ALE;
                    end else if (int_rst55_active) begin
                        int_vector <= VEC_RST55;
                        int_is_trap <= 1'b0;
                        int_is_intr <= 1'b0;
                        int_saved_pc <= core_pc;
                        int_saved_sp <= core_sp;
                        addr_out <= core_sp - 16'd1;
                        ale_reg <= 1'b1;
                        io_m_reg <= 1'b0;
                        s0_reg <= 1'b1; s1_reg <= 1'b0;  // Memory write (int push)
                        state <= S_INT_PUSH_HI_ALE;
                    end else if (int_intr_active) begin
                        // INTR needs INTA cycle
                        int_is_trap <= 1'b0;
                        int_is_intr <= 1'b1;
                        int_saved_pc <= core_pc;
                        int_saved_sp <= core_sp;
                        inta_reg <= 1'b0;  // Assert INTA
                        ale_reg <= 1'b1;
                        s0_reg <= 1'b1; s1_reg <= 1'b1;  // INTA
                        state <= S_INTA_ALE;
                    end else begin
                        // No interrupt pending, continue to IDLE
                        state <= S_IDLE;
                    end
                end

                // =============================================================
                // Interrupt Push Sequence (for TRAP, RST7.5, RST6.5, RST5.5)
                // =============================================================
                S_INT_PUSH_HI_ALE: begin
                    ale_reg <= 1'b0;
                    data_out <= int_saved_pc[15:8];  // PCH
                    data_out_en <= 1'b1;
                    wr_reg <= 1'b0;
                    state <= S_INT_PUSH_HI;
                end

                S_INT_PUSH_HI: begin
                    state <= S_INT_PUSH_HI_WAIT;
                end

                S_INT_PUSH_HI_WAIT: begin
                    if (ready) begin
                        wr_reg <= 1'b1;
                        data_out_en <= 1'b0;
                        // Now push low byte
                        addr_out <= int_saved_sp - 16'd2;  // SP-2 for low byte
                        ale_reg <= 1'b1;
                        s0_reg <= 1'b1; s1_reg <= 1'b0;  // Memory write (int push)
                        state <= S_INT_PUSH_LO_ALE;
                    end
                end

                S_INT_PUSH_LO_ALE: begin
                    ale_reg <= 1'b0;
                    data_out <= int_saved_pc[7:0];  // PCL
                    data_out_en <= 1'b1;
                    wr_reg <= 1'b0;
                    state <= S_INT_PUSH_LO;
                end

                S_INT_PUSH_LO: begin
                    state <= S_INT_PUSH_LO_WAIT;
                end

                S_INT_PUSH_LO_WAIT: begin
                    if (ready) begin
                        wr_reg <= 1'b1;
                        data_out_en <= 1'b0;
                        // Signal interrupt acknowledge - wrapper will:
                        // - Load int_vector into PC
                        // - Decrement SP by 2
                        // - Clear INTE (unless int_is_trap)
                        // - Clear halted flag
                        int_ack <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                // =============================================================
                // INTA Cycle (for INTR)
                // External device places instruction on bus during INTA
                // =============================================================
                S_INTA_ALE: begin
                    ale_reg <= 1'b0;
                    // Keep INTA asserted, read instruction from bus
                    rd_reg <= 1'b0;
                    state <= S_INTA;
                end

                S_INTA: begin
                    state <= S_INTA_WAIT;
                end

                S_INTA_WAIT: begin
                    if (ready) begin
                        // Read instruction from bus (usually RST n)
                        opcode_reg <= ad;
                        rd_reg <= 1'b1;
                        inta_reg <= 1'b1;  // Deassert INTA
                        // Execute the instruction - it will push PC and jump
                        // Go directly to execute (no more fetches needed for RST)
                        execute_pulse <= 1'b1;
                        state <= S_EXECUTE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Bus Output Logic
    // =========================================================================

    // AD bus is bidirectional
    assign ad = ale_reg ? addr_out[7:0] :
                data_out_en ? data_out :
                8'hZZ;

    // High address always output
    assign a_hi = addr_out[15:8];

    // Control signals
    assign ale = ale_reg;
    assign rd_n = rd_reg;
    assign wr_n = wr_reg;
    assign io_m_n = io_m_reg;
    assign inta_n = inta_reg;

    // Status signals (active during T1 when ALE high)
    // S1 S0: 00=Halt, 01=Write, 10=Read, 11=Fetch/INTA
    assign s0 = s0_reg;
    assign s1 = s1_reg;

    assign resout = ~reset_n;
    assign sod = core_sod;  // Serial output data from SIM instruction

    // =========================================================================
    // CPU Core Instance
    // =========================================================================

    i8085_wrapper core (
        .clk(clk),
        .reset_n(reset_n),

        // Memory Bus
        .mem_addr(core_mem_addr),
        .mem_data_in(mem_read_data),
        .mem_data_out(core_mem_data_out),
        .mem_rd(core_mem_rd),
        .mem_wr(core_mem_wr),

        // Stack Write Bus
        .stack_wr_addr(core_stack_wr_addr),
        .stack_wr_data_lo(core_stack_wr_lo),
        .stack_wr_data_hi(core_stack_wr_hi),
        .stack_wr(core_stack_wr),

        // I/O Bus
        .io_port(core_io_port),
        .io_data_out(core_io_data_out),
        .io_data_in(io_read_data),
        .io_rd(core_io_rd),
        .io_wr(core_io_wr),

        // Instruction input
        .opcode(opcode_reg),
        .imm1(imm1_reg),
        .imm2(imm2_reg),

        // Memory read data
        .mem_read_data(mem_read_data),

        // Stack read data
        .stack_lo(stack_lo),
        .stack_hi(stack_hi),

        // Control
        .execute(execute_pulse),

        // Interrupt control
        .int_ack(int_ack),
        .int_vector(int_vector),
        .int_is_trap(int_is_trap),

        // Interrupt inputs (directly wired to core for RIM)
        .sid(sid),
        .rst55_level(rst55),
        .rst65_level(rst65),

        // Status outputs
        .pc(core_pc),
        .sp(core_sp),
        .reg_a(core_reg_a),
        .reg_b(core_reg_b),
        .reg_c(core_reg_c),
        .reg_d(core_reg_d),
        .reg_e(core_reg_e),
        .reg_h(core_reg_h),
        .reg_l(core_reg_l),
        .halted(core_halted),
        .inte(core_inte),
        .flag_z(core_flag_z),
        .flag_c(core_flag_c),

        // Interrupt mask/status outputs
        .mask_55(core_mask_55),
        .mask_65(core_mask_65),
        .mask_75(core_mask_75),
        .rst75_pending(core_rst75_pending),
        .sod(core_sod)
    );

endmodule
