// GPIO8 - Hand-written Verilog
// 8-pin GPIO with edge-triggered IRQ and open-drain support
// Replaces XLS-generated gpio8.v + gpio8_wrapper.v
// NOTE: Bitbanding removed to save LUTs

module gpio8_wrapper (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [3:0]  addr,
    input  wire [7:0]  data_in,
    output reg  [7:0]  data_out,
    input  wire        rd,
    input  wire        wr,
    input  wire [7:0]  pins_in,
    output wire [7:0]  pins_out,
    output wire [7:0]  pins_oe,
    output wire        irq
);
    // Register addresses (no bitbanding - only 8 registers)
    localparam REG_DATA_OUT   = 4'h0;
    localparam REG_DATA_IN    = 4'h1;
    localparam REG_DIR        = 4'h2;
    localparam REG_IRQ_EN     = 4'h3;
    localparam REG_IRQ_RISE   = 4'h4;
    localparam REG_IRQ_FALL   = 4'h5;
    localparam REG_IRQ_STATUS = 4'h6;
    localparam REG_OUT_MODE   = 4'h7;

    // Registers
    reg [7:0] r_data_out;
    reg [7:0] r_dir;
    reg [7:0] r_irq_en;
    reg [7:0] r_irq_rise;
    reg [7:0] r_irq_fall;
    reg [7:0] r_irq_status;
    reg [7:0] r_out_mode;
    reg [7:0] r_pin_prev;

    // Actual pin values (output overrides input when direction is output)
    wire [7:0] actual_pins = (r_data_out & r_dir) | (pins_in & ~r_dir);

    // Edge detection
    wire [7:0] rising  = actual_pins & ~r_pin_prev;
    wire [7:0] falling = ~actual_pins & r_pin_prev;
    wire [7:0] rise_irqs = rising & r_irq_rise & r_irq_en;
    wire [7:0] fall_irqs = falling & r_irq_fall & r_irq_en;

    // Outputs
    assign pins_out = r_data_out;
    // Open-drain: only drive low (OE=0 when out_mode=1 and data=1)
    assign pins_oe = r_dir & ~(r_out_mode & r_data_out);
    assign irq = |(r_irq_status & r_irq_en);

    // Read mux
    always @(*) begin
        case (addr)
            REG_DATA_OUT:   data_out = r_data_out;
            REG_DATA_IN:    data_out = actual_pins;
            REG_DIR:        data_out = r_dir;
            REG_IRQ_EN:     data_out = r_irq_en;
            REG_IRQ_RISE:   data_out = r_irq_rise;
            REG_IRQ_FALL:   data_out = r_irq_fall;
            REG_IRQ_STATUS: data_out = r_irq_status;
            REG_OUT_MODE:   data_out = r_out_mode;
            default:        data_out = 8'hFF;
        endcase
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            r_data_out <= 8'h0;
            r_dir <= 8'h0;
            r_irq_en <= 8'h0;
            r_irq_rise <= 8'h0;
            r_irq_fall <= 8'h0;
            r_irq_status <= 8'h0;
            r_out_mode <= 8'h0;
            r_pin_prev <= 8'h0;
        end else begin
            // Update pin history for edge detection
            r_pin_prev <= actual_pins;

            // Accumulate edge IRQs
            r_irq_status <= r_irq_status | rise_irqs | fall_irqs;

            // Register writes
            if (wr) begin
                case (addr)
                    REG_DATA_OUT:   r_data_out <= data_in;
                    REG_DIR:        r_dir <= data_in;
                    REG_IRQ_EN:     r_irq_en <= data_in;
                    REG_IRQ_RISE:   r_irq_rise <= data_in;
                    REG_IRQ_FALL:   r_irq_fall <= data_in;
                    REG_IRQ_STATUS: r_irq_status <= r_irq_status & ~data_in;  // W1C
                    REG_OUT_MODE:   r_out_mode <= data_in;
                endcase
            end
        end
    end
endmodule
