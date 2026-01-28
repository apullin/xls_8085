// Minimal RAM test - just a few NOPs and a HLT
// Used to debug fundamental CPU FSM issues with RAM execution

`timescale 1ns / 1ps

module minimal_ram_tb;

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

    // Program: MVI A, 0x55 then HLT
    // 0x00: 3E (MVI A)
    // 0x01: 55 (immediate value)
    // 0x02: 76 (HLT)
    initial begin
        #1;
        // Word 0: bytes 0x00-0x01 = {0x55, 0x3E} = 0x553E
        dut.mem.ram_bank0.mem[0] = 16'h553E;
        // Word 1: bytes 0x02-0x03 = {xx, 0x76} = 0x??76
        dut.mem.ram_bank0.mem[1] = 16'h0076;  // HLT at byte 0x02
    end

    integer cycle;
    reg halted_seen;

    initial begin
        $display("=== Minimal RAM Test: NOP NOP NOP HLT ===");
        reset_n = 0;
        gpio0_in = 8'h00;
        gpio1_in = 4'h0;
        cycle = 0;
        halted_seen = 0;

        repeat(10) @(posedge clk);
        reset_n = 1;
        $display("Reset released");

        // Run for 100 cycles, watching for HLT
        while (cycle < 100 && !halted_seen) begin
            @(posedge clk);
            cycle = cycle + 1;

            // Print every cycle for detailed trace
            $display("cycle %3d: PC=0x%04x fsm=%2d op=0x%02x bus_addr=0x%04x halted=%b exec=%b",
                     cycle, dut.cpu.r_pc, dut.cpu.fsm_state, dut.cpu.fetched_op,
                     dut.cpu.bus_addr, dut.cpu.halted, dut.cpu.execute_pulse);

            // Check for HLT state (fsm_state = S_HALTED = 14)
            if (dut.cpu.fsm_state == 15) begin  // S_HALTED = 15
                halted_seen = 1;
                $display(">>> CPU halted at cycle %0d", cycle);
            end
        end

        if (halted_seen) begin
            $display("\nRESULT: PASS - CPU executed NOP NOP NOP HLT correctly");
        end else begin
            $display("\nRESULT: FAIL - CPU did not halt within 100 cycles");
        end

        $finish;
    end

endmodule
