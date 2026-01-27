// Minimal JZ test - verify conditional jump works
`timescale 1ns / 1ps

module jz_test_tb;

    parameter CLK_PERIOD = 83;

    reg         clk;
    reg         reset_n;
    wire        trap = 1'b0;
    wire        rst75 = 1'b0;
    wire        rst65 = 1'b0;
    wire        rst55 = 1'b0;
    wire        sid = 1'b0;
    wire        sod;
    wire        spi_sck, spi_cs_n, spi_mosi;
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

    i8085sg dut (
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

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Simple test: XRA A (sets Z=1), JZ PASS (should take branch), HLT at PASS
    // If JZ works, we should hit HLT at address 0x06
    // If JZ fails, we fall through to HLT at 0x05
    //
    // 0x0000: AF          XRA A       ; A=0, Z=1
    // 0x0001: CA 06 00    JZ 0x0006   ; should jump to 0x0006
    // 0x0004: 3E FF       MVI A, 0xFF ; should be skipped
    // 0x0006: 76          HLT         ; target
    //
    // If A=0xFF at end, JZ didn't work. If A=0x00, JZ worked.

    initial begin
        #1;
        // 0x0000-0x0001: AF CA (XRA A, JZ)
        dut.ram_bank0.mem[0] = 16'hCAAF;
        // 0x0002-0x0003: 06 00 (JZ target lo, hi)
        dut.ram_bank0.mem[1] = 16'h0006;
        // 0x0004-0x0005: 3E FF (MVI A, 0xFF)
        dut.ram_bank0.mem[2] = 16'hFF3E;
        // 0x0006-0x0007: 76 xx (HLT)
        dut.ram_bank0.mem[3] = 16'h0076;

        $display("=== JZ Conditional Jump Test ===");
    end

    integer cycle;
    reg halted_seen;

    initial begin
        reset_n = 0;
        gpio0_in = 8'h00;
        gpio1_in = 4'h0;
        cycle = 0;
        halted_seen = 0;

        repeat(10) @(posedge clk);
        reset_n = 1;
        $display("Reset released");

        while (cycle < 100 && !halted_seen) begin
            @(posedge clk);
            cycle = cycle + 1;

            $display("cycle %3d: PC=0x%04x fsm=%2d op=0x%02x A=0x%02x Z=%b halted=%b",
                     cycle, dut.cpu_pc, dut.fsm_state, dut.fetched_op,
                     dut.cpu.reg_a, dut.cpu.flag_z, dut.cpu.halted);

            if (dut.fsm_state == 14) begin
                halted_seen = 1;
                $display(">>> CPU halted at cycle %0d, PC=0x%04x", cycle, dut.cpu_pc);
            end
        end

        if (halted_seen) begin
            if (dut.cpu.reg_a == 8'h00) begin
                $display("\nRESULT: PASS - JZ branch taken correctly (A=0x00)");
            end else begin
                $display("\nRESULT: FAIL - JZ branch NOT taken (A=0x%02x)", dut.cpu.reg_a);
            end
        end else begin
            $display("\nRESULT: FAIL - CPU did not halt within 100 cycles");
        end

        $finish;
    end

endmodule
