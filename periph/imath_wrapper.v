// Integer Math Accelerator (imath)
// Uses 2x SB_MAC16 for fast multiply operations
//   - mac_u: unsigned 16×16 multiply
//   - mac_s: signed 16×16 multiply
//
// Supports:
//   8×8   → 16-bit result (1 cycle)
//   16×16 → 32-bit result (1 cycle)
//   32×32 → 64-bit result (4 cycles)
//
// Both signed and unsigned modes supported.
//
// Register Map (0x7F60-0x7F6F):
//   0x0-0x3: A_0..A_3 (operand A, 32-bit little-endian)
//   0x4-0x7: B_0..B_3 (operand B, 32-bit little-endian)
//   0x8-0xF: R_0..R_7 (result, 64-bit little-endian) / CTRL at 0xF
//
// CTRL register (0xF):
//   [1:0] MODE: 0=8×8, 1=16×16, 2=32×32
//   [2]   SIGNED: 0=unsigned, 1=signed
//   [7]   BUSY: 1=operation in progress (read-only)

module imath_wrapper (
    input  wire        clk,
    input  wire        reset_n,

    // Bus interface
    input  wire [3:0]  addr,
    input  wire [7:0]  data_in,
    output reg  [7:0]  data_out,
    input  wire        rd,
    input  wire        wr
);

    // Operand and result registers
    reg [31:0] op_a;
    reg [31:0] op_b;
    reg [63:0] result;

    // Control state
    reg [1:0]  mode;
    reg        is_signed;
    reg        busy;
    reg [1:0]  phase;        // 0-3 for 32×32 partial products
    reg        result_neg;   // For signed 32×32: negate final result

    // DSP I/O
    reg  [15:0] mac_u_a, mac_u_b;  // Unsigned DSP inputs
    reg  [15:0] mac_s_a, mac_s_b;  // Signed DSP inputs
    wire [31:0] mac_u_out;         // Unsigned DSP output
    wire [31:0] mac_s_out;         // Signed DSP output

    // Unsigned 16×16 DSP
    SB_MAC16 #(
        .NEG_TRIGGER(1'b0),
        .A_REG(1'b0), .B_REG(1'b0), .C_REG(1'b0), .D_REG(1'b0),
        .TOP_8x8_MULT_REG(1'b0), .BOT_8x8_MULT_REG(1'b0),
        .PIPELINE_16x16_MULT_REG1(1'b0), .PIPELINE_16x16_MULT_REG2(1'b0),
        .TOPOUTPUT_SELECT(2'b00), .TOPADDSUB_LOWERINPUT(2'b00),
        .TOPADDSUB_UPPERINPUT(1'b0), .TOPADDSUB_CARRYSELECT(2'b00),
        .BOTOUTPUT_SELECT(2'b00), .BOTADDSUB_LOWERINPUT(2'b00),
        .BOTADDSUB_UPPERINPUT(1'b0), .BOTADDSUB_CARRYSELECT(2'b00),
        .MODE_8x8(1'b0),
        .A_SIGNED(1'b0),
        .B_SIGNED(1'b0)
    ) mac_u (
        .CLK(clk), .CE(1'b1),
        .A(mac_u_a), .B(mac_u_b),
        .C(16'b0), .D(16'b0),
        .AHOLD(1'b0), .BHOLD(1'b0), .CHOLD(1'b0), .DHOLD(1'b0),
        .IRSTTOP(1'b0), .IRSTBOT(1'b0), .ORSTTOP(1'b0), .ORSTBOT(1'b0),
        .OLOADTOP(1'b0), .OLOADBOT(1'b0),
        .ADDSUBTOP(1'b0), .ADDSUBBOT(1'b0),
        .OHOLDTOP(1'b0), .OHOLDBOT(1'b0),
        .CI(1'b0), .ACCUMCI(1'b0), .SIGNEXTIN(1'b0),
        .O(mac_u_out), .CO(), .ACCUMCO(), .SIGNEXTOUT()
    );

    // Signed 16×16 DSP
    SB_MAC16 #(
        .NEG_TRIGGER(1'b0),
        .A_REG(1'b0), .B_REG(1'b0), .C_REG(1'b0), .D_REG(1'b0),
        .TOP_8x8_MULT_REG(1'b0), .BOT_8x8_MULT_REG(1'b0),
        .PIPELINE_16x16_MULT_REG1(1'b0), .PIPELINE_16x16_MULT_REG2(1'b0),
        .TOPOUTPUT_SELECT(2'b00), .TOPADDSUB_LOWERINPUT(2'b00),
        .TOPADDSUB_UPPERINPUT(1'b0), .TOPADDSUB_CARRYSELECT(2'b00),
        .BOTOUTPUT_SELECT(2'b00), .BOTADDSUB_LOWERINPUT(2'b00),
        .BOTADDSUB_UPPERINPUT(1'b0), .BOTADDSUB_CARRYSELECT(2'b00),
        .MODE_8x8(1'b0),
        .A_SIGNED(1'b1),
        .B_SIGNED(1'b1)
    ) mac_s (
        .CLK(clk), .CE(1'b1),
        .A(mac_s_a), .B(mac_s_b),
        .C(16'b0), .D(16'b0),
        .AHOLD(1'b0), .BHOLD(1'b0), .CHOLD(1'b0), .DHOLD(1'b0),
        .IRSTTOP(1'b0), .IRSTBOT(1'b0), .ORSTTOP(1'b0), .ORSTBOT(1'b0),
        .OLOADTOP(1'b0), .OLOADBOT(1'b0),
        .ADDSUBTOP(1'b0), .ADDSUBBOT(1'b0),
        .OHOLDTOP(1'b0), .OHOLDBOT(1'b0),
        .CI(1'b0), .ACCUMCI(1'b0), .SIGNEXTIN(1'b0),
        .O(mac_s_out), .CO(), .ACCUMCO(), .SIGNEXTOUT()
    );

    // 32×32 signed support: absolute value and result sign
    wire a_neg = op_a[31];
    wire b_neg = op_b[31];
    wire [31:0] abs_a = a_neg ? (~op_a + 32'd1) : op_a;
    wire [31:0] abs_b = b_neg ? (~op_b + 32'd1) : op_b;

    // Saved values for 32×32 multi-cycle operation
    reg [31:0] mul_a, mul_b;     // Operands (or absolute values for signed)
    reg [31:0] p0, p1, p2;       // Partial products

    // Effective mode during CTRL write
    wire [1:0] eff_mode   = (wr && addr == 4'hF) ? data_in[1:0] : mode;
    wire       eff_signed = (wr && addr == 4'hF) ? data_in[2]   : is_signed;

    // DSP input muxing
    always @(*) begin
        // Default: zero
        mac_u_a = 16'b0;
        mac_u_b = 16'b0;
        mac_s_a = 16'b0;
        mac_s_b = 16'b0;

        case (eff_mode)
            2'd0: begin  // 8×8
                if (eff_signed) begin
                    // Sign-extend 8-bit to 16-bit for signed DSP
                    mac_s_a = {{8{op_a[7]}}, op_a[7:0]};
                    mac_s_b = {{8{op_b[7]}}, op_b[7:0]};
                end else begin
                    mac_u_a = {8'b0, op_a[7:0]};
                    mac_u_b = {8'b0, op_b[7:0]};
                end
            end
            2'd1: begin  // 16×16
                if (eff_signed) begin
                    mac_s_a = op_a[15:0];
                    mac_s_b = op_b[15:0];
                end else begin
                    mac_u_a = op_a[15:0];
                    mac_u_b = op_b[15:0];
                end
            end
            2'd2: begin  // 32×32 - 4 phases, always use unsigned DSP on abs values
                case (phase)
                    2'd0: begin mac_u_a = mul_a[15:0];  mac_u_b = mul_b[15:0];  end  // lo×lo
                    2'd1: begin mac_u_a = mul_a[31:16]; mac_u_b = mul_b[31:16]; end  // hi×hi
                    2'd2: begin mac_u_a = mul_a[15:0];  mac_u_b = mul_b[31:16]; end  // lo×hi
                    2'd3: begin mac_u_a = mul_a[31:16]; mac_u_b = mul_b[15:0];  end  // hi×lo
                endcase
            end
        endcase
    end

    // State machine
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            op_a <= 32'b0;
            op_b <= 32'b0;
            result <= 64'b0;
            mode <= 2'b0;
            is_signed <= 1'b0;
            busy <= 1'b0;
            phase <= 2'b0;
            result_neg <= 1'b0;
            mul_a <= 32'b0;
            mul_b <= 32'b0;
            p0 <= 32'b0;
            p1 <= 32'b0;
            p2 <= 32'b0;
        end else begin
            // 32×32 multi-cycle state machine
            if (busy && mode == 2'd2) begin
                case (phase)
                    2'd0: begin
                        p0 <= mac_u_out;           // Save lo×lo
                        phase <= 2'd1;
                    end
                    2'd1: begin
                        p1 <= mac_u_out;           // Save hi×hi
                        phase <= 2'd2;
                    end
                    2'd2: begin
                        p2 <= mac_u_out;           // Save lo×hi
                        phase <= 2'd3;
                    end
                    2'd3: begin
                        // Combine: hi×hi<<32 + (lo×hi + hi×lo)<<16 + lo×lo
                        // p0 = lo×lo, p1 = hi×hi, p2 = lo×hi, mac_u_out = hi×lo
                        if (result_neg) begin
                            result <= ~({p1, 32'b0} + {16'b0, p2 + mac_u_out, 16'b0} + {32'b0, p0}) + 64'd1;
                        end else begin
                            result <= {p1, 32'b0} + {16'b0, p2 + mac_u_out, 16'b0} + {32'b0, p0};
                        end
                        busy <= 1'b0;
                        phase <= 2'd0;
                    end
                endcase
            end

            // Register writes
            if (wr) begin
                case (addr)
                    4'h0: op_a[7:0]   <= data_in;
                    4'h1: op_a[15:8]  <= data_in;
                    4'h2: op_a[23:16] <= data_in;
                    4'h3: op_a[31:24] <= data_in;
                    4'h4: op_b[7:0]   <= data_in;
                    4'h5: op_b[15:8]  <= data_in;
                    4'h6: op_b[23:16] <= data_in;
                    4'h7: op_b[31:24] <= data_in;
                    4'hF: begin
                        mode <= data_in[1:0];
                        is_signed <= data_in[2];

                        case (data_in[1:0])
                            2'd0: begin  // 8×8: 1 cycle
                                if (data_in[2])
                                    result <= {48'b0, mac_s_out[15:0]};
                                else
                                    result <= {48'b0, mac_u_out[15:0]};
                                busy <= 1'b0;
                            end
                            2'd1: begin  // 16×16: 1 cycle
                                if (data_in[2])
                                    result <= {32'b0, mac_s_out};
                                else
                                    result <= {32'b0, mac_u_out};
                                busy <= 1'b0;
                            end
                            2'd2: begin  // 32×32: start 4-cycle operation
                                busy <= 1'b1;
                                phase <= 2'd0;
                                if (data_in[2]) begin
                                    // Signed: use absolute values, remember to negate
                                    mul_a <= abs_a;
                                    mul_b <= abs_b;
                                    result_neg <= a_neg ^ b_neg;
                                end else begin
                                    mul_a <= op_a;
                                    mul_b <= op_b;
                                    result_neg <= 1'b0;
                                end
                            end
                            default: busy <= 1'b0;
                        endcase
                    end
                endcase
            end
        end
    end

    // Register read logic
    always @(*) begin
        case (addr)
            4'h0: data_out = op_a[7:0];
            4'h1: data_out = op_a[15:8];
            4'h2: data_out = op_a[23:16];
            4'h3: data_out = op_a[31:24];
            4'h4: data_out = op_b[7:0];
            4'h5: data_out = op_b[15:8];
            4'h6: data_out = op_b[23:16];
            4'h7: data_out = op_b[31:24];
            4'h8: data_out = result[7:0];
            4'h9: data_out = result[15:8];
            4'hA: data_out = result[23:16];
            4'hB: data_out = result[31:24];
            4'hC: data_out = result[39:32];
            4'hD: data_out = result[47:40];
            4'hE: data_out = result[55:48];
            4'hF: data_out = {busy, 4'b0, is_signed, mode};
            default: data_out = 8'h00;
        endcase
    end

endmodule
