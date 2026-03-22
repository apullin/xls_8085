// i8085_core_opt.v - Optimized 8085 execute unit
// Hand-optimized from XLS output for LUT efficiency:
// - Single parity calculation (not 18 speculative)
// - Efficient opcode decode ROM
// - Register file via index + data (not one-hot mux)
//
// Interface change: register file is external (in wrapper)
// Core receives reg read data, outputs reg write addr/data

module i8085_core_opt (
    // Register file interface (replaces state[99:44])
    input  wire [7:0]  reg_src_data,    // Data from source register (sss field)
    input  wire [7:0]  reg_dst_data,    // Data from dest register (nnn field)
    input  wire [7:0]  reg_a,           // Accumulator (always needed)

    // Other state inputs
    input  wire [15:0] sp,
    input  wire [15:0] pc,
    input  wire [4:0]  flags,           // {sign, zero, aux, parity, carry}
    input  wire        halted,
    input  wire        inte,
    input  wire [2:0]  int_masks,       // {mask_55, mask_65, mask_75}
    input  wire        rst75_pending,
    input  wire        sod_latch,

    // Instruction inputs
    input  wire [7:0]  opcode,
    input  wire [7:0]  byte2,
    input  wire [7:0]  byte3,
    input  wire [7:0]  mem_read_data,   // Data from M (HL) location
    input  wire [7:0]  stack_read_lo,
    input  wire [7:0]  stack_read_hi,
    input  wire [7:0]  io_read_data,

    // External inputs
    input  wire        sid,
    input  wire        rst55_level,
    input  wire        rst65_level,

    // Register file write interface
    output wire [2:0]  reg_wr_idx,      // Which register to write (0-7, 7=A)
    output wire [7:0]  reg_wr_data,     // Data to write
    output wire        reg_wr_en,       // Write enable

    // Register pair outputs (for HL, BC, DE, SP updates)
    output wire [7:0]  reg_h_out,
    output wire [7:0]  reg_l_out,
    output wire        reg_hl_wr,
    output wire [7:0]  reg_b_out,
    output wire [7:0]  reg_c_out,
    output wire        reg_bc_wr,
    output wire [7:0]  reg_d_out,
    output wire [7:0]  reg_e_out,
    output wire        reg_de_wr,

    // Other state outputs
    output wire [15:0] sp_out,
    output wire        sp_wr,
    output wire [15:0] pc_out,
    output wire [4:0]  flags_out,
    output wire        halted_out,
    output wire        inte_out,
    output wire [2:0]  int_masks_out,
    output wire        rst75_pending_out,
    output wire        sod_latch_out,

    // Memory bus outputs
    output wire [15:0] mem_addr,
    output wire [7:0]  mem_data,
    output wire        mem_wr,

    // Stack bus outputs
    output wire [15:0] stack_addr,
    output wire [7:0]  stack_data_lo,
    output wire [7:0]  stack_data_hi,
    output wire        stack_wr,

    // I/O bus outputs
    output wire [7:0]  io_port,
    output wire [7:0]  io_data,
    output wire        io_rd,
    output wire        io_wr
);

    // =========================================================================
    // Opcode decode ROM - replaces individual comparisons
    // =========================================================================

    // Opcode fields
    wire [2:0] nnn = opcode[5:3];  // Destination register
    wire [2:0] sss = opcode[2:0];  // Source register
    wire [1:0] rp  = opcode[5:4];  // Register pair

    // Decode categories (one-hot)
    reg [31:0] op_cat;

    localparam CAT_NOP     = 0;
    localparam CAT_MOV     = 1;   // MOV r,r / MOV r,M / MOV M,r
    localparam CAT_MVI     = 2;   // MVI r,d8 / MVI M,d8
    localparam CAT_LXI     = 3;   // LXI rp,d16
    localparam CAT_LDA     = 4;   // LDA addr
    localparam CAT_STA     = 5;   // STA addr
    localparam CAT_LHLD    = 6;   // LHLD addr
    localparam CAT_SHLD    = 7;   // SHLD addr
    localparam CAT_LDAX    = 8;   // LDAX rp
    localparam CAT_STAX    = 9;   // STAX rp
    localparam CAT_XCHG    = 10;  // XCHG
    localparam CAT_ALU_R   = 11;  // ADD/ADC/SUB/SBB/ANA/XRA/ORA/CMP r
    localparam CAT_ALU_M   = 12;  // ADD/ADC/SUB/SBB/ANA/XRA/ORA/CMP M
    localparam CAT_ALU_I   = 13;  // ADI/ACI/SUI/SBI/ANI/XRI/ORI/CPI
    localparam CAT_INR     = 14;  // INR r/M
    localparam CAT_DCR     = 15;  // DCR r/M
    localparam CAT_INX     = 16;  // INX rp
    localparam CAT_DCX     = 17;  // DCX rp
    localparam CAT_DAD     = 18;  // DAD rp
    localparam CAT_DAA     = 19;  // DAA
    localparam CAT_ROT     = 20;  // RLC/RRC/RAL/RAR
    localparam CAT_CMA     = 21;  // CMA
    localparam CAT_CMC     = 22;  // CMC
    localparam CAT_STC     = 23;  // STC
    localparam CAT_JMP     = 24;  // JMP/Jcc
    localparam CAT_CALL    = 25;  // CALL/Ccc
    localparam CAT_RET     = 26;  // RET/Rcc
    localparam CAT_RST     = 27;  // RST n
    localparam CAT_PUSH    = 28;  // PUSH rp
    localparam CAT_POP     = 29;  // POP rp
    localparam CAT_IO      = 30;  // IN/OUT
    localparam CAT_MISC    = 31;  // HLT, EI, DI, RIM, SIM, etc.

    // Opcode decode - combinational ROM
    always @(*) begin
        op_cat = 32'b0;
        casez (opcode)
            8'b00000000: op_cat[CAT_NOP]   = 1'b1;  // NOP
            8'b01110110: op_cat[CAT_MISC]  = 1'b1;  // HLT
            8'b01??????: op_cat[CAT_MOV]   = 1'b1;  // MOV (except HLT)
            8'b00???110: op_cat[CAT_MVI]   = 1'b1;  // MVI
            8'b00??0001: op_cat[CAT_LXI]   = 1'b1;  // LXI
            8'b00111010: op_cat[CAT_LDA]   = 1'b1;  // LDA
            8'b00110010: op_cat[CAT_STA]   = 1'b1;  // STA
            8'b00101010: op_cat[CAT_LHLD]  = 1'b1;  // LHLD
            8'b00100010: op_cat[CAT_SHLD]  = 1'b1;  // SHLD
            8'b000?1010: op_cat[CAT_LDAX]  = 1'b1;  // LDAX B/D
            8'b000?0010: op_cat[CAT_STAX]  = 1'b1;  // STAX B/D
            8'b11101011: op_cat[CAT_XCHG]  = 1'b1;  // XCHG
            8'b10???110: op_cat[CAT_ALU_M] = 1'b1;  // ALU with M
            8'b10??????: op_cat[CAT_ALU_R] = 1'b1;  // ALU with r
            8'b11???110: op_cat[CAT_ALU_I] = 1'b1;  // ALU immediate
            8'b00???100: op_cat[CAT_INR]   = 1'b1;  // INR
            8'b00???101: op_cat[CAT_DCR]   = 1'b1;  // DCR
            8'b00??0011: op_cat[CAT_INX]   = 1'b1;  // INX
            8'b00??1011: op_cat[CAT_DCX]   = 1'b1;  // DCX
            8'b00??1001: op_cat[CAT_DAD]   = 1'b1;  // DAD
            8'b00100111: op_cat[CAT_DAA]   = 1'b1;  // DAA
            8'b000?0111: op_cat[CAT_ROT]   = 1'b1;  // RLC/RAL
            8'b000?1111: op_cat[CAT_ROT]   = 1'b1;  // RRC/RAR
            8'b00101111: op_cat[CAT_CMA]   = 1'b1;  // CMA
            8'b00111111: op_cat[CAT_CMC]   = 1'b1;  // CMC
            8'b00110111: op_cat[CAT_STC]   = 1'b1;  // STC
            8'b11000011: op_cat[CAT_JMP]   = 1'b1;  // JMP
            8'b11???010: op_cat[CAT_JMP]   = 1'b1;  // Jcc
            8'b11001101: op_cat[CAT_CALL]  = 1'b1;  // CALL
            8'b11???100: op_cat[CAT_CALL]  = 1'b1;  // Ccc
            8'b11001001: op_cat[CAT_RET]   = 1'b1;  // RET
            8'b11???000: op_cat[CAT_RET]   = 1'b1;  // Rcc
            8'b11???111: op_cat[CAT_RST]   = 1'b1;  // RST
            8'b11??0101: op_cat[CAT_PUSH]  = 1'b1;  // PUSH
            8'b11??0001: op_cat[CAT_POP]   = 1'b1;  // POP
            8'b11011011: op_cat[CAT_IO]    = 1'b1;  // IN
            8'b11010011: op_cat[CAT_IO]    = 1'b1;  // OUT
            default:     op_cat[CAT_MISC]  = 1'b1;  // EI, DI, RIM, SIM, XTHL, PCHL, SPHL
        endcase
    end

    // ALU operation decode (from opcode[5:3] for ALU ops)
    wire [2:0] alu_op = opcode[5:3];
    localparam ALU_ADD = 3'b000;
    localparam ALU_ADC = 3'b001;
    localparam ALU_SUB = 3'b010;
    localparam ALU_SBB = 3'b011;
    localparam ALU_ANA = 3'b100;
    localparam ALU_XRA = 3'b101;
    localparam ALU_ORA = 3'b110;
    localparam ALU_CMP = 3'b111;

    // =========================================================================
    // Flag extraction
    // =========================================================================

    wire f_sign   = flags[4];
    wire f_zero   = flags[3];
    wire f_aux    = flags[2];
    wire f_parity = flags[1];
    wire f_carry  = flags[0];

    // =========================================================================
    // Register/Memory source value selection
    // =========================================================================

    // Source value for ALU operations
    wire src_is_m = (sss == 3'b110);
    wire [7:0] src_val = src_is_m ? mem_read_data : reg_src_data;

    // Destination is M?
    wire dst_is_m = (nnn == 3'b110);

    // Value at destination (for INR/DCR)
    wire [7:0] dst_val = dst_is_m ? mem_read_data : reg_dst_data;

    // =========================================================================
    // ALU operations
    // =========================================================================

    wire [7:0] alu_b = (op_cat[CAT_ALU_I]) ? byte2 : src_val;

    // Adder/subtractor with carry
    wire alu_is_sub = (alu_op == ALU_SUB) | (alu_op == ALU_SBB) | (alu_op == ALU_CMP);
    wire alu_use_carry = (alu_op == ALU_ADC) | (alu_op == ALU_SBB);
    wire [7:0] alu_b_adj = alu_is_sub ? ~alu_b : alu_b;
    wire alu_cin = alu_is_sub ? (alu_use_carry ? ~f_carry : 1'b1)
                              : (alu_use_carry ? f_carry : 1'b0);
    wire [8:0] alu_sum = {1'b0, reg_a} + {1'b0, alu_b_adj} + {8'b0, alu_cin};
    wire [7:0] alu_add_result = alu_sum[7:0];
    wire alu_carry_out = alu_is_sub ? ~alu_sum[8] : alu_sum[8];

    // Aux carry (carry from bit 3 to 4)
    wire [4:0] alu_lo_sum = {1'b0, reg_a[3:0]} + {1'b0, alu_b_adj[3:0]} + {4'b0, alu_cin};
    wire alu_aux_carry = alu_lo_sum[4];

    // Logic operations
    wire [7:0] alu_and_result = reg_a & alu_b;
    wire [7:0] alu_xor_result = reg_a ^ alu_b;
    wire [7:0] alu_or_result  = reg_a | alu_b;

    // ALU result mux
    reg [7:0] alu_result;
    always @(*) begin
        case (alu_op)
            ALU_ADD, ALU_ADC, ALU_SUB, ALU_SBB, ALU_CMP: alu_result = alu_add_result;
            ALU_ANA: alu_result = alu_and_result;
            ALU_XRA: alu_result = alu_xor_result;
            ALU_ORA: alu_result = alu_or_result;
            default: alu_result = alu_add_result;
        endcase
    end

    // INR/DCR
    wire [8:0] inr_result = {1'b0, dst_val} + 9'd1;
    wire [8:0] dcr_result = {1'b0, dst_val} + 9'h1ff;  // +(-1)
    wire [4:0] inr_lo = {1'b0, dst_val[3:0]} + 5'd1;
    wire [4:0] dcr_lo = {1'b0, dst_val[3:0]} + 5'h1f;

    // =========================================================================
    // Single parity calculation (optimization: compute once on final result)
    // =========================================================================

    // Select which result needs parity
    wire [7:0] parity_input = op_cat[CAT_INR] ? inr_result[7:0] :
                              op_cat[CAT_DCR] ? dcr_result[7:0] :
                              alu_result;

    // Single parity XOR tree
    wire parity = ~(parity_input[0] ^ parity_input[1] ^ parity_input[2] ^ parity_input[3] ^
                    parity_input[4] ^ parity_input[5] ^ parity_input[6] ^ parity_input[7]);

    // =========================================================================
    // Rotate operations
    // =========================================================================

    wire [7:0] rlc_result = {reg_a[6:0], reg_a[7]};
    wire [7:0] rrc_result = {reg_a[0], reg_a[7:1]};
    wire [7:0] ral_result = {reg_a[6:0], f_carry};
    wire [7:0] rar_result = {f_carry, reg_a[7:1]};

    wire rot_carry = opcode[3] ? (opcode[4] ? reg_a[0] : reg_a[7])   // RRC/RLC
                               : (opcode[4] ? reg_a[0] : reg_a[7]);  // RAR/RAL

    reg [7:0] rot_result;
    always @(*) begin
        case (opcode[4:3])
            2'b00: rot_result = rlc_result;
            2'b01: rot_result = rrc_result;
            2'b10: rot_result = ral_result;
            2'b11: rot_result = rar_result;
            default: rot_result = reg_a;
        endcase
    end

    // =========================================================================
    // DAA (Decimal Adjust Accumulator)
    // =========================================================================

    wire daa_add_lo = (reg_a[3:0] > 4'h9) | f_aux;
    wire [7:0] daa_tmp = daa_add_lo ? (reg_a + 8'h06) : reg_a;
    wire daa_add_hi = (daa_tmp[7:4] > 4'h9) | f_carry;
    wire [7:0] daa_result = daa_add_hi ? (daa_tmp + 8'h60) : daa_tmp;
    wire daa_carry = f_carry | daa_add_hi;
    wire daa_aux = daa_add_lo;

    // =========================================================================
    // Condition code evaluation
    // =========================================================================

    reg cond_met;
    always @(*) begin
        case (opcode[5:3])
            3'b000: cond_met = ~f_zero;    // NZ
            3'b001: cond_met = f_zero;     // Z
            3'b010: cond_met = ~f_carry;   // NC
            3'b011: cond_met = f_carry;    // C
            3'b100: cond_met = ~f_parity;  // PO
            3'b101: cond_met = f_parity;   // PE
            3'b110: cond_met = ~f_sign;    // P
            3'b111: cond_met = f_sign;     // M
            default: cond_met = 1'b1;
        endcase
    end

    // =========================================================================
    // Register pair operations
    // =========================================================================

    // Current register pair value
    wire [15:0] rp_bc = {reg_b_out, reg_c_out};  // Will be wired from inputs
    wire [15:0] rp_de = {reg_d_out, reg_e_out};
    wire [15:0] rp_hl = {reg_h_out, reg_l_out};

    // For this optimized version, we need HL value for DAD, etc.
    // These will come from external register file reads

    // =========================================================================
    // Address calculations
    // =========================================================================

    wire [15:0] addr_imm16 = {byte3, byte2};
    wire [15:0] pc_plus_1 = pc + 16'd1;
    wire [15:0] pc_plus_2 = pc + 16'd2;
    wire [15:0] pc_plus_3 = pc + 16'd3;
    wire [15:0] sp_minus_2 = sp - 16'd2;
    wire [15:0] sp_plus_2 = sp + 16'd2;
    wire [15:0] rst_vector = {10'b0, nnn, 3'b0};

    // =========================================================================
    // RIM/SIM
    // =========================================================================

    wire [7:0] rim_result = {sid, rst75_pending, rst65_level, rst55_level,
                             inte, int_masks};

    wire sim_set_masks = byte2[3];
    wire sim_set_sod = byte2[6];
    wire sim_reset_75 = byte2[4];

    // =========================================================================
    // Output generation (simplified - full implementation would be larger)
    // =========================================================================

    // For now, output basic signals - full implementation would mirror XLS logic
    // This is a template showing the structure; complete implementation needed

    // PC output
    assign pc_out = halted ? pc :
                    op_cat[CAT_JMP] ? (opcode == 8'hC3 ? addr_imm16 : (cond_met ? addr_imm16 : pc_plus_3)) :
                    op_cat[CAT_CALL] ? (opcode == 8'hCD ? addr_imm16 : (cond_met ? addr_imm16 : pc_plus_3)) :
                    op_cat[CAT_RET] ? (opcode == 8'hC9 ? {stack_read_hi, stack_read_lo} :
                                      (cond_met ? {stack_read_hi, stack_read_lo} : pc_plus_1)) :
                    op_cat[CAT_RST] ? rst_vector :
                    (op_cat[CAT_LXI] | op_cat[CAT_LDA] | op_cat[CAT_STA] |
                     op_cat[CAT_LHLD] | op_cat[CAT_SHLD] | op_cat[CAT_ALU_I] |
                     op_cat[CAT_JMP] | op_cat[CAT_CALL]) ? pc_plus_3 :
                    op_cat[CAT_MVI] ? pc_plus_2 :
                    pc_plus_1;

    // Accumulator write (goes to reg index 7)
    wire a_wr = op_cat[CAT_ALU_R] | op_cat[CAT_ALU_M] | op_cat[CAT_ALU_I] |
                op_cat[CAT_ROT] | op_cat[CAT_CMA] | op_cat[CAT_DAA] |
                op_cat[CAT_LDA] | op_cat[CAT_LDAX] |
                (op_cat[CAT_MOV] & (nnn == 3'b111)) |
                (op_cat[CAT_MVI] & (nnn == 3'b111)) |
                (op_cat[CAT_INR] & (nnn == 3'b111)) |
                (op_cat[CAT_DCR] & (nnn == 3'b111)) |
                (op_cat[CAT_POP] & (rp == 2'b11)) |
                (opcode == 8'h20);  // RIM

    // Accumulator result
    wire [7:0] a_result = (op_cat[CAT_ALU_R] | op_cat[CAT_ALU_M] | op_cat[CAT_ALU_I]) ?
                          ((alu_op == ALU_CMP) ? reg_a : alu_result) :
                          op_cat[CAT_ROT] ? rot_result :
                          op_cat[CAT_CMA] ? ~reg_a :
                          op_cat[CAT_DAA] ? daa_result :
                          op_cat[CAT_LDA] ? mem_read_data :
                          op_cat[CAT_LDAX] ? mem_read_data :
                          op_cat[CAT_MOV] ? (src_is_m ? mem_read_data : reg_src_data) :
                          op_cat[CAT_MVI] ? byte2 :
                          op_cat[CAT_INR] ? inr_result[7:0] :
                          op_cat[CAT_DCR] ? dcr_result[7:0] :
                          (opcode == 8'h20) ? rim_result :  // RIM
                          reg_a;

    // Register write outputs
    assign reg_wr_idx = nnn;
    assign reg_wr_data = op_cat[CAT_MVI] ? byte2 :
                         op_cat[CAT_MOV] ? (src_is_m ? mem_read_data : reg_src_data) :
                         op_cat[CAT_INR] ? inr_result[7:0] :
                         op_cat[CAT_DCR] ? dcr_result[7:0] :
                         a_result;
    assign reg_wr_en = (op_cat[CAT_MOV] & ~dst_is_m) |
                       (op_cat[CAT_MVI] & ~dst_is_m) |
                       (op_cat[CAT_INR] & ~dst_is_m) |
                       (op_cat[CAT_DCR] & ~dst_is_m) |
                       a_wr;

    // Flags output
    wire update_flags = op_cat[CAT_ALU_R] | op_cat[CAT_ALU_M] | op_cat[CAT_ALU_I] |
                        op_cat[CAT_INR] | op_cat[CAT_DCR] | op_cat[CAT_DAA];

    wire new_sign = parity_input[7];
    wire new_zero = (parity_input == 8'h00);
    wire new_aux = op_cat[CAT_INR] ? inr_lo[4] :
                   op_cat[CAT_DCR] ? dcr_lo[4] :
                   op_cat[CAT_DAA] ? daa_aux :
                   alu_aux_carry;
    wire new_carry = op_cat[CAT_DAA] ? daa_carry :
                     op_cat[CAT_ROT] ? rot_carry :
                     op_cat[CAT_CMC] ? ~f_carry :
                     op_cat[CAT_STC] ? 1'b1 :
                     alu_carry_out;

    assign flags_out = update_flags ? {new_sign, new_zero, new_aux, parity, new_carry} :
                       op_cat[CAT_ROT] ? {f_sign, f_zero, f_aux, f_parity, rot_carry} :
                       op_cat[CAT_CMC] ? {f_sign, f_zero, f_aux, f_parity, ~f_carry} :
                       op_cat[CAT_STC] ? {f_sign, f_zero, f_aux, f_parity, 1'b1} :
                       op_cat[CAT_POP] & (rp == 2'b11) ?
                           {stack_read_lo[7], stack_read_lo[6], stack_read_lo[4],
                            stack_read_lo[2], stack_read_lo[0]} :
                       flags;

    // Halted output
    assign halted_out = (opcode == 8'h76) | halted;

    // INTE output
    assign inte_out = (opcode == 8'hFB) ? 1'b1 :  // EI
                      (opcode == 8'hF3) ? 1'b0 :  // DI
                      inte;

    // Interrupt masks output
    assign int_masks_out = (opcode == 8'h30 && byte2[3]) ?  // SIM with mask set
                           {byte2[0], byte2[1], byte2[2]} : int_masks;

    // RST 7.5 pending
    assign rst75_pending_out = (opcode == 8'h30 && byte2[4]) ? 1'b0 : rst75_pending;

    // SOD latch
    assign sod_latch_out = (opcode == 8'h30 && byte2[6]) ? byte2[7] : sod_latch;

    // SP output
    assign sp_out = op_cat[CAT_CALL] ? sp_minus_2 :
                    op_cat[CAT_RST] ? sp_minus_2 :
                    op_cat[CAT_PUSH] ? sp_minus_2 :
                    op_cat[CAT_RET] ? sp_plus_2 :
                    op_cat[CAT_POP] ? sp_plus_2 :
                    (opcode == 8'hF9) ? rp_hl :  // SPHL
                    sp;
    assign sp_wr = op_cat[CAT_CALL] | op_cat[CAT_RST] | op_cat[CAT_PUSH] |
                   op_cat[CAT_RET] | op_cat[CAT_POP] | (opcode == 8'hF9);

    // Memory interface (simplified)
    assign mem_addr = op_cat[CAT_STA] ? addr_imm16 :
                      op_cat[CAT_SHLD] ? addr_imm16 :
                      op_cat[CAT_STAX] ? (rp[0] ? rp_de : rp_bc) :
                      (op_cat[CAT_MOV] & dst_is_m) ? rp_hl :
                      (op_cat[CAT_MVI] & dst_is_m) ? rp_hl :
                      (op_cat[CAT_INR] & dst_is_m) ? rp_hl :
                      (op_cat[CAT_DCR] & dst_is_m) ? rp_hl :
                      16'h0000;

    assign mem_data = op_cat[CAT_STA] ? reg_a :
                      op_cat[CAT_STAX] ? reg_a :
                      op_cat[CAT_SHLD] ? reg_l_out :  // First byte
                      (op_cat[CAT_MOV] & dst_is_m) ? (src_is_m ? mem_read_data : reg_src_data) :
                      (op_cat[CAT_MVI] & dst_is_m) ? byte2 :
                      (op_cat[CAT_INR] & dst_is_m) ? inr_result[7:0] :
                      (op_cat[CAT_DCR] & dst_is_m) ? dcr_result[7:0] :
                      8'h00;

    assign mem_wr = op_cat[CAT_STA] | op_cat[CAT_SHLD] | op_cat[CAT_STAX] |
                    (op_cat[CAT_MOV] & dst_is_m) |
                    (op_cat[CAT_MVI] & dst_is_m) |
                    (op_cat[CAT_INR] & dst_is_m) |
                    (op_cat[CAT_DCR] & dst_is_m);

    // Stack interface
    assign stack_addr = sp_minus_2;
    assign stack_data_lo = op_cat[CAT_PUSH] ?
                           (rp == 2'b11 ? {f_sign, f_zero, 1'b0, f_aux, 1'b0, f_parity, 1'b1, f_carry} :
                            rp == 2'b00 ? reg_c_out :
                            rp == 2'b01 ? reg_e_out : reg_l_out) :
                           pc_plus_3[7:0];  // For CALL
    assign stack_data_hi = op_cat[CAT_PUSH] ?
                           (rp == 2'b11 ? reg_a :
                            rp == 2'b00 ? reg_b_out :
                            rp == 2'b01 ? reg_d_out : reg_h_out) :
                           pc_plus_3[15:8];  // For CALL
    assign stack_wr = op_cat[CAT_CALL] | op_cat[CAT_RST] | op_cat[CAT_PUSH];

    // I/O interface
    assign io_port = byte2;
    assign io_data = reg_a;
    assign io_rd = (opcode == 8'hDB);  // IN
    assign io_wr = (opcode == 8'hD3);  // OUT

    // Register pair outputs - these need external register file connection
    // For now, pass through (wrapper will handle actual register file)
    assign reg_h_out = 8'h00;  // Placeholder - wrapper provides actual values
    assign reg_l_out = 8'h00;
    assign reg_b_out = 8'h00;
    assign reg_c_out = 8'h00;
    assign reg_d_out = 8'h00;
    assign reg_e_out = 8'h00;
    assign reg_hl_wr = 1'b0;
    assign reg_bc_wr = 1'b0;
    assign reg_de_wr = 1'b0;

endmodule
