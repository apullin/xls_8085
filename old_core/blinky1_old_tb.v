// Blinky1 RAM Testbench for OLD architecture
// Same test as blinky1_new_tb.v but for i8085sg_old

`timescale 1ns / 1ps

module blinky1_old_tb;

    parameter CLK_PERIOD = 83;  // ~12 MHz
    parameter TIMEOUT_CYCLES = 100000;

    reg         clk;
    reg         reset_n;

    wire        trap = 1'b0;
    wire        rst75 = 1'b0;
    wire        rst65 = 1'b0;
    wire        rst55 = 1'b0;
    wire        sid = 1'b0;
    wire        sod;

    wire        spi_sck;
    wire        spi_cs_n;
    wire        spi_mosi;
    wire        spi_miso = 1'b1;

    wire        timer0_irq;
    wire        pwm0, pwm1, pwm2, pwm3;

    wire [7:0]  gpio0_out, gpio0_oe;
    reg  [7:0]  gpio0_in;
    wire [3:0]  gpio1_out, gpio1_oe;
    reg  [3:0]  gpio1_in;

    wire        userial0_rx_miso = 1'b1;
    wire        userial0_tx_mosi, userial0_sck, userial0_cs_n;
    wire        userial1_rx_miso = 1'b1;
    wire        userial1_tx_mosi, userial1_sck, userial1_cs_n;

    wire        i2c0_sda_in = 1'b1;
    wire        i2c0_sda_out, i2c0_sda_oe;
    wire        i2c0_scl_in = 1'b1;
    wire        i2c0_scl_out, i2c0_scl_oe;

    i8085sg_old dut (
        .clk(clk),
        .reset_n(reset_n),
        .trap(trap),
        .rst75(rst75),
        .rst65(rst65),
        .rst55(rst55),
        .sid(sid),
        .sod(sod),
        .spi_sck(spi_sck),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .timer0_irq(timer0_irq),
        .pwm0(pwm0),
        .pwm1(pwm1),
        .pwm2(pwm2),
        .pwm3(pwm3),
        .gpio0_in(gpio0_in),
        .gpio0_out(gpio0_out),
        .gpio0_oe(gpio0_oe),
        .gpio1_in(gpio1_in),
        .gpio1_out(gpio1_out),
        .gpio1_oe(gpio1_oe),
        .userial0_rx_miso(userial0_rx_miso),
        .userial0_tx_mosi(userial0_tx_mosi),
        .userial0_sck(userial0_sck),
        .userial0_cs_n(userial0_cs_n),
        .userial1_rx_miso(userial1_rx_miso),
        .userial1_tx_mosi(userial1_tx_mosi),
        .userial1_sck(userial1_sck),
        .userial1_cs_n(userial1_cs_n),
        .i2c0_sda_in(i2c0_sda_in),
        .i2c0_sda_out(i2c0_sda_out),
        .i2c0_sda_oe(i2c0_sda_oe),
        .i2c0_scl_in(i2c0_scl_in),
        .i2c0_scl_out(i2c0_scl_out),
        .i2c0_scl_oe(i2c0_scl_oe)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Load same program - OLD arch has SPRAMs directly in top module
    initial begin
        #1;
        dut.ram_bank0.mem[0] = 16'h1221;
        dut.ram_bank0.mem[1] = 16'h363F;
        dut.ram_bank0.mem[2] = 16'h0601;
        dut.ram_bank0.mem[3] = 16'h7800;
        dut.ram_bank0.mem[4] = 16'h01EE;
        dut.ram_bank0.mem[5] = 16'h2147;
        dut.ram_bank0.mem[6] = 16'h3F10;
        dut.ram_bank0.mem[7] = 16'h1677;
        dut.ram_bank0.mem[8] = 16'h1E01;
        dut.ram_bank0.mem[9] = 16'h1D02;
        dut.ram_bank0.mem[10] = 16'h13C2;
        dut.ram_bank0.mem[11] = 16'h1500;
        dut.ram_bank0.mem[12] = 16'h11C2;
        dut.ram_bank0.mem[13] = 16'hC300;
        dut.ram_bank0.mem[14] = 16'h0007;
        $display("Program loaded into SPRAM bank 0 (OLD arch)");
    end

    reg [31:0] cycle_count;
    reg [7:0]  gpio0_prev;
    reg [7:0]  toggle_count;
    reg        test_pass;

    initial begin
        $display("=============================================");
        $display("Blinky1 RAM Testbench - OLD ARCHITECTURE");
        $display("=============================================");

        reset_n = 0;
        gpio0_in = 8'h00;
        gpio1_in = 4'h0;
        cycle_count = 0;
        gpio0_prev = 8'h00;
        toggle_count = 0;
        test_pass = 0;

        repeat(10) @(posedge clk);
        reset_n = 1;
        $display("Reset released, starting execution from RAM...");

        while (cycle_count < TIMEOUT_CYCLES && toggle_count < 4) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            if (gpio0_out[0] != gpio0_prev[0] && gpio0_oe[0]) begin
                toggle_count = toggle_count + 1;
                $display("  Toggle %0d: GPIO0[0] = %b at cycle %0d",
                         toggle_count, gpio0_out[0], cycle_count);
            end
            gpio0_prev = gpio0_out;
        end

        $display("\n=============================================");
        if (toggle_count >= 4) begin
            $display("RESULT: PASS - %0d toggles detected", toggle_count);
            test_pass = 1;
        end else begin
            $display("RESULT: FAIL - Only %0d toggles (expected 4)", toggle_count);
            $display("  Timeout after %0d cycles", cycle_count);
        end
        $display("=============================================\n");

        $finish;
    end

    initial begin
        #(CLK_PERIOD * TIMEOUT_CYCLES * 2);
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
