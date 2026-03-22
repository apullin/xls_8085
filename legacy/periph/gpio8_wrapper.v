// GPIO8 Wrapper - Adds state registers around XLS-generated combinational logic
//
// 8-bit GPIO with edge-triggered IRQ and bitbanded DATA access

module gpio8_wrapper (
    input  wire        clk,
    input  wire        reset_n,

    // Memory-mapped register interface (16 bytes)
    input  wire [3:0]  addr,
    input  wire [7:0]  data_in,
    output wire [7:0]  data_out,
    input  wire        rd,
    input  wire        wr,

    // GPIO pins
    input  wire [7:0]  pins_in,     // Input from pads
    output wire [7:0]  pins_out,    // Output to pads
    output wire [7:0]  pins_oe,     // Output enable (active high)

    // Interrupt output
    output wire        irq
);

    // =========================================================================
    // State Registers
    // =========================================================================
    // GpioState: data_out[7:0], dir[7:0], out_mode[7:0], irq_en[7:0],
    //            irq_rise[7:0], irq_fall[7:0], irq_status[7:0], pin_prev[7:0]
    // Total: 64 bits

    reg [7:0] r_data_out;
    reg [7:0] r_dir;
    reg [7:0] r_out_mode;
    reg [7:0] r_irq_en;
    reg [7:0] r_irq_rise;
    reg [7:0] r_irq_fall;
    reg [7:0] r_irq_status;
    reg [7:0] r_pin_prev;

    // Pack state for XLS core (MSB first based on struct order)
    wire [63:0] state_in = {
        r_data_out,    // [63:56]
        r_dir,         // [55:48]
        r_out_mode,    // [47:40]
        r_irq_en,      // [39:32]
        r_irq_rise,    // [31:24]
        r_irq_fall,    // [23:16]
        r_irq_status,  // [15:8]
        r_pin_prev     // [7:0]
    };

    // Pack input for XLS core
    // GpioInput: addr[3:0], data_in[7:0], rd, wr, pins_in[7:0]
    wire [21:0] bus_in = {
        addr,      // [21:18]
        data_in,   // [17:10]
        rd,        // [9]
        wr,        // [8]
        pins_in    // [7:0]
    };

    // =========================================================================
    // XLS Combinational Core
    // =========================================================================

    wire [88:0] core_out;

    __gpio8__gpio_tick core (
        .state(state_in),
        .bus_in(bus_in),
        .out(core_out)
    );

    // Unpack output (89 bits total)
    // GpioState = 64 bits, GpioOutput = 25 bits (8+1+8+8)
    // out[88:25] = next_state
    // out[24:17] = data_out
    // out[16]    = irq
    // out[15:8]  = pins_out
    // out[7:0]   = pins_oe
    wire [63:0] next_state = core_out[88:25];
    wire [7:0]  next_data_out_bus = core_out[24:17];
    wire        next_irq = core_out[16];
    wire [7:0]  next_pins_out = core_out[15:8];
    wire [7:0]  next_pins_oe = core_out[7:0];

    // =========================================================================
    // State Update
    // =========================================================================

    // Unpack next state
    wire [7:0] next_r_data_out   = next_state[63:56];
    wire [7:0] next_r_dir        = next_state[55:48];
    wire [7:0] next_r_out_mode   = next_state[47:40];
    wire [7:0] next_r_irq_en     = next_state[39:32];
    wire [7:0] next_r_irq_rise   = next_state[31:24];
    wire [7:0] next_r_irq_fall   = next_state[23:16];
    wire [7:0] next_r_irq_status = next_state[15:8];
    wire [7:0] next_r_pin_prev   = next_state[7:0];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            r_data_out   <= 8'h00;
            r_dir        <= 8'h00;
            r_out_mode   <= 8'h00;
            r_irq_en     <= 8'h00;
            r_irq_rise   <= 8'h00;
            r_irq_fall   <= 8'h00;
            r_irq_status <= 8'h00;
            r_pin_prev   <= 8'h00;
        end else begin
            r_data_out   <= next_r_data_out;
            r_dir        <= next_r_dir;
            r_out_mode   <= next_r_out_mode;
            r_irq_en     <= next_r_irq_en;
            r_irq_rise   <= next_r_irq_rise;
            r_irq_fall   <= next_r_irq_fall;
            r_irq_status <= next_r_irq_status;
            r_pin_prev   <= next_r_pin_prev;
        end
    end

    // =========================================================================
    // Output - directly from combinational logic for immediate response
    // =========================================================================

    assign data_out = next_data_out_bus;
    assign irq = next_irq;
    assign pins_out = next_pins_out;
    assign pins_oe = next_pins_oe;

endmodule
