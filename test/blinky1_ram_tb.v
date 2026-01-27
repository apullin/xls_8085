// Blinky1 RAM Testbench - Full CPU test running from SPRAM
// Simpler than ROM test - no SPI flash needed
// Program loaded directly into RAM bank 0 starting at 0x0000
//
// Test criteria: GPIO0[0] toggles 4 times within timeout

`timescale 1ns / 1ps

module blinky1_ram_tb;

    // =========================================================================
    // Parameters
    // =========================================================================

    parameter CLK_PERIOD = 83;  // ~12 MHz
    parameter TIMEOUT_CYCLES = 100000;  // Shorter timeout for RAM test

    // =========================================================================
    // DUT Signals
    // =========================================================================

    reg         clk;
    reg         reset_n;

    // Unused inputs
    wire        trap = 1'b0;
    wire        rst75 = 1'b0;
    wire        rst65 = 1'b0;
    wire        rst55 = 1'b0;
    wire        sid = 1'b0;
    wire        sod;

    // SPI Flash (inactive)
    wire        spi_sck;
    wire        spi_cs_n;
    wire        spi_mosi;
    wire        spi_miso = 1'b1;  // Pullup

    // Timer/PWM
    wire        timer0_irq;
    wire        pwm0, pwm1, pwm2, pwm3;

    // GPIO
    wire [7:0]  gpio0_out, gpio0_oe;
    reg  [7:0]  gpio0_in;
    wire [3:0]  gpio1_out, gpio1_oe;
    reg  [3:0]  gpio1_in;

    // Userial (unused)
    wire        userial0_rx_miso = 1'b1;
    wire        userial0_tx_mosi, userial0_sck, userial0_cs_n;
    wire        userial1_rx_miso = 1'b1;
    wire        userial1_tx_mosi, userial1_sck, userial1_cs_n;

    // I2C (unused)
    wire        i2c0_sda_in = 1'b1;
    wire        i2c0_sda_out, i2c0_sda_oe;
    wire        i2c0_scl_in = 1'b1;
    wire        i2c0_scl_out, i2c0_scl_oe;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================

    i8085sg dut (
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

    // =========================================================================
    // Clock Generation
    // =========================================================================

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // =========================================================================
    // Program Loading into SPRAM Bank 0
    // =========================================================================

    // Simplified blinky without CALL - direct inline loop
    // This avoids stack issues and simplifies debugging
    //
    // Address  Bytes       Instruction
    // 0x0000   21 12 3F    LXI H, 0x3F12 (GPIO0_DIR)
    // 0x0003   36 01       MVI M, 0x01
    // 0x0005   06 00       MVI B, 0x00
    // 0x0007   78          MOV A, B       <- MAIN_LOOP
    // 0x0008   EE 01       XRI 0x01
    // 0x000A   47          MOV B, A
    // 0x000B   21 10 3F    LXI H, 0x3F10 (GPIO0_DATA_OUT)
    // 0x000E   77          MOV M, A
    // 0x000F   16 02       MVI D, 0x02    <- inline delay
    // 0x0011   1E 04       MVI E, 0x04    <- DELAY_OUTER
    // 0x0013   1D          DCR E          <- DELAY_INNER
    // 0x0014   C2 13 00    JNZ DELAY_INNER
    // 0x0017   15          DCR D
    // 0x0018   C2 11 00    JNZ DELAY_OUTER
    // 0x001B   C3 07 00    JMP MAIN_LOOP

    // SPRAM is 16-bit wide, addressed by word (14-bit address)
    // Byte address 0x00, 0x01 -> word address 0x0000
    // We use hierarchical access: dut.ram_bank0.mem[word_addr]

    initial begin
        // Wait for simulation to start
        #1;

        // Load program as 16-bit words (little-endian pairs)
        // Word 0 (addr 0x0000-0x0001): 21 12 -> 0x1221
        dut.ram_bank0.mem[0] = 16'h1221;
        // Word 1 (addr 0x0002-0x0003): 3F 36 -> 0x363F
        dut.ram_bank0.mem[1] = 16'h363F;
        // Word 2 (addr 0x0004-0x0005): 01 06 -> 0x0601
        dut.ram_bank0.mem[2] = 16'h0601;
        // Word 3 (addr 0x0006-0x0007): 00 78 -> 0x7800
        dut.ram_bank0.mem[3] = 16'h7800;
        // Word 4 (addr 0x0008-0x0009): EE 01 -> 0x01EE
        dut.ram_bank0.mem[4] = 16'h01EE;
        // Word 5 (addr 0x000A-0x000B): 47 21 -> 0x2147
        dut.ram_bank0.mem[5] = 16'h2147;
        // Word 6 (addr 0x000C-0x000D): 10 3F -> 0x3F10
        dut.ram_bank0.mem[6] = 16'h3F10;
        // Word 7 (addr 0x000E-0x000F): 77 16 -> 0x1677
        dut.ram_bank0.mem[7] = 16'h1677;
        // Word 8 (addr 0x0010-0x0011): 01 1E -> 0x1E01 (D=1 outer loop)
        dut.ram_bank0.mem[8] = 16'h1E01;
        // Word 9 (addr 0x0012-0x0013): 02 1D -> 0x1D02 (E=2 inner loop)
        dut.ram_bank0.mem[9] = 16'h1D02;
        // Word 10 (addr 0x0014-0x0015): C2 13 -> 0x13C2
        dut.ram_bank0.mem[10] = 16'h13C2;
        // Word 11 (addr 0x0016-0x0017): 00 15 -> 0x1500
        dut.ram_bank0.mem[11] = 16'h1500;
        // Word 12 (addr 0x0018-0x0019): C2 11 -> 0x11C2
        dut.ram_bank0.mem[12] = 16'h11C2;
        // Word 13 (addr 0x001A-0x001B): 00 C3 -> 0xC300
        dut.ram_bank0.mem[13] = 16'hC300;
        // Word 14 (addr 0x001C-0x001D): 07 00 -> 0x0007
        dut.ram_bank0.mem[14] = 16'h0007;

        $display("Program loaded into SPRAM bank 0");
    end

    // =========================================================================
    // Test Logic
    // =========================================================================

    reg [31:0] cycle_count;
    reg [7:0]  gpio0_prev;
    reg [7:0]  toggle_count;
    reg        test_pass;

    initial begin
        $display("=============================================");
        $display("Blinky1 RAM Testbench - Busywait GPIO Toggle");
        $display("=============================================");

        // Initialize
        reset_n = 0;
        gpio0_in = 8'h00;
        gpio1_in = 4'h0;
        cycle_count = 0;
        gpio0_prev = 8'h00;
        toggle_count = 0;
        test_pass = 0;

        // Release reset
        repeat(10) @(posedge clk);
        reset_n = 1;
        $display("Reset released, starting execution from RAM...");
        $display("  SPRAM word[0] = 0x%04x (should be 0x1221)", dut.ram_bank0.mem[0]);
        $display("  SPRAM word[1] = 0x%04x (should be 0x363F)", dut.ram_bank0.mem[1]);

        // Run until 4 toggles or timeout
        while (cycle_count < TIMEOUT_CYCLES && toggle_count < 4) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            // Debug output for first 200 cycles, then every 1000
            if ((cycle_count <= 200 && cycle_count % 5 == 0) || (cycle_count % 1000 == 0)) begin
                $display("  cycle %0d: PC=0x%04x fsm=%0d op=0x%02x A=0x%02x B=0x%02x gpio_out=0x%02x gpio_oe=0x%02x",
                         cycle_count, dut.cpu_pc, dut.fsm_state, dut.fetched_op,
                         dut.cpu.reg_a, dut.cpu.reg_b, gpio0_out, gpio0_oe);
            end

            // Detect GPIO0[0] toggle
            if (gpio0_out[0] != gpio0_prev[0] && gpio0_oe[0]) begin
                toggle_count = toggle_count + 1;
                $display("  Toggle %0d: GPIO0[0] = %b at cycle %0d",
                         toggle_count, gpio0_out[0], cycle_count);
            end
            gpio0_prev = gpio0_out;
        end

        // Results
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

    // Watchdog timer
    initial begin
        #(CLK_PERIOD * TIMEOUT_CYCLES * 2);
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
