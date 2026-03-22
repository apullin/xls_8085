// SPI Flash Read Engine
// Implements JEDEC standard read command (0x03) for SPI NOR flash
// SPI Mode 0: CPOL=0, CPHA=0 (clock idle low, sample on rising edge)
// SCK = system clock / 2

module spi_engine (
    input  wire        clk,
    input  wire        reset_n,

    // Command Interface
    input  wire        cmd_start,     // Pulse to start transaction
    input  wire [23:0] cmd_addr,      // 24-bit flash address
    input  wire [6:0]  cmd_len,       // Bytes to read (1-64, 0 = 64)
    output wire        cmd_busy,      // Transaction in progress

    // Data Interface
    output reg  [7:0]  data_out,      // Received byte
    output reg         data_valid,    // Byte ready (1-cycle pulse)
    output reg  [5:0]  data_index,    // Byte position within transfer (0-63)

    // SPI Pins
    output reg         spi_sck,
    output reg         spi_cs_n,
    output reg         spi_mosi,
    input  wire        spi_miso
);

    // =========================================================================
    // FSM States
    // =========================================================================

    localparam S_IDLE     = 3'd0;
    localparam S_CMD      = 3'd1;   // Send 0x03 command (8 bits)
    localparam S_ADDR     = 3'd2;   // Send 24-bit address
    localparam S_DATA     = 3'd3;   // Receive data bytes
    localparam S_DONE     = 3'd4;   // Deassert CS, return to idle

    reg [2:0] state;

    // =========================================================================
    // Shift Registers and Counters
    // =========================================================================

    reg [31:0] tx_shift;      // Transmit shift register (cmd + addr)
    reg [7:0]  rx_shift;      // Receive shift register
    reg [5:0]  bit_count;     // Bits remaining in current phase
    reg [6:0]  bytes_remain;  // Bytes remaining to receive
    reg        sck_phase;     // 0 = falling edge next, 1 = rising edge next

    // Latched command parameters
    reg [23:0] addr_latch;
    reg [6:0]  len_latch;

    assign cmd_busy = (state != S_IDLE);

    // =========================================================================
    // SPI Clock Generation and Data Shifting
    // =========================================================================

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_IDLE;
            spi_sck <= 1'b0;
            spi_cs_n <= 1'b1;
            spi_mosi <= 1'b0;
            tx_shift <= 32'd0;
            rx_shift <= 8'd0;
            bit_count <= 6'd0;
            bytes_remain <= 7'd0;
            sck_phase <= 1'b0;
            data_out <= 8'd0;
            data_valid <= 1'b0;
            data_index <= 6'd0;
            addr_latch <= 24'd0;
            len_latch <= 7'd0;
        end else begin
            // Default: clear data_valid pulse
            data_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    spi_sck <= 1'b0;
                    spi_cs_n <= 1'b1;
                    sck_phase <= 1'b0;

                    if (cmd_start) begin
                        // Latch parameters and start transaction
                        addr_latch <= cmd_addr;
                        len_latch <= (cmd_len == 7'd0) ? 7'd64 : cmd_len;
                        bytes_remain <= (cmd_len == 7'd0) ? 7'd64 : cmd_len;
                        data_index <= 6'd0;

                        // Prepare command byte in shift register
                        tx_shift <= {8'h03, cmd_addr};  // 0x03 = Read command
                        bit_count <= 6'd8;  // 8 bits for command

                        // Assert CS
                        spi_cs_n <= 1'b0;
                        spi_mosi <= 1'b0;  // Will be set on first clock
                        state <= S_CMD;
                    end
                end

                S_CMD: begin
                    // Send 8-bit command (0x03)
                    if (sck_phase == 1'b0) begin
                        // Falling edge: setup data (or first bit setup)
                        spi_mosi <= tx_shift[31];
                        spi_sck <= 1'b0;
                        sck_phase <= 1'b1;
                    end else begin
                        // Rising edge: clock data out
                        spi_sck <= 1'b1;
                        tx_shift <= {tx_shift[30:0], 1'b0};
                        bit_count <= bit_count - 6'd1;
                        sck_phase <= 1'b0;

                        if (bit_count == 6'd1) begin
                            // Command done, start address phase
                            bit_count <= 6'd24;
                            state <= S_ADDR;
                        end
                    end
                end

                S_ADDR: begin
                    // Send 24-bit address
                    if (sck_phase == 1'b0) begin
                        // Falling edge: setup data
                        spi_mosi <= tx_shift[31];
                        spi_sck <= 1'b0;
                        sck_phase <= 1'b1;
                    end else begin
                        // Rising edge: clock data out
                        spi_sck <= 1'b1;
                        tx_shift <= {tx_shift[30:0], 1'b0};
                        bit_count <= bit_count - 6'd1;
                        sck_phase <= 1'b0;

                        if (bit_count == 6'd1) begin
                            // Address done, start data receive
                            bit_count <= 6'd8;
                            rx_shift <= 8'd0;
                            state <= S_DATA;
                        end
                    end
                end

                S_DATA: begin
                    // Receive data bytes
                    if (sck_phase == 1'b0) begin
                        // Falling edge: prepare for next bit
                        spi_sck <= 1'b0;
                        spi_mosi <= 1'b0;  // Don't care during read
                        sck_phase <= 1'b1;
                    end else begin
                        // Rising edge: sample MISO
                        spi_sck <= 1'b1;
                        rx_shift <= {rx_shift[6:0], spi_miso};
                        bit_count <= bit_count - 6'd1;
                        sck_phase <= 1'b0;

                        if (bit_count == 6'd1) begin
                            // Byte complete
                            data_out <= {rx_shift[6:0], spi_miso};
                            data_valid <= 1'b1;
                            data_index <= data_index;
                            bytes_remain <= bytes_remain - 7'd1;

                            if (bytes_remain == 7'd1) begin
                                // Last byte, end transaction
                                state <= S_DONE;
                            end else begin
                                // More bytes to receive
                                bit_count <= 6'd8;
                                rx_shift <= 8'd0;
                                data_index <= data_index + 6'd1;
                            end
                        end
                    end
                end

                S_DONE: begin
                    // Deassert CS and return to idle
                    spi_sck <= 1'b0;
                    spi_cs_n <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
