// Universal Serial Engine - UART/SPI switchable
// Shares FIFOs, shift registers, clock generation between modes
// Mode 0: UART (async, start/stop bits, optional parity)
// Mode 1: SPI Master (CPOL/CPHA, 8-bit transfers)

module userial_wrapper (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [3:0]  addr,
    input  wire [7:0]  data_in,
    output reg  [7:0]  data_out,
    input  wire        rd,
    input  wire        wr,
    // UART/SPI pins (shared based on mode)
    input  wire        rx_miso,      // UART RX or SPI MISO
    output reg         tx_mosi,      // UART TX or SPI MOSI
    output reg         sck,          // SPI clock (shared based on mode)
    output reg         cs_n,         // SPI chip select
    output wire        irq
);

    // Register addresses
    localparam REG_CTRL     = 4'h0;  // Control
    localparam REG_MODE_CFG = 4'h1;  // Mode-specific config
    localparam REG_STAT     = 4'h2;  // Status
    localparam REG_FIFOLVL  = 4'h3;  // FIFO levels
    localparam REG_TXDATA   = 4'h4;  // TX data (write)
    localparam REG_RXDATA   = 4'h5;  // RX data (read)
    localparam REG_CLK_L    = 4'h6;  // Clock divider low
    localparam REG_CLK_H    = 4'h7;  // Clock divider high
    localparam REG_CLK_F    = 4'h8;  // Fractional (UART only)
    localparam REG_IRQ_EN   = 4'h9;  // IRQ enable
    localparam REG_IRQ_STAT = 4'hA;  // IRQ status
    localparam REG_IFLS     = 4'hB;  // FIFO level select
    localparam REG_SPI_CS   = 4'hC;  // SPI CS control

    // CTRL bits
    localparam CTRL_EN      = 7;
    localparam CTRL_TXEN    = 6;
    localparam CTRL_RXEN    = 5;
    localparam CTRL_FEN     = 4;
    localparam CTRL_MODE    = 3;     // 0=UART, 1=SPI
    localparam CTRL_LBE     = 2;     // Loopback (UART)
    localparam CTRL_WLEN    = 1;     // Word len: UART 0=7bit 1=8bit
    localparam CTRL_LSBF    = 0;     // LSB first (SPI)

    // MODE_CFG bits (shared based on mode)
    // UART: [2] even_parity, [1] STP2, [0] PEN
    // SPI:  [1] CPOL, [0] CPHA

    // State machines
    localparam S_IDLE   = 3'd0;
    localparam S_START  = 3'd1;  // UART start bit
    localparam S_DATA   = 3'd2;  // Data bits
    localparam S_PARITY = 3'd3;  // UART parity
    localparam S_STOP   = 3'd4;  // UART stop
    localparam S_STOP2  = 3'd5;  // UART second stop

    // Registers
    reg [7:0]  ctrl;
    reg [7:0]  mode_cfg;
    reg [15:0] clk_div;
    reg [5:0]  clk_frac;
    reg [7:0]  irq_en;
    reg [7:0]  irq_stat;
    reg [5:0]  ifls;
    reg        spi_cs_reg;

    // Clock generator
    reg [15:0] clk_cnt;
    reg [5:0]  frac_accum;
    wire       clk_tick = (clk_cnt == 16'h0);

    // TX state
    reg [2:0]  tx_state;
    reg [7:0]  tx_shift;
    reg [3:0]  tx_bit_idx;
    reg [3:0]  tx_sample_cnt;
    reg        tx_parity;

    // RX state
    reg [2:0]  rx_state;
    reg [7:0]  rx_shift;
    reg [3:0]  rx_bit_idx;
    reg [3:0]  rx_sample_cnt;
    reg        rx_parity;
    reg        rx_prev;

    // Errors
    reg        overrun_err, frame_err, parity_err;

    // TX FIFO - LUT-RAM
    reg [7:0]  tx_fifo [0:3];
    reg [1:0]  tx_head, tx_tail;
    reg [2:0]  tx_count;
    wire       tx_empty = (tx_count == 0);
    wire       tx_full = tx_count[2];

    // RX FIFO - LUT-RAM
    reg [7:0]  rx_fifo [0:3];
    reg [1:0]  rx_head, rx_tail;
    reg [2:0]  rx_count;
    wire       rx_empty = (rx_count == 0);
    wire       rx_full = rx_count[2];

    // Control decode
    wire enabled = ctrl[CTRL_EN];
    wire tx_en = ctrl[CTRL_TXEN];
    wire rx_en = ctrl[CTRL_RXEN];
    wire fifo_en = ctrl[CTRL_FEN];
    wire spi_mode = ctrl[CTRL_MODE];
    wire loopback = ctrl[CTRL_LBE];
    wire wlen8 = ctrl[CTRL_WLEN];
    wire lsb_first = ctrl[CTRL_LSBF];

    // UART config
    wire parity_en = mode_cfg[0] && !spi_mode;
    wire stp2 = mode_cfg[1] && !spi_mode;
    wire even_parity = mode_cfg[2];

    // SPI config
    wire cpol = mode_cfg[1] && spi_mode;
    wire cpha = mode_cfg[0] && spi_mode;

    // Thresholds (from IFLS register)
    wire [1:0] rx_thr = ifls[5:4];
    wire [1:0] tx_thr = ifls[1:0];

    // Status
    wire busy = (tx_state != S_IDLE) || (rx_state != S_IDLE);
    wire [7:0] stat_reg = {busy, tx_empty, tx_full, rx_empty, rx_full,
                           overrun_err, frame_err, parity_err};

    // RX input
    wire rx_in = loopback ? tx_mosi : rx_miso;

    // IRQ generation (eliminated threshold adders where possible)
    wire irq_txlvl = (tx_count <= {1'b0, tx_thr} + 3'd1);
    wire irq_rxlvl = (rx_count > {1'b0, rx_thr});  // >= thr+1 is same as > thr
    assign irq = |(irq_stat & irq_en);

    // CS directly directly directly directly directly directly directly directly directly output
    always @(*) cs_n = spi_mode ? ~spi_cs_reg : 1'b1;

    // Read mux
    always @(*) begin
        case (addr)
            REG_CTRL:     data_out = ctrl;
            REG_MODE_CFG: data_out = mode_cfg;
            REG_STAT:     data_out = stat_reg;
            REG_FIFOLVL:  data_out = {1'b0, rx_count, 1'b0, tx_count};
            REG_RXDATA:   data_out = rx_empty ? 8'h0 : rx_fifo[rx_tail];
            REG_CLK_L:    data_out = clk_div[7:0];
            REG_CLK_H:    data_out = clk_div[15:8];
            REG_CLK_F:    data_out = {2'b0, clk_frac};
            REG_IRQ_EN:   data_out = irq_en;
            REG_IRQ_STAT: data_out = irq_stat;
            REG_IFLS:     data_out = {2'b0, ifls};
            REG_SPI_CS:   data_out = {7'b0, spi_cs_reg};
            default:      data_out = 8'hFF;
        endcase
    end

    // Main logic
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ctrl <= 8'h0;
            mode_cfg <= 8'h0;
            clk_div <= 16'h0;
            clk_frac <= 6'h0;
            irq_en <= 8'h0;
            irq_stat <= 8'h0;
            ifls <= 6'h0;
            spi_cs_reg <= 1'b0;
            clk_cnt <= 16'h0;
            frac_accum <= 6'h0;
            tx_state <= S_IDLE;
            tx_shift <= 8'h0;
            tx_bit_idx <= 4'h0;
            tx_sample_cnt <= 4'h0;
            tx_parity <= 1'b0;
            tx_mosi <= 1'b1;
            sck <= 1'b0;
            rx_state <= S_IDLE;
            rx_shift <= 8'h0;
            rx_bit_idx <= 4'h0;
            rx_sample_cnt <= 4'h0;
            rx_parity <= 1'b0;
            rx_prev <= 1'b1;
            overrun_err <= 1'b0;
            frame_err <= 1'b0;
            parity_err <= 1'b0;
            tx_head <= 2'h0;
            tx_tail <= 2'h0;
            tx_count <= 3'h0;
            rx_head <= 2'h0;
            rx_tail <= 2'h0;
            rx_count <= 3'h0;
        end else begin
            // Update IRQ status
            irq_stat[3] <= irq_txlvl;
            irq_stat[2] <= irq_rxlvl;
            irq_stat[1] <= overrun_err;
            irq_stat[0] <= frame_err;

            // Register writes
            if (wr) begin
                case (addr)
                    REG_CTRL:     ctrl <= data_in;
                    REG_MODE_CFG: mode_cfg <= data_in;
                    REG_CLK_L:    clk_div[7:0] <= data_in;
                    REG_CLK_H:    clk_div[15:8] <= data_in;
                    REG_CLK_F:    clk_frac <= data_in[5:0];
                    REG_IRQ_EN:   irq_en <= data_in;
                    REG_IRQ_STAT: irq_stat <= irq_stat & ~data_in;
                    REG_IFLS:     ifls <= data_in[5:0];
                    REG_SPI_CS:   spi_cs_reg <= data_in[0];
                    REG_TXDATA:   if (!tx_full) begin
                        tx_fifo[tx_head] <= data_in;
                        tx_head <= tx_head + 1;
                        tx_count <= tx_count + 1;
                    end
                endcase
            end

            // RX FIFO pop on read
            if (rd && addr == REG_RXDATA && !rx_empty) begin
                rx_tail <= rx_tail + 1;
                rx_count <= rx_count - 1;
                overrun_err <= 1'b0;
                frame_err <= 1'b0;
                parity_err <= 1'b0;
            end

            // Clock generator
            if (enabled) begin
                if (clk_cnt == 16'h0) begin
                    if (!spi_mode && frac_accum + clk_frac >= 6'd64) begin
                        clk_cnt <= clk_div + 16'h1;
                        frac_accum <= frac_accum + clk_frac - 6'd64;
                    end else begin
                        clk_cnt <= clk_div;
                        if (!spi_mode) frac_accum <= frac_accum + clk_frac;
                    end
                end else begin
                    clk_cnt <= clk_cnt - 16'h1;
                end
            end

            // =====================================================
            // SPI MODE
            // =====================================================
            if (spi_mode && enabled) begin
                sck <= cpol;  // Idle clock state

                if (!tx_en && !rx_en) begin
                    tx_state <= S_IDLE;
                    rx_state <= S_IDLE;
                end else if (clk_tick) begin
                    case (tx_state)
                        S_IDLE: begin
                            if (!tx_empty && spi_cs_reg) begin
                                tx_shift <= tx_fifo[tx_tail];
                                tx_tail <= tx_tail + 1;
                                tx_count <= tx_count - 1;
                                tx_bit_idx <= 4'd0;
                                tx_state <= S_DATA;
                                tx_sample_cnt <= 4'd0;
                                rx_shift <= 8'h0;
                            end
                        end

                        S_DATA: begin
                            tx_sample_cnt <= tx_sample_cnt + 1;

                            if (tx_sample_cnt == 4'd0) begin
                                // First half - set data (for CPHA=0) or toggle clock
                                if (cpha) begin
                                    sck <= ~cpol;
                                end else begin
                                    tx_mosi <= lsb_first ? tx_shift[0] : tx_shift[7];
                                end
                            end else if (tx_sample_cnt == 4'd1) begin
                                // Second half
                                if (cpha) begin
                                    tx_mosi <= lsb_first ? tx_shift[0] : tx_shift[7];
                                    // Sample RX on this edge
                                    if (lsb_first)
                                        rx_shift <= {rx_in, rx_shift[7:1]};
                                    else
                                        rx_shift <= {rx_shift[6:0], rx_in};
                                end else begin
                                    sck <= ~cpol;
                                    // Sample RX on this edge
                                    if (lsb_first)
                                        rx_shift <= {rx_in, rx_shift[7:1]};
                                    else
                                        rx_shift <= {rx_shift[6:0], rx_in};
                                end
                            end else if (tx_sample_cnt == 4'd2) begin
                                // Third quarter - return clock
                                sck <= cpol;
                                if (lsb_first)
                                    tx_shift <= {1'b0, tx_shift[7:1]};
                                else
                                    tx_shift <= {tx_shift[6:0], 1'b0};
                            end else if (tx_sample_cnt == 4'd3) begin
                                // Complete bit
                                tx_sample_cnt <= 4'd0;
                                if (tx_bit_idx == 4'd7) begin
                                    // Byte complete
                                    tx_state <= S_IDLE;
                                    // Store RX byte
                                    if (rx_en) begin
                                        if (rx_full)
                                            overrun_err <= 1'b1;
                                        else begin
                                            rx_fifo[rx_head] <= rx_shift;
                                            rx_head <= rx_head + 1;
                                            rx_count <= rx_count + 1;
                                        end
                                    end
                                end else begin
                                    tx_bit_idx <= tx_bit_idx + 1;
                                end
                            end
                        end

                        default: tx_state <= S_IDLE;
                    endcase
                end

            // =====================================================
            // UART MODE
            // =====================================================
            end else if (!spi_mode && enabled) begin
                sck <= 1'b0;  // No clock in UART mode
                rx_prev <= rx_in;

                // TX state machine
                if (!tx_en) begin
                    tx_state <= S_IDLE;
                    tx_mosi <= 1'b1;
                end else if (clk_tick) begin
                    case (tx_state)
                        S_IDLE: begin
                            tx_mosi <= 1'b1;
                            if (!tx_empty) begin
                                tx_shift <= tx_fifo[tx_tail];
                                tx_tail <= tx_tail + 1;
                                tx_count <= tx_count - 1;
                                tx_state <= S_START;
                                tx_sample_cnt <= 4'h0;
                                tx_parity <= 1'b0;
                            end
                        end

                        S_START: begin
                            tx_mosi <= 1'b0;
                            if (tx_sample_cnt == 4'd15) begin
                                tx_state <= S_DATA;
                                tx_sample_cnt <= 4'h0;
                                tx_bit_idx <= 4'h0;
                            end else
                                tx_sample_cnt <= tx_sample_cnt + 1;
                        end

                        S_DATA: begin
                            tx_mosi <= tx_shift[0];
                            tx_parity <= tx_parity ^ tx_shift[0];
                            if (tx_sample_cnt == 4'd15) begin
                                tx_shift <= {1'b0, tx_shift[7:1]};
                                tx_sample_cnt <= 4'h0;
                                if (tx_bit_idx == (wlen8 ? 4'd7 : 4'd6)) begin
                                    tx_state <= parity_en ? S_PARITY : S_STOP;
                                    tx_bit_idx <= 4'h0;
                                end else
                                    tx_bit_idx <= tx_bit_idx + 1;
                            end else
                                tx_sample_cnt <= tx_sample_cnt + 1;
                        end

                        S_PARITY: begin
                            tx_mosi <= even_parity ? tx_parity : ~tx_parity;
                            if (tx_sample_cnt == 4'd15) begin
                                tx_state <= S_STOP;
                                tx_sample_cnt <= 4'h0;
                            end else
                                tx_sample_cnt <= tx_sample_cnt + 1;
                        end

                        S_STOP: begin
                            tx_mosi <= 1'b1;
                            if (tx_sample_cnt == 4'd15) begin
                                if (stp2) begin
                                    tx_state <= S_STOP2;
                                    tx_sample_cnt <= 4'h0;
                                end else
                                    tx_state <= S_IDLE;
                            end else
                                tx_sample_cnt <= tx_sample_cnt + 1;
                        end

                        S_STOP2: begin
                            tx_mosi <= 1'b1;
                            if (tx_sample_cnt == 4'd15)
                                tx_state <= S_IDLE;
                            else
                                tx_sample_cnt <= tx_sample_cnt + 1;
                        end

                        default: tx_state <= S_IDLE;
                    endcase
                end

                // RX state machine
                if (!rx_en) begin
                    rx_state <= S_IDLE;
                end else if (clk_tick) begin
                    case (rx_state)
                        S_IDLE: begin
                            if (rx_prev && !rx_in) begin
                                rx_state <= S_START;
                                rx_sample_cnt <= 4'h0;
                            end
                        end

                        S_START: begin
                            if (rx_sample_cnt == 4'd7) begin
                                if (rx_in) rx_state <= S_IDLE;  // False start
                            end
                            if (rx_sample_cnt == 4'd15) begin
                                rx_state <= S_DATA;
                                rx_sample_cnt <= 4'h0;
                                rx_bit_idx <= 4'h0;
                                rx_shift <= 8'h0;
                                rx_parity <= 1'b0;
                            end else
                                rx_sample_cnt <= rx_sample_cnt + 1;
                        end

                        S_DATA: begin
                            if (rx_sample_cnt == 4'd7) begin
                                rx_shift <= {rx_in, rx_shift[7:1]};
                                rx_parity <= rx_parity ^ rx_in;
                            end
                            if (rx_sample_cnt == 4'd15) begin
                                rx_sample_cnt <= 4'h0;
                                if (rx_bit_idx == (wlen8 ? 4'd7 : 4'd6))
                                    rx_state <= parity_en ? S_PARITY : S_STOP;
                                else
                                    rx_bit_idx <= rx_bit_idx + 1;
                            end else
                                rx_sample_cnt <= rx_sample_cnt + 1;
                        end

                        S_PARITY: begin
                            if (rx_sample_cnt == 4'd7) begin
                                if ((even_parity ? rx_parity : ~rx_parity) != rx_in)
                                    parity_err <= 1'b1;
                            end
                            if (rx_sample_cnt == 4'd15) begin
                                rx_state <= S_STOP;
                                rx_sample_cnt <= 4'h0;
                            end else
                                rx_sample_cnt <= rx_sample_cnt + 1;
                        end

                        S_STOP: begin
                            if (rx_sample_cnt == 4'd7) begin
                                if (!rx_in) frame_err <= 1'b1;
                            end
                            if (rx_sample_cnt == 4'd15) begin
                                if (rx_full)
                                    overrun_err <= 1'b1;
                                else begin
                                    rx_fifo[rx_head] <= wlen8 ? rx_shift : {1'b0, rx_shift[7:1]};
                                    rx_head <= rx_head + 1;
                                    rx_count <= rx_count + 1;
                                end
                                rx_state <= S_IDLE;
                            end else
                                rx_sample_cnt <= rx_sample_cnt + 1;
                        end

                        default: rx_state <= S_IDLE;
                    endcase
                end

            end else begin
                // Disabled
                tx_state <= S_IDLE;
                rx_state <= S_IDLE;
                tx_mosi <= 1'b1;
                sck <= 1'b0;
            end
        end
    end

endmodule
