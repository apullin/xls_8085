// i8085sg_new.v - Refactored "System General" MCU variant
// Uses i8085_cpu (self-contained) and memory_controller modules
// Phase 4 of refactoring: thin integration wrapper
//
// Build-time config (inclusive):
//   -DHAS_GPIO1     Enable 4-bit GPIO1 (~60 LCs)
//   -DHAS_USERIAL1  Enable second userial as full UART/SPI (~500 LCs)
//   -DHAS_SPI1      Enable second serial as SPI-only (~230 LCs)

module i8085sg (
    input  wire        clk,
    input  wire        reset_n,

    // Interrupts
    input  wire        trap,
    input  wire        rst75,
    input  wire        rst65,
    input  wire        rst55,

    // Serial I/O
    input  wire        sid,
    output wire        sod,

    // SPI Flash
    output wire        spi_sck,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,

    // Timer (4 PWM channels)
    output wire        timer0_irq,
    output wire        pwm0,
    output wire        pwm1,
    output wire        pwm2,
    output wire        pwm3,

    // GPIO 0 (8-bit)
    input  wire [7:0]  gpio0_in,
    output wire [7:0]  gpio0_out,
    output wire [7:0]  gpio0_oe,

    // GPIO 1 (4-bit only)
    input  wire [3:0]  gpio1_in,
    output wire [3:0]  gpio1_out,
    output wire [3:0]  gpio1_oe,

    // Universal Serial 0
    input  wire        userial0_rx_miso,
    output wire        userial0_tx_mosi,
    output wire        userial0_sck,
    output wire        userial0_cs_n,

    // Universal Serial 1
    input  wire        userial1_rx_miso,
    output wire        userial1_tx_mosi,
    output wire        userial1_sck,
    output wire        userial1_cs_n,

    // I2C0
    input  wire        i2c0_sda_in,
    output wire        i2c0_sda_out,
    output wire        i2c0_sda_oe,
    input  wire        i2c0_scl_in,
    output wire        i2c0_scl_out,
    output wire        i2c0_scl_oe
);

    // =========================================================================
    // Forward Declarations (for elaboration order)
    // =========================================================================

    // Interrupt controller outputs (used by CPU)
    wire        int_pending;
    wire [15:0] int_vector;
    reg         trap_pending;

    // =========================================================================
    // CPU Instance
    // =========================================================================

    wire [15:0] cpu_bus_addr;
    wire [7:0]  cpu_bus_data_out;
    wire        cpu_bus_rd;
    wire        cpu_bus_wr;
    wire [7:0]  cpu_bus_data_in;
    wire        cpu_bus_ready;

    wire [15:0] cpu_stack_wr_addr;
    wire [7:0]  cpu_stack_wr_data_lo;
    wire [7:0]  cpu_stack_wr_data_hi;
    wire        cpu_stack_wr;

    wire [7:0]  cpu_io_port;
    wire [7:0]  cpu_io_data_out;
    wire        cpu_io_rd, cpu_io_wr;

    wire [7:0]  cpu_rom_bank;
    wire [2:0]  cpu_ram_bank;

    wire        cpu_int_ack;
    wire [15:0] cpu_pc, cpu_sp;
    wire        cpu_halted, cpu_inte;
    wire        cpu_mask_55, cpu_mask_65, cpu_mask_75;
    wire        cpu_sod;

    i8085_cpu cpu (
        .clk(clk),
        .reset_n(reset_n),
        .bus_addr(cpu_bus_addr),
        .bus_data_out(cpu_bus_data_out),
        .bus_rd(cpu_bus_rd),
        .bus_wr(cpu_bus_wr),
        .bus_data_in(cpu_bus_data_in),
        .bus_ready(cpu_bus_ready),
        .stack_wr_addr(cpu_stack_wr_addr),
        .stack_wr_data_lo(cpu_stack_wr_data_lo),
        .stack_wr_data_hi(cpu_stack_wr_data_hi),
        .stack_wr(cpu_stack_wr),
        .io_port(cpu_io_port),
        .io_data_out(cpu_io_data_out),
        .io_data_in(8'hFF),  // No external I/O devices
        .io_rd(cpu_io_rd),
        .io_wr(cpu_io_wr),
        .rom_bank(cpu_rom_bank),
        .ram_bank(cpu_ram_bank),
        .int_req(int_pending),
        .int_vector(int_vector),
        .int_is_trap(trap_pending),
        .int_ack(cpu_int_ack),
        .sid(sid),
        .rst55_level(rst55),
        .rst65_level(rst65),
        .pc(cpu_pc),
        .sp(cpu_sp),
        .reg_a(), .reg_b(), .reg_c(), .reg_d(), .reg_e(), .reg_h(), .reg_l(),
        .halted(cpu_halted),
        .inte(cpu_inte),
        .flag_z(), .flag_c(),
        .mask_55(cpu_mask_55),
        .mask_65(cpu_mask_65),
        .mask_75(cpu_mask_75),
        .rst75_pending(),
        .sod(cpu_sod)
    );

    assign sod = cpu_sod;

    // =========================================================================
    // Memory Controller
    // =========================================================================

    wire [3:0] periph_addr;
    wire [7:0] periph_wdata;
    wire       periph_rd, periph_wr;
    wire [3:0] periph_slot;
    wire [7:0] periph_rdata;

    memory_controller mem (
        .clk(clk),
        .reset_n(reset_n),
        .cpu_addr(cpu_bus_addr),
        .cpu_data_out(cpu_bus_data_out),
        .cpu_rd(cpu_bus_rd),
        .cpu_wr(cpu_bus_wr),
        .cpu_data_in(cpu_bus_data_in),
        .cpu_ready(cpu_bus_ready),
        .stack_wr_addr(cpu_stack_wr_addr),
        .stack_wr_data_lo(cpu_stack_wr_data_lo),
        .stack_wr_data_hi(cpu_stack_wr_data_hi),
        .stack_wr(cpu_stack_wr),
        .rom_bank(cpu_rom_bank),
        .ram_bank(cpu_ram_bank),
        .spi_sck(spi_sck),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .periph_addr(periph_addr),
        .periph_wdata(periph_wdata),
        .periph_rd(periph_rd),
        .periph_wr(periph_wr),
        .periph_slot(periph_slot),
        .periph_rdata(periph_rdata),
        // DMA port unused in SG variant
        .dma_req(1'b0),
        .dma_addr(14'd0),
        .dma_bank(2'd0),
        .dma_wdata(16'd0),
        .dma_we(4'b0000),
        .dma_rdata()
    );

    // =========================================================================
    // Peripheral Address Decode
    // =========================================================================

    wire sel_timer0   = (periph_slot == 4'h0);
    wire sel_gpio0    = (periph_slot == 4'h1);
    wire sel_userial0 = (periph_slot == 4'h2);
    wire sel_userial1 = (periph_slot == 4'h3);
    wire sel_gpio1    = (periph_slot == 4'h4);
    wire sel_i2c0     = (periph_slot == 4'h5);
    wire sel_imath    = (periph_slot == 4'h6);

    wire timer0_rd   = periph_rd & sel_timer0;
    wire gpio0_rd    = periph_rd & sel_gpio0;
    wire gpio1_rd    = periph_rd & sel_gpio1;
    wire userial0_rd = periph_rd & sel_userial0;
    wire userial1_rd = periph_rd & sel_userial1;
    wire i2c0_rd     = periph_rd & sel_i2c0;
    wire imath_rd    = periph_rd & sel_imath;

    wire timer0_wr   = periph_wr & sel_timer0;
    wire gpio0_wr    = periph_wr & sel_gpio0;
    wire gpio1_wr    = periph_wr & sel_gpio1;
    wire userial0_wr = periph_wr & sel_userial0;
    wire userial1_wr = periph_wr & sel_userial1;
    wire i2c0_wr     = periph_wr & sel_i2c0;
    wire imath_wr    = periph_wr & sel_imath;

    wire [7:0] timer0_rdata, gpio0_rdata, gpio1_rdata;
    wire [7:0] userial0_rdata, userial1_rdata, i2c0_rdata, imath_rdata;
    wire       timer0_irq_w, gpio0_irq, gpio1_irq, userial0_irq, userial1_irq, i2c0_irq;

    assign timer0_irq = timer0_irq_w;

    assign periph_rdata = ({8{sel_timer0}}   & timer0_rdata)   |
                          ({8{sel_gpio0}}    & gpio0_rdata)    |
                          ({8{sel_gpio1}}    & gpio1_rdata)    |
                          ({8{sel_userial0}} & userial0_rdata) |
                          ({8{sel_userial1}} & userial1_rdata) |
                          ({8{sel_i2c0}}     & i2c0_rdata)     |
                          ({8{sel_imath}}    & imath_rdata);

    // =========================================================================
    // Peripherals
    // =========================================================================

    timer16_wrapper timer0 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_addr), .data_in(periph_wdata), .data_out(timer0_rdata),
        .rd(timer0_rd), .wr(timer0_wr),
        .tick(1'b1), .irq(timer0_irq_w),
        .pwm0(pwm0), .pwm1(pwm1), .pwm2(pwm2), .pwm3(pwm3)
    );

    gpio8_wrapper gpio0 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_addr), .data_in(periph_wdata), .data_out(gpio0_rdata),
        .rd(gpio0_rd), .wr(gpio0_wr),
        .pins_in(gpio0_in), .pins_out(gpio0_out), .pins_oe(gpio0_oe),
        .irq(gpio0_irq)
    );

`ifdef HAS_GPIO1
    gpio4_wrapper gpio1 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_addr), .data_in(periph_wdata), .data_out(gpio1_rdata),
        .rd(gpio1_rd), .wr(gpio1_wr),
        .pins_in(gpio1_in), .pins_out(gpio1_out), .pins_oe(gpio1_oe),
        .irq(gpio1_irq)
    );
`else
    assign gpio1_out = 4'b0;
    assign gpio1_oe = 4'b0;
    assign gpio1_rdata = 8'hFF;
    assign gpio1_irq = 1'b0;
`endif

    userial_wrapper userial0 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_addr), .data_in(periph_wdata), .data_out(userial0_rdata),
        .rd(userial0_rd), .wr(userial0_wr),
        .rx_miso(userial0_rx_miso), .tx_mosi(userial0_tx_mosi),
        .sck(userial0_sck), .cs_n(userial0_cs_n),
        .irq(userial0_irq)
    );

`ifdef HAS_USERIAL1
    userial_wrapper userial1 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_addr), .data_in(periph_wdata), .data_out(userial1_rdata),
        .rd(userial1_rd), .wr(userial1_wr),
        .rx_miso(userial1_rx_miso), .tx_mosi(userial1_tx_mosi),
        .sck(userial1_sck), .cs_n(userial1_cs_n),
        .irq(userial1_irq)
    );
`elsif HAS_SPI1
    spi_wrapper spi1 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_addr), .data_in(periph_wdata), .data_out(userial1_rdata),
        .rd(userial1_rd), .wr(userial1_wr),
        .miso(userial1_rx_miso), .mosi(userial1_tx_mosi),
        .sck(userial1_sck), .cs_n(userial1_cs_n),
        .irq(userial1_irq)
    );
`else
    assign userial1_tx_mosi = 1'b1;
    assign userial1_sck = 1'b0;
    assign userial1_cs_n = 1'b1;
    assign userial1_rdata = 8'hFF;
    assign userial1_irq = 1'b0;
`endif

    i2c_wrapper i2c0 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_addr), .data_in(periph_wdata), .data_out(i2c0_rdata),
        .rd(i2c0_rd), .wr(i2c0_wr),
        .sda_in(i2c0_sda_in), .sda_out(i2c0_sda_out), .sda_oe(i2c0_sda_oe),
        .scl_in(i2c0_scl_in), .scl_out(i2c0_scl_out), .scl_oe(i2c0_scl_oe),
        .irq(i2c0_irq)
    );

    imath_lite_wrapper imath0 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_addr), .data_in(periph_wdata), .data_out(imath_rdata),
        .rd(imath_rd), .wr(imath_wr)
    );

    // =========================================================================
    // Interrupt Controller
    // =========================================================================

    reg rst75_prev, trap_prev;
    reg rst75_pending;  // trap_pending declared above
    reg intr_pending;

    wire [2:0] int_priority = timer0_irq_w  ? 3'd1 :
                              gpio0_irq     ? 3'd2 :
                              userial0_irq  ? 3'd3 :
                              userial1_irq  ? 3'd4 :
                              gpio1_irq     ? 3'd5 :
                              i2c0_irq      ? 3'd6 : 3'd0;
    wire [15:0] periph_int_vector = {10'b0, int_priority, 3'b000};

    assign int_pending = trap_pending ||
                         (cpu_inte && (rst75_pending ||
                                       (rst65 && !cpu_mask_65) ||
                                       (rst55 && !cpu_mask_55) ||
                                       intr_pending));

    assign int_vector = trap_pending ? 16'h0024 :
                        rst75_pending ? 16'h003C :
                        (rst65 && !cpu_mask_65) ? 16'h0034 :
                        (rst55 && !cpu_mask_55) ? 16'h002C :
                        intr_pending ? periph_int_vector : 16'h0000;

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
            if (rst75 && !rst75_prev) rst75_pending <= 1'b1;
            if ((trap && !trap_prev) || trap) trap_pending <= 1'b1;
            intr_pending <= timer0_irq_w | gpio0_irq | gpio1_irq | userial0_irq | userial1_irq | i2c0_irq;
            if (cpu_int_ack) begin
                if (trap_pending) trap_pending <= 1'b0;
                else if (rst75_pending) rst75_pending <= 1'b0;
            end
        end
    end

endmodule
