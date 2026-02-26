// i8085_decode.v - Shared instruction decode logic
// Extracts instruction classification from opcode byte
// Used by CPU fetch FSM to determine operand requirements

module i8085_decode (
    input  wire [7:0] opcode,

    // Instruction length (1, 2, or 3 bytes)
    output reg  [1:0] inst_len,

    // Operand fetch requirements
    output reg        needs_hl_read,     // MOV r,(HL), ALU (HL), INC/DEC (HL)
    output wire       needs_bc_read,     // LDAX B
    output wire       needs_de_read,     // LDAX D
    output wire       needs_direct_read, // LDA, LHLD (direct address)
    output reg        needs_stack_read,  // RET, Rcc, POP, XTHL
    output wire       needs_io_read      // IN instruction
);

    // Instruction length decode
    always @(*) begin
        casez (opcode)
            // 3-byte instructions:
            // LXI (00rp0001), JMP (11000011), Jcc (11ccc010),
            // CALL (11001101), Ccc (11ccc100), STA/LDA (0011x010), SHLD/LHLD (0010x010)
            // JNX5 (DD), JX5 (FD)
            8'b00??0001, 8'b11000011, 8'b11???010,
            8'b11001101, 8'b11???100, 8'b0011?010, 8'b0010?010,
            8'hDD, 8'hFD:
                inst_len = 2'd3;
            // 2-byte instructions: MVI (00rrr110), ALU immediate (11xxx110), IN/OUT (1101x011)
            // LDHI (28), LDSI (38)
            8'b00???110, 8'b11???110, 8'b1101?011,
            8'h28, 8'h38:
                inst_len = 2'd2;
            default:
                inst_len = 2'd1;
        endcase
    end

    // HL indirect read: MOV r,(HL), ALU (HL), INC (HL), DEC (HL)
    always @(*) begin
        casez (opcode)
            8'b01???110,  // MOV r,(HL) - 46,4E,56,5E,66,6E,7E
            8'b10???110,  // ALU (HL) - ADD/ADC/SUB/SBB/ANA/XRA/ORA/CMP M
            8'b00110100,  // INR M (34)
            8'b00110101:  // DCR M (35)
                needs_hl_read = 1'b1;
            default:
                needs_hl_read = 1'b0;
        endcase
    end

    // BC indirect read: LDAX B (0A)
    assign needs_bc_read = (opcode == 8'h0A);

    // DE indirect read: LDAX D (1A), LHLX (ED)
    assign needs_de_read = (opcode == 8'h1A) || (opcode == 8'hED);

    // Direct address read: LDA (3A), LHLD (2A)
    assign needs_direct_read = (opcode == 8'h3A) || (opcode == 8'h2A);

    // Stack read: RET, Rcc, POP, XTHL
    always @(*) begin
        casez (opcode)
            8'b11001001,  // RET (C9)
            8'b11???000,  // Rcc - conditional return (C0,C8,D0,D8,E0,E8,F0,F8)
            8'b11??0001,  // POP (C1,D1,E1,F1)
            8'b11100011:  // XTHL (E3)
                needs_stack_read = 1'b1;
            default:
                needs_stack_read = 1'b0;
        endcase
    end

    // I/O read: IN (DB)
    assign needs_io_read = (opcode == 8'hDB);

endmodule
