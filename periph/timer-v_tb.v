// Timer16 Testbench
`timescale 1ns/1ps

module timer16_tb;
    reg        clk;
    reg        reset_n;
    reg  [3:0] addr;
    reg  [7:0] data_in;
    wire [7:0] data_out;
    reg        rd, wr;
    reg        tick;
    wire       irq;

    // Register addresses
    localparam REG_CNT_LO    = 4'h0;
    localparam REG_CNT_HI    = 4'h1;
    localparam REG_RELOAD_LO = 4'h2;
    localparam REG_RELOAD_HI = 4'h3;
    localparam REG_PRESCALE  = 4'h4;
    localparam REG_CTRL      = 4'h5;
    localparam REG_IRQ_EN    = 4'h6;
    localparam REG_STATUS    = 4'h7;
    localparam REG_CMP0_LO   = 4'h8;
    localparam REG_CMP0_HI   = 4'h9;

    // CTRL bits
    localparam CTRL_ENABLE      = 8'h01;
    localparam CTRL_AUTO_RELOAD = 8'h02;
    localparam CTRL_COUNT_DOWN  = 8'h04;

    // Status/IRQ bits
    localparam FLAG_CMP0 = 8'h01;
    localparam FLAG_OVF  = 8'h10;

    timer16_wrapper dut (
        .clk(clk), .reset_n(reset_n),
        .addr(addr), .data_in(data_in), .data_out(data_out),
        .rd(rd), .wr(wr),
        .tick(tick), .irq(irq)
    );

    // Clock generation (20MHz = 50ns period)
    initial clk = 0;
    always #25 clk = ~clk;

    // Write helper task
    task write_reg(input [3:0] a, input [7:0] d);
        begin
            @(posedge clk);
            addr = a; data_in = d; wr = 1;
            @(posedge clk);
            wr = 0;
        end
    endtask

    // Read helper task
    task read_reg(input [3:0] a, output [7:0] d);
        begin
            @(posedge clk);
            addr = a; rd = 1;
            @(posedge clk);
            d = data_out;
            rd = 0;
        end
    endtask

    // Generate N ticks
    task do_ticks(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(posedge clk);
                tick = 1;
                @(posedge clk);
                tick = 0;
            end
        end
    endtask

    reg [7:0] tmp;
    reg [15:0] cnt;
    integer errors;

    initial begin
        $dumpfile("timer16_tb.vcd");
        $dumpvars(0, timer16_tb);

        errors = 0;
        reset_n = 0; rd = 0; wr = 0; addr = 0; data_in = 0; tick = 0;

        repeat(5) @(posedge clk);
        reset_n = 1;
        repeat(2) @(posedge clk);

        $display("=== Timer16 Testbench ===");

        // Test 1: Basic count up
        $display("\nTest 1: Count up (no prescale)");
        write_reg(REG_CNT_LO, 8'h00);
        write_reg(REG_CNT_HI, 8'h00);
        write_reg(REG_PRESCALE, 8'h00);  // No prescale
        write_reg(REG_CTRL, CTRL_ENABLE);

        do_ticks(5);

        read_reg(REG_CNT_LO, tmp); cnt[7:0] = tmp;
        read_reg(REG_CNT_HI, tmp); cnt[15:8] = tmp;

        if (cnt !== 16'h0005) begin
            $display("  FAIL: counter=%h, expected 0005", cnt);
            errors = errors + 1;
        end else $display("  PASS: counter = %h", cnt);

        // Disable for next test
        write_reg(REG_CTRL, 8'h00);

        // Test 2: Prescaler
        $display("\nTest 2: Prescaler (div by 3)");
        write_reg(REG_CNT_LO, 8'h00);
        write_reg(REG_CNT_HI, 8'h00);
        write_reg(REG_PRESCALE, 8'h02);  // Divide by 3 (0,1,2)
        write_reg(REG_CTRL, CTRL_ENABLE);

        do_ticks(9);  // Should count 3 times (9/3)

        read_reg(REG_CNT_LO, tmp); cnt[7:0] = tmp;
        read_reg(REG_CNT_HI, tmp); cnt[15:8] = tmp;

        if (cnt !== 16'h0003) begin
            $display("  FAIL: counter=%h, expected 0003", cnt);
            errors = errors + 1;
        end else $display("  PASS: counter = %h (with prescale)", cnt);

        write_reg(REG_CTRL, 8'h00);

        // Test 3: Compare match IRQ
        $display("\nTest 3: Compare match IRQ");
        write_reg(REG_CNT_LO, 8'h00);
        write_reg(REG_CNT_HI, 8'h00);
        write_reg(REG_PRESCALE, 8'h00);
        write_reg(REG_CMP0_LO, 8'h03);  // Match at 3
        write_reg(REG_CMP0_HI, 8'h00);
        write_reg(REG_IRQ_EN, FLAG_CMP0);
        write_reg(REG_STATUS, 8'hFF);   // Clear any pending
        write_reg(REG_CTRL, CTRL_ENABLE);

        if (irq !== 1'b0) begin
            $display("  FAIL: IRQ asserted before match");
            errors = errors + 1;
        end

        do_ticks(4);  // Counter reaches 3, then compare fires on next tick

        @(posedge clk);
        if (irq !== 1'b1) begin
            $display("  FAIL: IRQ not asserted on compare match");
            errors = errors + 1;
        end else $display("  PASS: IRQ asserted on compare match");

        // Clear IRQ
        write_reg(REG_STATUS, FLAG_CMP0);
        @(posedge clk);
        if (irq !== 1'b0) begin
            $display("  FAIL: IRQ not cleared");
            errors = errors + 1;
        end else $display("  PASS: IRQ cleared with W1C");

        write_reg(REG_CTRL, 8'h00);

        // Test 4: Overflow and auto-reload
        $display("\nTest 4: Overflow and auto-reload");
        write_reg(REG_CNT_LO, 8'hFD);   // Start at 0xFFFD
        write_reg(REG_CNT_HI, 8'hFF);
        write_reg(REG_RELOAD_LO, 8'h10);  // Reload to 0x0010
        write_reg(REG_RELOAD_HI, 8'h00);
        write_reg(REG_PRESCALE, 8'h00);
        write_reg(REG_IRQ_EN, FLAG_OVF);
        write_reg(REG_STATUS, 8'hFF);
        write_reg(REG_CTRL, CTRL_ENABLE | CTRL_AUTO_RELOAD);

        do_ticks(3);  // FFFD -> FFFE -> FFFF -> overflow -> reload to 0010

        @(posedge clk);
        if (irq !== 1'b1) begin
            $display("  FAIL: overflow IRQ not asserted");
            errors = errors + 1;
        end else $display("  PASS: overflow IRQ asserted");

        read_reg(REG_CNT_LO, tmp); cnt[7:0] = tmp;
        read_reg(REG_CNT_HI, tmp); cnt[15:8] = tmp;

        if (cnt !== 16'h0010) begin
            $display("  FAIL: counter=%h after reload, expected 0010", cnt);
            errors = errors + 1;
        end else $display("  PASS: auto-reload to %h", cnt);

        write_reg(REG_CTRL, 8'h00);

        // Test 5: Count down
        $display("\nTest 5: Count down");
        write_reg(REG_CNT_LO, 8'h05);
        write_reg(REG_CNT_HI, 8'h00);
        write_reg(REG_PRESCALE, 8'h00);
        write_reg(REG_CTRL, CTRL_ENABLE | CTRL_COUNT_DOWN);

        do_ticks(3);

        read_reg(REG_CNT_LO, tmp); cnt[7:0] = tmp;
        read_reg(REG_CNT_HI, tmp); cnt[15:8] = tmp;

        if (cnt !== 16'h0002) begin
            $display("  FAIL: counter=%h, expected 0002", cnt);
            errors = errors + 1;
        end else $display("  PASS: count down: %h", cnt);

        write_reg(REG_CTRL, 8'h00);

        // Summary
        $display("\n=== Test Summary ===");
        if (errors == 0)
            $display("All tests PASSED");
        else
            $display("%d tests FAILED", errors);

        $finish;
    end
endmodule
