// i8085sv_new.v - "System Vector" MCU variant (refactored)
// Uses shared i8085_cpu.v and memory_controller.v
//
// Peripherals: timer16, gpio8, userial, i2c, imath_lite, vmath
// vmath uses DMA port for direct SPRAM access
//
// UP5K utilization: ~5200 LCs (98%)

module i8085sv (
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

    // Timer
    output wire        timer0_irq,

    // GPIO
    input  wire [7:0]  gpio0_in,
    output wire [7:0]  gpio0_out,
    output wire [7:0]  gpio0_oe,

    // Universal Serial (UART/SPI switchable)
    input  wire        userial0_rx_miso,
    output wire        userial0_tx_mosi,
    output wire        userial0_sck,
    output wire        userial0_cs_n,

    // I2C0
    input  wire        i2c0_sda_in,
    output wire        i2c0_sda_out,
    output wire        i2c0_sda_oe,
    input  wire        i2c0_scl_in,
    output wire        i2c0_scl_out,
    output wire        i2c0_scl_oe,

    // Status
    output wire        cpu_halted,
    output wire        resout
);

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
    // Interrupt Controller
    // =========================================================================

    // Forward declarations for signals used in CPU instantiation
    wire int_pending;
    wire [15:0] int_vector;
    reg trap_pending;

    reg rst75_prev, trap_prev;
    reg rst75_pending;
    reg intr_pending;

    wire timer0_irq_w, gpio0_irq, userial0_irq, i2c0_irq;

    wire [2:0] int_priority = timer0_irq_w  ? 3'd1 :
                              gpio0_irq     ? 3'd2 :
                              userial0_irq  ? 3'd3 :
                              i2c0_irq      ? 3'd6 : 3'd0;
    wire [15:0] periph_int_vector = {10'b0, int_priority, 3'b000};

    assign timer0_irq = timer0_irq_w;

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
            intr_pending <= timer0_irq_w | gpio0_irq | userial0_irq | i2c0_irq;
            if (cpu_int_ack) begin
                if (trap_pending) trap_pending <= 1'b0;
                else if (rst75_pending) rst75_pending <= 1'b0;
            end
        end
    end

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
    wire        cpu_inte;
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
    // vmath DMA signals
    // =========================================================================

    wire        vmath_bus_req;
    wire [13:0] vmath_mem_addr;
    wire [1:0]  vmath_mem_bank;
    wire [15:0] vmath_mem_wdata;
    wire [3:0]  vmath_mem_we;
    wire [15:0] vmath_mem_rdata;

    // =========================================================================
    // Memory Controller
    // =========================================================================

    wire [3:0]  periph_addr;
    wire [7:0]  periph_wdata;
    wire        periph_rd;
    wire        periph_wr;
    wire [3:0]  periph_slot;
    wire [7:0]  periph_rdata;

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
        // DMA port for vmath
        .dma_req(vmath_bus_req),
        .dma_addr(vmath_mem_addr),
        .dma_bank(vmath_mem_bank),
        .dma_wdata(vmath_mem_wdata),
        .dma_we(vmath_mem_we),
        .dma_rdata(vmath_mem_rdata)
    );

    // =========================================================================
    // Peripheral Address Decode
    // =========================================================================

    wire sel_timer0   = (periph_slot == 4'h0);
    wire sel_gpio0    = (periph_slot == 4'h1);
    wire sel_userial0 = (periph_slot == 4'h2);
    wire sel_i2c0     = (periph_slot == 4'h5);
    wire sel_imath    = (periph_slot == 4'h6);
    wire sel_vmath    = (periph_slot == 4'h7);

    wire timer0_rd   = periph_rd & sel_timer0;
    wire timer0_wr   = periph_wr & sel_timer0;
    wire gpio0_rd    = periph_rd & sel_gpio0;
    wire gpio0_wr    = periph_wr & sel_gpio0;
    wire userial0_rd = periph_rd & sel_userial0;
    wire userial0_wr = periph_wr & sel_userial0;
    wire i2c0_rd     = periph_rd & sel_i2c0;
    wire i2c0_wr     = periph_wr & sel_i2c0;
    wire imath_rd    = periph_rd & sel_imath;
    wire imath_wr    = periph_wr & sel_imath;
    wire vmath_rd    = periph_rd & sel_vmath;
    wire vmath_wr    = periph_wr & sel_vmath;

    // =========================================================================
    // Peripheral Instances
    // =========================================================================

    wire [7:0] timer0_rdata, gpio0_rdata, userial0_rdata, i2c0_rdata, imath_rdata, vmath_rdata;

    timer16_wrapper timer0 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_addr), .data_in(periph_wdata), .data_out(timer0_rdata),
        .rd(timer0_rd), .wr(timer0_wr),
        .tick(1'b1), .irq(timer0_irq_w)
    );

    gpio8_wrapper gpio0 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_addr), .data_in(periph_wdata), .data_out(gpio0_rdata),
        .rd(gpio0_rd), .wr(gpio0_wr),
        .pins_in(gpio0_in), .pins_out(gpio0_out), .pins_oe(gpio0_oe),
        .irq(gpio0_irq)
    );

    userial_wrapper userial0 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_addr), .data_in(periph_wdata), .data_out(userial0_rdata),
        .rd(userial0_rd), .wr(userial0_wr),
        .rx_miso(userial0_rx_miso), .tx_mosi(userial0_tx_mosi),
        .sck(userial0_sck), .cs_n(userial0_cs_n),
        .irq(userial0_irq)
    );

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

    // vmath_wrapper needs bank mapping adjustment:
    // memory_controller uses 2-bit bank (0-3) but vmath expects full physical mapping
    wire        vmath_busy;

    vmath_wrapper vmath0 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_addr), .data_in(periph_wdata), .data_out(vmath_rdata),
        .rd(vmath_rd), .wr(vmath_wr),
        .mem_addr(vmath_mem_addr), .mem_bank(vmath_mem_bank),
        .mem_rdata(vmath_mem_rdata), .mem_wdata(vmath_mem_wdata), .mem_we(vmath_mem_we),
        .bus_request(vmath_bus_req), .busy(vmath_busy)
    );

    // =========================================================================
    // Peripheral Read Mux
    // =========================================================================

    assign periph_rdata = sel_timer0   ? timer0_rdata   :
                          sel_gpio0    ? gpio0_rdata    :
                          sel_userial0 ? userial0_rdata :
                          sel_i2c0     ? i2c0_rdata     :
                          sel_imath    ? imath_rdata    :
                          sel_vmath    ? vmath_rdata    :
                          8'hFF;

endmodule
