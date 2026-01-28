// Timer16 - Hand-written Verilog
// 16-bit timer with configurable compare channels, prescaler, up/down counting
// Replaces XLS-generated timer16.v + timer16_wrapper.v
//
// Build-time config:
//   -DTIMER_3CMP  reduce from 4 to 3 compare channels
//   -DTIMER_2CMP  reduce from 4 to 2 compare channels (implies 3CMP)

module timer16_wrapper (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [3:0]  addr,
    input  wire [7:0]  data_in,
    output reg  [7:0]  data_out,
    input  wire        rd,
    input  wire        wr,
    input  wire        tick,
    output wire        irq
);
    // Register addresses
    localparam REG_CNT_LO    = 4'h0;
    localparam REG_CNT_HI    = 4'h1;
    localparam REG_RELOAD_LO = 4'h2;
    localparam REG_RELOAD_HI = 4'h3;
    localparam REG_PRESCALE  = 4'h4;
    localparam REG_CTRL      = 4'h5;
    localparam REG_IRQ_EN    = 4'h6;
    localparam REG_STATUS    = 4'h7;
    localparam REG_CMP0_LO   = 4'h8;
    localparam REG_CMP0_HI   = 4'h9;
    localparam REG_CMP1_LO   = 4'hA;
    localparam REG_CMP1_HI   = 4'hB;
`ifndef TIMER_2CMP
    localparam REG_CMP2_LO   = 4'hC;
    localparam REG_CMP2_HI   = 4'hD;
  `ifndef TIMER_3CMP
    localparam REG_CMP3_LO   = 4'hE;
    localparam REG_CMP3_HI   = 4'hF;
  `endif
`endif

    // CTRL bits
    localparam CTRL_ENABLE      = 0;
    localparam CTRL_AUTO_RELOAD = 1;
    localparam CTRL_COUNT_DOWN  = 2;

    // STATUS/IRQ bits
    localparam FLAG_CMP0 = 0;
    localparam FLAG_CMP1 = 1;
`ifndef TIMER_2CMP
    localparam FLAG_CMP2 = 2;
  `ifndef TIMER_3CMP
    localparam FLAG_CMP3 = 3;
  `endif
`endif
    localparam FLAG_OVF  = 4;

    // Registers
    reg [15:0] counter;
    reg [15:0] reload;
    reg [7:0]  prescale;
    reg [7:0]  prescale_cnt;
    reg [7:0]  ctrl;
    reg [7:0]  irq_en;
    reg [7:0]  status;
    reg [15:0] cmp0, cmp1;
`ifndef TIMER_2CMP
    reg [15:0] cmp2;
  `ifndef TIMER_3CMP
    reg [15:0] cmp3;
  `endif
`endif
    reg [7:0]  cnt_hi_latch;

    // Control signals
    wire enabled = ctrl[CTRL_ENABLE];
    wire auto_reload = ctrl[CTRL_AUTO_RELOAD];
    wire count_down = ctrl[CTRL_COUNT_DOWN];

    // IRQ output
    assign irq = |(status & irq_en);

    // Read mux
    always @(*) begin
        case (addr)
            REG_CNT_LO:    data_out = counter[7:0];
            REG_CNT_HI:    data_out = cnt_hi_latch;
            REG_RELOAD_LO: data_out = reload[7:0];
            REG_RELOAD_HI: data_out = reload[15:8];
            REG_PRESCALE:  data_out = prescale;
            REG_CTRL:      data_out = ctrl;
            REG_IRQ_EN:    data_out = irq_en;
            REG_STATUS:    data_out = status;
            REG_CMP0_LO:   data_out = cmp0[7:0];
            REG_CMP0_HI:   data_out = cmp0[15:8];
            REG_CMP1_LO:   data_out = cmp1[7:0];
            REG_CMP1_HI:   data_out = cmp1[15:8];
`ifndef TIMER_2CMP
            REG_CMP2_LO:   data_out = cmp2[7:0];
            REG_CMP2_HI:   data_out = cmp2[15:8];
  `ifndef TIMER_3CMP
            REG_CMP3_LO:   data_out = cmp3[7:0];
            REG_CMP3_HI:   data_out = cmp3[15:8];
  `endif
`endif
            default:       data_out = 8'hFF;
        endcase
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            counter <= 16'h0;
            reload <= 16'h0;
            prescale <= 8'h0;
            prescale_cnt <= 8'h0;
            ctrl <= 8'h0;
            irq_en <= 8'h0;
            status <= 8'h0;
            cmp0 <= 16'h0;
            cmp1 <= 16'h0;
`ifndef TIMER_2CMP
            cmp2 <= 16'h0;
  `ifndef TIMER_3CMP
            cmp3 <= 16'h0;
  `endif
`endif
            cnt_hi_latch <= 8'h0;
        end else begin
            // Atomic read: latch high byte when low byte is read
            if (rd && addr == REG_CNT_LO)
                cnt_hi_latch <= counter[15:8];

            // Register writes
            if (wr) begin
                case (addr)
                    REG_CNT_LO:    counter[7:0] <= data_in;
                    REG_CNT_HI:    counter[15:8] <= data_in;
                    REG_RELOAD_LO: reload[7:0] <= data_in;
                    REG_RELOAD_HI: reload[15:8] <= data_in;
                    REG_PRESCALE:  prescale <= data_in;
                    REG_CTRL:      ctrl <= data_in;
                    REG_IRQ_EN:    irq_en <= data_in;
                    REG_STATUS:    status <= status & ~data_in;  // W1C
                    REG_CMP0_LO:   cmp0[7:0] <= data_in;
                    REG_CMP0_HI:   cmp0[15:8] <= data_in;
                    REG_CMP1_LO:   cmp1[7:0] <= data_in;
                    REG_CMP1_HI:   cmp1[15:8] <= data_in;
`ifndef TIMER_2CMP
                    REG_CMP2_LO:   cmp2[7:0] <= data_in;
                    REG_CMP2_HI:   cmp2[15:8] <= data_in;
  `ifndef TIMER_3CMP
                    REG_CMP3_LO:   cmp3[7:0] <= data_in;
                    REG_CMP3_HI:   cmp3[15:8] <= data_in;
  `endif
`endif
                endcase
            end

            // Timer counting logic
            if (tick && enabled) begin
                if (prescale_cnt >= prescale) begin
                    prescale_cnt <= 8'h0;

                    // Calculate next counter value and check overflow
                    if (count_down) begin
                        // Count down mode
                        if (counter == 16'h0000) begin
                            // Overflow (underflow)
                            status[FLAG_OVF] <= 1'b1;
                            if (auto_reload)
                                counter <= reload;
                            else
                                ctrl[CTRL_ENABLE] <= 1'b0;  // One-shot: disable
                        end else begin
                            counter <= counter - 16'h1;
                        end
                    end else begin
                        // Count up mode
                        if (counter == 16'hFFFF) begin
                            // Overflow
                            status[FLAG_OVF] <= 1'b1;
                            if (auto_reload)
                                counter <= reload;
                            else
                                ctrl[CTRL_ENABLE] <= 1'b0;  // One-shot: disable
                        end else begin
                            counter <= counter + 16'h1;
                        end
                    end

                    // Compare match detection (against current counter value)
                    if (counter == cmp0) status[FLAG_CMP0] <= 1'b1;
                    if (counter == cmp1) status[FLAG_CMP1] <= 1'b1;
`ifndef TIMER_2CMP
                    if (counter == cmp2) status[FLAG_CMP2] <= 1'b1;
  `ifndef TIMER_3CMP
                    if (counter == cmp3) status[FLAG_CMP3] <= 1'b1;
  `endif
`endif

                end else begin
                    prescale_cnt <= prescale_cnt + 8'h1;
                end
            end
        end
    end
endmodule
