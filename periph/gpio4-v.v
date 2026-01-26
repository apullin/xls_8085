// GPIO4 - Hand-written Verilog
// 4-pin GPIO with edge-triggered IRQ and open-drain support
// Smaller version of gpio8_wrapper for constrained designs

module gpio4_wrapper (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [3:0]  addr,
    input  wire [7:0]  data_in,
    output reg  [7:0]  data_out,
    input  wire        rd,
    input  wire        wr,
    input  wire [3:0]  pins_in,
    output wire [3:0]  pins_out,
    output wire [3:0]  pins_oe,
    output wire        irq
);
    // Register addresses (same as gpio8 for software compatibility)
    localparam REG_DATA_OUT   = 4'h0;
    localparam REG_DATA_IN    = 4'h1;
    localparam REG_DIR        = 4'h2;
    localparam REG_IRQ_EN     = 4'h3;
    localparam REG_IRQ_RISE   = 4'h4;
    localparam REG_IRQ_FALL   = 4'h5;
    localparam REG_IRQ_STATUS = 4'h6;
    localparam REG_OUT_MODE   = 4'h7;

    // 4-bit registers (not 8-bit!)
    reg [3:0] r_data_out;
    reg [3:0] r_dir;
    reg [3:0] r_irq_en;
    reg [3:0] r_irq_rise;
    reg [3:0] r_irq_fall;
    reg [3:0] r_irq_status;
    reg [3:0] r_out_mode;
    reg [3:0] r_pin_prev;

    // Actual pin values (output overrides input when direction is output)
    wire [3:0] actual_pins = (r_data_out & r_dir) | (pins_in & ~r_dir);

    // Edge detection
    wire [3:0] rising  = actual_pins & ~r_pin_prev;
    wire [3:0] falling = ~actual_pins & r_pin_prev;
    wire [3:0] rise_irqs = rising & r_irq_rise & r_irq_en;
    wire [3:0] fall_irqs = falling & r_irq_fall & r_irq_en;

    // Outputs
    assign pins_out = r_data_out;
    // Open-drain: only drive low (OE=0 when out_mode=1 and data=1)
    assign pins_oe = r_dir & ~(r_out_mode & r_data_out);
    assign irq = |(r_irq_status & r_irq_en);

    // Read mux - 4-bit mux then pad (saves LUTs vs 8-bit mux)
    reg [3:0] data_out_4;
    always @(*) begin
        case (addr)
            REG_DATA_OUT:   data_out_4 = r_data_out;
            REG_DATA_IN:    data_out_4 = actual_pins;
            REG_DIR:        data_out_4 = r_dir;
            REG_IRQ_EN:     data_out_4 = r_irq_en;
            REG_IRQ_RISE:   data_out_4 = r_irq_rise;
            REG_IRQ_FALL:   data_out_4 = r_irq_fall;
            REG_IRQ_STATUS: data_out_4 = r_irq_status;
            REG_OUT_MODE:   data_out_4 = r_out_mode;
            default:        data_out_4 = 4'hF;
        endcase
        data_out = {4'h0, data_out_4};
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            r_data_out <= 4'h0;
            r_dir <= 4'h0;
            r_irq_en <= 4'h0;
            r_irq_rise <= 4'h0;
            r_irq_fall <= 4'h0;
            r_irq_status <= 4'h0;
            r_out_mode <= 4'h0;
            r_pin_prev <= 4'h0;
        end else begin
            // Update pin history for edge detection
            r_pin_prev <= actual_pins;

            // Accumulate edge IRQs
            r_irq_status <= r_irq_status | rise_irqs | fall_irqs;

            // Register writes (only use lower 4 bits of data_in)
            if (wr) begin
                case (addr)
                    REG_DATA_OUT:   r_data_out <= data_in[3:0];
                    REG_DIR:        r_dir <= data_in[3:0];
                    REG_IRQ_EN:     r_irq_en <= data_in[3:0];
                    REG_IRQ_RISE:   r_irq_rise <= data_in[3:0];
                    REG_IRQ_FALL:   r_irq_fall <= data_in[3:0];
                    REG_IRQ_STATUS: r_irq_status <= r_irq_status & ~data_in[3:0];  // W1C
                    REG_OUT_MODE:   r_out_mode <= data_in[3:0];
                endcase
            end
        end
    end
endmodule
