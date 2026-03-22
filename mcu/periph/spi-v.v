// SPI Master - Hand-written Verilog with LUT-RAM FIFOs
// Replaces XLS-generated spi.v + spi_wrapper.v
// Functionally equivalent but uses efficient FIFO inference

module spi_wrapper (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [3:0]  addr,
    input  wire [7:0]  data_in,
    output reg  [7:0]  data_out,
    input  wire        rd,
    input  wire        wr,
    input  wire        miso,
    output reg         sck,
    output reg         mosi,
    output reg         cs_n,
    output wire        irq
);
    // Register addresses
    localparam REG_CTRL     = 4'h0;  // [7]EN [6]CPHA [5]CPOL [4]AUTO_CS
    localparam REG_STAT     = 4'h1;  // [7]BUSY [6]TXE [5]TXF [4]RXE [3]RXF
    localparam REG_DIV      = 4'h2;  // Clock divider
    localparam REG_CS       = 4'h3;  // Manual CS control
    localparam REG_TXDATA   = 4'h4;  // TX FIFO write
    localparam REG_RXDATA   = 4'h5;  // RX FIFO read
    localparam REG_IRQ_EN   = 4'h6;  // IRQ enable
    localparam REG_IRQ_STAT = 4'h7;  // IRQ status (W1C)
    localparam REG_FIFOLVL  = 4'h8;  // FIFO levels

    // Control/status registers
    reg [7:0] ctrl, div, cs_reg, irq_en, irq_stat;
    reg [7:0] div_cnt;
    reg [1:0] state;  // 0=idle, 1=transfer, 2=done
    reg [7:0] tx_shift, rx_shift;
    reg [2:0] bit_idx;
    reg sck_phase;

    // TX FIFO - LUT-RAM inference
    reg [7:0] tx_fifo [0:3];
    reg [1:0] tx_head, tx_tail;
    reg [2:0] tx_count;

    // RX FIFO - LUT-RAM inference
    reg [7:0] rx_fifo [0:3];
    reg [1:0] rx_head, rx_tail;
    reg [2:0] rx_count;

    // Status flags
    wire tx_empty = (tx_count == 0);
    wire tx_full = tx_count[2];
    wire rx_empty = (rx_count == 0);
    wire rx_full = rx_count[2];
    wire busy = (state != 0);

    // Control bits
    wire enabled = ctrl[7];
    wire cpha = ctrl[6];
    wire cpol = ctrl[5];
    wire auto_cs = ctrl[4];
    wire sck_idle = cpol;

    // IRQ output
    assign irq = |(irq_stat & irq_en);

    // Read mux
    always @(*) begin
        case (addr)
            REG_CTRL:     data_out = ctrl;
            REG_STAT:     data_out = {busy, tx_empty, tx_full, rx_empty, rx_full, 3'b0};
            REG_DIV:      data_out = div;
            REG_CS:       data_out = cs_reg;
            REG_RXDATA:   data_out = rx_empty ? 8'h00 : rx_fifo[rx_tail];
            REG_IRQ_EN:   data_out = irq_en;
            REG_IRQ_STAT: data_out = irq_stat;
            REG_FIFOLVL:  data_out = {1'b0, rx_count, 1'b0, tx_count};
            default:      data_out = 8'hFF;
        endcase
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ctrl <= 0; div <= 0; cs_reg <= 8'h01;
            irq_en <= 0; irq_stat <= 0;
            div_cnt <= 0; state <= 0; bit_idx <= 0; sck_phase <= 0;
            tx_shift <= 0; rx_shift <= 0;
            tx_head <= 0; tx_tail <= 0; tx_count <= 0;
            rx_head <= 0; rx_tail <= 0; rx_count <= 0;
            sck <= 0; mosi <= 0; cs_n <= 1;
        end else begin
            // Update IRQ status bits
            irq_stat[0] <= tx_empty;      // TXE
            irq_stat[1] <= !rx_empty;     // RXNE

            // Register writes
            if (wr) case (addr)
                REG_CTRL:     ctrl <= data_in;
                REG_DIV:      div <= data_in;
                REG_CS:       cs_reg <= data_in;
                REG_IRQ_EN:   irq_en <= data_in;
                REG_IRQ_STAT: irq_stat <= irq_stat & ~data_in;
                REG_TXDATA:   if (!tx_full) begin
                    tx_fifo[tx_head] <= data_in;
                    tx_head <= tx_head + 1;
                    tx_count <= tx_count + 1;
                end
            endcase

            // RX FIFO pop on read
            if (rd && addr == REG_RXDATA && !rx_empty) begin
                rx_tail <= rx_tail + 1;
                rx_count <= rx_count - 1;
            end

            // SPI state machine
            if (!enabled) begin
                state <= 0;
                sck <= sck_idle;
                cs_n <= auto_cs ? 1'b1 : cs_reg[0];
                div_cnt <= 0;
                sck_phase <= 0;
            end else case (state)
                2'd0: begin  // IDLE
                    sck <= sck_idle;
                    if (!tx_empty) begin
                        // Load byte and start transfer
                        tx_shift <= tx_fifo[tx_tail];
                        tx_tail <= tx_tail + 1;
                        tx_count <= tx_count - 1;
                        rx_shift <= 0;
                        bit_idx <= 0;
                        div_cnt <= div;
                        sck_phase <= 0;
                        state <= 1;
                        cs_n <= auto_cs ? 1'b0 : cs_reg[0];
                        mosi <= cpha ? 1'b0 : tx_fifo[tx_tail][7];
                    end else begin
                        cs_n <= auto_cs ? 1'b1 : cs_reg[0];
                    end
                end

                2'd1: begin  // TRANSFER
                    if (div_cnt > 0) begin
                        div_cnt <= div_cnt - 1;
                    end else begin
                        div_cnt <= div;
                        sck_phase <= !sck_phase;
                        sck <= sck_phase ? sck_idle : !sck_idle;

                        // Sample edge
                        if (cpha ? sck_phase : !sck_phase) begin
                            rx_shift <= {rx_shift[6:0], miso};
                        end

                        // Shift edge
                        if (cpha ? !sck_phase : sck_phase) begin
                            if (bit_idx == 7) begin
                                // Byte complete - store RX
                                if (!rx_full) begin
                                    rx_fifo[rx_head] <= rx_shift;
                                    rx_head <= rx_head + 1;
                                    rx_count <= rx_count + 1;
                                end
                                // More TX data?
                                if (!tx_empty) begin
                                    tx_shift <= tx_fifo[tx_tail];
                                    tx_tail <= tx_tail + 1;
                                    tx_count <= tx_count - 1;
                                    bit_idx <= 0;
                                    mosi <= cpha ? 1'b0 : tx_fifo[tx_tail][7];
                                end else begin
                                    state <= 2;
                                    irq_stat[2] <= 1;  // DONE
                                end
                            end else begin
                                bit_idx <= bit_idx + 1;
                                tx_shift <= {tx_shift[6:0], 1'b0};
                                mosi <= tx_shift[6];
                            end
                        end
                    end
                end

                2'd2: begin  // DONE
                    sck <= sck_idle;
                    cs_n <= auto_cs ? 1'b1 : cs_reg[0];
                    state <= 0;
                end
            endcase
        end
    end
endmodule
