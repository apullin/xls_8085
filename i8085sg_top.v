// i8085sg_top.v - "System General" top wrapper with SB_IO
// 2x userial, 12 GPIO, 4 PWM (center-aligned), imath_lite, I2C

module i8085sg_top (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        trap,
    input  wire        rst75,
    input  wire        rst65,
    input  wire        rst55,
    input  wire        sid,
    output wire        sod,
    output wire        spi_sck,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        timer0_irq,
    output wire        pwm0,
    output wire        pwm1,
    output wire        pwm2,
    output wire        pwm3,
    inout  wire [7:0]  gpio0,
    inout  wire [3:0]  gpio1,   // Only 4-bit
    // Universal Serial
    input  wire        userial0_rx_miso,
    output wire        userial0_tx_mosi,
    output wire        userial0_sck,
    output wire        userial0_cs_n,
    // Universal Serial 1
    input  wire        userial1_rx_miso,
    output wire        userial1_tx_mosi,
    output wire        userial1_sck,
    output wire        userial1_cs_n,
    // I2C
    inout  wire        i2c0_sda,
    inout  wire        i2c0_scl
);

    wire [7:0] gpio0_in, gpio0_out, gpio0_oe;
    wire [3:0] gpio1_in, gpio1_out, gpio1_oe;
    wire i2c0_sda_in, i2c0_sda_out, i2c0_sda_oe;
    wire i2c0_scl_in, i2c0_scl_out, i2c0_scl_oe;

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : gpio0_io
            SB_IO #(.PIN_TYPE(6'b1010_01), .PULLUP(1'b0)) gpio_iob (
                .PACKAGE_PIN(gpio0[i]),
                .OUTPUT_ENABLE(gpio0_oe[i]),
                .D_OUT_0(gpio0_out[i]),
                .D_IN_0(gpio0_in[i])
            );
        end
        for (i = 0; i < 4; i = i + 1) begin : gpio1_io
            SB_IO #(.PIN_TYPE(6'b1010_01), .PULLUP(1'b0)) gpio_iob (
                .PACKAGE_PIN(gpio1[i]),
                .OUTPUT_ENABLE(gpio1_oe[i]),
                .D_OUT_0(gpio1_out[i]),
                .D_IN_0(gpio1_in[i])
            );
        end
    endgenerate

    SB_IO #(.PIN_TYPE(6'b1010_01), .PULLUP(1'b1)) i2c_sda_iob (
        .PACKAGE_PIN(i2c0_sda),
        .OUTPUT_ENABLE(i2c0_sda_oe),
        .D_OUT_0(i2c0_sda_out),
        .D_IN_0(i2c0_sda_in)
    );

    SB_IO #(.PIN_TYPE(6'b1010_01), .PULLUP(1'b1)) i2c_scl_iob (
        .PACKAGE_PIN(i2c0_scl),
        .OUTPUT_ENABLE(i2c0_scl_oe),
        .D_OUT_0(i2c0_scl_out),
        .D_IN_0(i2c0_scl_in)
    );

    i8085sg mcu (
        .clk(clk), .reset_n(reset_n),
        .trap(trap), .rst75(rst75), .rst65(rst65), .rst55(rst55),
        .sid(sid), .sod(sod),
        .spi_sck(spi_sck), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
        .timer0_irq(timer0_irq),
        .pwm0(pwm0), .pwm1(pwm1), .pwm2(pwm2), .pwm3(pwm3),
        .gpio0_in(gpio0_in), .gpio0_out(gpio0_out), .gpio0_oe(gpio0_oe),
        .gpio1_in(gpio1_in), .gpio1_out(gpio1_out), .gpio1_oe(gpio1_oe),
        .userial0_rx_miso(userial0_rx_miso), .userial0_tx_mosi(userial0_tx_mosi),
        .userial0_sck(userial0_sck), .userial0_cs_n(userial0_cs_n),
        .userial1_rx_miso(userial1_rx_miso), .userial1_tx_mosi(userial1_tx_mosi),
        .userial1_sck(userial1_sck), .userial1_cs_n(userial1_cs_n),
        .i2c0_sda_in(i2c0_sda_in), .i2c0_sda_out(i2c0_sda_out), .i2c0_sda_oe(i2c0_sda_oe),
        .i2c0_scl_in(i2c0_scl_in), .i2c0_scl_out(i2c0_scl_out), .i2c0_scl_oe(i2c0_scl_oe)
    );

endmodule
