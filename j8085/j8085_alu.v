// j8085_alu.v - 8-bit ALU with flag generation for j8085 pipeline
//
// Combinational: result and flags valid same cycle as inputs.
// Supports all 8085 ALU operations including rotate, DAA, complement.
//
// Flag bits: [6]=V, [5]=X5, [4]=S, [3]=Z, [2]=AC, [1]=P, [0]=CY

`timescale 1ns / 1ps

module j8085_alu (
    input  wire [3:0]  alu_op,
    input  wire [7:0]  operand_a,     // Usually accumulator
    input  wire [7:0]  operand_b,     // Source register or immediate
    input  wire [6:0]  flags_in,      // Current flags [V,X5,S,Z,AC,P,CY]

    output reg  [7:0]  result,
    output reg  [6:0]  flags_out      // New flags [V,X5,S,Z,AC,P,CY]
);

    // ALU operation codes
    localparam ALU_ADD  = 4'd0;   // A + B
    localparam ALU_ADC  = 4'd1;   // A + B + CY
    localparam ALU_SUB  = 4'd2;   // A - B
    localparam ALU_SBB  = 4'd3;   // A - B - CY
    localparam ALU_ANA  = 4'd4;   // A & B
    localparam ALU_XRA  = 4'd5;   // A ^ B
    localparam ALU_ORA  = 4'd6;   // A | B
    localparam ALU_CMP  = 4'd7;   // A - B (result discarded, flags only)
    localparam ALU_INC  = 4'd8;   // B + 1 (CY unchanged)
    localparam ALU_DEC  = 4'd9;   // B - 1 (CY unchanged)
    localparam ALU_RLC  = 4'd10;  // Rotate A left (bit 7 → CY and bit 0)
    localparam ALU_RRC  = 4'd11;  // Rotate A right (bit 0 → CY and bit 7)
    localparam ALU_RAL  = 4'd12;  // Rotate A left through carry
    localparam ALU_RAR  = 4'd13;  // Rotate A right through carry
    localparam ALU_DAA  = 4'd14;  // Decimal adjust accumulator
    localparam ALU_PASS = 4'd15;  // Pass B through (for MOV, MVI, etc.)

    // Flag bit positions: {V,X5,S,Z,AC,P,CY}
    localparam F_V  = 6;
    localparam F_X5 = 5;
    localparam F_S  = 4;
    localparam F_Z  = 3;
    localparam F_AC = 2;
    localparam F_P  = 1;
    localparam F_CY = 0;

    // Internal signals
    reg  [8:0]  sum9;        // 9-bit result for carry detection
    reg  [4:0]  half_sum;    // 5-bit result for aux carry detection
    wire        parity;      // Even parity of result

    // Parity: XOR tree (even parity = 1 when even number of 1s)
    assign parity = ~(result[7] ^ result[6] ^ result[5] ^ result[4] ^
                      result[3] ^ result[2] ^ result[1] ^ result[0]);

    always @(*) begin
        // Defaults
        sum9 = 9'd0;
        half_sum = 5'd0;
        result = 8'h00;
        flags_out = flags_in;  // Preserve by default

        case (alu_op)
            ALU_ADD: begin
                sum9 = {1'b0, operand_a} + {1'b0, operand_b};
                half_sum = {1'b0, operand_a[3:0]} + {1'b0, operand_b[3:0]};
                result = sum9[7:0];
                // V: overflow when same-sign operands produce different-sign result
                flags_out = {~(operand_a[7] ^ operand_b[7]) & (operand_a[7] ^ result[7]),
                             flags_in[F_X5],
                             result[7], result == 8'd0, half_sum[4], parity, sum9[8]};
            end

            ALU_ADC: begin
                sum9 = {1'b0, operand_a} + {1'b0, operand_b} + {8'd0, flags_in[F_CY]};
                half_sum = {1'b0, operand_a[3:0]} + {1'b0, operand_b[3:0]} + {4'd0, flags_in[F_CY]};
                result = sum9[7:0];
                flags_out = {~(operand_a[7] ^ operand_b[7]) & (operand_a[7] ^ result[7]),
                             flags_in[F_X5],
                             result[7], result == 8'd0, half_sum[4], parity, sum9[8]};
            end

            ALU_SUB, ALU_CMP: begin
                sum9 = {1'b0, operand_a} - {1'b0, operand_b};
                half_sum = {1'b0, operand_a[3:0]} - {1'b0, operand_b[3:0]};
                result = sum9[7:0];
                // V: overflow when different-sign operands and result sign != A sign
                flags_out = {(operand_a[7] ^ operand_b[7]) & (operand_a[7] ^ result[7]),
                             flags_in[F_X5],
                             result[7], result == 8'd0, half_sum[4], parity, sum9[8]};
            end

            ALU_SBB: begin
                sum9 = {1'b0, operand_a} - {1'b0, operand_b} - {8'd0, flags_in[F_CY]};
                half_sum = {1'b0, operand_a[3:0]} - {1'b0, operand_b[3:0]} - {4'd0, flags_in[F_CY]};
                result = sum9[7:0];
                flags_out = {(operand_a[7] ^ operand_b[7]) & (operand_a[7] ^ result[7]),
                             flags_in[F_X5],
                             result[7], result == 8'd0, half_sum[4], parity, sum9[8]};
            end

            ALU_ANA: begin
                result = operand_a & operand_b;
                // ANA: V=0, AC = OR of bit 3 of operands (8085 behavior)
                flags_out = {1'b0, flags_in[F_X5],
                             result[7], result == 8'd0,
                             operand_a[3] | operand_b[3],
                             parity, 1'b0};
            end

            ALU_XRA: begin
                result = operand_a ^ operand_b;
                flags_out = {1'b0, flags_in[F_X5],
                             result[7], result == 8'd0, 1'b0, parity, 1'b0};
            end

            ALU_ORA: begin
                result = operand_a | operand_b;
                flags_out = {1'b0, flags_in[F_X5],
                             result[7], result == 8'd0, 1'b0, parity, 1'b0};
            end

            ALU_INC: begin
                // INR: increment operand_b, CY unchanged
                sum9 = {1'b0, operand_b} + 9'd1;
                half_sum = {1'b0, operand_b[3:0]} + 5'd1;
                result = sum9[7:0];
                // V: overflow if 0x7F→0x80
                flags_out = {~operand_b[7] & result[7], flags_in[F_X5],
                             result[7], result == 8'd0, half_sum[4], parity, flags_in[F_CY]};
            end

            ALU_DEC: begin
                // DCR: decrement operand_b, CY unchanged
                sum9 = {1'b0, operand_b} - 9'd1;
                half_sum = {1'b0, operand_b[3:0]} - 5'd1;
                result = sum9[7:0];
                // V: overflow if 0x80→0x7F
                flags_out = {operand_b[7] & ~result[7], flags_in[F_X5],
                             result[7], result == 8'd0, half_sum[4], parity, flags_in[F_CY]};
            end

            ALU_RLC: begin
                // Rotate A left: bit 7 → CY and bit 0
                result = {operand_a[6:0], operand_a[7]};
                flags_out = {flags_in[F_V], flags_in[F_X5],
                             flags_in[F_S], flags_in[F_Z], flags_in[F_AC],
                             flags_in[F_P], operand_a[7]};
            end

            ALU_RRC: begin
                // Rotate A right: bit 0 → CY and bit 7
                result = {operand_a[0], operand_a[7:1]};
                flags_out = {flags_in[F_V], flags_in[F_X5],
                             flags_in[F_S], flags_in[F_Z], flags_in[F_AC],
                             flags_in[F_P], operand_a[0]};
            end

            ALU_RAL: begin
                // Rotate A left through carry
                result = {operand_a[6:0], flags_in[F_CY]};
                flags_out = {flags_in[F_V], flags_in[F_X5],
                             flags_in[F_S], flags_in[F_Z], flags_in[F_AC],
                             flags_in[F_P], operand_a[7]};
            end

            ALU_RAR: begin
                // Rotate A right through carry
                result = {flags_in[F_CY], operand_a[7:1]};
                flags_out = {flags_in[F_V], flags_in[F_X5],
                             flags_in[F_S], flags_in[F_Z], flags_in[F_AC],
                             flags_in[F_P], operand_a[0]};
            end

            ALU_DAA: begin
                // Decimal Adjust Accumulator
                // Step 1: adjust low nibble
                if (operand_a[3:0] > 4'd9 || flags_in[F_AC]) begin
                    half_sum = {1'b0, operand_a[3:0]} + 5'd6;
                end else begin
                    half_sum = {1'b0, operand_a[3:0]};
                end

                // Step 2: adjust high nibble
                begin : daa_high
                    reg [4:0] high_nibble;
                    reg       new_cy;
                    high_nibble = {1'b0, operand_a[7:4]} + {4'd0, half_sum[4]};
                    if (high_nibble > 5'd9 || flags_in[F_CY]) begin
                        high_nibble = high_nibble + 5'd6;
                        new_cy = 1'b1;
                    end else begin
                        new_cy = flags_in[F_CY];
                    end
                    result = {high_nibble[3:0], half_sum[3:0]};
                    flags_out = {flags_in[F_V], flags_in[F_X5],
                                 result[7], result == 8'd0, half_sum[4], parity, new_cy};
                end
            end

            ALU_PASS: begin
                // Pass-through: result = operand_b, flags unchanged
                result = operand_b;
                // flags_out already = flags_in (default)
            end

            default: begin
                result = 8'h00;
            end
        endcase
    end

endmodule
