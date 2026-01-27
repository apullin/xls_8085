// Blinky2 RAM Testbench - Timer polling GPIO toggle
// Tests timer peripheral overflow flag by polling
// Simpler than interrupt-based test - verifies timer works
//
// Test criteria: GPIO0[0] toggles 4 times within timeout

`timescale 1ns / 1ps

module blinky2_ram_tb;

    // =========================================================================
    // Parameters
    // =========================================================================

    parameter CLK_PERIOD = 83;  // ~12 MHz
    parameter TIMEOUT_CYCLES = 50000;

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
    wire        spi_miso = 1'b1;

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

    // Timer polling blinky - poll overflow flag, toggle GPIO
    // Register addresses (i8085sg):
    //   Timer0: 0x3F00-0x3F0F (CTRL=0x3F05, STATUS=0x3F07, RELOAD_LO=0x3F02, RELOAD_HI=0x3F03)
    //   GPIO0:  0x3F10-0x3F1F (DATA_OUT=0x3F10, DIR=0x3F12)
    //
    // Timer STATUS bits: OVF=0x10
    // Timer CTRL bits: EN=0x01, AR=0x02, DN=0x04 (count-down)
    //
    // Program:
    // 0x0000: LXI H, 0x3F12    ; GPIO0_DIR
    // 0x0003: MVI M, 0x01      ; bit 0 output
    // 0x0005: LXI H, 0x3F02    ; TIMER0_RELOAD_LO
    // 0x0008: MVI M, 0x10      ; reload = 0x0010 (very fast)
    // 0x000A: INX H            ; RELOAD_HI
    // 0x000B: MVI M, 0x00
    // 0x000D: LXI H, 0x3F05    ; TIMER0_CTRL
    // 0x0010: MVI M, 0x07      ; EN | AR | DN (count-down mode)
    // 0x0012: MVI B, 0x00      ; B = toggle state
    // MAIN_LOOP:
    // 0x0014: LXI H, 0x3F07    ; TIMER0_STATUS
    // POLL:
    // 0x0017: MOV A, M         ; read status
    // 0x0018: ANI 0x10         ; mask OVF
    // 0x001A: JZ POLL          ; loop if not set
    // 0x001D: MVI M, 0x10      ; clear OVF (write 1 to clear)
    // 0x001F: MOV A, B         ; get toggle state
    // 0x0020: XRI 0x01         ; toggle
    // 0x0022: MOV B, A         ; save
    // 0x0023: LXI H, 0x3F10    ; GPIO0_DATA_OUT
    // 0x0026: MOV M, A         ; write GPIO
    // 0x0027: JMP MAIN_LOOP    ; repeat

    initial begin
        #1;
        // 0x0000-0x0001: 21 12 -> LXI H (21), lo(12)
        dut.ram_bank0.mem[0] = 16'h1221;
        // 0x0002-0x0003: 7F 36 -> hi(7F), MVI M (36)
        dut.ram_bank0.mem[1] = 16'h367F;
        // 0x0004-0x0005: 01 21 -> imm(01), LXI H (21)
        dut.ram_bank0.mem[2] = 16'h2101;
        // 0x0006-0x0007: 02 7F -> lo(02), hi(7F)
        dut.ram_bank0.mem[3] = 16'h7F02;
        // 0x0008-0x0009: 36 10 -> MVI M (36), imm(10)
        dut.ram_bank0.mem[4] = 16'h1036;
        // 0x000A-0x000B: 23 36 -> INX H (23), MVI M (36)
        dut.ram_bank0.mem[5] = 16'h3623;
        // 0x000C-0x000D: 00 21 -> imm(00), LXI H (21)
        dut.ram_bank0.mem[6] = 16'h2100;
        // 0x000E-0x000F: 05 7F -> lo(05), hi(7F)
        dut.ram_bank0.mem[7] = 16'h7F05;
        // 0x0010-0x0011: 36 03 -> MVI M (36), imm(03)
        dut.ram_bank0.mem[8] = 16'h0336;
        // 0x0012-0x0013: 06 00 -> MVI B (06), imm(00)
        dut.ram_bank0.mem[9] = 16'h0006;
        // MAIN_LOOP (0x0014):
        // 0x0014-0x0015: 21 07 -> LXI H (21), lo(07)
        dut.ram_bank0.mem[10] = 16'h0721;
        // 0x0016-0x0017: 7F 7E -> hi(7F), MOV A,M (7E)
        dut.ram_bank0.mem[11] = 16'h7E7F;
        // POLL (0x0017, but MOV A,M is single byte at 0x0017):
        // Wait - need to recount. Let me redo this more carefully.

        // Actually the program needs reorganization. Let me write it properly:
        // 0x0000: 21 12 3F    LXI H, 0x3F12
        // 0x0003: 36 01       MVI M, 0x01
        // 0x0005: 21 02 3F    LXI H, 0x3F02 (RELOAD_LO)
        // 0x0008: 36 10       MVI M, 0x10
        // 0x000A: 23          INX H
        // 0x000B: 36 00       MVI M, 0x00
        // 0x000D: 21 05 3F    LXI H, 0x3F05 (CTRL)
        // 0x0010: 36 07       MVI M, 0x07 (EN|AR|DN = count-down)
        // 0x0012: 06 00       MVI B, 0x00
        // MAIN_LOOP (0x0014):
        // 0x0014: 21 07 3F    LXI H, 0x3F07 (STATUS)
        // POLL (0x0017):
        // 0x0017: 7E          MOV A, M
        // 0x0018: E6 10       ANI 0x10
        // 0x001A: CA 17 00    JZ POLL (0x0017)
        // 0x001D: 36 10       MVI M, 0x10 (clear OVF)
        // 0x001F: 78          MOV A, B
        // 0x0020: EE 01       XRI 0x01
        // 0x0022: 47          MOV B, A
        // 0x0023: 21 10 3F    LXI H, 0x3F10
        // 0x0026: 77          MOV M, A
        // 0x0027: C3 14 00    JMP MAIN_LOOP

        // Rewriting with correct byte packing:
        dut.ram_bank0.mem[0]  = 16'h1221;  // 0x00-01: 21 12 (LXI H, lo=0x12)
        dut.ram_bank0.mem[1]  = 16'h363F;  // 0x02-03: 3F 36 (hi=0x3F, MVI M)
        dut.ram_bank0.mem[2]  = 16'h2101;  // 0x04-05: 01 21 (imm=0x01, LXI H)
        dut.ram_bank0.mem[3]  = 16'h3F02;  // 0x06-07: 02 3F (lo=0x02, hi=0x3F)
        dut.ram_bank0.mem[4]  = 16'h1036;  // 0x08-09: 36 10 (MVI M, imm=0x10)
        dut.ram_bank0.mem[5]  = 16'h3623;  // 0x0A-0B: 23 36 (INX H, MVI M)
        dut.ram_bank0.mem[6]  = 16'h2100;  // 0x0C-0D: 00 21 (imm=0x00, LXI H)
        dut.ram_bank0.mem[7]  = 16'h3F05;  // 0x0E-0F: 05 3F (lo=0x05, hi=0x3F)
        dut.ram_bank0.mem[8]  = 16'h0736;  // 0x10-11: 36 07 (MVI M, imm=0x07 = EN|AR|DN)
        dut.ram_bank0.mem[9]  = 16'h0006;  // 0x12-13: 06 00 (MVI B, imm=0x00)
        // MAIN_LOOP at 0x14:
        dut.ram_bank0.mem[10] = 16'h0721;  // 0x14-15: 21 07 (LXI H, lo=0x07)
        dut.ram_bank0.mem[11] = 16'h7E3F;  // 0x16-17: 3F 7E (hi=0x3F, MOV A,M)
        // POLL at 0x17, but MOV A,M is at 0x17
        // 0x18-19: E6 10 (ANI 0x10)
        dut.ram_bank0.mem[12] = 16'h10E6;  // 0x18-19: E6 10
        // 0x1A-1C: CA 17 00 (JZ 0x0017)
        dut.ram_bank0.mem[13] = 16'h17CA;  // 0x1A-1B: CA 17
        dut.ram_bank0.mem[14] = 16'h3600;  // 0x1C-1D: 00 36 (hi=0x00, MVI M)
        dut.ram_bank0.mem[15] = 16'h7810;  // 0x1E-1F: 10 78 (imm=0x10, MOV A,B)
        dut.ram_bank0.mem[16] = 16'h01EE;  // 0x20-21: EE 01 (XRI 0x01)
        dut.ram_bank0.mem[17] = 16'h2147;  // 0x22-23: 47 21 (MOV B,A, LXI H)
        dut.ram_bank0.mem[18] = 16'h3F10;  // 0x24-25: 10 3F (lo=0x10, hi=0x3F)
        dut.ram_bank0.mem[19] = 16'hC377;  // 0x26-27: 77 C3 (MOV M,A, JMP)
        dut.ram_bank0.mem[20] = 16'h0014;  // 0x28-29: 14 00 (lo=0x14, hi=0x00)

        $display("Program loaded into SPRAM bank 0 (timer polling blinky)");
    end

    // =========================================================================
    // Test Logic
    // =========================================================================

    reg [31:0] cycle_count;
    reg [7:0]  gpio0_prev;
    reg [7:0]  toggle_count;
    reg        test_pass;

    initial begin
        $display("============================================");
        $display("Blinky2 RAM Testbench - Timer Polling GPIO Toggle");
        $display("============================================");

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

        // Run until 4 toggles or timeout
        while (cycle_count < TIMEOUT_CYCLES && toggle_count < 4) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            // Debug output
            if ((cycle_count <= 200 && cycle_count % 5 == 0) || (cycle_count % 5000 == 0)) begin
                $display("  cycle %0d: PC=0x%04x op=0x%02x A=0x%02x cnt=0x%04x status=0x%02x",
                         cycle_count, dut.cpu_pc, dut.fetched_op,
                         dut.cpu.reg_a, dut.timer0.counter, dut.timer0.status);
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
        $display("\n============================================");
        if (toggle_count >= 4) begin
            $display("RESULT: PASS - %0d toggles detected", toggle_count);
            test_pass = 1;
        end else begin
            $display("RESULT: FAIL - Only %0d toggles (expected 4)", toggle_count);
            $display("  Timeout after %0d cycles", cycle_count);
        end
        $display("============================================\n");

        $finish;
    end

    // Watchdog timer
    initial begin
        #(CLK_PERIOD * TIMEOUT_CYCLES * 2);
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
