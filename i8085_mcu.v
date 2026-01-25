// Intel 8085 MCU Configuration for iCE40 UP5K
// Self-contained microcontroller - no external address/data bus
//
// This is a true MCU: CPU + memory + peripherals in one package.
// External pins are dedicated peripheral I/O, not a memory bus.
//
// Memory Map:
//   0x0000-0x7EFF: Internal SPRAM (32KB - 256 bytes, banked via port 0xF1)
//   0x7F00-0x7FFF: Peripheral registers (256 bytes)
//   0x8000-0xFFFF: Internal SPI flash cache (32KB, banked via port 0xF0)
//
// Peripheral Map (directly addressed, no I/O instructions needed):
//   0x7F00-0x7F0F: Timer0 (16-bit timer with 4 compare channels)
//   0x7F10-0x7F1F: GPIO0 (8-pin GPIO with IRQ and bitbanding)
//   0x7F20-0x7F2F: UART0 (debug/console UART)
//   0x7F30-0x7F3F: UART1 (system UART)
//   0x7F40-0x7F4F: SPI1 (general-purpose SPI master)
//   0x7F50-0x7F5F: I2C0 (hard silicon I2C, master+slave)
//   0x7F60-0x7F6F: imath (integer math accelerator, 2x DSP)
//   0x7F70-0x7FFF: Reserved (vmath future: 6x DSP)
//
// Vectored Interrupts (no scanning required):
//   0x0008 (RST 1): Timer0  - check timer status for CC0-3/overflow
//   0x0010 (RST 2): GPIO0
//   0x0018 (RST 3): UART0
//   0x0020 (RST 4): UART1
//   0x0028 (RST 5): SPI1
//   0x0030 (RST 6): I2C0
//   0x0038 (RST 7): Software syscall (not used by hardware)
//
// I/O Ports (legacy, but kept for compatibility):
//   0xF0: ROM bank register (8-bit, 256 banks x 32KB = 8MB)
//   0xF1: RAM bank register (2-bit, 4 banks x 32KB = 128KB)

module i8085_mcu (
    // Clock and Reset
    input  wire        clk,          // System clock (48MHz from HFOSC typical)
    input  wire        reset_n,      // Active low reset

    // Dedicated interrupt pins
    input  wire        trap,         // TRAP - NMI
    input  wire        rst75,        // RST7.5 - edge triggered
    input  wire        rst65,        // RST6.5 - level triggered
    input  wire        rst55,        // RST5.5 - level triggered

    // Serial I/O (directly exposed)
    input  wire        sid,          // Serial Input Data
    output wire        sod,          // Serial Output Data

    // SPI Flash Interface
    output wire        spi_sck,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,

    // Timer outputs
    output wire        timer0_irq,   // Timer0 interrupt output

    // GPIO pins
    input  wire [7:0]  gpio0_in,     // GPIO0 input pins
    output wire [7:0]  gpio0_out,    // GPIO0 output pins
    output wire [7:0]  gpio0_oe,     // GPIO0 output enables

    // UART0 (debug/console)
    input  wire        uart0_rx,
    output wire        uart0_tx,

    // UART1 (system)
    input  wire        uart1_rx,
    output wire        uart1_tx,

    // SPI1 (general-purpose)
    input  wire        spi1_miso,
    output wire        spi1_sck,
    output wire        spi1_mosi,
    output wire        spi1_cs_n,

    // I2C0 (directly connect to SB_IO for open-drain)
    input  wire        i2c0_sda_in,
    output wire        i2c0_sda_out,
    output wire        i2c0_sda_oe,
    input  wire        i2c0_scl_in,
    output wire        i2c0_scl_out,
    output wire        i2c0_scl_oe,

    // Status (directly exposed for debug)
    output wire        cpu_halted,   // CPU is in HALT state
    output wire        resout        // Reset output (active during reset stretch)
);

    // =========================================================================
    // Peripheral Address Map
    // =========================================================================

    // Base addresses for peripherals (memory-mapped)
    localparam [15:0] PERIPH_BASE   = 16'h7F00;
    localparam [15:0] PERIPH_END    = 16'h7FFF;

    localparam [15:0] TIMER0_BASE   = 16'h7F00;  // 0x7F00-0x7F0F
    localparam [15:0] GPIO0_BASE    = 16'h7F10;  // 0x7F10-0x7F1F
    localparam [15:0] UART0_BASE    = 16'h7F20;  // 0x7F20-0x7F2F
    localparam [15:0] UART1_BASE    = 16'h7F30;  // 0x7F30-0x7F3F
    localparam [15:0] SPI1_BASE     = 16'h7F40;  // 0x7F40-0x7F4F
    localparam [15:0] I2C0_BASE     = 16'h7F50;  // 0x7F50-0x7F5F
    localparam [15:0] IMATH_BASE    = 16'h7F60;  // 0x7F60-0x7F6F
    localparam [15:0] SYSCTRL_BASE  = 16'h7FF0;  // 0x7FF0-0x7FFF (reserved)

    // I/O port addresses (legacy)
    localparam [7:0] PORT_ROM_BANK  = 8'hF0;
    localparam [7:0] PORT_RAM_BANK  = 8'hF1;

    // =========================================================================
    // Address Decode Functions
    // =========================================================================

    function is_periph;
        input [15:0] addr;
        begin
            is_periph = (addr >= PERIPH_BASE) && (addr <= PERIPH_END);
        end
    endfunction

    function is_timer0;
        input [15:0] addr;
        begin
            is_timer0 = (addr >= TIMER0_BASE) && (addr < TIMER0_BASE + 16'd16);
        end
    endfunction

    function is_gpio0;
        input [15:0] addr;
        begin
            is_gpio0 = (addr >= GPIO0_BASE) && (addr < GPIO0_BASE + 16'd16);
        end
    endfunction

    function is_uart0;
        input [15:0] addr;
        begin
            is_uart0 = (addr >= UART0_BASE) && (addr < UART0_BASE + 16'd16);
        end
    endfunction

    function is_uart1;
        input [15:0] addr;
        begin
            is_uart1 = (addr >= UART1_BASE) && (addr < UART1_BASE + 16'd16);
        end
    endfunction

    function is_spi1;
        input [15:0] addr;
        begin
            is_spi1 = (addr >= SPI1_BASE) && (addr < SPI1_BASE + 16'd16);
        end
    endfunction

    function is_i2c0;
        input [15:0] addr;
        begin
            is_i2c0 = (addr >= I2C0_BASE) && (addr < I2C0_BASE + 16'd16);
        end
    endfunction

    function is_imath;
        input [15:0] addr;
        begin
            is_imath = (addr >= IMATH_BASE) && (addr < IMATH_BASE + 16'd16);
        end
    endfunction

    function is_rom;
        input [15:0] addr;
        begin
            is_rom = addr[15];  // 0x8000-0xFFFF
        end
    endfunction

    function is_ram;
        input [15:0] addr;
        begin
            is_ram = !addr[15] && !is_periph(addr);  // 0x0000-0x7EFF
        end
    endfunction

    // =========================================================================
    // Reset Stretch
    // =========================================================================

    reg [3:0] reset_stretch;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            reset_stretch <= 4'hF;
        else if (reset_stretch != 0)
            reset_stretch <= reset_stretch - 1;
    end
    assign resout = (reset_stretch != 0);

    // =========================================================================
    // SPRAM - 4 banks for 128KB total
    // =========================================================================

    reg  [13:0] ram_addr;
    reg  [15:0] ram_wdata;
    reg  [3:0]  ram_we;
    wire [15:0] ram_rdata;

    reg         ram_cs_0, ram_cs_1, ram_cs_2, ram_cs_3;
    wire [15:0] ram_rdata_0, ram_rdata_1, ram_rdata_2, ram_rdata_3;

    SB_SPRAM256KA ram_bank0 (
        .ADDRESS(ram_addr), .DATAIN(ram_wdata), .MASKWREN(ram_we),
        .WREN(|ram_we & ram_cs_0), .CHIPSELECT(ram_cs_0), .CLOCK(clk),
        .STANDBY(1'b0), .SLEEP(1'b0), .POWEROFF(1'b1), .DATAOUT(ram_rdata_0)
    );

    SB_SPRAM256KA ram_bank1 (
        .ADDRESS(ram_addr), .DATAIN(ram_wdata), .MASKWREN(ram_we),
        .WREN(|ram_we & ram_cs_1), .CHIPSELECT(ram_cs_1), .CLOCK(clk),
        .STANDBY(1'b0), .SLEEP(1'b0), .POWEROFF(1'b1), .DATAOUT(ram_rdata_1)
    );

    SB_SPRAM256KA ram_bank2 (
        .ADDRESS(ram_addr), .DATAIN(ram_wdata), .MASKWREN(ram_we),
        .WREN(|ram_we & ram_cs_2), .CHIPSELECT(ram_cs_2), .CLOCK(clk),
        .STANDBY(1'b0), .SLEEP(1'b0), .POWEROFF(1'b1), .DATAOUT(ram_rdata_2)
    );

    SB_SPRAM256KA ram_bank3 (
        .ADDRESS(ram_addr), .DATAIN(ram_wdata), .MASKWREN(ram_we),
        .WREN(|ram_we & ram_cs_3), .CHIPSELECT(ram_cs_3), .CLOCK(clk),
        .STANDBY(1'b0), .SLEEP(1'b0), .POWEROFF(1'b1), .DATAOUT(ram_rdata_3)
    );

    reg [1:0] ram_bank_latch;
    always @(posedge clk) ram_bank_latch <= ram_bank_reg;

    assign ram_rdata = (ram_bank_latch == 2'd0) ? ram_rdata_0 :
                       (ram_bank_latch == 2'd1) ? ram_rdata_1 :
                       (ram_bank_latch == 2'd2) ? ram_rdata_2 : ram_rdata_3;

    // =========================================================================
    // Bank Registers
    // =========================================================================

    reg  [7:0]  rom_bank_reg;     // ROM bank (256 x 32KB = 8MB)
    reg  [1:0]  ram_bank_reg;     // RAM bank (4 x 32KB = 128KB)

    // =========================================================================
    // SPI Flash Cache
    // =========================================================================

    reg         rom_cs;
    reg         rom_rd_reg;
    wire [7:0]  cache_rom_data;
    wire        cache_rom_ready;

    spi_flash_cache flash_cache (
        .clk(clk), .reset_n(reset_n),
        .rom_addr(fetch_addr[14:0]), .rom_rd(rom_rd_reg),
        .rom_data(cache_rom_data), .rom_ready(cache_rom_ready),
        .bank_sel(rom_bank_reg),
        .spi_sck(spi_sck), .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi), .spi_miso(spi_miso)
    );

    // =========================================================================
    // Peripheral: Timer0
    // =========================================================================

    reg         timer0_sel;
    reg  [3:0]  timer0_addr;
    reg  [7:0]  timer0_wdata;
    reg         timer0_rd;
    reg         timer0_wr;
    wire [7:0]  timer0_rdata;

    timer16_wrapper timer0 (
        .clk(clk),
        .reset_n(reset_n),
        .addr(timer0_addr),
        .data_in(timer0_wdata),
        .data_out(timer0_rdata),
        .rd(timer0_rd),
        .wr(timer0_wr),
        .tick(1'b1),           // Tick every cycle for now
        .irq(timer0_irq)
    );

    // =========================================================================
    // Peripheral: GPIO0
    // =========================================================================

    reg         gpio0_sel;
    reg  [3:0]  gpio0_addr;
    reg  [7:0]  gpio0_wdata;
    reg         gpio0_rd;
    reg         gpio0_wr;
    wire [7:0]  gpio0_rdata;
    wire        gpio0_irq;

    gpio8_wrapper gpio0 (
        .clk(clk),
        .reset_n(reset_n),
        .addr(gpio0_addr),
        .data_in(gpio0_wdata),
        .data_out(gpio0_rdata),
        .rd(gpio0_rd),
        .wr(gpio0_wr),
        .pins_in(gpio0_in),
        .pins_out(gpio0_out),
        .pins_oe(gpio0_oe),
        .irq(gpio0_irq)
    );

    // =========================================================================
    // Peripheral: UART0 (debug/console)
    // =========================================================================

    reg         uart0_sel;
    reg  [3:0]  uart0_addr;
    reg  [7:0]  uart0_wdata;
    reg         uart0_rd;
    reg         uart0_wr;
    wire [7:0]  uart0_rdata;
    wire        uart0_irq;

    uart_wrapper uart0 (
        .clk(clk),
        .reset_n(reset_n),
        .addr(uart0_addr),
        .data_in(uart0_wdata),
        .data_out(uart0_rdata),
        .rd(uart0_rd),
        .wr(uart0_wr),
        .rx_pin(uart0_rx),
        .tx_pin(uart0_tx),
        .irq(uart0_irq)
    );

    // =========================================================================
    // Peripheral: UART1 (system)
    // =========================================================================

    reg         uart1_sel;
    reg  [3:0]  uart1_addr;
    reg  [7:0]  uart1_wdata;
    reg         uart1_rd;
    reg         uart1_wr;
    wire [7:0]  uart1_rdata;
    wire        uart1_irq;

    uart_wrapper uart1 (
        .clk(clk),
        .reset_n(reset_n),
        .addr(uart1_addr),
        .data_in(uart1_wdata),
        .data_out(uart1_rdata),
        .rd(uart1_rd),
        .wr(uart1_wr),
        .rx_pin(uart1_rx),
        .tx_pin(uart1_tx),
        .irq(uart1_irq)
    );

    // =========================================================================
    // Peripheral: SPI1 (general-purpose)
    // =========================================================================

    reg         spi1_sel;
    reg  [3:0]  spi1_addr;
    reg  [7:0]  spi1_wdata;
    reg         spi1_rd;
    reg         spi1_wr;
    wire [7:0]  spi1_rdata;
    wire        spi1_irq;

    spi_wrapper spi1 (
        .clk(clk),
        .reset_n(reset_n),
        .addr(spi1_addr),
        .data_in(spi1_wdata),
        .data_out(spi1_rdata),
        .rd(spi1_rd),
        .wr(spi1_wr),
        .miso(spi1_miso),
        .sck(spi1_sck),
        .mosi(spi1_mosi),
        .cs_n(spi1_cs_n),
        .irq(spi1_irq)
    );

    // =========================================================================
    // Peripheral: I2C0 (hard silicon I2C)
    // =========================================================================

    reg         i2c0_sel;
    reg  [3:0]  i2c0_addr;
    reg  [7:0]  i2c0_wdata;
    reg         i2c0_rd;
    reg         i2c0_wr;
    wire [7:0]  i2c0_rdata;
    wire        i2c0_irq;

    i2c_wrapper i2c0 (
        .clk(clk),
        .reset_n(reset_n),
        .addr(i2c0_addr),
        .data_in(i2c0_wdata),
        .data_out(i2c0_rdata),
        .rd(i2c0_rd),
        .wr(i2c0_wr),
        .sda_in(i2c0_sda_in),
        .sda_out(i2c0_sda_out),
        .sda_oe(i2c0_sda_oe),
        .scl_in(i2c0_scl_in),
        .scl_out(i2c0_scl_out),
        .scl_oe(i2c0_scl_oe),
        .irq(i2c0_irq)
    );

    // =========================================================================
    // Peripheral: imath (integer math accelerator)
    // =========================================================================

    reg         imath_sel;
    reg  [3:0]  imath_addr;
    reg  [7:0]  imath_wdata;
    reg         imath_rd;
    reg         imath_wr;
    wire [7:0]  imath_rdata;

    imath_wrapper imath0 (
        .clk(clk),
        .reset_n(reset_n),
        .addr(imath_addr),
        .data_in(imath_wdata),
        .data_out(imath_rdata),
        .rd(imath_rd),
        .wr(imath_wr)
    );

    // =========================================================================
    // Interrupt Controller
    // =========================================================================

    reg rst75_prev, trap_prev;
    reg rst75_pending, trap_pending;
    reg intr_pending;

    // Vectored interrupt priority encoder
    // Each peripheral gets its own RST vector - no scanning needed
    // Priority: Timer0 > GPIO0 > UART0 > UART1 > SPI1 > I2C0
    wire [15:0] periph_int_vector = timer0_irq ? 16'h0008 :  // RST 1
                                    gpio0_irq  ? 16'h0010 :  // RST 2
                                    uart0_irq  ? 16'h0018 :  // RST 3
                                    uart1_irq  ? 16'h0020 :  // RST 4
                                    spi1_irq   ? 16'h0028 :  // RST 5
                                    i2c0_irq   ? 16'h0030 :  // RST 6
                                    16'h0000;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rst75_prev <= 1'b0;
            trap_prev <= 1'b0;
            rst75_pending <= 1'b0;
            trap_pending <= 1'b0;
            intr_pending <= 1'b0;
        end else begin
            rst75_prev <= rst75;
            trap_prev <= trap;

            // RST7.5: rising edge triggered
            if (rst75 && !rst75_prev)
                rst75_pending <= 1'b1;

            // TRAP: rising edge OR high level
            if ((trap && !trap_prev) || trap)
                trap_pending <= 1'b1;

            // Peripheral IRQs combined to INTR
            intr_pending <= timer0_irq | gpio0_irq | uart0_irq | uart1_irq | spi1_irq | i2c0_irq;

            // Clear on acknowledge
            if (int_ack_pulse) begin
                if (trap_pending)
                    trap_pending <= 1'b0;
                else if (rst75_pending)
                    rst75_pending <= 1'b0;
            end
        end
    end

    reg int_ack_pulse;

    // =========================================================================
    // CPU Interface Signals
    // =========================================================================

    wire [15:0] cpu_mem_addr;
    wire [7:0]  cpu_mem_data_out;
    wire        cpu_mem_wr;
    wire [15:0] cpu_stack_wr_addr;
    wire [7:0]  cpu_stack_wr_lo, cpu_stack_wr_hi;
    wire        cpu_stack_wr;
    wire [7:0]  cpu_io_port;
    wire [7:0]  cpu_io_data_out;
    wire        cpu_io_rd, cpu_io_wr;
    wire [15:0] cpu_pc, cpu_sp;
    wire        cpu_halted_wire;
    wire        cpu_inte;
    wire        cpu_sod;
    wire        cpu_mask_55, cpu_mask_65, cpu_mask_75;

    assign sod = cpu_sod;
    assign cpu_halted = cpu_halted_wire;

    // =========================================================================
    // FSM States
    // =========================================================================

    localparam S_FETCH_OP       = 4'd0;
    localparam S_WAIT_OP        = 4'd1;
    localparam S_FETCH_IMM1     = 4'd2;
    localparam S_WAIT_IMM1      = 4'd3;
    localparam S_FETCH_IMM2     = 4'd4;
    localparam S_WAIT_IMM2      = 4'd5;
    localparam S_READ_MEM       = 4'd6;
    localparam S_WAIT_MEM       = 4'd7;
    localparam S_READ_STK_LO    = 4'd8;
    localparam S_WAIT_STK_LO    = 4'd9;
    localparam S_READ_STK_HI    = 4'd10;
    localparam S_WAIT_STK_HI    = 4'd11;
    localparam S_EXECUTE        = 4'd12;
    localparam S_WRITE_STK      = 4'd13;
    localparam S_HALTED         = 4'd14;

    reg [3:0]  fsm_state;
    reg [15:0] fetch_addr;
    reg [7:0]  fetched_op;
    reg [7:0]  fetched_imm1;
    reg [7:0]  fetched_imm2;
    reg        execute_pulse;
    reg [7:0]  mem_rd_buf;
    reg [7:0]  stk_lo_buf, stk_hi_buf;
    reg [7:0]  io_rd_buf;
    reg [7:0]  periph_rd_buf;

    // =========================================================================
    // Instruction Decode Helpers
    // =========================================================================

    function [1:0] inst_len;
        input [7:0] op;
        casez (op)
            8'b00??0001, 8'b11000011, 8'b11??0010,
            8'b11001101, 8'b11??0100, 8'b0011?010, 8'b0010?010:
                inst_len = 2'd3;
            8'b00???110, 8'b11???110, 8'b1101?011:
                inst_len = 2'd2;
            default:
                inst_len = 2'd1;
        endcase
    endfunction

    function needs_hl_read;
        input [7:0] op;
        casez (op)
            8'b01???110, 8'b10???110, 8'b00110100, 8'b00110101:
                needs_hl_read = 1'b1;
            default:
                needs_hl_read = 1'b0;
        endcase
    endfunction

    function needs_bc_read; input [7:0] op; needs_bc_read = (op == 8'h0A); endfunction
    function needs_de_read; input [7:0] op; needs_de_read = (op == 8'h1A); endfunction
    function needs_direct_read; input [7:0] op; needs_direct_read = (op == 8'h3A) || (op == 8'h2A); endfunction

    function needs_stack_read;
        input [7:0] op;
        casez (op)
            8'b11001001, 8'b11???000, 8'b11??0001, 8'b11100011:
                needs_stack_read = 1'b1;
            default:
                needs_stack_read = 1'b0;
        endcase
    endfunction

    function needs_io_read; input [7:0] op; needs_io_read = (op == 8'hDB); endfunction

    // =========================================================================
    // Data Mux
    // =========================================================================

    wire [7:0] ram_word_byte = fetch_addr[0] ? ram_rdata[15:8] : ram_rdata[7:0];

    // Memory read data mux: ROM, peripherals, or RAM
    wire [7:0] mem_byte = rom_cs ? cache_rom_data :
                          timer0_sel ? timer0_rdata :
                          gpio0_sel ? gpio0_rdata :
                          uart0_sel ? uart0_rdata :
                          uart1_sel ? uart1_rdata :
                          spi1_sel ? spi1_rdata :
                          i2c0_sel ? i2c0_rdata :
                          imath_sel ? imath_rdata :
                          ram_word_byte;

    wire mem_ready = rom_cs ? cache_rom_ready : 1'b1;

    // =========================================================================
    // Address Decode
    // =========================================================================

    task set_addr_decode;
        input [15:0] addr;
        begin
            fetch_addr <= addr;
            ram_addr <= addr[14:1];

            // Clear all selects first
            ram_cs_0 <= 1'b0; ram_cs_1 <= 1'b0;
            ram_cs_2 <= 1'b0; ram_cs_3 <= 1'b0;
            rom_cs <= 1'b0;
            rom_rd_reg <= 1'b0;
            timer0_sel <= 1'b0;
            timer0_addr <= addr[3:0];
            timer0_rd <= 1'b0;
            timer0_wr <= 1'b0;
            gpio0_sel <= 1'b0;
            gpio0_addr <= addr[3:0];
            gpio0_rd <= 1'b0;
            gpio0_wr <= 1'b0;
            uart0_sel <= 1'b0;
            uart0_addr <= addr[3:0];
            uart0_rd <= 1'b0;
            uart0_wr <= 1'b0;
            uart1_sel <= 1'b0;
            uart1_addr <= addr[3:0];
            uart1_rd <= 1'b0;
            uart1_wr <= 1'b0;
            spi1_sel <= 1'b0;
            spi1_addr <= addr[3:0];
            spi1_rd <= 1'b0;
            spi1_wr <= 1'b0;
            i2c0_sel <= 1'b0;
            i2c0_addr <= addr[3:0];
            i2c0_rd <= 1'b0;
            i2c0_wr <= 1'b0;
            imath_sel <= 1'b0;
            imath_addr <= addr[3:0];
            imath_rd <= 1'b0;
            imath_wr <= 1'b0;

            if (is_rom(addr)) begin
                // Upper 32KB: ROM from SPI flash
                rom_cs <= 1'b1;
                rom_rd_reg <= 1'b1;
            end else if (is_timer0(addr)) begin
                timer0_sel <= 1'b1;
                timer0_addr <= addr[3:0];
            end else if (is_gpio0(addr)) begin
                gpio0_sel <= 1'b1;
                gpio0_addr <= addr[3:0];
            end else if (is_uart0(addr)) begin
                uart0_sel <= 1'b1;
                uart0_addr <= addr[3:0];
            end else if (is_uart1(addr)) begin
                uart1_sel <= 1'b1;
                uart1_addr <= addr[3:0];
            end else if (is_spi1(addr)) begin
                spi1_sel <= 1'b1;
                spi1_addr <= addr[3:0];
            end else if (is_i2c0(addr)) begin
                i2c0_sel <= 1'b1;
                i2c0_addr <= addr[3:0];
            end else if (is_imath(addr)) begin
                imath_sel <= 1'b1;
                imath_addr <= addr[3:0];
            end else if (is_ram(addr)) begin
                // Internal RAM (banked)
                ram_cs_0 <= (ram_bank_reg == 2'd0);
                ram_cs_1 <= (ram_bank_reg == 2'd1);
                ram_cs_2 <= (ram_bank_reg == 2'd2);
                ram_cs_3 <= (ram_bank_reg == 2'd3);
            end
        end
    endtask

    // =========================================================================
    // FSM Logic
    // =========================================================================

    wire [15:0] direct_addr = {fetched_imm2, fetched_imm1};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            fsm_state <= S_FETCH_OP;
            fetch_addr <= 16'h0000;
            fetched_op <= 8'h00;
            fetched_imm1 <= 8'h00;
            fetched_imm2 <= 8'h00;
            execute_pulse <= 1'b0;
            mem_rd_buf <= 8'h00;
            stk_lo_buf <= 8'h00;
            stk_hi_buf <= 8'h00;
            io_rd_buf <= 8'h00;
            periph_rd_buf <= 8'h00;
            ram_addr <= 14'd0;
            ram_wdata <= 16'd0;
            ram_we <= 4'b0000;
            ram_cs_0 <= 1'b0; ram_cs_1 <= 1'b0;
            ram_cs_2 <= 1'b0; ram_cs_3 <= 1'b0;
            rom_cs <= 1'b0;
            rom_rd_reg <= 1'b0;
            rom_bank_reg <= 8'h00;
            ram_bank_reg <= 2'b00;
            timer0_sel <= 1'b0;
            timer0_addr <= 4'd0;
            timer0_wdata <= 8'd0;
            timer0_rd <= 1'b0;
            timer0_wr <= 1'b0;
            gpio0_sel <= 1'b0;
            gpio0_addr <= 4'd0;
            gpio0_wdata <= 8'd0;
            gpio0_rd <= 1'b0;
            gpio0_wr <= 1'b0;
            uart0_sel <= 1'b0;
            uart0_addr <= 4'd0;
            uart0_wdata <= 8'd0;
            uart0_rd <= 1'b0;
            uart0_wr <= 1'b0;
            uart1_sel <= 1'b0;
            uart1_addr <= 4'd0;
            uart1_wdata <= 8'd0;
            uart1_rd <= 1'b0;
            uart1_wr <= 1'b0;
            spi1_sel <= 1'b0;
            spi1_addr <= 4'd0;
            spi1_wdata <= 8'd0;
            spi1_rd <= 1'b0;
            spi1_wr <= 1'b0;
            i2c0_sel <= 1'b0;
            i2c0_addr <= 4'd0;
            i2c0_wdata <= 8'd0;
            i2c0_rd <= 1'b0;
            i2c0_wr <= 1'b0;
            imath_sel <= 1'b0;
            imath_addr <= 4'd0;
            imath_wdata <= 8'd0;
            imath_rd <= 1'b0;
            imath_wr <= 1'b0;
            int_ack_pulse <= 1'b0;
        end else begin
            execute_pulse <= 1'b0;
            ram_we <= 4'b0000;
            rom_rd_reg <= 1'b0;
            timer0_rd <= 1'b0;
            timer0_wr <= 1'b0;
            gpio0_rd <= 1'b0;
            gpio0_wr <= 1'b0;
            uart0_rd <= 1'b0;
            uart0_wr <= 1'b0;
            uart1_rd <= 1'b0;
            uart1_wr <= 1'b0;
            spi1_rd <= 1'b0;
            spi1_wr <= 1'b0;
            i2c0_rd <= 1'b0;
            i2c0_wr <= 1'b0;
            imath_rd <= 1'b0;
            imath_wr <= 1'b0;
            int_ack_pulse <= 1'b0;

            case (fsm_state)
                S_FETCH_OP: begin
                    if (cpu_halted_wire) begin
                        fsm_state <= S_HALTED;
                    end else begin
                        set_addr_decode(cpu_pc);
                        fsm_state <= S_WAIT_OP;
                    end
                end

                S_WAIT_OP: begin
                    // Set read strobe for peripherals
                    if (timer0_sel) timer0_rd <= 1'b1;
                    if (gpio0_sel) gpio0_rd <= 1'b1;
                    if (uart0_sel) uart0_rd <= 1'b1;
                    if (uart1_sel) uart1_rd <= 1'b1;
                    if (spi1_sel) spi1_rd <= 1'b1;
                    if (i2c0_sel) i2c0_rd <= 1'b1;
                    if (imath_sel) imath_rd <= 1'b1;

                    if (!mem_ready) begin
                        // Wait for ROM cache
                    end else begin
                        fetched_op <= mem_byte;
                        if (inst_len(mem_byte) >= 2'd2) begin
                            set_addr_decode(cpu_pc + 16'd1);
                            fsm_state <= S_FETCH_IMM1;
                        end else if (needs_hl_read(mem_byte) || needs_bc_read(mem_byte) || needs_de_read(mem_byte)) begin
                            fsm_state <= S_READ_MEM;
                        end else if (needs_stack_read(mem_byte)) begin
                            set_addr_decode(cpu_sp);
                            fsm_state <= S_READ_STK_LO;
                        end else begin
                            fsm_state <= S_EXECUTE;
                        end
                    end
                end

                S_FETCH_IMM1: fsm_state <= S_WAIT_IMM1;

                S_WAIT_IMM1: begin
                    if (timer0_sel) timer0_rd <= 1'b1;
                    if (gpio0_sel) gpio0_rd <= 1'b1;
                    if (uart0_sel) uart0_rd <= 1'b1;
                    if (uart1_sel) uart1_rd <= 1'b1;
                    if (spi1_sel) spi1_rd <= 1'b1;
                    if (i2c0_sel) i2c0_rd <= 1'b1;
                    if (imath_sel) imath_rd <= 1'b1;

                    if (!mem_ready) begin
                        // Wait
                    end else begin
                        fetched_imm1 <= mem_byte;
                        if (inst_len(fetched_op) >= 2'd3) begin
                            set_addr_decode(cpu_pc + 16'd2);
                            fsm_state <= S_FETCH_IMM2;
                        end else if (needs_io_read(fetched_op)) begin
                            // I/O read - bank registers
                            io_rd_buf <= 8'hFF;
                            fsm_state <= S_EXECUTE;
                        end else if (needs_hl_read(fetched_op) || needs_bc_read(fetched_op) || needs_de_read(fetched_op)) begin
                            fsm_state <= S_READ_MEM;
                        end else if (needs_stack_read(fetched_op)) begin
                            set_addr_decode(cpu_sp);
                            fsm_state <= S_READ_STK_LO;
                        end else begin
                            fsm_state <= S_EXECUTE;
                        end
                    end
                end

                S_FETCH_IMM2: fsm_state <= S_WAIT_IMM2;

                S_WAIT_IMM2: begin
                    if (timer0_sel) timer0_rd <= 1'b1;
                    if (gpio0_sel) gpio0_rd <= 1'b1;
                    if (uart0_sel) uart0_rd <= 1'b1;
                    if (uart1_sel) uart1_rd <= 1'b1;
                    if (spi1_sel) spi1_rd <= 1'b1;
                    if (i2c0_sel) i2c0_rd <= 1'b1;
                    if (imath_sel) imath_rd <= 1'b1;

                    if (!mem_ready) begin
                        // Wait
                    end else begin
                        fetched_imm2 <= mem_byte;
                        if (needs_direct_read(fetched_op)) begin
                            set_addr_decode({mem_byte, fetched_imm1});
                            fsm_state <= S_READ_MEM;
                        end else if (needs_stack_read(fetched_op)) begin
                            set_addr_decode(cpu_sp);
                            fsm_state <= S_READ_STK_LO;
                        end else begin
                            fsm_state <= S_EXECUTE;
                        end
                    end
                end

                S_READ_MEM: fsm_state <= S_WAIT_MEM;

                S_WAIT_MEM: begin
                    if (timer0_sel) timer0_rd <= 1'b1;
                    if (gpio0_sel) gpio0_rd <= 1'b1;
                    if (uart0_sel) uart0_rd <= 1'b1;
                    if (uart1_sel) uart1_rd <= 1'b1;
                    if (spi1_sel) spi1_rd <= 1'b1;
                    if (i2c0_sel) i2c0_rd <= 1'b1;
                    if (imath_sel) imath_rd <= 1'b1;

                    if (!mem_ready) begin
                        // Wait
                    end else begin
                        mem_rd_buf <= mem_byte;
                        if (fetched_op == 8'h2A) begin
                            set_addr_decode(direct_addr + 16'd1);
                            fsm_state <= S_READ_STK_LO;
                        end else if (needs_stack_read(fetched_op)) begin
                            set_addr_decode(cpu_sp);
                            fsm_state <= S_READ_STK_LO;
                        end else begin
                            fsm_state <= S_EXECUTE;
                        end
                    end
                end

                S_READ_STK_LO: fsm_state <= S_WAIT_STK_LO;

                S_WAIT_STK_LO: begin
                    if (timer0_sel) timer0_rd <= 1'b1;
                    if (gpio0_sel) gpio0_rd <= 1'b1;
                    if (uart0_sel) uart0_rd <= 1'b1;
                    if (uart1_sel) uart1_rd <= 1'b1;
                    if (spi1_sel) spi1_rd <= 1'b1;
                    if (i2c0_sel) i2c0_rd <= 1'b1;
                    if (imath_sel) imath_rd <= 1'b1;

                    if (!mem_ready) begin
                        // Wait
                    end else begin
                        stk_lo_buf <= mem_byte;
                        set_addr_decode(fetch_addr + 16'd1);
                        fsm_state <= S_READ_STK_HI;
                    end
                end

                S_READ_STK_HI: fsm_state <= S_WAIT_STK_HI;

                S_WAIT_STK_HI: begin
                    if (timer0_sel) timer0_rd <= 1'b1;
                    if (gpio0_sel) gpio0_rd <= 1'b1;
                    if (uart0_sel) uart0_rd <= 1'b1;
                    if (uart1_sel) uart1_rd <= 1'b1;
                    if (spi1_sel) spi1_rd <= 1'b1;
                    if (i2c0_sel) i2c0_rd <= 1'b1;
                    if (imath_sel) imath_rd <= 1'b1;

                    if (!mem_ready) begin
                        // Wait
                    end else begin
                        stk_hi_buf <= mem_byte;
                        fsm_state <= S_EXECUTE;
                    end
                end

                S_EXECUTE: begin
                    execute_pulse <= 1'b1;
                    if (cpu_stack_wr) begin
                        set_addr_decode(cpu_stack_wr_addr);
                        ram_wdata <= {cpu_stack_wr_hi, cpu_stack_wr_lo};
                        ram_we <= cpu_stack_wr_addr[0] ? 4'b1100 : 4'b0011;
                        fsm_state <= S_WRITE_STK;
                    end else if (cpu_mem_wr) begin
                        set_addr_decode(cpu_mem_addr);
                        if (is_timer0(cpu_mem_addr)) begin
                            timer0_addr <= cpu_mem_addr[3:0];
                            timer0_wdata <= cpu_mem_data_out;
                            timer0_wr <= 1'b1;
                            fsm_state <= S_FETCH_OP;
                        end else if (is_gpio0(cpu_mem_addr)) begin
                            gpio0_addr <= cpu_mem_addr[3:0];
                            gpio0_wdata <= cpu_mem_data_out;
                            gpio0_wr <= 1'b1;
                            fsm_state <= S_FETCH_OP;
                        end else if (is_uart0(cpu_mem_addr)) begin
                            uart0_addr <= cpu_mem_addr[3:0];
                            uart0_wdata <= cpu_mem_data_out;
                            uart0_wr <= 1'b1;
                            fsm_state <= S_FETCH_OP;
                        end else if (is_uart1(cpu_mem_addr)) begin
                            uart1_addr <= cpu_mem_addr[3:0];
                            uart1_wdata <= cpu_mem_data_out;
                            uart1_wr <= 1'b1;
                            fsm_state <= S_FETCH_OP;
                        end else if (is_spi1(cpu_mem_addr)) begin
                            spi1_addr <= cpu_mem_addr[3:0];
                            spi1_wdata <= cpu_mem_data_out;
                            spi1_wr <= 1'b1;
                            fsm_state <= S_FETCH_OP;
                        end else if (is_i2c0(cpu_mem_addr)) begin
                            i2c0_addr <= cpu_mem_addr[3:0];
                            i2c0_wdata <= cpu_mem_data_out;
                            i2c0_wr <= 1'b1;
                            fsm_state <= S_FETCH_OP;
                        end else if (is_imath(cpu_mem_addr)) begin
                            imath_addr <= cpu_mem_addr[3:0];
                            imath_wdata <= cpu_mem_data_out;
                            imath_wr <= 1'b1;
                            fsm_state <= S_FETCH_OP;
                        end else if (is_ram(cpu_mem_addr)) begin
                            ram_wdata <= {cpu_mem_data_out, cpu_mem_data_out};
                            ram_we <= cpu_mem_addr[0] ? 4'b1100 : 4'b0011;
                            fsm_state <= S_FETCH_OP;
                        end else begin
                            // Invalid address, ignore
                            fsm_state <= S_FETCH_OP;
                        end
                    end else if (cpu_io_wr) begin
                        // Handle bank register writes
                        if (cpu_io_port == PORT_ROM_BANK)
                            rom_bank_reg <= cpu_io_data_out;
                        else if (cpu_io_port == PORT_RAM_BANK)
                            ram_bank_reg <= cpu_io_data_out[1:0];
                        fsm_state <= S_FETCH_OP;
                    end else begin
                        fsm_state <= S_FETCH_OP;
                    end
                end

                S_WRITE_STK: begin
                    if (cpu_stack_wr_addr[0] == 1'b0) begin
                        set_addr_decode(cpu_stack_wr_addr + 16'd2);
                        ram_wdata <= {cpu_stack_wr_hi, cpu_stack_wr_hi};
                        ram_we <= 4'b0011;
                    end
                    fsm_state <= S_FETCH_OP;
                end

                S_HALTED: begin
                    // Check for interrupts to wake from HALT
                    if (trap_pending || (cpu_inte && (rst75_pending || rst65 || rst55 || intr_pending))) begin
                        fsm_state <= S_FETCH_OP;
                    end
                end

                default: fsm_state <= S_FETCH_OP;
            endcase
        end
    end

    // =========================================================================
    // CPU Core
    // =========================================================================

    i8085_wrapper cpu (
        .clk(clk),
        .reset_n(reset_n),
        .mem_addr(cpu_mem_addr),
        .mem_data_in(mem_byte),
        .mem_data_out(cpu_mem_data_out),
        .mem_rd(),
        .mem_wr(cpu_mem_wr),
        .stack_wr_addr(cpu_stack_wr_addr),
        .stack_wr_data_lo(cpu_stack_wr_lo),
        .stack_wr_data_hi(cpu_stack_wr_hi),
        .stack_wr(cpu_stack_wr),
        .io_port(cpu_io_port),
        .io_data_out(cpu_io_data_out),
        .io_data_in(io_rd_buf),
        .io_rd(cpu_io_rd),
        .io_wr(cpu_io_wr),
        .opcode(fetched_op),
        .imm1(fetched_imm1),
        .imm2(fetched_imm2),
        .mem_read_data(mem_rd_buf),
        .stack_lo(stk_lo_buf),
        .stack_hi(stk_hi_buf),
        .execute(execute_pulse),
        .int_ack(int_ack_pulse),
        .int_vector(trap_pending ? 16'h0024 :
                    rst75_pending ? 16'h003C :
                    (rst65 && !cpu_mask_65) ? 16'h0034 :
                    (rst55 && !cpu_mask_55) ? 16'h002C :
                    intr_pending ? periph_int_vector : 16'h0000),  // Vectored peripheral IRQs
        .int_is_trap(trap_pending),
        .sid(sid),
        .rst55_level(rst55),
        .rst65_level(rst65),
        .pc(cpu_pc),
        .sp(cpu_sp),
        .reg_a(),
        .reg_b(),
        .reg_c(),
        .reg_d(),
        .reg_e(),
        .reg_h(),
        .reg_l(),
        .halted(cpu_halted_wire),
        .inte(cpu_inte),
        .flag_z(),
        .flag_c(),
        .mask_55(cpu_mask_55),
        .mask_65(cpu_mask_65),
        .mask_75(cpu_mask_75),
        .rst75_pending(),
        .sod(cpu_sod)
    );

endmodule
