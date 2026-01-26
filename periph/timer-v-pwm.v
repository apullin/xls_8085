// Timer16 with PWM - Hand-written Verilog
// 16-bit timer with 4 compare channels, prescaler, up/down counting
// Added: 4 PWM outputs (active when counter < cmpN)
// Added: Up-down (center-aligned) counting mode for motor control PWM

module timer16_wrapper (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [3:0]  addr,
    input  wire [7:0]  data_in,
    output reg  [7:0]  data_out,
    input  wire        rd,
    input  wire        wr,
    input  wire        tick,
    output wire        irq,
    // PWM outputs (4 channels, center-aligned in up-down mode)
    output wire        pwm0,
    output wire        pwm1,
    output wire        pwm2,
    output wire        pwm3
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
    localparam REG_CMP2_LO   = 4'hC;
    localparam REG_CMP2_HI   = 4'hD;
    localparam REG_CMP3_LO   = 4'hE;
    localparam REG_CMP3_HI   = 4'hF;

    // CTRL bits
    localparam CTRL_ENABLE      = 0;
    localparam CTRL_AUTO_RELOAD = 1;
    localparam CTRL_COUNT_DOWN  = 2;
    localparam CTRL_UP_DOWN     = 3;  // Center-aligned mode: count up to reload, then down to 0

    // STATUS/IRQ bits
    localparam FLAG_CMP0 = 0;
    localparam FLAG_CMP1 = 1;
    localparam FLAG_CMP2 = 2;
    localparam FLAG_CMP3 = 3;
    localparam FLAG_OVF  = 4;  // Top of count (overflow or up-down peak)
    localparam FLAG_UNF  = 5;  // Bottom of count (up-down mode only)
    localparam FLAG_DIR  = 6;  // Read-only: 0=counting up, 1=counting down

    // Registers
    reg [15:0] counter;
    reg [15:0] reload;
    reg [7:0]  prescale;
    reg [7:0]  prescale_cnt;
    reg [7:0]  ctrl;
    reg [7:0]  irq_en;
    reg [7:0]  status;
    reg [15:0] cmp0, cmp1, cmp2, cmp3;
    reg [7:0]  cnt_hi_latch;
    reg        pwm0_prev, pwm1_prev, pwm2_prev, pwm3_prev;

    // Direction state for up-down mode
    reg count_dir;  // 0=counting up, 1=counting down

    // Control signals
    wire enabled = ctrl[CTRL_ENABLE];
    wire auto_reload = ctrl[CTRL_AUTO_RELOAD];
    wire count_down = ctrl[CTRL_COUNT_DOWN];
    wire up_down = ctrl[CTRL_UP_DOWN];

    // IRQ output
    assign irq = |(status & irq_en);

    // PWM outputs: high when counter < cmpN (center-aligned with up-down mode)
    assign pwm0 = enabled & (counter < cmp0);
    assign pwm1 = enabled & (counter < cmp1);
    assign pwm2 = enabled & (counter < cmp2);
    assign pwm3 = enabled & (counter < cmp3);

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
            REG_STATUS:    data_out = {1'b0, count_dir, status[5:0]};
            REG_CMP0_LO:   data_out = cmp0[7:0];
            REG_CMP0_HI:   data_out = cmp0[15:8];
            REG_CMP1_LO:   data_out = cmp1[7:0];
            REG_CMP1_HI:   data_out = cmp1[15:8];
            REG_CMP2_LO:   data_out = cmp2[7:0];
            REG_CMP2_HI:   data_out = cmp2[15:8];
            REG_CMP3_LO:   data_out = cmp3[7:0];
            REG_CMP3_HI:   data_out = cmp3[15:8];
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
            cmp2 <= 16'h0;
            cmp3 <= 16'h0;
            cnt_hi_latch <= 8'h0;
            count_dir <= 1'b0;
            pwm0_prev <= 1'b0;
            pwm1_prev <= 1'b0;
            pwm2_prev <= 1'b0;
            pwm3_prev <= 1'b0;
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
                    REG_CMP2_LO:   cmp2[7:0] <= data_in;
                    REG_CMP2_HI:   cmp2[15:8] <= data_in;
                    REG_CMP3_LO:   cmp3[7:0] <= data_in;
                    REG_CMP3_HI:   cmp3[15:8] <= data_in;
                endcase
            end

            // Timer counting logic
            if (tick && enabled) begin
                if (prescale_cnt >= prescale) begin
                    prescale_cnt <= 8'h0;

                    // Calculate next counter value and check overflow
                    if (up_down) begin
                        // Up-down (center-aligned) mode: 0 -> reload -> 0 -> ...
                        // Period = 2 * reload ticks (triangle wave)
                        if (count_dir) begin
                            counter <= counter - 16'h1;
                            // Switch to up when counter==1 (becomes 0): ~|[15:1] & [0]
                            if (counter[15:1] == 15'h0 && counter[0])
                                count_dir <= 1'b0;
                        end else begin
                            counter <= counter + 16'h1;
                            if (counter == reload) count_dir <= 1'b1;
                        end
                    end else if (count_down) begin
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

                    // Compare match detection via PWM edge (saves 4x 16-bit comparators)
                    pwm0_prev <= pwm0; if (pwm0 != pwm0_prev) status[FLAG_CMP0] <= 1'b1;
                    pwm1_prev <= pwm1; if (pwm1 != pwm1_prev) status[FLAG_CMP1] <= 1'b1;
                    pwm2_prev <= pwm2; if (pwm2 != pwm2_prev) status[FLAG_CMP2] <= 1'b1;
                    pwm3_prev <= pwm3; if (pwm3 != pwm3_prev) status[FLAG_CMP3] <= 1'b1;

                end else begin
                    prescale_cnt <= prescale_cnt + 8'h1;
                end
            end
        end
    end
endmodule
