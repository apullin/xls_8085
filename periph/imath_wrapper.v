// Integer Math Accelerator (imath) - 4 DSP, All Unsigned
// Uses 4x SB_MAC16 for fast unsigned multiply operations
//
// Supports (ALL UNSIGNED):
//   8×8   → 16-bit unsigned result (1 cycle)
//   16×16 → 32-bit unsigned result (1 cycle)
//   32×32 → 64-bit unsigned result (1 cycle)
//
// For signed multiplication, software must:
//   1. Record signs of operands
//   2. Take absolute values
//   3. Multiply unsigned
//   4. Negate result if signs differ
//
// Register Map (0x7F60-0x7F6F):
//   0x0-0x3: A_0..A_3 (operand A, 32-bit little-endian)
//   0x4-0x7: B_0..B_3 (operand B, 32-bit little-endian)
//   0x8-0xF: R_0..R_7 (result, 64-bit little-endian) / CTRL at 0xF
//
// CTRL register (0xF):
//   [1:0] MODE: 0=8×8, 1=16×16, 2=32×32
//   [7]   BUSY: always 0 (single-cycle operations)

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

    // Effective mode during CTRL write (for combinational result)
    wire [1:0] eff_mode = (wr && addr == 4'hF) ? data_in[1:0] : mode;

    // DSP inputs - unsigned, mode-dependent width
    wire [15:0] a_lo = (eff_mode == 2'd0) ? {8'b0, op_a[7:0]} : op_a[15:0];
    wire [15:0] a_hi = (eff_mode == 2'd2) ? op_a[31:16] : 16'b0;
    wire [15:0] b_lo = (eff_mode == 2'd0) ? {8'b0, op_b[7:0]} : op_b[15:0];
    wire [15:0] b_hi = (eff_mode == 2'd2) ? op_b[31:16] : 16'b0;

    // DSP outputs
    wire [31:0] p_ll, p_lh, p_hl, p_hh;

    // All 4 DSPs configured identically (unsigned)
    SB_MAC16 #(
        .NEG_TRIGGER(1'b0),
        .A_REG(1'b0), .B_REG(1'b0), .C_REG(1'b0), .D_REG(1'b0),
        .TOP_8x8_MULT_REG(1'b0), .BOT_8x8_MULT_REG(1'b0),
        .PIPELINE_16x16_MULT_REG1(1'b0), .PIPELINE_16x16_MULT_REG2(1'b0),
        .TOPOUTPUT_SELECT(2'b00), .TOPADDSUB_LOWERINPUT(2'b00),
        .TOPADDSUB_UPPERINPUT(1'b0), .TOPADDSUB_CARRYSELECT(2'b00),
        .BOTOUTPUT_SELECT(2'b00), .BOTADDSUB_LOWERINPUT(2'b00),
        .BOTADDSUB_UPPERINPUT(1'b0), .BOTADDSUB_CARRYSELECT(2'b00),
        .MODE_8x8(1'b0), .A_SIGNED(1'b0), .B_SIGNED(1'b0)
    ) dsp_ll (
        .CLK(clk), .CE(1'b1), .A(a_lo), .B(b_lo),
        .C(16'b0), .D(16'b0),
        .AHOLD(1'b0), .BHOLD(1'b0), .CHOLD(1'b0), .DHOLD(1'b0),
        .IRSTTOP(1'b0), .IRSTBOT(1'b0), .ORSTTOP(1'b0), .ORSTBOT(1'b0),
        .OLOADTOP(1'b0), .OLOADBOT(1'b0),
        .ADDSUBTOP(1'b0), .ADDSUBBOT(1'b0),
        .OHOLDTOP(1'b0), .OHOLDBOT(1'b0),
        .CI(1'b0), .ACCUMCI(1'b0), .SIGNEXTIN(1'b0),
        .O(p_ll), .CO(), .ACCUMCO(), .SIGNEXTOUT()
    );

    SB_MAC16 #(
        .NEG_TRIGGER(1'b0),
        .A_REG(1'b0), .B_REG(1'b0), .C_REG(1'b0), .D_REG(1'b0),
        .TOP_8x8_MULT_REG(1'b0), .BOT_8x8_MULT_REG(1'b0),
        .PIPELINE_16x16_MULT_REG1(1'b0), .PIPELINE_16x16_MULT_REG2(1'b0),
        .TOPOUTPUT_SELECT(2'b00), .TOPADDSUB_LOWERINPUT(2'b00),
        .TOPADDSUB_UPPERINPUT(1'b0), .TOPADDSUB_CARRYSELECT(2'b00),
        .BOTOUTPUT_SELECT(2'b00), .BOTADDSUB_LOWERINPUT(2'b00),
        .BOTADDSUB_UPPERINPUT(1'b0), .BOTADDSUB_CARRYSELECT(2'b00),
        .MODE_8x8(1'b0), .A_SIGNED(1'b0), .B_SIGNED(1'b0)
    ) dsp_lh (
        .CLK(clk), .CE(1'b1), .A(a_lo), .B(b_hi),
        .C(16'b0), .D(16'b0),
        .AHOLD(1'b0), .BHOLD(1'b0), .CHOLD(1'b0), .DHOLD(1'b0),
        .IRSTTOP(1'b0), .IRSTBOT(1'b0), .ORSTTOP(1'b0), .ORSTBOT(1'b0),
        .OLOADTOP(1'b0), .OLOADBOT(1'b0),
        .ADDSUBTOP(1'b0), .ADDSUBBOT(1'b0),
        .OHOLDTOP(1'b0), .OHOLDBOT(1'b0),
        .CI(1'b0), .ACCUMCI(1'b0), .SIGNEXTIN(1'b0),
        .O(p_lh), .CO(), .ACCUMCO(), .SIGNEXTOUT()
    );

    SB_MAC16 #(
        .NEG_TRIGGER(1'b0),
        .A_REG(1'b0), .B_REG(1'b0), .C_REG(1'b0), .D_REG(1'b0),
        .TOP_8x8_MULT_REG(1'b0), .BOT_8x8_MULT_REG(1'b0),
        .PIPELINE_16x16_MULT_REG1(1'b0), .PIPELINE_16x16_MULT_REG2(1'b0),
        .TOPOUTPUT_SELECT(2'b00), .TOPADDSUB_LOWERINPUT(2'b00),
        .TOPADDSUB_UPPERINPUT(1'b0), .TOPADDSUB_CARRYSELECT(2'b00),
        .BOTOUTPUT_SELECT(2'b00), .BOTADDSUB_LOWERINPUT(2'b00),
        .BOTADDSUB_UPPERINPUT(1'b0), .BOTADDSUB_CARRYSELECT(2'b00),
        .MODE_8x8(1'b0), .A_SIGNED(1'b0), .B_SIGNED(1'b0)
    ) dsp_hl (
        .CLK(clk), .CE(1'b1), .A(a_hi), .B(b_lo),
        .C(16'b0), .D(16'b0),
        .AHOLD(1'b0), .BHOLD(1'b0), .CHOLD(1'b0), .DHOLD(1'b0),
        .IRSTTOP(1'b0), .IRSTBOT(1'b0), .ORSTTOP(1'b0), .ORSTBOT(1'b0),
        .OLOADTOP(1'b0), .OLOADBOT(1'b0),
        .ADDSUBTOP(1'b0), .ADDSUBBOT(1'b0),
        .OHOLDTOP(1'b0), .OHOLDBOT(1'b0),
        .CI(1'b0), .ACCUMCI(1'b0), .SIGNEXTIN(1'b0),
        .O(p_hl), .CO(), .ACCUMCO(), .SIGNEXTOUT()
    );

    SB_MAC16 #(
        .NEG_TRIGGER(1'b0),
        .A_REG(1'b0), .B_REG(1'b0), .C_REG(1'b0), .D_REG(1'b0),
        .TOP_8x8_MULT_REG(1'b0), .BOT_8x8_MULT_REG(1'b0),
        .PIPELINE_16x16_MULT_REG1(1'b0), .PIPELINE_16x16_MULT_REG2(1'b0),
        .TOPOUTPUT_SELECT(2'b00), .TOPADDSUB_LOWERINPUT(2'b00),
        .TOPADDSUB_UPPERINPUT(1'b0), .TOPADDSUB_CARRYSELECT(2'b00),
        .BOTOUTPUT_SELECT(2'b00), .BOTADDSUB_LOWERINPUT(2'b00),
        .BOTADDSUB_UPPERINPUT(1'b0), .BOTADDSUB_CARRYSELECT(2'b00),
        .MODE_8x8(1'b0), .A_SIGNED(1'b0), .B_SIGNED(1'b0)
    ) dsp_hh (
        .CLK(clk), .CE(1'b1), .A(a_hi), .B(b_hi),
        .C(16'b0), .D(16'b0),
        .AHOLD(1'b0), .BHOLD(1'b0), .CHOLD(1'b0), .DHOLD(1'b0),
        .IRSTTOP(1'b0), .IRSTBOT(1'b0), .ORSTTOP(1'b0), .ORSTBOT(1'b0),
        .OLOADTOP(1'b0), .OLOADBOT(1'b0),
        .ADDSUBTOP(1'b0), .ADDSUBBOT(1'b0),
        .OHOLDTOP(1'b0), .OHOLDBOT(1'b0),
        .CI(1'b0), .ACCUMCI(1'b0), .SIGNEXTIN(1'b0),
        .O(p_hh), .CO(), .ACCUMCO(), .SIGNEXTOUT()
    );

    // Combine: result = p_hh<<32 + (p_lh + p_hl)<<16 + p_ll
    wire [63:0] result_32 = {p_hh, 32'b0} + {16'b0, p_lh + p_hl, 16'b0} + {32'b0, p_ll};

    // Mode-dependent result
    wire [63:0] computed_result =
        (eff_mode == 2'd2) ? result_32 :
        (eff_mode == 2'd1) ? {32'b0, p_ll} :
                            {48'b0, p_ll[15:0]};

    // Register writes
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            op_a <= 32'b0;
            op_b <= 32'b0;
            result <= 64'b0;
            mode <= 2'b0;
        end else if (wr) begin
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
                    result <= computed_result;
                end
            endcase
        end
    end

    // Register read
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
            4'hF: data_out = {6'b0, mode};
            default: data_out = 8'h00;
        endcase
    end

endmodule
