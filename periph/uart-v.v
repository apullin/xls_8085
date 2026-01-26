// UART - Hand-written Verilog with LUT-RAM FIFOs
// Full-featured UART with 4-entry FIFOs, fractional baud, parity
// Replaces XLS-generated uart.v + uart_wrapper.v

module uart_wrapper (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [3:0]  addr,
    input  wire [7:0]  data_in,
    output reg  [7:0]  data_out,
    input  wire        rd,
    input  wire        wr,
    input  wire        rx_pin,
    output reg         tx_pin,
    output wire        irq
);
    // Register addresses
    localparam REG_CTRL     = 4'h0;
    localparam REG_PARITY   = 4'h1;
    localparam REG_STAT     = 4'h2;
    localparam REG_FIFOLVL  = 4'h3;
    localparam REG_TXDATA   = 4'h4;
    localparam REG_RXDATA   = 4'h5;
    localparam REG_BRD_L    = 4'h6;
    localparam REG_BRD_H    = 4'h7;
    localparam REG_BRD_F    = 4'h8;
    localparam REG_IRQ_EN   = 4'h9;
    localparam REG_IRQ_STAT = 4'hA;
    localparam REG_IFLS     = 4'hB;
    localparam REG_RXTO_CFG = 4'hC;

    // CTRL bits
    localparam CTRL_EN   = 7;
    localparam CTRL_TXEN = 6;
    localparam CTRL_RXEN = 5;
    localparam CTRL_FEN  = 4;
    localparam CTRL_LBE  = 3;
    localparam CTRL_WLEN = 2;
    localparam CTRL_STP2 = 1;
    localparam CTRL_PEN  = 0;

    // State machines
    localparam TX_IDLE  = 2'd0;
    localparam TX_START = 2'd1;
    localparam TX_DATA  = 2'd2;
    localparam TX_STOP  = 2'd3;

    localparam RX_IDLE  = 2'd0;
    localparam RX_START = 2'd1;
    localparam RX_DATA  = 2'd2;
    localparam RX_STOP  = 2'd3;

    // Configuration registers
    reg [7:0]  ctrl;
    reg [7:0]  parity_cfg;
    reg [15:0] brd_int;
    reg [5:0]  brd_frac;
    reg [7:0]  irq_en;
    reg [7:0]  irq_stat;
    reg [5:0]  ifls;
    reg [7:0]  rxto_cfg;

    // Baud rate generator
    reg [15:0] baud_cnt;
    reg [5:0]  frac_accum;
    wire       baud_tick = (baud_cnt == 16'h0);

    // TX state
    reg [1:0]  tx_state;
    reg [7:0]  tx_shift;
    reg [3:0]  tx_bit_idx;
    reg [3:0]  tx_sample_cnt;
    reg        tx_parity;

    // RX state
    reg [1:0]  rx_state;
    reg [7:0]  rx_shift;
    reg [3:0]  rx_bit_idx;
    reg [3:0]  rx_sample_cnt;
    reg        rx_parity;
    reg        rx_prev;

    // Error flags
    reg        overrun_err;
    reg        frame_err;
    reg        parity_err;

    // RX timeout
    reg [7:0]  rxto_cnt;

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

    // Control signals
    wire enabled = ctrl[CTRL_EN];
    wire tx_en = ctrl[CTRL_TXEN];
    wire rx_en = ctrl[CTRL_RXEN];
    wire fifo_en = ctrl[CTRL_FEN];
    wire loopback = ctrl[CTRL_LBE];
    wire wlen8 = ctrl[CTRL_WLEN];
    wire stp2 = ctrl[CTRL_STP2];
    wire parity_en = ctrl[CTRL_PEN];
    wire even_parity = parity_cfg[0];

    // Thresholds (from IFLS register)
    wire [1:0] rx_thr = ifls[5:4];
    wire [1:0] tx_thr = ifls[1:0];

    // Status
    wire busy = (tx_state != TX_IDLE);
    wire [7:0] stat_reg = {busy, tx_empty, tx_full, rx_empty, rx_full,
                           overrun_err, frame_err, parity_err};

    // RX input (loopback or external)
    wire rx_in = loopback ? tx_pin : rx_pin;

    // IRQ generation (eliminated threshold adders where possible)
    // tx_count <= tx_thr+1: keep small 2-bit add, hard to simplify
    wire irq_txlvl = (tx_count <= {1'b0, tx_thr} + 3'd1);
    // rx_count >= rx_thr+1 is same as rx_count > rx_thr (no adder!)
    wire irq_rxlvl = (rx_count > {1'b0, rx_thr});
    wire irq_rxto = (rxto_cnt >= rxto_cfg) && (rxto_cfg != 0) && !rx_empty;
    assign irq = |(irq_stat & irq_en);

    // Read mux
    always @(*) begin
        case (addr)
            REG_CTRL:     data_out = ctrl;
            REG_PARITY:   data_out = {7'b0, parity_cfg[0]};
            REG_STAT:     data_out = stat_reg;
            REG_FIFOLVL:  data_out = {1'b0, rx_count, 1'b0, tx_count};
            REG_RXDATA:   data_out = rx_empty ? 8'h0 : rx_fifo[rx_tail];
            REG_BRD_L:    data_out = brd_int[7:0];
            REG_BRD_H:    data_out = brd_int[15:8];
            REG_BRD_F:    data_out = {2'b0, brd_frac};
            REG_IRQ_EN:   data_out = irq_en;
            REG_IRQ_STAT: data_out = irq_stat;
            REG_IFLS:     data_out = {2'b0, ifls};
            REG_RXTO_CFG: data_out = rxto_cfg;
            default:      data_out = 8'hFF;
        endcase
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ctrl <= 8'h0;
            parity_cfg <= 8'h0;
            brd_int <= 16'h0;
            brd_frac <= 6'h0;
            irq_en <= 8'h0;
            irq_stat <= 8'h0;
            ifls <= 6'h0;
            rxto_cfg <= 8'h0;
            baud_cnt <= 16'h0;
            frac_accum <= 6'h0;
            tx_state <= TX_IDLE;
            tx_shift <= 8'h0;
            tx_bit_idx <= 4'h0;
            tx_sample_cnt <= 4'h0;
            tx_parity <= 1'b0;
            tx_pin <= 1'b1;
            rx_state <= RX_IDLE;
            rx_shift <= 8'h0;
            rx_bit_idx <= 4'h0;
            rx_sample_cnt <= 4'h0;
            rx_parity <= 1'b0;
            rx_prev <= 1'b1;
            overrun_err <= 1'b0;
            frame_err <= 1'b0;
            parity_err <= 1'b0;
            rxto_cnt <= 8'h0;
            tx_head <= 2'h0;
            tx_tail <= 2'h0;
            tx_count <= 3'h0;
            rx_head <= 2'h0;
            rx_tail <= 2'h0;
            rx_count <= 3'h0;
        end else begin
            // Update IRQ status (level-sensitive bits)
            irq_stat[3] <= irq_txlvl;
            irq_stat[2] <= irq_rxlvl;
            irq_stat[4] <= irq_rxto;
            irq_stat[1] <= overrun_err;
            irq_stat[0] <= frame_err;

            // Register writes
            if (wr) begin
                case (addr)
                    REG_CTRL:     ctrl <= data_in;
                    REG_PARITY:   parity_cfg <= data_in;
                    REG_BRD_L:    brd_int[7:0] <= data_in;
                    REG_BRD_H:    brd_int[15:8] <= data_in;
                    REG_BRD_F:    brd_frac <= data_in[5:0];
                    REG_IRQ_EN:   irq_en <= data_in;
                    REG_IRQ_STAT: irq_stat <= irq_stat & ~data_in;  // W1C
                    REG_IFLS:     ifls <= data_in[5:0];
                    REG_RXTO_CFG: rxto_cfg <= data_in;
                    REG_TXDATA:   if (!tx_full) begin
                        tx_fifo[tx_head] <= data_in;
                        tx_head <= tx_head + 1;
                        tx_count <= tx_count + 1;
                    end
                endcase
            end

            // RX FIFO pop and clear errors on RXDATA read
            if (rd && addr == REG_RXDATA && !rx_empty) begin
                rx_tail <= rx_tail + 1;
                rx_count <= rx_count - 1;
                overrun_err <= 1'b0;
                frame_err <= 1'b0;
                parity_err <= 1'b0;
            end

            // Baud rate generator with fractional support
            if (enabled) begin
                if (baud_cnt == 16'h0) begin
                    // Add fractional part
                    if (frac_accum + brd_frac >= 6'd64) begin
                        baud_cnt <= brd_int + 16'h1;
                        frac_accum <= frac_accum + brd_frac - 6'd64;
                    end else begin
                        baud_cnt <= brd_int;
                        frac_accum <= frac_accum + brd_frac;
                    end
                end else begin
                    baud_cnt <= baud_cnt - 16'h1;
                end
            end

            // TX state machine
            if (!enabled || !tx_en) begin
                tx_state <= TX_IDLE;
                tx_pin <= 1'b1;
            end else if (baud_tick) begin
                case (tx_state)
                    TX_IDLE: begin
                        tx_pin <= 1'b1;
                        if (!tx_empty) begin
                            tx_shift <= tx_fifo[tx_tail];
                            tx_tail <= tx_tail + 1;
                            tx_count <= tx_count - 1;
                            tx_state <= TX_START;
                            tx_sample_cnt <= 4'h0;
                            tx_parity <= 1'b0;
                        end
                    end

                    TX_START: begin
                        tx_pin <= 1'b0;  // Start bit
                        if (tx_sample_cnt == 4'd15) begin
                            tx_state <= TX_DATA;
                            tx_sample_cnt <= 4'h0;
                            tx_bit_idx <= 4'h0;
                        end else begin
                            tx_sample_cnt <= tx_sample_cnt + 1;
                        end
                    end

                    TX_DATA: begin
                        tx_pin <= tx_shift[0];
                        tx_parity <= tx_parity ^ tx_shift[0];
                        if (tx_sample_cnt == 4'd15) begin
                            tx_shift <= {1'b0, tx_shift[7:1]};
                            tx_sample_cnt <= 4'h0;
                            if (tx_bit_idx == (wlen8 ? 4'd7 : 4'd6)) begin
                                if (parity_en) begin
                                    tx_bit_idx <= 4'd15;  // Parity phase
                                end else begin
                                    tx_state <= TX_STOP;
                                    tx_bit_idx <= 4'h0;
                                end
                            end else if (tx_bit_idx == 4'd15) begin
                                // Parity bit done
                                tx_state <= TX_STOP;
                                tx_bit_idx <= 4'h0;
                            end else begin
                                tx_bit_idx <= tx_bit_idx + 1;
                            end
                        end else begin
                            tx_sample_cnt <= tx_sample_cnt + 1;
                        end
                        // Output parity when in parity phase
                        if (tx_bit_idx == 4'd15) begin
                            tx_pin <= even_parity ? tx_parity : ~tx_parity;
                        end
                    end

                    TX_STOP: begin
                        tx_pin <= 1'b1;  // Stop bit
                        if (tx_sample_cnt == 4'd15) begin
                            if (stp2 && tx_bit_idx == 4'd0) begin
                                tx_bit_idx <= 4'd1;
                                tx_sample_cnt <= 4'h0;
                            end else begin
                                tx_state <= TX_IDLE;
                            end
                        end else begin
                            tx_sample_cnt <= tx_sample_cnt + 1;
                        end
                    end
                endcase
            end

            // RX state machine
            rx_prev <= rx_in;
            if (!enabled || !rx_en) begin
                rx_state <= RX_IDLE;
                rxto_cnt <= 8'h0;
            end else if (baud_tick) begin
                case (rx_state)
                    RX_IDLE: begin
                        // Detect falling edge (start bit)
                        if (rx_prev && !rx_in) begin
                            rx_state <= RX_START;
                            rx_sample_cnt <= 4'h0;
                        end
                        // RX timeout counter
                        if (!rx_empty && rx_sample_cnt == 4'd15) begin
                            if (rxto_cnt < 8'hFF)
                                rxto_cnt <= rxto_cnt + 1;
                        end
                        rx_sample_cnt <= rx_sample_cnt + 1;
                    end

                    RX_START: begin
                        if (rx_sample_cnt == 4'd7) begin
                            // Check start bit is still low at midpoint
                            if (rx_in) begin
                                // False start
                                rx_state <= RX_IDLE;
                            end
                        end
                        if (rx_sample_cnt == 4'd15) begin
                            rx_state <= RX_DATA;
                            rx_sample_cnt <= 4'h0;
                            rx_bit_idx <= 4'h0;
                            rx_shift <= 8'h0;
                            rx_parity <= 1'b0;
                        end else begin
                            rx_sample_cnt <= rx_sample_cnt + 1;
                        end
                    end

                    RX_DATA: begin
                        if (rx_sample_cnt == 4'd7) begin
                            // Sample at midpoint
                            rx_shift <= {rx_in, rx_shift[7:1]};
                            rx_parity <= rx_parity ^ rx_in;
                        end
                        if (rx_sample_cnt == 4'd15) begin
                            rx_sample_cnt <= 4'h0;
                            if (rx_bit_idx == (wlen8 ? 4'd7 : 4'd6)) begin
                                if (parity_en) begin
                                    rx_bit_idx <= 4'd15;  // Parity phase
                                end else begin
                                    rx_state <= RX_STOP;
                                end
                            end else if (rx_bit_idx == 4'd15) begin
                                // Parity done - check it
                                if ((even_parity ? rx_parity : ~rx_parity) != rx_in)
                                    parity_err <= 1'b1;
                                rx_state <= RX_STOP;
                            end else begin
                                rx_bit_idx <= rx_bit_idx + 1;
                            end
                        end else begin
                            rx_sample_cnt <= rx_sample_cnt + 1;
                        end
                    end

                    RX_STOP: begin
                        if (rx_sample_cnt == 4'd7) begin
                            // Check stop bit
                            if (!rx_in)
                                frame_err <= 1'b1;
                        end
                        if (rx_sample_cnt == 4'd15) begin
                            // Store byte
                            if (rx_full) begin
                                overrun_err <= 1'b1;
                            end else begin
                                rx_fifo[rx_head] <= wlen8 ? rx_shift : {1'b0, rx_shift[7:1]};
                                rx_head <= rx_head + 1;
                                rx_count <= rx_count + 1;
                            end
                            rxto_cnt <= 8'h0;
                            rx_state <= RX_IDLE;
                        end else begin
                            rx_sample_cnt <= rx_sample_cnt + 1;
                        end
                    end
                endcase
            end
        end
    end
endmodule
