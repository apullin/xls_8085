// imath_lite Testbench
// Tests 8x8 and 16x16 multiply with SB_MAC16 DSP simulation models
`timescale 1ns/1ps

module imath_lite_tb;
    reg        clk;
    reg        reset_n;
    reg  [3:0] addr;
    reg  [7:0] data_in;
    wire [7:0] data_out;
    reg        rd, wr;

    // Register addresses
    localparam REG_A_LO   = 4'h0;
    localparam REG_A_HI   = 4'h1;
    localparam REG_B_LO   = 4'h4;
    localparam REG_B_HI   = 4'h5;
    localparam REG_R_0    = 4'h8;
    localparam REG_R_1    = 4'h9;
    localparam REG_R_2    = 4'hA;
    localparam REG_R_3    = 4'hB;
    localparam REG_CTRL   = 4'hF;

    // CTRL bits
    localparam CTRL_MODE_16  = 8'h01;  // 0=8x8, 1=16x16
    localparam CTRL_SIGNED   = 8'h04;  // 0=unsigned, 1=signed

    imath_lite_wrapper dut (
        .clk(clk), .reset_n(reset_n),
        .addr(addr), .data_in(data_in), .data_out(data_out),
        .rd(rd), .wr(wr)
    );

    // Clock generation (20MHz = 50ns period)
    initial clk = 0;
    always #25 clk = ~clk;

    // Write helper
    task write_reg(input [3:0] a, input [7:0] d);
        begin
            @(posedge clk);
            addr = a; data_in = d; wr = 1;
            @(posedge clk);
            wr = 0;
        end
    endtask

    // Read helper
    task read_reg(input [3:0] a, output [7:0] d);
        begin
            @(posedge clk);
            addr = a; rd = 1;
            @(posedge clk);
            d = data_out;
            rd = 0;
        end
    endtask

    // Write 16-bit value
    task write16(input [3:0] base, input [15:0] val);
        begin
            write_reg(base, val[7:0]);
            write_reg(base + 1, val[15:8]);
        end
    endtask

    // Read 32-bit result
    task read32(output [31:0] val);
        reg [7:0] b0, b1, b2, b3;
        begin
            read_reg(REG_R_0, b0);
            read_reg(REG_R_1, b1);
            read_reg(REG_R_2, b2);
            read_reg(REG_R_3, b3);
            val = {b3, b2, b1, b0};
        end
    endtask

    reg [31:0] result;
    reg [31:0] expected;
    integer errors;

    initial begin
        $dumpfile("imath_lite_tb.vcd");
        $dumpvars(0, imath_lite_tb);

        errors = 0;
        reset_n = 0; rd = 0; wr = 0; addr = 0; data_in = 0;

        repeat(5) @(posedge clk);
        reset_n = 1;
        repeat(2) @(posedge clk);

        $display("=== imath_lite Testbench ===");

        // Test 1: 8x8 unsigned: 12 * 13 = 156
        $display("\nTest 1: 8x8 unsigned (12 * 13 = 156)");
        write_reg(REG_A_LO, 8'd12);
        write_reg(REG_B_LO, 8'd13);
        repeat(5) @(posedge clk);  // Let inputs settle
        $display("  Before CTRL write: op_a=%d, op_b=%d", dut.op_a, dut.op_b);
        write_reg(REG_CTRL, 8'h00);  // 8x8, unsigned - captures result
        repeat(3) @(posedge clk);  // Wait for DSP
        $display("  DSP unsigned out: 0x%h", dut.mac_u_out);
        $display("  Result reg: 0x%h", dut.result);

        read32(result);
        expected = 32'd156;
        if (result !== expected) begin
            $display("  FAIL: result=%d, expected=%d", result, expected);
            errors = errors + 1;
        end else $display("  PASS: %d * %d = %d", 12, 13, result);

        // Test 2: 8x8 unsigned: 255 * 255 = 65025
        $display("\nTest 2: 8x8 unsigned (255 * 255 = 65025)");
        write_reg(REG_A_LO, 8'd255);
        write_reg(REG_B_LO, 8'd255);
        write_reg(REG_CTRL, 8'h00);
        @(posedge clk);

        read32(result);
        expected = 32'd65025;
        if (result !== expected) begin
            $display("  FAIL: result=%d, expected=%d", result, expected);
            errors = errors + 1;
        end else $display("  PASS: 255 * 255 = %d", result);

        // Test 3: 8x8 signed: -10 * 5 = -50
        $display("\nTest 3: 8x8 signed (-10 * 5 = -50)");
        write_reg(REG_A_LO, 8'hF6);  // -10 in two's complement
        write_reg(REG_B_LO, 8'd5);
        write_reg(REG_CTRL, CTRL_SIGNED);
        @(posedge clk);

        read32(result);
        expected = 32'hFFFFFFCE;  // -50 sign-extended to 32 bits
        // Actually for 8x8 mode, result is only 16 bits
        expected = 32'h0000FFCE;  // -50 in 16-bit, zero-extended
        if (result[15:0] !== 16'hFFCE) begin
            $display("  FAIL: result=%h, expected lower 16=%h", result, 16'hFFCE);
            errors = errors + 1;
        end else $display("  PASS: -10 * 5 = %d (0x%h)", $signed(result[15:0]), result[15:0]);

        // Test 4: 16x16 unsigned: 1000 * 2000 = 2000000
        $display("\nTest 4: 16x16 unsigned (1000 * 2000 = 2000000)");
        write16(REG_A_LO, 16'd1000);
        write16(REG_B_LO, 16'd2000);
        write_reg(REG_CTRL, CTRL_MODE_16);
        @(posedge clk);

        read32(result);
        expected = 32'd2000000;
        if (result !== expected) begin
            $display("  FAIL: result=%d, expected=%d", result, expected);
            errors = errors + 1;
        end else $display("  PASS: 1000 * 2000 = %d", result);

        // Test 5: 16x16 unsigned: 65535 * 65535 = 4294836225
        $display("\nTest 5: 16x16 unsigned (65535 * 65535)");
        write16(REG_A_LO, 16'hFFFF);
        write16(REG_B_LO, 16'hFFFF);
        write_reg(REG_CTRL, CTRL_MODE_16);
        @(posedge clk);

        read32(result);
        expected = 32'hFFFE0001;  // 65535 * 65535 = 4294836225
        if (result !== expected) begin
            $display("  FAIL: result=0x%h, expected=0x%h", result, expected);
            errors = errors + 1;
        end else $display("  PASS: 65535 * 65535 = 0x%h (%d)", result, result);

        // Test 6: 16x16 signed: -1000 * 500 = -500000
        $display("\nTest 6: 16x16 signed (-1000 * 500 = -500000)");
        write16(REG_A_LO, -16'd1000);  // 0xFC18
        write16(REG_B_LO, 16'd500);
        write_reg(REG_CTRL, CTRL_MODE_16 | CTRL_SIGNED);
        @(posedge clk);

        read32(result);
        expected = -32'd500000;  // 0xFFF85EE0
        if (result !== expected) begin
            $display("  FAIL: result=0x%h (%d), expected=0x%h (%d)",
                     result, $signed(result), expected, $signed(expected));
            errors = errors + 1;
        end else $display("  PASS: -1000 * 500 = %d", $signed(result));

        // Summary
        $display("\n=== Test Summary ===");
        if (errors == 0)
            $display("All tests PASSED");
        else
            $display("%d tests FAILED", errors);

        $finish;
    end
endmodule
