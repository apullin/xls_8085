// GPIO8 Testbench
`timescale 1ns/1ps

module gpio8_tb;
    reg        clk;
    reg        reset_n;
    reg  [3:0] addr;
    reg  [7:0] data_in;
    wire [7:0] data_out;
    reg        rd, wr;
    reg  [7:0] pins_in;
    wire [7:0] pins_out;
    wire [7:0] pins_oe;
    wire       irq;

    // Register addresses
    localparam REG_DATA_OUT   = 4'h0;
    localparam REG_DATA_IN    = 4'h1;
    localparam REG_DIR        = 4'h2;
    localparam REG_IRQ_EN     = 4'h3;
    localparam REG_IRQ_RISE   = 4'h4;
    localparam REG_IRQ_FALL   = 4'h5;
    localparam REG_IRQ_STATUS = 4'h6;
    localparam REG_OUT_MODE   = 4'h7;

    gpio8_wrapper dut (
        .clk(clk), .reset_n(reset_n),
        .addr(addr), .data_in(data_in), .data_out(data_out),
        .rd(rd), .wr(wr),
        .pins_in(pins_in), .pins_out(pins_out), .pins_oe(pins_oe),
        .irq(irq)
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

    reg [7:0] tmp;
    integer errors;

    initial begin
        $dumpfile("gpio8_tb.vcd");
        $dumpvars(0, gpio8_tb);

        errors = 0;
        reset_n = 0; rd = 0; wr = 0; addr = 0; data_in = 0; pins_in = 8'h00;

        repeat(5) @(posedge clk);
        reset_n = 1;
        repeat(2) @(posedge clk);

        $display("=== GPIO8 Testbench ===");

        // Test 1: Basic output
        $display("\nTest 1: Basic output");
        write_reg(REG_DIR, 8'hFF);       // All outputs
        write_reg(REG_DATA_OUT, 8'hA5);
        #1;
        if (pins_out !== 8'hA5) begin
            $display("  FAIL: pins_out=%h, expected A5", pins_out);
            errors = errors + 1;
        end else $display("  PASS: pins_out = %h", pins_out);

        if (pins_oe !== 8'hFF) begin
            $display("  FAIL: pins_oe=%h, expected FF", pins_oe);
            errors = errors + 1;
        end else $display("  PASS: pins_oe = %h", pins_oe);

        // Test 2: Input read
        $display("\nTest 2: Input read");
        write_reg(REG_DIR, 8'h00);       // All inputs
        pins_in = 8'h3C;
        @(posedge clk);
        read_reg(REG_DATA_IN, tmp);
        if (tmp !== 8'h3C) begin
            $display("  FAIL: read %h, expected 3C", tmp);
            errors = errors + 1;
        end else $display("  PASS: read %h", tmp);

        // Test 3: Mixed I/O
        $display("\nTest 3: Mixed I/O");
        write_reg(REG_DIR, 8'hF0);       // Upper nibble out, lower in
        write_reg(REG_DATA_OUT, 8'hA0);
        pins_in = 8'h05;
        @(posedge clk);
        read_reg(REG_DATA_IN, tmp);
        // Should read: upper from output (A0 & F0 = A0), lower from input (05 & 0F = 05)
        if (tmp !== 8'hA5) begin
            $display("  FAIL: read %h, expected A5", tmp);
            errors = errors + 1;
        end else $display("  PASS: read %h (mixed)", tmp);

        // Test 4: Rising edge IRQ
        $display("\nTest 4: Rising edge IRQ");
        write_reg(REG_DIR, 8'h00);       // All inputs
        write_reg(REG_IRQ_RISE, 8'h01);  // Enable rising edge on bit 0
        write_reg(REG_IRQ_EN, 8'h01);    // Enable IRQ on bit 0
        write_reg(REG_IRQ_STATUS, 8'hFF); // Clear any pending
        pins_in = 8'h00;
        @(posedge clk); @(posedge clk);

        if (irq !== 1'b0) begin
            $display("  FAIL: IRQ asserted before edge");
            errors = errors + 1;
        end

        pins_in = 8'h01;  // Rising edge on bit 0
        @(posedge clk); @(posedge clk);

        if (irq !== 1'b1) begin
            $display("  FAIL: IRQ not asserted after rising edge");
            errors = errors + 1;
        end else $display("  PASS: IRQ asserted on rising edge");

        // Test 5: IRQ clear (W1C)
        $display("\nTest 5: IRQ clear (W1C)");
        write_reg(REG_IRQ_STATUS, 8'h01);  // Clear bit 0
        @(posedge clk);
        if (irq !== 1'b0) begin
            $display("  FAIL: IRQ not cleared");
            errors = errors + 1;
        end else $display("  PASS: IRQ cleared with W1C");

        // Test 6: Falling edge IRQ
        $display("\nTest 6: Falling edge IRQ");
        write_reg(REG_IRQ_RISE, 8'h00);
        write_reg(REG_IRQ_FALL, 8'h02);  // Enable falling edge on bit 1
        write_reg(REG_IRQ_EN, 8'h02);
        pins_in = 8'h02;
        @(posedge clk); @(posedge clk);
        write_reg(REG_IRQ_STATUS, 8'hFF);

        pins_in = 8'h00;  // Falling edge on bit 1
        @(posedge clk); @(posedge clk);

        if (irq !== 1'b1) begin
            $display("  FAIL: IRQ not asserted after falling edge");
            errors = errors + 1;
        end else $display("  PASS: IRQ asserted on falling edge");

        // Test 7: Open-drain mode
        $display("\nTest 7: Open-drain mode");
        write_reg(REG_DIR, 8'hFF);       // All outputs
        write_reg(REG_OUT_MODE, 8'hFF);  // All open-drain
        write_reg(REG_DATA_OUT, 8'hA5);
        #1;
        // Open-drain: OE=0 when data=1 (high-Z), OE=1 when data=0 (drive low)
        // data=A5=10100101, so OE should be ~A5 = 01011010 = 5A
        if (pins_oe !== 8'h5A) begin
            $display("  FAIL: pins_oe=%h, expected 5A (open-drain)", pins_oe);
            errors = errors + 1;
        end else $display("  PASS: Open-drain OE correct (%h)", pins_oe);

        // Summary
        $display("\n=== Test Summary ===");
        if (errors == 0)
            $display("All tests PASSED");
        else
            $display("%d tests FAILED", errors);

        $finish;
    end
endmodule
