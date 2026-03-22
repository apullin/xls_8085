// Intel 8085 Top-Level for iCE40 with SPRAM
// Uses one SB_SPRAM256KA block (32KB = 16K x 16-bit)
// Address space: 0x0000-0x7FFF

module i8085_top (
    input  wire        clk,
    input  wire        reset_n,

    // Debug/status outputs
    output wire [15:0] debug_pc,
    output wire [7:0]  debug_a,
    output wire        debug_halted,

    // Optional external I/O
    output wire [7:0]  port_out,
    output wire        port_out_valid
);

    // =========================================================================
    // CPU State Registers
    // =========================================================================

    reg [7:0]  reg_b, reg_c, reg_d, reg_e, reg_h, reg_l, reg_a;
    reg [15:0] sp, pc;
    reg        flag_sign, flag_zero, flag_aux, flag_parity, flag_carry;
    reg        halted, inte;

    // Instruction buffer
    reg [7:0]  opcode, byte2, byte3;
    reg [7:0]  mem_read_data;
    reg [7:0]  stack_read_lo, stack_read_hi;

    // =========================================================================
    // SPRAM Interface
    // =========================================================================

    reg  [13:0] spram_addr;
    reg  [15:0] spram_wdata;
    reg  [3:0]  spram_maskwren;  // Byte enables: [3:2] for high byte, [1:0] for low byte
    reg         spram_wren;
    wire [15:0] spram_rdata;

    SB_SPRAM256KA spram (
        .ADDRESS(spram_addr),
        .DATAIN(spram_wdata),
        .MASKWREN(spram_maskwren),
        .WREN(spram_wren),
        .CHIPSELECT(1'b1),
        .CLOCK(clk),
        .STANDBY(1'b0),
        .SLEEP(1'b0),
        .POWEROFF(1'b1),
        .DATAOUT(spram_rdata)
    );

    // =========================================================================
    // State Machine
    // =========================================================================

    localparam S_FETCH1      = 4'd0;   // Fetch opcode (and possibly byte2)
    localparam S_FETCH2      = 4'd1;   // Fetch byte2/byte3 if needed
    localparam S_READ_MEM    = 4'd2;   // Read from (HL) if needed
    localparam S_READ_STACK1 = 4'd3;   // Read stack low byte
    localparam S_READ_STACK2 = 4'd4;   // Read stack high byte
    localparam S_EXECUTE     = 4'd5;   // Execute instruction
    localparam S_WRITE_MEM   = 4'd6;   // Write to memory if needed
    localparam S_HALTED      = 4'd7;   // CPU halted

    reg [3:0] state;
    reg [2:0] inst_len;  // 1, 2, or 3 bytes
    reg       needs_mem_read;
    reg       needs_stack_read;

    // =========================================================================
    // Instruction Length Decoder (simple version)
    // =========================================================================

    function [2:0] get_inst_length;
        input [7:0] op;
        begin
            casez (op)
                // 3-byte instructions
                8'b00??0001: get_inst_length = 3'd3;  // LXI
                8'b11000011: get_inst_length = 3'd3;  // JMP
                8'b11??0010: get_inst_length = 3'd3;  // Jcond
                8'b11001101: get_inst_length = 3'd3;  // CALL
                8'b11??0100: get_inst_length = 3'd3;  // Ccond
                8'b00110010: get_inst_length = 3'd3;  // STA
                8'b00111010: get_inst_length = 3'd3;  // LDA
                8'b00100010: get_inst_length = 3'd3;  // SHLD
                8'b00101010: get_inst_length = 3'd3;  // LHLD

                // 2-byte instructions
                8'b00???110: get_inst_length = 3'd2;  // MVI
                8'b11???110: get_inst_length = 3'd2;  // immediate ALU (ADI, SUI, etc)
                8'b11011011: get_inst_length = 3'd2;  // IN
                8'b11010011: get_inst_length = 3'd2;  // OUT

                // 1-byte instructions (default)
                default:     get_inst_length = 3'd1;
            endcase
        end
    endfunction

    // Check if instruction needs memory read at (HL)
    function needs_hl_read;
        input [7:0] op;
        begin
            casez (op)
                8'b01???110: needs_hl_read = 1'b1;  // MOV r,M
                8'b10???110: needs_hl_read = 1'b1;  // ALU with M (ADD M, SUB M, etc)
                8'b00110100: needs_hl_read = 1'b1;  // INR M
                8'b00110101: needs_hl_read = 1'b1;  // DCR M
                default:     needs_hl_read = 1'b0;
            endcase
        end
    endfunction

    // Check if instruction needs stack read
    function needs_stack;
        input [7:0] op;
        begin
            casez (op)
                8'b11001001: needs_stack = 1'b1;  // RET
                8'b11???000: needs_stack = 1'b1;  // Rcond
                8'b11??0001: needs_stack = 1'b1;  // POP
                default:     needs_stack = 1'b0;
            endcase
        end
    endfunction

    // =========================================================================
    // CPU Core Instance
    // =========================================================================

    // XLS tuple packing: first field in LSBs
    // State[94:0]:
    //   [7:0]   = reg_b
    //   [15:8]  = reg_c
    //   [23:16] = reg_d
    //   [31:24] = reg_e
    //   [39:32] = reg_h
    //   [47:40] = reg_l
    //   [55:48] = reg_a
    //   [71:56] = sp
    //   [87:72] = pc
    //   [88]    = flag_sign
    //   [89]    = flag_zero
    //   [90]    = flag_aux
    //   [91]    = flag_parity
    //   [92]    = flag_carry
    //   [93]    = halted
    //   [94]    = inte

    wire [94:0] cpu_state_in = {
        inte,
        halted,
        flag_carry, flag_parity, flag_aux, flag_zero, flag_sign,
        pc,
        sp,
        reg_a,
        reg_l,
        reg_h,
        reg_e,
        reg_d,
        reg_c,
        reg_b
    };

    wire [119:0] cpu_out;

    __i8085_core__execute cpu_core (
        .state(cpu_state_in),
        .opcode(opcode),
        .byte2(byte2),
        .byte3(byte3),
        .mem_read_data(mem_read_data),
        .stack_read_lo(stack_read_lo),
        .stack_read_hi(stack_read_hi),
        .out(cpu_out)
    );

    // Unpack CPU output - state is [94:0], MemBusOut is [119:95]
    wire [7:0]  new_reg_b     = cpu_out[7:0];
    wire [7:0]  new_reg_c     = cpu_out[15:8];
    wire [7:0]  new_reg_d     = cpu_out[23:16];
    wire [7:0]  new_reg_e     = cpu_out[31:24];
    wire [7:0]  new_reg_h     = cpu_out[39:32];
    wire [7:0]  new_reg_l     = cpu_out[47:40];
    wire [7:0]  new_reg_a     = cpu_out[55:48];
    wire [15:0] new_sp        = cpu_out[71:56];
    wire [15:0] new_pc        = cpu_out[87:72];
    wire        new_flag_sign = cpu_out[88];
    wire        new_flag_zero = cpu_out[89];
    wire        new_flag_aux  = cpu_out[90];
    wire        new_flag_parity = cpu_out[91];
    wire        new_flag_carry = cpu_out[92];
    wire        new_halted    = cpu_out[93];
    wire        new_inte      = cpu_out[94];

    // MemBusOut: (addr[16], data[8], write_enable[1])
    wire [15:0] mem_write_addr = cpu_out[110:95];
    wire [7:0]  mem_write_data = cpu_out[118:111];
    wire        mem_write_en   = cpu_out[119];

    // =========================================================================
    // Main State Machine
    // =========================================================================

    wire [15:0] hl = {reg_h, reg_l};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // Reset CPU state
            reg_b <= 8'h00; reg_c <= 8'h00;
            reg_d <= 8'h00; reg_e <= 8'h00;
            reg_h <= 8'h00; reg_l <= 8'h00;
            reg_a <= 8'h00;
            sp <= 16'hFFFF;
            pc <= 16'h0000;
            flag_sign <= 1'b0; flag_zero <= 1'b0;
            flag_aux <= 1'b0; flag_parity <= 1'b0; flag_carry <= 1'b0;
            halted <= 1'b0;
            inte <= 1'b0;

            // Reset instruction buffer
            opcode <= 8'h00;
            byte2 <= 8'h00;
            byte3 <= 8'h00;
            mem_read_data <= 8'h00;
            stack_read_lo <= 8'h00;
            stack_read_hi <= 8'h00;

            // Reset state machine
            state <= S_FETCH1;
            inst_len <= 3'd1;
            needs_mem_read <= 1'b0;
            needs_stack_read <= 1'b0;

            // SPRAM signals
            spram_addr <= 14'd0;
            spram_wdata <= 16'd0;
            spram_maskwren <= 4'b0000;
            spram_wren <= 1'b0;

        end else begin
            // Default: no write
            spram_wren <= 1'b0;
            spram_maskwren <= 4'b0000;

            case (state)
                S_FETCH1: begin
                    if (halted) begin
                        state <= S_HALTED;
                    end else begin
                        // Read 16 bits starting at PC (gets opcode and possibly byte2)
                        spram_addr <= pc[14:1];
                        state <= S_FETCH2;
                    end
                end

                S_FETCH2: begin
                    // Capture fetched bytes
                    if (pc[0] == 1'b0) begin
                        opcode <= spram_rdata[7:0];
                        byte2 <= spram_rdata[15:8];
                    end else begin
                        opcode <= spram_rdata[15:8];
                        // byte2 is at next word, need another fetch
                        byte2 <= 8'h00;  // Will be fetched if needed
                    end

                    // Determine instruction properties
                    inst_len <= get_inst_length(pc[0] ? spram_rdata[15:8] : spram_rdata[7:0]);
                    needs_mem_read <= needs_hl_read(pc[0] ? spram_rdata[15:8] : spram_rdata[7:0]);
                    needs_stack_read <= needs_stack(pc[0] ? spram_rdata[15:8] : spram_rdata[7:0]);

                    // If we need more bytes or byte2 wasn't in this word
                    if (pc[0] == 1'b1 || get_inst_length(pc[0] ? spram_rdata[15:8] : spram_rdata[7:0]) == 3'd3) begin
                        // Fetch next word for remaining bytes
                        spram_addr <= pc[14:1] + 14'd1;
                        state <= S_READ_MEM;  // Reusing this state for byte fetch
                    end else if (needs_hl_read(pc[0] ? spram_rdata[15:8] : spram_rdata[7:0])) begin
                        spram_addr <= hl[14:1];
                        state <= S_READ_MEM;
                    end else if (needs_stack(pc[0] ? spram_rdata[15:8] : spram_rdata[7:0])) begin
                        spram_addr <= sp[14:1];
                        state <= S_READ_STACK1;
                    end else begin
                        state <= S_EXECUTE;
                    end
                end

                S_READ_MEM: begin
                    // This state handles both remaining instruction bytes and (HL) read
                    // For simplicity, assume we're reading (HL) here
                    if (hl[0] == 1'b0) begin
                        mem_read_data <= spram_rdata[7:0];
                    end else begin
                        mem_read_data <= spram_rdata[15:8];
                    end

                    if (needs_stack_read) begin
                        spram_addr <= sp[14:1];
                        state <= S_READ_STACK1;
                    end else begin
                        state <= S_EXECUTE;
                    end
                end

                S_READ_STACK1: begin
                    // Read SP and SP+1
                    if (sp[0] == 1'b0) begin
                        stack_read_lo <= spram_rdata[7:0];
                        stack_read_hi <= spram_rdata[15:8];
                        state <= S_EXECUTE;
                    end else begin
                        stack_read_lo <= spram_rdata[15:8];
                        // Need to fetch SP+1 from next word
                        spram_addr <= sp[14:1] + 14'd1;
                        state <= S_READ_STACK2;
                    end
                end

                S_READ_STACK2: begin
                    stack_read_hi <= spram_rdata[7:0];
                    state <= S_EXECUTE;
                end

                S_EXECUTE: begin
                    // Update CPU state from core output
                    reg_b <= new_reg_b; reg_c <= new_reg_c;
                    reg_d <= new_reg_d; reg_e <= new_reg_e;
                    reg_h <= new_reg_h; reg_l <= new_reg_l;
                    reg_a <= new_reg_a;
                    sp <= new_sp;
                    pc <= new_pc;
                    flag_sign <= new_flag_sign;
                    flag_zero <= new_flag_zero;
                    flag_aux <= new_flag_aux;
                    flag_parity <= new_flag_parity;
                    flag_carry <= new_flag_carry;
                    halted <= new_halted;
                    inte <= new_inte;

                    // Handle memory write if needed
                    if (mem_write_en) begin
                        spram_addr <= mem_write_addr[14:1];
                        spram_wdata <= {mem_write_data, mem_write_data};  // Duplicate for byte select
                        spram_wren <= 1'b1;
                        if (mem_write_addr[0] == 1'b0) begin
                            spram_maskwren <= 4'b0011;  // Write low byte
                        end else begin
                            spram_maskwren <= 4'b1100;  // Write high byte
                        end
                        state <= S_WRITE_MEM;
                    end else begin
                        state <= S_FETCH1;
                    end
                end

                S_WRITE_MEM: begin
                    spram_wren <= 1'b0;
                    state <= S_FETCH1;
                end

                S_HALTED: begin
                    // Stay halted until reset
                    state <= S_HALTED;
                end

                default: begin
                    state <= S_FETCH1;
                end
            endcase
        end
    end

    // =========================================================================
    // Debug Outputs
    // =========================================================================

    assign debug_pc = pc;
    assign debug_a = reg_a;
    assign debug_halted = halted;

    // Stub for port output (could be memory-mapped I/O)
    assign port_out = 8'h00;
    assign port_out_valid = 1'b0;

endmodule
