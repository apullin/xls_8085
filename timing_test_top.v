// Minimal top wrappers for timing analysis only
// Exposes just clk, reset_n, SPI flash - everything else internal

module sg_timing_top (
    input  wire clk,
    input  wire reset_n,
    output wire spi_sck,
    output wire spi_cs_n,
    output wire spi_mosi,
    input  wire spi_miso
);
    i8085sg mcu (
        .clk(clk), .reset_n(reset_n),
        .trap(1'b0), .rst75(1'b0), .rst65(1'b0), .rst55(1'b0),
        .sid(1'b0),
        .spi_sck(spi_sck), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
        .gpio0_in(8'h00), .gpio1_in(4'h0),
        .userial0_rx_miso(1'b1), .userial1_rx_miso(1'b1),
        .i2c0_sda_in(1'b1), .i2c0_scl_in(1'b1)
    );
endmodule

module sv_timing_top (
    input  wire clk,
    input  wire reset_n,
    output wire spi_sck,
    output wire spi_cs_n,
    output wire spi_mosi,
    input  wire spi_miso
);
    i8085sv mcu (
        .clk(clk), .reset_n(reset_n),
        .trap(1'b0), .rst75(1'b0), .rst65(1'b0), .rst55(1'b0),
        .sid(1'b0),
        .spi_sck(spi_sck), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
        .gpio0_in(8'h00),
        .userial0_rx_miso(1'b1),
        .i2c0_sda_in(1'b1), .i2c0_scl_in(1'b1)
    );
endmodule
