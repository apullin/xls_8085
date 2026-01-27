// Blinky3 RAM Testbench - Timer compare match polling
// Tests timer CMP0 compare match and overflow flags
// Creates 50% duty cycle: CMP0 turns LED on, OVF turns LED off
//
// Test criteria: GPIO0[0] toggles 4 times within timeout

`timescale 1ns / 1ps

module blinky3_ram_tb;

    // =========================================================================
    // Parameters
    // =========================================================================

    parameter CLK_PERIOD = 83;  // ~12 MHz
    parameter TIMEOUT_CYCLES = 100000;

    // =========================================================================
    // DUT Signals
    // =========================================================================

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

    // Timer compare match blinky - uses CMP0 and OVF
    // CMP0 match turns LED on, OVF turns LED off (50% duty cycle)
    //
    // Timer registers at 0x3F00:
    //   RELOAD_LO=0x3F02, RELOAD_HI=0x3F03
    //   CTRL=0x3F05, STATUS=0x3F07
    //   CMP0_LO=0x3F08, CMP0_HI=0x3F09
    //
    // GPIO at 0x3F10:
    //   DATA_OUT=0x3F10, DIR=0x3F12
    //
    // STATUS bits: CMP0=0x01, OVF=0x10
    // CTRL bits: EN=0x01, AR=0x02, DN=0x04 (count-down)
    //
    // Program:
    // 0x0000: LXI H, 0x3F12    ; GPIO0_DIR
    // 0x0003: MVI M, 0x01      ; bit 0 output
    // 0x0005: LXI H, 0x3F08    ; TIMER0_CMP0_LO
    // 0x0008: MVI M, 0x08      ; CMP0 = 0x0008 (halfway to 0x10)
    // 0x000A: INX H            ; CMP0_HI
    // 0x000B: MVI M, 0x00
    // 0x000D: LXI H, 0x3F02    ; TIMER0_RELOAD_LO
    // 0x0010: MVI M, 0x10      ; RELOAD = 0x0010
    // 0x0012: INX H            ; RELOAD_HI
    // 0x0013: MVI M, 0x00
    // 0x0015: LXI H, 0x3F05    ; TIMER0_CTRL
    // 0x0018: MVI M, 0x07      ; EN | AR | DN
    // MAIN_LOOP (0x001A):
    // 0x001A: LXI H, 0x3F07    ; TIMER0_STATUS
    // POLL_CMP0 (0x001D):
    // 0x001D: MOV A, M         ; read status
    // 0x001E: ANI 0x01         ; mask CMP0
    // 0x0020: JZ POLL_CMP0     ; loop if not set
    // 0x0023: MVI M, 0x01      ; clear CMP0
    // 0x0025: LXI H, 0x3F10    ; GPIO0_DATA_OUT
    // 0x0028: MVI M, 0x01      ; LED ON
    // 0x002A: LXI H, 0x3F07    ; TIMER0_STATUS
    // POLL_OVF (0x002D):
    // 0x002D: MOV A, M         ; read status
    // 0x002E: ANI 0x10         ; mask OVF
    // 0x0030: JZ POLL_OVF      ; loop if not set
    // 0x0033: MVI M, 0x10      ; clear OVF
    // 0x0035: LXI H, 0x3F10    ; GPIO0_DATA_OUT
    // 0x0038: MVI M, 0x00      ; LED OFF
    // 0x003A: JMP MAIN_LOOP    ; repeat

    // Simplified program: just poll CMP0 flag and toggle
    // Based on blinky2 but using CMP0 instead of OVF
    //
    // 0x0000: LXI H, 0x3F12    ; GPIO0_DIR
    // 0x0003: MVI M, 0x01      ; bit 0 output
    // 0x0005: LXI H, 0x3F08    ; TIMER0_CMP0_LO
    // 0x0008: MVI M, 0x08      ; CMP0 = 8 (half of 16)
    // 0x000A: INX H
    // 0x000B: MVI M, 0x00
    // 0x000D: LXI H, 0x3F02    ; TIMER0_RELOAD_LO
    // 0x0010: MVI M, 0x10      ; reload = 16
    // 0x0012: INX H
    // 0x0013: MVI M, 0x00
    // 0x0015: LXI H, 0x3F05    ; TIMER0_CTRL
    // 0x0018: MVI M, 0x07      ; EN | AR | DN
    // 0x001A: MVI B, 0x00      ; B = toggle state
    // MAIN_LOOP (0x001C):
    // 0x001C: LXI H, 0x3F07    ; TIMER0_STATUS
    // POLL (0x001F):
    // 0x001F: MOV A, M         ; read status
    // 0x0020: ANI 0x01         ; mask CMP0
    // 0x0022: JZ POLL          ; loop if not set (JZ 0x001F)
    // 0x0025: MVI M, 0x01      ; clear CMP0
    // 0x0027: MOV A, B
    // 0x0028: XRI 0x01
    // 0x002A: MOV B, A
    // 0x002B: LXI H, 0x3F10    ; GPIO0_DATA_OUT
    // 0x002E: MOV M, A
    // 0x002F: JMP MAIN_LOOP    ; (JMP 0x001C)

    initial begin
        #1;
        // 0x0000-0x0001: 21 12
        dut.ram_bank0.mem[0]  = 16'h1221;
        // 0x0002-0x0003: 3F 36
        dut.ram_bank0.mem[1]  = 16'h363F;
        // 0x0004-0x0005: 01 21
        dut.ram_bank0.mem[2]  = 16'h2101;
        // 0x0006-0x0007: 08 3F (CMP0_LO addr)
        dut.ram_bank0.mem[3]  = 16'h3F08;
        // 0x0008-0x0009: 36 08
        dut.ram_bank0.mem[4]  = 16'h0836;
        // 0x000A-0x000B: 23 36
        dut.ram_bank0.mem[5]  = 16'h3623;
        // 0x000C-0x000D: 00 21
        dut.ram_bank0.mem[6]  = 16'h2100;
        // 0x000E-0x000F: 02 3F (RELOAD_LO addr)
        dut.ram_bank0.mem[7]  = 16'h3F02;
        // 0x0010-0x0011: 36 10
        dut.ram_bank0.mem[8]  = 16'h1036;
        // 0x0012-0x0013: 23 36
        dut.ram_bank0.mem[9]  = 16'h3623;
        // 0x0014-0x0015: 00 21
        dut.ram_bank0.mem[10] = 16'h2100;
        // 0x0016-0x0017: 05 3F (CTRL addr)
        dut.ram_bank0.mem[11] = 16'h3F05;
        // 0x0018-0x0019: 36 07 (MVI M, 0x07 = EN|AR|DN)
        dut.ram_bank0.mem[12] = 16'h0736;
        // 0x001A-0x001B: 06 00 (MVI B, 0)
        dut.ram_bank0.mem[13] = 16'h0006;
        // MAIN_LOOP at 0x001C:
        // 0x001C-0x001D: 21 07
        dut.ram_bank0.mem[14] = 16'h0721;
        // 0x001E-0x001F: 3F 7E (hi, MOV A,M)
        dut.ram_bank0.mem[15] = 16'h7E3F;
        // POLL at 0x001F (MOV A,M)
        // 0x0020-0x0021: E6 01 (ANI 0x01)
        dut.ram_bank0.mem[16] = 16'h01E6;
        // 0x0022-0x0023: CA 1F (JZ lo)
        dut.ram_bank0.mem[17] = 16'h1FCA;
        // 0x0024-0x0025: 00 36 (JZ hi, MVI M)
        dut.ram_bank0.mem[18] = 16'h3600;
        // 0x0026-0x0027: 01 78 (imm, MOV A,B)
        dut.ram_bank0.mem[19] = 16'h7801;
        // 0x0028-0x0029: EE 01 (XRI 0x01)
        dut.ram_bank0.mem[20] = 16'h01EE;
        // 0x002A-0x002B: 47 21 (MOV B,A, LXI H)
        dut.ram_bank0.mem[21] = 16'h2147;
        // 0x002C-0x002D: 10 3F (lo, hi)
        dut.ram_bank0.mem[22] = 16'h3F10;
        // 0x002E-0x002F: 77 C3 (MOV M,A, JMP)
        dut.ram_bank0.mem[23] = 16'hC377;
        // 0x0030-0x0031: 1C 00 (JMP target)
        dut.ram_bank0.mem[24] = 16'h001C;

        $display("Program loaded into SPRAM bank 0 (timer CMP0 blinky)");
    end

    // =========================================================================
    // Test Logic
    // =========================================================================

    reg [31:0] cycle_count;
    reg [7:0]  gpio0_prev;
    reg [7:0]  toggle_count;
    reg        pwm0_prev;
    reg [7:0]  pwm0_toggle_count;
    reg        test_pass;

    initial begin
        $display("============================================");
        $display("Blinky3 RAM Testbench - Timer Compare Match");
        $display("============================================");

        reset_n = 0;
        gpio0_in = 8'h00;
        gpio1_in = 4'h0;
        cycle_count = 0;
        gpio0_prev = 8'h00;
        toggle_count = 0;
        pwm0_prev = 0;
        pwm0_toggle_count = 0;
        test_pass = 0;

        repeat(10) @(posedge clk);
        reset_n = 1;
        $display("Reset released, starting execution from RAM...");

        while (cycle_count < TIMEOUT_CYCLES && toggle_count < 4) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            if ((cycle_count <= 200 && cycle_count % 5 == 0) || (cycle_count % 5000 == 0)) begin
                $display("  cycle %0d: PC=0x%04x op=0x%02x A=0x%02x Z=%b cnt=0x%04x status=0x%02x",
                         cycle_count, dut.cpu_pc, dut.fetched_op,
                         dut.cpu.reg_a, dut.cpu.flag_z,
                         dut.timer0.counter, dut.timer0.status);
            end

            if (gpio0_out[0] != gpio0_prev[0] && gpio0_oe[0]) begin
                toggle_count = toggle_count + 1;
                $display("  GPIO Toggle %0d: GPIO0[0] = %b at cycle %0d",
                         toggle_count, gpio0_out[0], cycle_count);
            end
            gpio0_prev = gpio0_out;

            // Monitor PWM0 output (hardware-driven by timer compare)
            if (pwm0 != pwm0_prev) begin
                pwm0_toggle_count = pwm0_toggle_count + 1;
                if (pwm0_toggle_count <= 8)
                    $display("  PWM0 edge %0d: pwm0 = %b at cycle %0d (cnt=0x%04x)",
                             pwm0_toggle_count, pwm0, cycle_count, dut.timer0.counter);
            end
            pwm0_prev = pwm0;
        end

        $display("\n============================================");
        $display("PWM0 hardware toggles: %0d", pwm0_toggle_count);
        $display("GPIO0 software toggles: %0d", toggle_count);
        if (toggle_count >= 4 && pwm0_toggle_count >= 8) begin
            $display("RESULT: PASS - GPIO and PWM both toggling");
            test_pass = 1;
        end else if (toggle_count >= 4) begin
            $display("RESULT: PARTIAL - GPIO ok but PWM0 not toggling (%0d)", pwm0_toggle_count);
            test_pass = 0;
        end else begin
            $display("RESULT: FAIL - Only %0d GPIO toggles (expected 4)", toggle_count);
            $display("  Timeout after %0d cycles", cycle_count);
        end
        $display("============================================\n");

        $finish;
    end

    initial begin
        #(CLK_PERIOD * TIMEOUT_CYCLES * 2);
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
