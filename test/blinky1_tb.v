// Blinky1 Testbench - Full CPU test with busywait GPIO toggle
// Tests i8085sg running the blinky1_busywait program
//
// Test criteria: GPIO0[0] toggles 4 times within timeout

`timescale 1ns / 1ps

module blinky1_tb;

    // =========================================================================
    // Parameters
    // =========================================================================

    parameter CLK_PERIOD = 83;  // ~12 MHz
    parameter TIMEOUT_CYCLES = 500000;  // Simulation timeout

    // Peripheral addresses
    localparam GPIO0_DATA_OUT = 16'h7F10;
    localparam GPIO0_DIR      = 16'h7F12;

    // =========================================================================
    // DUT Signals
    // =========================================================================

    reg         clk;
    reg         reset_n;

    // Unused interrupt inputs
    wire        trap = 1'b0;
    wire        rst75 = 1'b0;
    wire        rst65 = 1'b0;
    wire        rst55 = 1'b0;
    wire        sid = 1'b0;
    wire        sod;

    // SPI Flash
    wire        spi_sck;
    wire        spi_cs_n;
    wire        spi_mosi;
    wire        spi_miso;

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
    // SPI Flash Model
    // =========================================================================

    spi_flash_sim #(.MEM_SIZE(32768)) flash (
        .spi_sck(spi_sck),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso)
    );

    // =========================================================================
    // Clock Generation
    // =========================================================================

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // =========================================================================
    // Program Loading
    // =========================================================================

    // Hand-assembled blinky1_busywait.asm
    // With DELAY_COUNT = 0x02 for fast simulation
    //
    // Address  Bytes       Instruction
    // 0x8000   21 12 7F    LXI H, 0x7F12 (GPIO0_DIR)
    // 0x8003   36 01       MVI M, 0x01
    // 0x8005   06 00       MVI B, 0x00
    // 0x8007   78          MOV A, B       <- MAIN_LOOP
    // 0x8008   EE 01       XRI 0x01
    // 0x800A   47          MOV B, A
    // 0x800B   21 10 7F    LXI H, 0x7F10 (GPIO0_DATA_OUT)
    // 0x800E   77          MOV M, A
    // 0x800F   CD 15 80    CALL DELAY
    // 0x8012   C3 07 80    JMP MAIN_LOOP
    // 0x8015   16 02       MVI D, 0x02    <- DELAY (reduced for sim)
    // 0x8017   1E 04       MVI E, 0x04    <- DELAY_OUTER (reduced)
    // 0x8019   1D          DCR E          <- DELAY_INNER
    // 0x801A   C2 19 80    JNZ DELAY_INNER
    // 0x801D   15          DCR D
    // 0x801E   C2 17 80    JNZ DELAY_OUTER
    // 0x8021   C9          RET

    initial begin
        // Wait for flash model to initialize
        #1;

        // Load program at offset 0 (maps to 0x8000 in CPU)
        flash.load_byte(24'h000000, 8'h21);  // LXI H, 0x7F12
        flash.load_byte(24'h000001, 8'h12);
        flash.load_byte(24'h000002, 8'h7F);
        flash.load_byte(24'h000003, 8'h36);  // MVI M, 0x01
        flash.load_byte(24'h000004, 8'h01);
        flash.load_byte(24'h000005, 8'h06);  // MVI B, 0x00
        flash.load_byte(24'h000006, 8'h00);
        flash.load_byte(24'h000007, 8'h78);  // MOV A, B
        flash.load_byte(24'h000008, 8'hEE);  // XRI 0x01
        flash.load_byte(24'h000009, 8'h01);
        flash.load_byte(24'h00000A, 8'h47);  // MOV B, A
        flash.load_byte(24'h00000B, 8'h21);  // LXI H, 0x7F10
        flash.load_byte(24'h00000C, 8'h10);
        flash.load_byte(24'h00000D, 8'h7F);
        flash.load_byte(24'h00000E, 8'h77);  // MOV M, A
        flash.load_byte(24'h00000F, 8'hCD);  // CALL DELAY
        flash.load_byte(24'h000010, 8'h15);
        flash.load_byte(24'h000011, 8'h80);
        flash.load_byte(24'h000012, 8'hC3);  // JMP MAIN_LOOP
        flash.load_byte(24'h000013, 8'h07);
        flash.load_byte(24'h000014, 8'h80);
        flash.load_byte(24'h000015, 8'h16);  // MVI D, 0x02
        flash.load_byte(24'h000016, 8'h02);
        flash.load_byte(24'h000017, 8'h1E);  // MVI E, 0x04
        flash.load_byte(24'h000018, 8'h04);
        flash.load_byte(24'h000019, 8'h1D);  // DCR E
        flash.load_byte(24'h00001A, 8'hC2);  // JNZ DELAY_INNER
        flash.load_byte(24'h00001B, 8'h19);
        flash.load_byte(24'h00001C, 8'h80);
        flash.load_byte(24'h00001D, 8'h15);  // DCR D
        flash.load_byte(24'h00001E, 8'hC2);  // JNZ DELAY_OUTER
        flash.load_byte(24'h00001F, 8'h17);
        flash.load_byte(24'h000020, 8'h80);
        flash.load_byte(24'h000021, 8'hC9);  // RET
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
        $display("Blinky1 Testbench - Busywait GPIO Toggle");
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
        $display("Reset released, starting execution...");

        // Run until 4 toggles or timeout
        while (cycle_count < TIMEOUT_CYCLES && toggle_count < 4) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

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
