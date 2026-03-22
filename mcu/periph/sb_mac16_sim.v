// Behavioral SB_MAC16 model for testbench
// Supports both simple multiply (imath) and multiply-accumulate (vmath)

module SB_MAC16 #(
    parameter [0:0] NEG_TRIGGER = 0,
    parameter [0:0] C_REG = 0,
    parameter [0:0] A_REG = 0,
    parameter [0:0] B_REG = 0,
    parameter [0:0] D_REG = 0,
    parameter [0:0] TOP_8x8_MULT_REG = 0,
    parameter [0:0] BOT_8x8_MULT_REG = 0,
    parameter [0:0] PIPELINE_16x16_MULT_REG1 = 0,
    parameter [0:0] PIPELINE_16x16_MULT_REG2 = 0,
    parameter [1:0] TOPOUTPUT_SELECT = 0,
    parameter [1:0] TOPADDSUB_LOWERINPUT = 0,
    parameter [0:0] TOPADDSUB_UPPERINPUT = 0,
    parameter [1:0] TOPADDSUB_CARRYSELECT = 0,
    parameter [1:0] BOTOUTPUT_SELECT = 0,
    parameter [1:0] BOTADDSUB_LOWERINPUT = 0,
    parameter [0:0] BOTADDSUB_UPPERINPUT = 0,
    parameter [1:0] BOTADDSUB_CARRYSELECT = 0,
    parameter [0:0] MODE_8x8 = 0,
    parameter [0:0] A_SIGNED = 0,
    parameter [0:0] B_SIGNED = 0
) (
    input CLK, CE,
    input [15:0] C, A, B, D,
    input AHOLD, BHOLD, CHOLD, DHOLD,
    input IRSTTOP, IRSTBOT,
    input ORSTTOP, ORSTBOT,
    input OLOADTOP, OLOADBOT,
    input ADDSUBTOP, ADDSUBBOT,
    input OHOLDTOP, OHOLDBOT,
    input CI, ACCUMCI, SIGNEXTIN,
    output [31:0] O,
    output CO, ACCUMCO, SIGNEXTOUT
);

    // 16x16 multiply
    wire signed [31:0] a_ext = A_SIGNED ? {{16{A[15]}}, A} : {16'b0, A};
    wire signed [31:0] b_ext = B_SIGNED ? {{16{B[15]}}, B} : {16'b0, B};
    wire signed [31:0] mult_result = a_ext * b_ext;

    // Accumulator register (for vmath MAC mode)
    reg [31:0] acc_reg;

    // Determine if we're in accumulator mode based on output select
    wire acc_mode = (TOPOUTPUT_SELECT == 2'b11) && (BOTOUTPUT_SELECT == 2'b11);

    // Output: either direct multiply or accumulator
    assign O = acc_mode ? acc_reg : mult_result;
    assign CO = 1'b0;
    assign ACCUMCO = 1'b0;
    assign SIGNEXTOUT = 1'b0;

    // Accumulator logic
    always @(posedge CLK) begin
        if (ORSTTOP || ORSTBOT) begin
            acc_reg <= 32'b0;
        end else if (CE) begin
            acc_reg <= acc_reg + mult_result;
        end
    end

endmodule
