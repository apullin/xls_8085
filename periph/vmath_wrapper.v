// Vector Math Unit (vmath) - 4-wide int8 MAC with DSP accumulators
// Uses 4x SB_MAC16 in 16x16 mode, each with internal 32-bit accumulator
// Eliminates per-cycle adder tree by accumulating inside DSPs
//
// Operation:
//   1. CPU sets A_PTR, B_PTR, LEN, BIAS via register writes
//   2. CPU writes START to CTRL (clears DSP accumulators)
//   3. vmath takes SPRAM bus, CPU stalls:
//      - Reads 4 bytes from A_PTR (weights)
//      - Reads 4 bytes from B_PTR (activations)
//      - Each DSP: acc += a[i] * b[i] (internal accumulate)
//      - Increments pointers by 4, decrements LEN by 4
//      - Repeats until LEN == 0
//   4. Sums 4 DSP accumulators + BIAS (one-time final add)
//   5. Writes result to OUT_PTR
//   6. Clears BUSY, releases bus
//
// DSP allocation: 4x SB_MAC16 (uses internal accumulators)
// Accumulator overflow: safe up to ~131K products per DSP (~500K total)
//
// Register Map:
//   0x0: A_PTR[7:0]    - Source pointer A (weights)
//   0x1: A_PTR[15:8]
//   0x2: A_PTR[23:16]  - Includes bank bits [16:15]
//   0x3: B_PTR[7:0]    - Source pointer B (activations)
//   0x4: B_PTR[15:8]
//   0x5: B_PTR[23:16]
//   0x6: LEN[7:0]      - Element count (must be multiple of 4)
//   0x7: LEN[15:8]
//   0x8: ACC[7:0]      - Final result (read-only)
//   0x9: ACC[15:8]
//   0xA: ACC[23:16]
//   0xB: ACC[31:24]
//   0xC: BIAS[7:0]     - Bias value
//   0xD: BIAS[15:8]
//   0xE: BIAS[23:16]
//   0xF: CTRL          - [0]=START, [1]=CLEAR_ACC, [6]=DONE, [7]=BUSY
//
// Performance: 6 cycles per 4 MACs = 1.5 cycles/MAC (same as before)
// LUT savings: ~100 LUTs (no per-cycle adder tree)

module vmath_wrapper (
    input  wire        clk,
    input  wire        reset_n,

    // CPU bus interface (8-bit)
    input  wire [3:0]  addr,
    input  wire [7:0]  data_in,
    output reg  [7:0]  data_out,
    input  wire        rd,
    input  wire        wr,

    // 16-bit SPRAM interface
    output reg  [13:0] mem_addr,
    output reg  [1:0]  mem_bank,
    input  wire [15:0] mem_rdata,
    output reg  [15:0] mem_wdata,
    output reg  [3:0]  mem_we,
    output wire        bus_request,

    // Status
    output wire        busy
);

    // Registers
    reg [23:0] a_ptr;
    reg [23:0] b_ptr;
    reg [23:0] out_ptr;
    reg [15:0] len;
    reg [31:0] acc;         // Final summed result
    reg [31:0] bias;

    reg        running;
    reg        done_flag;

    // FSM states
    localparam [3:0]
        ST_IDLE       = 4'd0,
        ST_LOAD_A_LO  = 4'd1,
        ST_LOAD_A_HI  = 4'd2,
        ST_LOAD_B_LO  = 4'd3,
        ST_LOAD_B_HI  = 4'd4,
        ST_COMPUTE    = 4'd5,
        ST_INC_CHECK  = 4'd6,
        ST_SUM_ACCS   = 4'd7,
        ST_ADD_BIAS   = 4'd8,
        ST_WRITE_LO   = 4'd9,
        ST_WRITE_HI   = 4'd10,
        ST_DONE       = 4'd11;

    reg [3:0] state;

    // Latched operands
    reg [31:0] a_val;
    reg [31:0] b_val;

    // DSP control
    reg dsp_clear;      // Clear accumulators (pulse)
    reg dsp_accum;      // Enable accumulation

    // DSP inputs - sign-extend 8-bit to 16-bit for 16x16 mode
    wire signed [15:0] dsp0_a = {{8{a_val[7]}}, a_val[7:0]};
    wire signed [15:0] dsp0_b = {{8{b_val[7]}}, b_val[7:0]};
    wire signed [15:0] dsp1_a = {{8{a_val[15]}}, a_val[15:8]};
    wire signed [15:0] dsp1_b = {{8{b_val[15]}}, b_val[15:8]};
    wire signed [15:0] dsp2_a = {{8{a_val[23]}}, a_val[23:16]};
    wire signed [15:0] dsp2_b = {{8{b_val[23]}}, b_val[23:16]};
    wire signed [15:0] dsp3_a = {{8{a_val[31]}}, a_val[31:24]};
    wire signed [15:0] dsp3_b = {{8{b_val[31]}}, b_val[31:24]};

    // DSP outputs (32-bit accumulators)
    wire [31:0] dsp0_acc;
    wire [31:0] dsp1_acc;
    wire [31:0] dsp2_acc;
    wire [31:0] dsp3_acc;

    // Final sum of all accumulators (only computed once at end)
    wire signed [31:0] acc_sum = dsp0_acc + dsp1_acc + dsp2_acc + dsp3_acc;

    // DSP 0: 16x16 multiply-accumulate for a0*b0
    SB_MAC16 #(
        .NEG_TRIGGER(1'b0),
        .A_REG(1'b0), .B_REG(1'b0), .C_REG(1'b0), .D_REG(1'b0),
        .TOP_8x8_MULT_REG(1'b0), .BOT_8x8_MULT_REG(1'b0),
        .PIPELINE_16x16_MULT_REG1(1'b0), .PIPELINE_16x16_MULT_REG2(1'b0),
        // Output from accumulator
        .TOPOUTPUT_SELECT(2'b11),      // Accumulator output
        .TOPADDSUB_LOWERINPUT(2'b00),  // Multiply result to adder
        .TOPADDSUB_UPPERINPUT(1'b0),   // Accumulator feedback
        .TOPADDSUB_CARRYSELECT(2'b10), // Cascade carry from bottom
        .BOTOUTPUT_SELECT(2'b11),      // Accumulator output
        .BOTADDSUB_LOWERINPUT(2'b00),  // Multiply result to adder
        .BOTADDSUB_UPPERINPUT(1'b0),   // Accumulator feedback
        .BOTADDSUB_CARRYSELECT(2'b00), // No carry in
        .MODE_8x8(1'b0),               // 16x16 mode
        .A_SIGNED(1'b1),
        .B_SIGNED(1'b1)
    ) dsp0 (
        .CLK(clk),
        .CE(dsp_accum),                // Only accumulate when enabled
        .A(dsp0_a), .B(dsp0_b),
        .C(16'b0), .D(16'b0),
        .AHOLD(1'b0), .BHOLD(1'b0), .CHOLD(1'b0), .DHOLD(1'b0),
        .IRSTTOP(1'b0), .IRSTBOT(1'b0),
        .ORSTTOP(dsp_clear), .ORSTBOT(dsp_clear),  // Clear accumulators
        .OLOADTOP(1'b0), .OLOADBOT(1'b0),
        .ADDSUBTOP(1'b0), .ADDSUBBOT(1'b0),        // Add (not subtract)
        .OHOLDTOP(1'b0), .OHOLDBOT(1'b0),
        .CI(1'b0), .ACCUMCI(1'b0), .SIGNEXTIN(1'b0),
        .O(dsp0_acc), .CO(), .ACCUMCO(), .SIGNEXTOUT()
    );

    // DSP 1: for a1*b1
    SB_MAC16 #(
        .NEG_TRIGGER(1'b0),
        .A_REG(1'b0), .B_REG(1'b0), .C_REG(1'b0), .D_REG(1'b0),
        .TOP_8x8_MULT_REG(1'b0), .BOT_8x8_MULT_REG(1'b0),
        .PIPELINE_16x16_MULT_REG1(1'b0), .PIPELINE_16x16_MULT_REG2(1'b0),
        .TOPOUTPUT_SELECT(2'b11),
        .TOPADDSUB_LOWERINPUT(2'b00),
        .TOPADDSUB_UPPERINPUT(1'b0),
        .TOPADDSUB_CARRYSELECT(2'b10),
        .BOTOUTPUT_SELECT(2'b11),
        .BOTADDSUB_LOWERINPUT(2'b00),
        .BOTADDSUB_UPPERINPUT(1'b0),
        .BOTADDSUB_CARRYSELECT(2'b00),
        .MODE_8x8(1'b0),
        .A_SIGNED(1'b1),
        .B_SIGNED(1'b1)
    ) dsp1 (
        .CLK(clk), .CE(dsp_accum),
        .A(dsp1_a), .B(dsp1_b),
        .C(16'b0), .D(16'b0),
        .AHOLD(1'b0), .BHOLD(1'b0), .CHOLD(1'b0), .DHOLD(1'b0),
        .IRSTTOP(1'b0), .IRSTBOT(1'b0),
        .ORSTTOP(dsp_clear), .ORSTBOT(dsp_clear),
        .OLOADTOP(1'b0), .OLOADBOT(1'b0),
        .ADDSUBTOP(1'b0), .ADDSUBBOT(1'b0),
        .OHOLDTOP(1'b0), .OHOLDBOT(1'b0),
        .CI(1'b0), .ACCUMCI(1'b0), .SIGNEXTIN(1'b0),
        .O(dsp1_acc), .CO(), .ACCUMCO(), .SIGNEXTOUT()
    );

    // DSP 2: for a2*b2
    SB_MAC16 #(
        .NEG_TRIGGER(1'b0),
        .A_REG(1'b0), .B_REG(1'b0), .C_REG(1'b0), .D_REG(1'b0),
        .TOP_8x8_MULT_REG(1'b0), .BOT_8x8_MULT_REG(1'b0),
        .PIPELINE_16x16_MULT_REG1(1'b0), .PIPELINE_16x16_MULT_REG2(1'b0),
        .TOPOUTPUT_SELECT(2'b11),
        .TOPADDSUB_LOWERINPUT(2'b00),
        .TOPADDSUB_UPPERINPUT(1'b0),
        .TOPADDSUB_CARRYSELECT(2'b10),
        .BOTOUTPUT_SELECT(2'b11),
        .BOTADDSUB_LOWERINPUT(2'b00),
        .BOTADDSUB_UPPERINPUT(1'b0),
        .BOTADDSUB_CARRYSELECT(2'b00),
        .MODE_8x8(1'b0),
        .A_SIGNED(1'b1),
        .B_SIGNED(1'b1)
    ) dsp2 (
        .CLK(clk), .CE(dsp_accum),
        .A(dsp2_a), .B(dsp2_b),
        .C(16'b0), .D(16'b0),
        .AHOLD(1'b0), .BHOLD(1'b0), .CHOLD(1'b0), .DHOLD(1'b0),
        .IRSTTOP(1'b0), .IRSTBOT(1'b0),
        .ORSTTOP(dsp_clear), .ORSTBOT(dsp_clear),
        .OLOADTOP(1'b0), .OLOADBOT(1'b0),
        .ADDSUBTOP(1'b0), .ADDSUBBOT(1'b0),
        .OHOLDTOP(1'b0), .OHOLDBOT(1'b0),
        .CI(1'b0), .ACCUMCI(1'b0), .SIGNEXTIN(1'b0),
        .O(dsp2_acc), .CO(), .ACCUMCO(), .SIGNEXTOUT()
    );

    // DSP 3: for a3*b3
    SB_MAC16 #(
        .NEG_TRIGGER(1'b0),
        .A_REG(1'b0), .B_REG(1'b0), .C_REG(1'b0), .D_REG(1'b0),
        .TOP_8x8_MULT_REG(1'b0), .BOT_8x8_MULT_REG(1'b0),
        .PIPELINE_16x16_MULT_REG1(1'b0), .PIPELINE_16x16_MULT_REG2(1'b0),
        .TOPOUTPUT_SELECT(2'b11),
        .TOPADDSUB_LOWERINPUT(2'b00),
        .TOPADDSUB_UPPERINPUT(1'b0),
        .TOPADDSUB_CARRYSELECT(2'b10),
        .BOTOUTPUT_SELECT(2'b11),
        .BOTADDSUB_LOWERINPUT(2'b00),
        .BOTADDSUB_UPPERINPUT(1'b0),
        .BOTADDSUB_CARRYSELECT(2'b00),
        .MODE_8x8(1'b0),
        .A_SIGNED(1'b1),
        .B_SIGNED(1'b1)
    ) dsp3 (
        .CLK(clk), .CE(dsp_accum),
        .A(dsp3_a), .B(dsp3_b),
        .C(16'b0), .D(16'b0),
        .AHOLD(1'b0), .BHOLD(1'b0), .CHOLD(1'b0), .DHOLD(1'b0),
        .IRSTTOP(1'b0), .IRSTBOT(1'b0),
        .ORSTTOP(dsp_clear), .ORSTBOT(dsp_clear),
        .OLOADTOP(1'b0), .OLOADBOT(1'b0),
        .ADDSUBTOP(1'b0), .ADDSUBBOT(1'b0),
        .OHOLDTOP(1'b0), .OHOLDBOT(1'b0),
        .CI(1'b0), .ACCUMCI(1'b0), .SIGNEXTIN(1'b0),
        .O(dsp3_acc), .CO(), .ACCUMCO(), .SIGNEXTOUT()
    );

    // Outputs
    assign bus_request = running;
    assign busy = running;

    // FSM
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= ST_IDLE;
            running <= 1'b0;
            done_flag <= 1'b0;
            a_ptr <= 24'b0;
            b_ptr <= 24'b0;
            out_ptr <= 24'b0;
            len <= 16'b0;
            acc <= 32'b0;
            bias <= 32'b0;
            a_val <= 32'b0;
            b_val <= 32'b0;
            mem_addr <= 14'b0;
            mem_bank <= 2'b0;
            mem_wdata <= 16'b0;
            mem_we <= 4'b0;
            dsp_clear <= 1'b0;
            dsp_accum <= 1'b0;
        end else begin
            // Defaults
            mem_we <= 4'b0;
            dsp_clear <= 1'b0;
            dsp_accum <= 1'b0;

            case (state)
                ST_IDLE: begin
                    // Wait for START
                end

                ST_LOAD_A_LO: begin
                    mem_addr <= a_ptr[14:1];
                    mem_bank <= a_ptr[16:15];
                    state <= ST_LOAD_A_HI;
                end

                ST_LOAD_A_HI: begin
                    a_val[15:0] <= mem_rdata;
                    mem_addr <= a_ptr[14:1] + 14'd1;
                    mem_bank <= a_ptr[16:15];
                    state <= ST_LOAD_B_LO;
                end

                ST_LOAD_B_LO: begin
                    a_val[31:16] <= mem_rdata;
                    mem_addr <= b_ptr[14:1];
                    mem_bank <= b_ptr[16:15];
                    state <= ST_LOAD_B_HI;
                end

                ST_LOAD_B_HI: begin
                    b_val[15:0] <= mem_rdata;
                    mem_addr <= b_ptr[14:1] + 14'd1;
                    mem_bank <= b_ptr[16:15];
                    state <= ST_COMPUTE;
                end

                ST_COMPUTE: begin
                    b_val[31:16] <= mem_rdata;
                    // DSP inputs are ready, trigger accumulation
                    dsp_accum <= 1'b1;
                    state <= ST_INC_CHECK;
                end

                ST_INC_CHECK: begin
                    // Increment pointers, decrement length
                    a_ptr <= a_ptr + 24'd4;
                    b_ptr <= b_ptr + 24'd4;
                    len <= len - 16'd4;

                    if (len <= 16'd4) begin
                        state <= ST_SUM_ACCS;
                    end else begin
                        state <= ST_LOAD_A_LO;
                    end
                end

                ST_SUM_ACCS: begin
                    // Sum all 4 DSP accumulators (one-time operation)
                    acc <= acc_sum;
                    state <= ST_ADD_BIAS;
                end

                ST_ADD_BIAS: begin
                    acc <= acc + bias;
                    state <= ST_WRITE_LO;
                end

                ST_WRITE_LO: begin
                    mem_addr <= out_ptr[14:1];
                    mem_bank <= out_ptr[16:15];
                    mem_wdata <= acc[15:0];
                    mem_we <= 4'b0011;
                    state <= ST_WRITE_HI;
                end

                ST_WRITE_HI: begin
                    mem_addr <= out_ptr[14:1] + 14'd1;
                    mem_bank <= out_ptr[16:15];
                    mem_wdata <= acc[31:16];
                    mem_we <= 4'b0011;
                    state <= ST_DONE;
                end

                ST_DONE: begin
                    running <= 1'b0;
                    done_flag <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase

            // Register writes (only when not running)
            if (wr && !running) begin
                case (addr)
                    4'h0: a_ptr[7:0]   <= data_in;
                    4'h1: a_ptr[15:8]  <= data_in;
                    4'h2: a_ptr[23:16] <= data_in;
                    4'h3: b_ptr[7:0]   <= data_in;
                    4'h4: b_ptr[15:8]  <= data_in;
                    4'h5: b_ptr[23:16] <= data_in;
                    4'h6: len[7:0]     <= data_in;
                    4'h7: len[15:8]    <= data_in;
                    4'h8: acc[7:0]     <= data_in;
                    4'h9: acc[15:8]    <= data_in;
                    4'hA: acc[23:16]   <= data_in;
                    4'hB: acc[31:24]   <= data_in;
                    4'hC: bias[7:0]    <= data_in;
                    4'hD: bias[15:8]   <= data_in;
                    4'hE: bias[23:16]  <= data_in;
                    4'hF: begin
                        if (data_in[0]) begin  // START
                            running <= 1'b1;
                            done_flag <= 1'b0;
                            out_ptr <= b_ptr;
                            dsp_clear <= 1'b1;  // Clear DSP accumulators
                            acc <= 32'b0;
                            state <= ST_LOAD_A_LO;
                        end
                    end
                endcase
            end
        end
    end

    // Register read
    always @(*) begin
        case (addr)
            4'h0: data_out = a_ptr[7:0];
            4'h1: data_out = a_ptr[15:8];
            4'h2: data_out = a_ptr[23:16];
            4'h3: data_out = b_ptr[7:0];
            4'h4: data_out = b_ptr[15:8];
            4'h5: data_out = b_ptr[23:16];
            4'h6: data_out = len[7:0];
            4'h7: data_out = len[15:8];
            4'h8: data_out = acc[7:0];
            4'h9: data_out = acc[15:8];
            4'hA: data_out = acc[23:16];
            4'hB: data_out = acc[31:24];
            4'hC: data_out = bias[7:0];
            4'hD: data_out = bias[15:8];
            4'hE: data_out = bias[23:16];
            4'hF: data_out = {running, done_flag, 6'b0};
            default: data_out = 8'h00;
        endcase
    end

endmodule
