// Integer Math Accelerator LITE (imath_lite)
// Simplified version - 8×8 and 16×16 only (no 32×32)
// Uses 2x SB_MAC16: one unsigned, one signed
//
// For 32×32 multiply, use software:
//   result = (a_hi×b_hi)<<32 + (a_lo×b_hi + a_hi×b_lo)<<16 + a_lo×b_lo
//
// Supports:
//   8×8   → 16-bit result (1 cycle)
//   16×16 → 32-bit result (1 cycle)
//
// Both signed and unsigned modes supported.
//
// Register Map (0x7F60-0x7F6F):
//   0x0-0x1: A_0..A_1 (operand A, 16-bit little-endian)
//   0x4-0x5: B_0..B_1 (operand B, 16-bit little-endian)
//   0x8-0xB: R_0..R_3 (result, 32-bit little-endian)
//   0xF:     CTRL register
//
// CTRL register (0xF):
//   [0]   MODE: 0=8×8, 1=16×16
//   [2]   SIGNED: 0=unsigned, 1=signed
//   [7]   BUSY: always 0 (single-cycle)
//
// Resources: 2 DSPs, ~124 LUTs

module imath_lite_wrapper (
    input  wire        clk,
    input  wire        reset_n,

    // Bus interface
    input  wire [3:0]  addr,
    input  wire [7:0]  data_in,
    output reg  [7:0]  data_out,
    input  wire        rd,
    input  wire        wr
);

    // Operand registers (16-bit only)
    reg [15:0] op_a;
    reg [15:0] op_b;
    reg [31:0] result;

    // Control state
    reg        mode;      // 0=8×8, 1=16×16
    reg        is_signed;

    // DSP I/O
    wire [15:0] mac_u_a, mac_u_b;  // Unsigned DSP inputs
    wire [15:0] mac_s_a, mac_s_b;  // Signed DSP inputs
    wire [31:0] mac_u_out;         // Unsigned DSP output
    wire [31:0] mac_s_out;         // Signed DSP output

    // Effective mode during CTRL write (for combinational result)
    wire eff_mode   = (wr && addr == 4'hF) ? data_in[0] : mode;
    wire eff_signed = (wr && addr == 4'hF) ? data_in[2] : is_signed;

    // DSP inputs - always connected (combinational)
    assign mac_u_a = eff_mode ? op_a : {8'b0, op_a[7:0]};
    assign mac_u_b = eff_mode ? op_b : {8'b0, op_b[7:0]};
    assign mac_s_a = eff_mode ? op_a : {{8{op_a[7]}}, op_a[7:0]};
    assign mac_s_b = eff_mode ? op_b : {{8{op_b[7]}}, op_b[7:0]};

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

    // Register writes
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            op_a <= 16'b0;
            op_b <= 16'b0;
            result <= 32'b0;
            mode <= 1'b0;
            is_signed <= 1'b0;
        end else if (wr) begin
            case (addr)
                4'h0: op_a[7:0]  <= data_in;
                4'h1: op_a[15:8] <= data_in;
                4'h4: op_b[7:0]  <= data_in;
                4'h5: op_b[15:8] <= data_in;
                4'hF: begin
                    mode <= data_in[0];
                    is_signed <= data_in[2];
                    // Capture result immediately (combinational from DSPs)
                    if (data_in[0]) begin  // 16×16
                        result <= data_in[2] ? mac_s_out : mac_u_out;
                    end else begin  // 8×8
                        result <= data_in[2] ? {16'b0, mac_s_out[15:0]} : {16'b0, mac_u_out[15:0]};
                    end
                end
            endcase
        end
    end

    // Register read logic
    always @(*) begin
        case (addr)
            4'h0: data_out = op_a[7:0];
            4'h1: data_out = op_a[15:8];
            4'h2: data_out = 8'h00;  // A_2 unused
            4'h3: data_out = 8'h00;  // A_3 unused
            4'h4: data_out = op_b[7:0];
            4'h5: data_out = op_b[15:8];
            4'h6: data_out = 8'h00;  // B_2 unused
            4'h7: data_out = 8'h00;  // B_3 unused
            4'h8: data_out = result[7:0];
            4'h9: data_out = result[15:8];
            4'hA: data_out = result[23:16];
            4'hB: data_out = result[31:24];
            4'hC: data_out = 8'h00;  // R_4 unused
            4'hD: data_out = 8'h00;  // R_5 unused
            4'hE: data_out = 8'h00;  // R_6 unused
            4'hF: data_out = {7'b0, is_signed, 2'b0, mode};  // BUSY always 0
            default: data_out = 8'h00;
        endcase
    end

endmodule
