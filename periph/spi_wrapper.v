// SPI Master Wrapper
// Wraps the XLS-generated combinational SPI logic with state registers

module spi_wrapper (
    input  wire        clk,
    input  wire        reset_n,

    // Bus interface
    input  wire [3:0]  addr,
    input  wire [7:0]  data_in,
    output wire [7:0]  data_out,
    input  wire        rd,
    input  wire        wr,

    // SPI pins
    input  wire        miso,
    output wire        sck,
    output wire        mosi,
    output wire        cs_n,

    // Interrupt
    output wire        irq
);

    // State register width from XLS-generated module
    // SpiState contains:
    //   ctrl: u8, div: u8, cs_reg: u8, irq_en: u8, irq_stat: u8 = 40 bits
    //   div_counter: u8, sck_phase: bool = 9 bits
    //   state: u2, tx_shift: u8, rx_shift: u8, bit_idx: u3 = 21 bits
    //   tx_fifo: u8[4] = 32 bits, tx_fifo_head: u2, tx_fifo_tail: u2, tx_fifo_count: u3 = 7 bits
    //   rx_fifo: u8[4] = 32 bits, rx_fifo_head: u2, rx_fifo_tail: u2, rx_fifo_count: u3 = 7 bits
    //   sck_out: bool, mosi_out: bool, cs_n_out: bool = 3 bits
    // Total: 40 + 9 + 21 + 39 + 39 + 3 = 151 bits
    localparam STATE_WIDTH = 151;

    // State register
    reg [STATE_WIDTH-1:0] state_reg;

    // Initial state (must match initial_state() in DSLX)
    // Packed order matches struct field order in DSLX
    localparam [STATE_WIDTH-1:0] INIT_STATE = {
        8'h00,                  // ctrl
        8'h00,                  // div
        8'h01,                  // cs_reg (CS deasserted)
        8'h00,                  // irq_en
        8'h00,                  // irq_stat
        8'h00,                  // div_counter
        1'b0,                   // sck_phase
        2'd0,                   // state (ST_IDLE)
        8'h00,                  // tx_shift
        8'h00,                  // rx_shift
        3'd0,                   // bit_idx
        32'h00000000,           // tx_fifo[4]
        2'd0,                   // tx_fifo_head
        2'd0,                   // tx_fifo_tail
        3'd0,                   // tx_fifo_count
        32'h00000000,           // rx_fifo[4]
        2'd0,                   // rx_fifo_head
        2'd0,                   // rx_fifo_tail
        3'd0,                   // rx_fifo_count
        1'b0,                   // sck_out
        1'b0,                   // mosi_out
        1'b1                    // cs_n_out (deasserted)
    };

    // Pack bus input
    wire [14:0] bus_in = {addr, data_in, wr, rd, miso};

    // XLS-generated combinational logic output
    wire [STATE_WIDTH + 10:0] tick_out;  // state + output (8 + 1 + 1 + 1 = 11 bits)

    // Instantiate XLS-generated module
    __spi__spi_tick_fn spi_logic (
        .state(state_reg),
        .bus_in(bus_in),
        .out(tick_out)
    );

    // Unpack output
    wire [STATE_WIDTH-1:0] next_state = tick_out[STATE_WIDTH + 10:11];
    wire [7:0] data_out_comb = tick_out[10:3];
    wire irq_comb = tick_out[2];
    wire sck_comb = tick_out[1];
    wire mosi_comb = tick_out[0];

    // Get cs_n from state (last bit of state)
    wire cs_n_comb = next_state[0];

    // State update
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_reg <= INIT_STATE;
        end else begin
            state_reg <= next_state;
        end
    end

    // Outputs
    assign data_out = data_out_comb;
    assign irq = irq_comb;
    assign sck = sck_comb;
    assign mosi = mosi_comb;
    assign cs_n = cs_n_comb;

endmodule
