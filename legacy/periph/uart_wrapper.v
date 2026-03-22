// UART Wrapper - Adds state registers around XLS-generated combinational logic
//
// UART with 8-deep FIFOs, fractional baud rate, parity, 7/8-bit word length

module uart_wrapper (
    input  wire        clk,
    input  wire        reset_n,

    // Memory-mapped register interface (16 bytes)
    input  wire [3:0]  addr,
    input  wire [7:0]  data_in,
    output wire [7:0]  data_out,
    input  wire        rd,
    input  wire        wr,

    // Serial pins
    input  wire        rx_pin,
    output wire        tx_pin,

    // Interrupt output
    output wire        irq
);

    // =========================================================================
    // State Registers
    // =========================================================================
    // UartState is 293 bits total - we'll let synthesis handle the packing

    reg [292:0] r_state;

    // Initial state values (from initial_state() function)
    localparam [292:0] INIT_STATE = 293'b0;

    // Pack input for XLS core
    // UartInput: addr[3:0], data_in[7:0], rd, wr, rx_pin
    wire [14:0] bus_in = {
        addr,       // [14:11]
        data_in,    // [10:3]
        rd,         // [2]
        wr,         // [1]
        rx_pin      // [0]
    };

    // =========================================================================
    // XLS Combinational Core
    // =========================================================================

    wire [302:0] core_out;

    __uart__uart_tick core (
        .state(r_state),
        .bus_in(bus_in),
        .out(core_out)
    );

    // Unpack output (303 bits total)
    // out[302:10] = next_state (293 bits)
    // out[9:2] = data_out (8 bits)
    // out[1] = irq
    // out[0] = tx_pin
    wire [292:0] next_state = core_out[302:10];
    wire [7:0]   next_data_out = core_out[9:2];
    wire         next_irq = core_out[1];
    wire         next_tx_pin = core_out[0];

    // =========================================================================
    // State Update
    // =========================================================================

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            r_state <= INIT_STATE;
        end else begin
            r_state <= next_state;
        end
    end

    // =========================================================================
    // Output - directly from combinational logic for immediate response
    // =========================================================================

    assign data_out = next_data_out;
    assign irq = next_irq;
    assign tx_pin = next_tx_pin;

endmodule
