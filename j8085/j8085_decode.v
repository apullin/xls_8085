// j8085_decode.v - Combinational instruction decoder for j8085 pipeline
//
// Decodes 8085 opcode byte into pipeline control signals.
// All outputs are combinational (valid same cycle as opcode input).
//
// Structured for incremental extension: each phase adds new instruction
// patterns to the casez blocks.

`timescale 1ns / 1ps

module j8085_decode (
    input  wire [7:0]  opcode,

    // Instruction length (1, 2, or 3 bytes)
    output reg  [1:0]  inst_len,

    // ALU control
    output reg  [3:0]  alu_op,
    output reg         alu_use_imm,      // Operand B is immediate (byte2)
    output reg         alu_use_a,        // Operand A is accumulator

    // Register select (8085 encoding: 000=B,001=C,010=D,011=E,100=H,101=L,110=M,111=A)
    output reg  [2:0]  src_sel,          // Source register (for ALU/MOV source)
    output reg  [2:0]  dst_sel,          // Destination register (for writeback)
    output reg  [1:0]  rp_sel,           // Register pair select (00=BC,01=DE,10=HL,11=SP/PSW)

    // Write enables
    output reg         writes_reg,       // Writes to dst_sel register
    output reg         writes_flags,     // Updates flags
    output reg  [6:0]  flag_mask,        // Which flags to update [V,X5,S,Z,AC,P,CY]

    // Instruction type
    output reg         is_nop,
    output reg         is_hlt,
    output reg         is_mov,           // MOV r,r
    output reg         is_mvi,           // MVI r,imm
    output reg         is_alu_reg,       // ALU with register operand
    output reg         is_alu_imm,       // ALU with immediate operand (ADI, SUI, etc.)
    output reg         is_inr,           // INR r
    output reg         is_dcr,           // DCR r

    // Memory access
    output reg         is_load,          // Read from memory
    output reg         is_store,         // Write to memory
    output reg         needs_hl_read,    // MOV r,M / ALU M / INR M / DCR M
    output reg         needs_bc_read,    // LDAX B
    output reg         needs_de_read,    // LDAX D
    output reg         needs_direct_read,// LDA, LHLD
    output reg         needs_stack_read, // POP, RET, XTHL

    // Branch
    output reg         is_jmp,           // Unconditional jump
    output reg         is_jcc,           // Conditional jump
    output reg  [2:0]  branch_cond,      // Condition code (NZ=0,Z=1,NC=2,C=3,PO=4,PE=5,P=6,M=7)
    output reg         is_call,
    output reg         is_ccc,           // Conditional call
    output reg         is_ret,
    output reg         is_rcc,           // Conditional return
    output reg         is_rst,           // RST n
    output reg         is_pchl,

    // Stack
    output reg         is_push,
    output reg         is_pop,
    output reg         is_xthl,
    output reg         is_sphl,

    // 16-bit operations
    output reg         is_lxi,           // LXI rp, imm16
    output reg         is_inx,           // INX rp
    output reg         is_dcx,           // DCX rp
    output reg         is_dad,           // DAD rp
    output reg         is_xchg,          // XCHG

    // I/O
    output reg         is_io_in,
    output reg         is_io_out,

    // Special
    output reg         is_ei,
    output reg         is_di,
    output reg         is_rim,
    output reg         is_sim,
    output reg         is_stc,           // STC
    output reg         is_cmc,           // CMC
    output reg         is_cma,           // CMA

    // Direct address load/store
    output reg         is_sta,
    output reg         is_lda,
    output reg         is_shld,
    output reg         is_lhld,
    output reg         is_stax,
    output reg         is_ldax,

    // Undocumented 8085
    output reg         is_dsub,          // HL -= BC
    output reg         is_arhl,          // Arithmetic shift right HL
    output reg         is_rdel,          // Rotate DE left through carry
    output reg         is_ldhi,          // DE = HL + imm8
    output reg         is_ldsi,          // DE = SP + imm8
    output reg         is_shlx,          // (DE) = HL
    output reg         is_lhlx,          // HL = (DE)
    output reg         is_rstv,          // RST 8 if V
    output reg         is_jnx5,          // Jump if not X5
    output reg         is_jx5            // Jump if X5
);

    // ALU operation codes (must match j8085_alu.v)
    localparam ALU_ADD  = 4'd0;
    localparam ALU_ADC  = 4'd1;
    localparam ALU_SUB  = 4'd2;
    localparam ALU_SBB  = 4'd3;
    localparam ALU_ANA  = 4'd4;
    localparam ALU_XRA  = 4'd5;
    localparam ALU_ORA  = 4'd6;
    localparam ALU_CMP  = 4'd7;
    localparam ALU_INC  = 4'd8;
    localparam ALU_DEC  = 4'd9;
    localparam ALU_RLC  = 4'd10;
    localparam ALU_RRC  = 4'd11;
    localparam ALU_RAL  = 4'd12;
    localparam ALU_RAR  = 4'd13;
    localparam ALU_DAA  = 4'd14;
    localparam ALU_PASS = 4'd15;

    // All-flags mask: {V,X5,S,Z,AC,P,CY}
    localparam FLAGS_ALL  = 7'b1011111;   // V,S,Z,AC,P,CY (not X5)
    localparam FLAGS_NOCY = 7'b1011110;   // V,S,Z,AC,P (INR/DCR don't touch CY)
    localparam FLAGS_NONE = 7'b0000000;
    localparam FLAGS_CY   = 7'b0000001;   // CY only (rotates, STC, CMC)

    always @(*) begin
        // ============================================================
        // Defaults: NOP-like behavior
        // ============================================================
        inst_len        = 2'd1;
        alu_op          = ALU_PASS;
        alu_use_imm     = 1'b0;
        alu_use_a       = 1'b0;
        src_sel         = opcode[2:0];   // sss field
        dst_sel         = opcode[5:3];   // ddd field
        rp_sel          = opcode[5:4];   // rp field
        writes_reg      = 1'b0;
        writes_flags    = 1'b0;
        flag_mask       = FLAGS_NONE;
        is_nop          = 1'b0;
        is_hlt          = 1'b0;
        is_mov          = 1'b0;
        is_mvi          = 1'b0;
        is_alu_reg      = 1'b0;
        is_alu_imm      = 1'b0;
        is_inr          = 1'b0;
        is_dcr          = 1'b0;
        is_load         = 1'b0;
        is_store        = 1'b0;
        needs_hl_read   = 1'b0;
        needs_bc_read   = 1'b0;
        needs_de_read   = 1'b0;
        needs_direct_read = 1'b0;
        needs_stack_read  = 1'b0;
        is_jmp          = 1'b0;
        is_jcc          = 1'b0;
        branch_cond     = opcode[5:3];
        is_call         = 1'b0;
        is_ccc          = 1'b0;
        is_ret          = 1'b0;
        is_rcc          = 1'b0;
        is_rst          = 1'b0;
        is_pchl         = 1'b0;
        is_push         = 1'b0;
        is_pop          = 1'b0;
        is_xthl         = 1'b0;
        is_sphl         = 1'b0;
        is_lxi          = 1'b0;
        is_inx          = 1'b0;
        is_dcx          = 1'b0;
        is_dad          = 1'b0;
        is_xchg         = 1'b0;
        is_io_in        = 1'b0;
        is_io_out       = 1'b0;
        is_ei           = 1'b0;
        is_di           = 1'b0;
        is_rim          = 1'b0;
        is_sim          = 1'b0;
        is_stc          = 1'b0;
        is_cmc          = 1'b0;
        is_cma          = 1'b0;
        is_sta          = 1'b0;
        is_lda          = 1'b0;
        is_shld         = 1'b0;
        is_lhld         = 1'b0;
        is_stax         = 1'b0;
        is_ldax         = 1'b0;
        is_dsub         = 1'b0;
        is_arhl         = 1'b0;
        is_rdel         = 1'b0;
        is_ldhi         = 1'b0;
        is_ldsi         = 1'b0;
        is_shlx         = 1'b0;
        is_lhlx         = 1'b0;
        is_rstv         = 1'b0;
        is_jnx5         = 1'b0;
        is_jx5          = 1'b0;

        // ============================================================
        // Instruction decode
        // ============================================================
        casez (opcode)

            // ── NOP (and undocumented NOPs) ─────────────────────────
            8'h00: begin
                is_nop = 1'b1;
            end

            // ── HLT ────────────────────────────────────────────────
            8'h76: begin
                is_hlt = 1'b1;
            end

            // ── MOV r, r  (01 ddd sss, except 76=HLT) ──────────────
            8'b01??????: begin
                if (opcode[2:0] == 3'b110) begin
                    // MOV r, M — load from (HL)
                    is_load = 1'b1;
                    needs_hl_read = 1'b1;
                    writes_reg = 1'b1;
                    alu_op = ALU_PASS;
                end else if (opcode[5:3] == 3'b110) begin
                    // MOV M, r — store to (HL)
                    is_store = 1'b1;
                end else begin
                    // MOV r, r — register to register
                    is_mov = 1'b1;
                    writes_reg = 1'b1;
                    alu_op = ALU_PASS;
                end
            end

            // ── MVI r, imm  (00 ddd 110) ───────────────────────────
            8'b00???110: begin
                inst_len = 2'd2;
                is_mvi = 1'b1;
                dst_sel = opcode[5:3];
                alu_op = ALU_PASS;
                alu_use_imm = 1'b1;
                if (opcode[5:3] == 3'b110) begin
                    // MVI M, imm — store immediate to (HL)
                    is_store = 1'b1;
                end else begin
                    writes_reg = 1'b1;
                end
            end

            // ── ALU register  (10 ooo sss) ─────────────────────────
            8'b10??????: begin
                is_alu_reg = 1'b1;
                alu_use_a = 1'b1;
                writes_flags = 1'b1;
                flag_mask = FLAGS_ALL;
                dst_sel = 3'b111;  // Result always goes to A
                case (opcode[5:3])
                    3'b000: alu_op = ALU_ADD;
                    3'b001: alu_op = ALU_ADC;
                    3'b010: alu_op = ALU_SUB;
                    3'b011: alu_op = ALU_SBB;
                    3'b100: alu_op = ALU_ANA;
                    3'b101: alu_op = ALU_XRA;
                    3'b110: alu_op = ALU_ORA;
                    3'b111: alu_op = ALU_CMP;
                endcase
                if (opcode[5:3] != 3'b111)  // CMP doesn't write A
                    writes_reg = 1'b1;
                if (opcode[2:0] == 3'b110) begin
                    // ALU M — operand from (HL)
                    is_load = 1'b1;
                    needs_hl_read = 1'b1;
                end
            end

            // ── ALU immediate  (11 ooo 110) ────────────────────────
            8'b11???110: begin
                inst_len = 2'd2;
                is_alu_imm = 1'b1;
                alu_use_a = 1'b1;
                alu_use_imm = 1'b1;
                writes_flags = 1'b1;
                flag_mask = FLAGS_ALL;
                dst_sel = 3'b111;  // A
                case (opcode[5:3])
                    3'b000: alu_op = ALU_ADD;  // ADI
                    3'b001: alu_op = ALU_ADC;  // ACI
                    3'b010: alu_op = ALU_SUB;  // SUI
                    3'b011: alu_op = ALU_SBB;  // SBI
                    3'b100: alu_op = ALU_ANA;  // ANI
                    3'b101: alu_op = ALU_XRA;  // XRI
                    3'b110: alu_op = ALU_ORA;  // ORI
                    3'b111: alu_op = ALU_CMP;  // CPI
                endcase
                if (opcode[5:3] != 3'b111)
                    writes_reg = 1'b1;
            end

            // ── INR r  (00 ddd 100) ────────────────────────────────
            8'b00???100: begin
                is_inr = 1'b1;
                alu_op = ALU_INC;
                writes_flags = 1'b1;
                flag_mask = FLAGS_NOCY;
                dst_sel = opcode[5:3];
                src_sel = opcode[5:3];  // Source = same register
                if (opcode[5:3] == 3'b110) begin
                    is_load = 1'b1;
                    is_store = 1'b1;
                    needs_hl_read = 1'b1;
                end else begin
                    writes_reg = 1'b1;
                end
            end

            // ── DCR r  (00 ddd 101) ────────────────────────────────
            8'b00???101: begin
                is_dcr = 1'b1;
                alu_op = ALU_DEC;
                writes_flags = 1'b1;
                flag_mask = FLAGS_NOCY;
                dst_sel = opcode[5:3];
                src_sel = opcode[5:3];
                if (opcode[5:3] == 3'b110) begin
                    is_load = 1'b1;
                    is_store = 1'b1;
                    needs_hl_read = 1'b1;
                end else begin
                    writes_reg = 1'b1;
                end
            end

            // ── Rotate instructions ────────────────────────────────
            8'h07: begin alu_op = ALU_RLC; writes_reg = 1'b1; writes_flags = 1'b1;
                         flag_mask = FLAGS_CY; dst_sel = 3'b111; alu_use_a = 1'b1; end
            8'h0F: begin alu_op = ALU_RRC; writes_reg = 1'b1; writes_flags = 1'b1;
                         flag_mask = FLAGS_CY; dst_sel = 3'b111; alu_use_a = 1'b1; end
            8'h17: begin alu_op = ALU_RAL; writes_reg = 1'b1; writes_flags = 1'b1;
                         flag_mask = FLAGS_CY; dst_sel = 3'b111; alu_use_a = 1'b1; end
            8'h1F: begin alu_op = ALU_RAR; writes_reg = 1'b1; writes_flags = 1'b1;
                         flag_mask = FLAGS_CY; dst_sel = 3'b111; alu_use_a = 1'b1; end

            // ── DAA ────────────────────────────────────────────────
            8'h27: begin alu_op = ALU_DAA; writes_reg = 1'b1; writes_flags = 1'b1;
                         flag_mask = FLAGS_ALL; dst_sel = 3'b111; alu_use_a = 1'b1; end

            // ── CMA ────────────────────────────────────────────────
            8'h2F: begin is_cma = 1'b1; writes_reg = 1'b1; dst_sel = 3'b111;
                         alu_use_a = 1'b1; end

            // ── STC ────────────────────────────────────────────────
            8'h37: begin is_stc = 1'b1; writes_flags = 1'b1; flag_mask = FLAGS_CY; end

            // ── CMC ────────────────────────────────────────────────
            8'h3F: begin is_cmc = 1'b1; writes_flags = 1'b1; flag_mask = FLAGS_CY; end

            // ── LXI rp, imm16  (00 rp 0001) ───────────────────────
            8'b00??0001: begin
                inst_len = 2'd3;
                is_lxi = 1'b1;
            end

            // ── INX rp  (00 rp 0011) ──────────────────────────────
            8'b00??0011: begin is_inx = 1'b1; end

            // ── DCX rp  (00 rp 1011) ──────────────────────────────
            8'b00??1011: begin is_dcx = 1'b1; end

            // ── DAD rp  (00 rp 1001) ──────────────────────────────
            8'b00??1001: begin
                is_dad = 1'b1;
                writes_flags = 1'b1;
                flag_mask = FLAGS_CY;
            end

            // ── STAX B/D  (00 rp 0010, rp=0 or 1) ─────────────────
            8'h02: begin is_stax = 1'b1; is_store = 1'b1; rp_sel = 2'b00; src_sel = 3'd7; end
            8'h12: begin is_stax = 1'b1; is_store = 1'b1; rp_sel = 2'b01; src_sel = 3'd7; end

            // ── LDAX B/D  (00 rp 1010, rp=0 or 1) ─────────────────
            8'h0A: begin is_ldax = 1'b1; is_load = 1'b1; needs_bc_read = 1'b1;
                         writes_reg = 1'b1; dst_sel = 3'b111; end
            8'h1A: begin is_ldax = 1'b1; is_load = 1'b1; needs_de_read = 1'b1;
                         writes_reg = 1'b1; dst_sel = 3'b111; end

            // ── STA addr  (32) ─────────────────────────────────────
            8'h32: begin inst_len = 2'd3; is_sta = 1'b1; is_store = 1'b1; src_sel = 3'd7; end

            // ── LDA addr  (3A) ─────────────────────────────────────
            8'h3A: begin inst_len = 2'd3; is_lda = 1'b1; is_load = 1'b1;
                         needs_direct_read = 1'b1; writes_reg = 1'b1; dst_sel = 3'b111; end

            // ── SHLD addr  (22) ────────────────────────────────────
            8'h22: begin inst_len = 2'd3; is_shld = 1'b1; is_store = 1'b1; end

            // ── LHLD addr  (2A) ────────────────────────────────────
            8'h2A: begin inst_len = 2'd3; is_lhld = 1'b1; is_load = 1'b1;
                         needs_direct_read = 1'b1; end

            // ── JMP  (C3) ──────────────────────────────────────────
            8'hC3: begin inst_len = 2'd3; is_jmp = 1'b1; end

            // ── Jcc  (11 ccc 010) ──────────────────────────────────
            8'b11???010: begin
                inst_len = 2'd3;
                is_jcc = 1'b1;
                branch_cond = opcode[5:3];
            end

            // ── CALL  (CD) ─────────────────────────────────────────
            8'hCD: begin inst_len = 2'd3; is_call = 1'b1; end

            // ── Ccc  (11 ccc 100) ──────────────────────────────────
            8'b11???100: begin
                inst_len = 2'd3;
                is_ccc = 1'b1;
                branch_cond = opcode[5:3];
            end

            // ── RET  (C9) ──────────────────────────────────────────
            8'hC9: begin is_ret = 1'b1; needs_stack_read = 1'b1; end

            // ── Rcc  (11 ccc 000) ──────────────────────────────────
            8'b11???000: begin
                is_rcc = 1'b1;
                branch_cond = opcode[5:3];
                needs_stack_read = 1'b1;
            end

            // ── RST n  (11 nnn 111) ────────────────────────────────
            8'b11???111: begin is_rst = 1'b1; end

            // ── PCHL  (E9) ─────────────────────────────────────────
            8'hE9: begin is_pchl = 1'b1; end

            // ── PUSH rp  (11 rp 0101) ──────────────────────────────
            8'b11??0101: begin is_push = 1'b1; end

            // ── POP rp  (11 rp 0001) ───────────────────────────────
            8'b11??0001: begin is_pop = 1'b1; needs_stack_read = 1'b1; end

            // ── XTHL  (E3) ─────────────────────────────────────────
            8'hE3: begin is_xthl = 1'b1; needs_stack_read = 1'b1; end

            // ── SPHL  (F9) ─────────────────────────────────────────
            8'hF9: begin is_sphl = 1'b1; end

            // ── XCHG  (EB) ─────────────────────────────────────────
            8'hEB: begin is_xchg = 1'b1; end

            // ── IN port  (DB) ──────────────────────────────────────
            8'hDB: begin inst_len = 2'd2; is_io_in = 1'b1; writes_reg = 1'b1;
                         dst_sel = 3'b111; end

            // ── OUT port  (D3) ─────────────────────────────────────
            8'hD3: begin inst_len = 2'd2; is_io_out = 1'b1; end

            // ── EI  (FB) ──────────────────────────────────────────
            8'hFB: begin is_ei = 1'b1; end

            // ── DI  (F3) ──────────────────────────────────────────
            8'hF3: begin is_di = 1'b1; end

            // ── RIM  (20) ─────────────────────────────────────────
            8'h20: begin is_rim = 1'b1; writes_reg = 1'b1; dst_sel = 3'b111; end

            // ── SIM  (30) ─────────────────────────────────────────
            8'h30: begin is_sim = 1'b1; end

            // ── Undocumented 8085 instructions ───────────────────

            // ── DSUB  (08) ───────────────────────────────────────
            8'h08: begin is_dsub = 1'b1; writes_flags = 1'b1; flag_mask = FLAGS_ALL; end

            // ── ARHL  (10) ───────────────────────────────────────
            8'h10: begin is_arhl = 1'b1; writes_flags = 1'b1; flag_mask = FLAGS_CY; end

            // ── RDEL  (18) ───────────────────────────────────────
            8'h18: begin is_rdel = 1'b1; writes_flags = 1'b1; flag_mask = 7'b1000001; end  // V + CY

            // ── LDHI  (28) ───────────────────────────────────────
            8'h28: begin inst_len = 2'd2; is_ldhi = 1'b1; end

            // ── LDSI  (38) ───────────────────────────────────────
            8'h38: begin inst_len = 2'd2; is_ldsi = 1'b1; end

            // ── RSTV  (CB) ───────────────────────────────────────
            8'hCB: begin is_rstv = 1'b1; end

            // ── SHLX  (D9) ───────────────────────────────────────
            8'hD9: begin is_shlx = 1'b1; is_store = 1'b1; end

            // ── JNX5  (DD) ───────────────────────────────────────
            8'hDD: begin inst_len = 2'd3; is_jnx5 = 1'b1; end

            // ── LHLX  (ED) ───────────────────────────────────────
            8'hED: begin is_lhlx = 1'b1; is_load = 1'b1; needs_de_read = 1'b1; end

            // ── JX5  (FD) ────────────────────────────────────────
            8'hFD: begin inst_len = 2'd3; is_jx5 = 1'b1; end

            // ── Default: treat as NOP (handles undocumented opcodes)
            default: begin
                is_nop = 1'b1;
            end

        endcase
    end

endmodule
