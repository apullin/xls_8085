// vmath Comprehensive Testbench
// Tests dot product with various lengths: 4, 8, 12, 16, 64, 256
// Tests signed values, bias, edge cases
`timescale 1ns/1ps

module vmath_tb;
    reg        clk;
    reg        reset_n;
    reg  [3:0] addr;
    reg  [7:0] data_in;
    wire [7:0] data_out;
    reg        rd, wr;

    // SPRAM interface
    wire [13:0] mem_addr;
    wire [1:0]  mem_bank;
    wire [15:0] mem_rdata;
    wire [15:0] mem_wdata;
    wire [3:0]  mem_we;
    wire        bus_request;
    wire        busy;

    // Register addresses
    localparam REG_A_PTR_LO  = 4'h0;
    localparam REG_A_PTR_MI  = 4'h1;
    localparam REG_A_PTR_HI  = 4'h2;
    localparam REG_B_PTR_LO  = 4'h3;
    localparam REG_B_PTR_MI  = 4'h4;
    localparam REG_B_PTR_HI  = 4'h5;
    localparam REG_LEN_LO    = 4'h6;
    localparam REG_LEN_HI    = 4'h7;
    localparam REG_ACC_0     = 4'h8;
    localparam REG_ACC_1     = 4'h9;
    localparam REG_ACC_2     = 4'hA;
    localparam REG_ACC_3     = 4'hB;
    localparam REG_BIAS_0    = 4'hC;
    localparam REG_BIAS_1    = 4'hD;
    localparam REG_BIAS_2    = 4'hE;
    localparam REG_CTRL      = 4'hF;

    // CTRL bits
    localparam CTRL_START    = 8'h01;

    // DUT
    vmath_wrapper dut (
        .clk(clk), .reset_n(reset_n),
        .addr(addr), .data_in(data_in), .data_out(data_out),
        .rd(rd), .wr(wr),
        .mem_addr(mem_addr), .mem_bank(mem_bank),
        .mem_rdata(mem_rdata), .mem_wdata(mem_wdata), .mem_we(mem_we),
        .bus_request(bus_request), .busy(busy)
    );

    // SPRAM instance (bank 0 only for simplicity)
    SB_SPRAM256KA spram (
        .ADDRESS(mem_addr),
        .DATAIN(mem_wdata),
        .MASKWREN(mem_we),
        .WREN(|mem_we),
        .CHIPSELECT(mem_bank == 2'b00),
        .CLOCK(clk),
        .STANDBY(1'b0),
        .SLEEP(1'b0),
        .POWEROFF(1'b1),
        .DATAOUT(mem_rdata)
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

    // Write 24-bit pointer
    task write_ptr(input [3:0] base, input [23:0] val);
        begin
            write_reg(base, val[7:0]);
            write_reg(base + 1, val[15:8]);
            write_reg(base + 2, val[23:16]);
        end
    endtask

    // Write 16-bit value
    task write16(input [3:0] base, input [15:0] val);
        begin
            write_reg(base, val[7:0]);
            write_reg(base + 1, val[15:8]);
        end
    endtask

    // Write 32-bit bias
    task write_bias(input [31:0] val);
        begin
            write_reg(REG_BIAS_0, val[7:0]);
            write_reg(REG_BIAS_1, val[15:8]);
            write_reg(REG_BIAS_2, val[23:16]);
            // Note: BIAS only has 24-bit register, but bias reg is 32-bit internally
        end
    endtask

    // Read 32-bit result
    task read_acc(output [31:0] val);
        reg [7:0] b0, b1, b2, b3;
        begin
            read_reg(REG_ACC_0, b0);
            read_reg(REG_ACC_1, b1);
            read_reg(REG_ACC_2, b2);
            read_reg(REG_ACC_3, b3);
            val = {b3, b2, b1, b0};
        end
    endtask

    // Load test vectors into SPRAM (direct access for setup)
    // Address is byte address, data is array of signed 8-bit values
    task load_vectors(input [15:0] addr_a, input [15:0] addr_b,
                      input integer len);
        integer i;
        reg [15:0] word_addr_a, word_addr_b;
        begin
            word_addr_a = addr_a >> 1;
            word_addr_b = addr_b >> 1;

            // Load vectors (2 bytes per word)
            for (i = 0; i < len; i = i + 2) begin
                // We need to directly write to SPRAM memory array
                // This is done via force for simulation
            end
        end
    endtask

    // Wait for vmath to complete
    task wait_done;
        reg [7:0] status;
        begin
            status = 8'h80;  // BUSY
            while (status[7]) begin
                @(posedge clk);
                read_reg(REG_CTRL, status);
            end
        end
    endtask

    // Test variables
    reg [31:0] result;
    reg signed [31:0] expected;
    integer errors;
    integer test_num;
    integer i;

    // Signed byte helper
    function signed [7:0] sb;
        input [7:0] val;
        sb = val;
    endfunction

    initial begin
        $dumpfile("vmath_tb.vcd");
        $dumpvars(0, vmath_tb);

        errors = 0;
        test_num = 0;
        reset_n = 0; rd = 0; wr = 0; addr = 0; data_in = 0;

        repeat(5) @(posedge clk);
        reset_n = 1;
        repeat(2) @(posedge clk);

        $display("=== vmath Comprehensive Testbench ===");
        $display("Testing int8 dot product with various vector lengths");

        //======================================================================
        // Test 1: 4-wide (single iteration) - simple positive values
        //======================================================================
        test_num = 1;
        $display("\n--- Test %0d: 4-wide (LEN=4), positive values ---", test_num);
        // A = [1, 2, 3, 4], B = [5, 6, 7, 8]
        // dot = 1*5 + 2*6 + 3*7 + 4*8 = 5 + 12 + 21 + 32 = 70

        // Load vectors at address 0x0000 (A) and 0x0100 (B)
        spram.mem[0] = {8'd2, 8'd1};   // A[1], A[0]
        spram.mem[1] = {8'd4, 8'd3};   // A[3], A[2]
        spram.mem[128] = {8'd6, 8'd5}; // B[1], B[0]
        spram.mem[129] = {8'd8, 8'd7}; // B[3], B[2]

        write_ptr(REG_A_PTR_LO, 24'h000000);  // A at 0x0000
        write_ptr(REG_B_PTR_LO, 24'h000100);  // B at 0x0100
        write16(REG_LEN_LO, 16'd4);
        write_bias(32'd0);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = 70;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot([1,2,3,4], [5,6,7,8]) = %0d", $signed(result));

        //======================================================================
        // Test 2: 4-wide with negative values
        //======================================================================
        test_num = 2;
        $display("\n--- Test %0d: 4-wide, signed values ---", test_num);
        // A = [-1, 2, -3, 4], B = [5, -6, 7, -8]
        // dot = (-1)*5 + 2*(-6) + (-3)*7 + 4*(-8) = -5 - 12 - 21 - 32 = -70

        spram.mem[0] = {8'd2, 8'hFF};     // A[1]=2, A[0]=-1
        spram.mem[1] = {8'd4, 8'hFD};     // A[3]=4, A[2]=-3
        spram.mem[128] = {8'hFA, 8'd5};   // B[1]=-6, B[0]=5
        spram.mem[129] = {8'hF8, 8'd7};   // B[3]=-8, B[2]=7

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000100);
        write16(REG_LEN_LO, 16'd4);
        write_bias(32'd0);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = -70;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot([-1,2,-3,4], [5,-6,7,-8]) = %0d", $signed(result));

        //======================================================================
        // Test 3: 4-wide with bias
        //======================================================================
        test_num = 3;
        $display("\n--- Test %0d: 4-wide with bias ---", test_num);
        // Same as test 1 but with bias = 1000
        // dot = 70 + 1000 = 1070

        spram.mem[0] = {8'd2, 8'd1};
        spram.mem[1] = {8'd4, 8'd3};
        spram.mem[128] = {8'd6, 8'd5};
        spram.mem[129] = {8'd8, 8'd7};

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000100);
        write16(REG_LEN_LO, 16'd4);
        write_bias(32'd1000);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = 1070;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot + bias = %0d", $signed(result));

        //======================================================================
        // Test 4: 8-wide (2 iterations)
        //======================================================================
        test_num = 4;
        $display("\n--- Test %0d: 8-wide (LEN=8), 2 iterations ---", test_num);
        // A = [1, 1, 1, 1, 1, 1, 1, 1], B = [1, 2, 3, 4, 5, 6, 7, 8]
        // dot = 1+2+3+4+5+6+7+8 = 36

        spram.mem[0] = {8'd1, 8'd1};   // A[1], A[0]
        spram.mem[1] = {8'd1, 8'd1};   // A[3], A[2]
        spram.mem[2] = {8'd1, 8'd1};   // A[5], A[4]
        spram.mem[3] = {8'd1, 8'd1};   // A[7], A[6]
        spram.mem[128] = {8'd2, 8'd1}; // B[1], B[0]
        spram.mem[129] = {8'd4, 8'd3}; // B[3], B[2]
        spram.mem[130] = {8'd6, 8'd5}; // B[5], B[4]
        spram.mem[131] = {8'd8, 8'd7}; // B[7], B[6]

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000100);
        write16(REG_LEN_LO, 16'd8);
        write_bias(32'd0);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = 36;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot(8 elements) = %0d", $signed(result));

        //======================================================================
        // Test 5: 12-wide (3 iterations)
        //======================================================================
        test_num = 5;
        $display("\n--- Test %0d: 12-wide (LEN=12), 3 iterations ---", test_num);
        // A = all 2s, B = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
        // dot = 2*(1+2+...+12) = 2*78 = 156

        spram.mem[0] = {8'd2, 8'd2};
        spram.mem[1] = {8'd2, 8'd2};
        spram.mem[2] = {8'd2, 8'd2};
        spram.mem[3] = {8'd2, 8'd2};
        spram.mem[4] = {8'd2, 8'd2};
        spram.mem[5] = {8'd2, 8'd2};
        spram.mem[128] = {8'd2, 8'd1};
        spram.mem[129] = {8'd4, 8'd3};
        spram.mem[130] = {8'd6, 8'd5};
        spram.mem[131] = {8'd8, 8'd7};
        spram.mem[132] = {8'd10, 8'd9};
        spram.mem[133] = {8'd12, 8'd11};

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000100);
        write16(REG_LEN_LO, 16'd12);
        write_bias(32'd0);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = 156;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot(12 elements) = %0d", $signed(result));

        //======================================================================
        // Test 6: 16-wide (4 iterations)
        //======================================================================
        test_num = 6;
        $display("\n--- Test %0d: 16-wide (LEN=16), 4 iterations ---", test_num);
        // A = [1,1,1,1...], B = [1,2,3,...16]
        // dot = 1+2+...+16 = 136

        for (i = 0; i < 8; i = i + 1) spram.mem[i] = {8'd1, 8'd1};
        spram.mem[128] = {8'd2, 8'd1};
        spram.mem[129] = {8'd4, 8'd3};
        spram.mem[130] = {8'd6, 8'd5};
        spram.mem[131] = {8'd8, 8'd7};
        spram.mem[132] = {8'd10, 8'd9};
        spram.mem[133] = {8'd12, 8'd11};
        spram.mem[134] = {8'd14, 8'd13};
        spram.mem[135] = {8'd16, 8'd15};

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000100);
        write16(REG_LEN_LO, 16'd16);
        write_bias(32'd0);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = 136;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot(16 elements) = %0d", $signed(result));

        //======================================================================
        // Test 7: 64-wide (16 iterations) - larger sequence
        //======================================================================
        test_num = 7;
        $display("\n--- Test %0d: 64-wide (LEN=64), 16 iterations ---", test_num);
        // A = all 1s, B = all 3s
        // dot = 64 * 1 * 3 = 192

        for (i = 0; i < 32; i = i + 1) spram.mem[i] = {8'd1, 8'd1};
        for (i = 0; i < 32; i = i + 1) spram.mem[128 + i] = {8'd3, 8'd3};

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000100);
        write16(REG_LEN_LO, 16'd64);
        write_bias(32'd0);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = 192;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot(64 elements) = %0d", $signed(result));

        //======================================================================
        // Test 8: 256-wide (64 iterations) - stress test
        //======================================================================
        test_num = 8;
        $display("\n--- Test %0d: 256-wide (LEN=256), 64 iterations ---", test_num);
        // A = all 1s, B = all 2s
        // dot = 256 * 1 * 2 = 512

        for (i = 0; i < 128; i = i + 1) spram.mem[i] = {8'd1, 8'd1};
        for (i = 0; i < 128; i = i + 1) spram.mem[256 + i] = {8'd2, 8'd2};

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000200);  // B at 0x0200
        write16(REG_LEN_LO, 16'd256);
        write_bias(32'd0);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = 512;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot(256 elements) = %0d", $signed(result));

        //======================================================================
        // Test 9: Max positive values
        //======================================================================
        test_num = 9;
        $display("\n--- Test %0d: Max positive values (127 * 127) ---", test_num);
        // A = [127, 127, 127, 127], B = [127, 127, 127, 127]
        // dot = 4 * 127 * 127 = 64516

        spram.mem[0] = {8'd127, 8'd127};
        spram.mem[1] = {8'd127, 8'd127};
        spram.mem[128] = {8'd127, 8'd127};
        spram.mem[129] = {8'd127, 8'd127};

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000100);
        write16(REG_LEN_LO, 16'd4);
        write_bias(32'd0);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = 64516;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot(max pos) = %0d", $signed(result));

        //======================================================================
        // Test 10: Max negative values
        //======================================================================
        test_num = 10;
        $display("\n--- Test %0d: Max negative values (-128 * -128) ---", test_num);
        // A = [-128, -128, -128, -128], B = [-128, -128, -128, -128]
        // dot = 4 * 128 * 128 = 65536

        spram.mem[0] = {8'h80, 8'h80};  // -128, -128
        spram.mem[1] = {8'h80, 8'h80};
        spram.mem[128] = {8'h80, 8'h80};
        spram.mem[129] = {8'h80, 8'h80};

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000100);
        write16(REG_LEN_LO, 16'd4);
        write_bias(32'd0);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = 65536;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot(max neg) = %0d", $signed(result));

        //======================================================================
        // Test 11: Mixed max values (overflow stress)
        //======================================================================
        test_num = 11;
        $display("\n--- Test %0d: Mixed extremes (-128 * 127) ---", test_num);
        // A = [-128, -128, -128, -128], B = [127, 127, 127, 127]
        // dot = 4 * (-128) * 127 = -65024

        spram.mem[0] = {8'h80, 8'h80};
        spram.mem[1] = {8'h80, 8'h80};
        spram.mem[128] = {8'd127, 8'd127};
        spram.mem[129] = {8'd127, 8'd127};

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000100);
        write16(REG_LEN_LO, 16'd4);
        write_bias(32'd0);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = -65024;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot(mixed) = %0d", $signed(result));

        //======================================================================
        // Test 12: Negative bias
        //======================================================================
        test_num = 12;
        $display("\n--- Test %0d: Negative bias ---", test_num);
        // dot = 70, bias = -100
        // result = 70 - 100 = -30

        spram.mem[0] = {8'd2, 8'd1};
        spram.mem[1] = {8'd4, 8'd3};
        spram.mem[128] = {8'd6, 8'd5};
        spram.mem[129] = {8'd8, 8'd7};

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000100);
        write16(REG_LEN_LO, 16'd4);
        // Write -100 as bias (two's complement)
        write_reg(REG_BIAS_0, 8'h9C);  // -100 low byte
        write_reg(REG_BIAS_1, 8'hFF);
        write_reg(REG_BIAS_2, 8'hFF);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = -30;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot + neg_bias = %0d", $signed(result));

        //======================================================================
        // Test 13: Zero vector
        //======================================================================
        test_num = 13;
        $display("\n--- Test %0d: Zero vector ---", test_num);
        // A = [0,0,0,0], B = [1,2,3,4]
        // dot = 0

        spram.mem[0] = 16'h0000;
        spram.mem[1] = 16'h0000;
        spram.mem[128] = {8'd2, 8'd1};
        spram.mem[129] = {8'd4, 8'd3};

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000100);
        write16(REG_LEN_LO, 16'd4);
        write_bias(32'd0);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = 0;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot(zeros) = %0d", $signed(result));

        //======================================================================
        // Test 14: Large accumulation (1024 elements)
        //======================================================================
        test_num = 14;
        $display("\n--- Test %0d: Large accumulation (1024 elements) ---", test_num);
        // A = all 1s, B = all 1s
        // dot = 1024

        for (i = 0; i < 512; i = i + 1) begin
            spram.mem[i] = {8'd1, 8'd1};
            spram.mem[1024 + i] = {8'd1, 8'd1};
        end

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000800);  // B at 0x0800
        write16(REG_LEN_LO, 16'd1024);
        write_bias(32'd0);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = 1024;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot(1024 elements) = %0d", $signed(result));

        //======================================================================
        // Test 15: 3-wide (partial iteration, padded to 4)
        //======================================================================
        test_num = 15;
        $display("\n--- Test %0d: 3-wide (LEN=4 with padding) ---", test_num);
        // A = [10, 20, 30, 0], B = [1, 2, 3, 0]
        // dot = 10*1 + 20*2 + 30*3 + 0*0 = 10 + 40 + 90 = 140

        spram.mem[0] = {8'd20, 8'd10};  // A[1], A[0]
        spram.mem[1] = {8'd0, 8'd30};   // A[3]=0 (pad), A[2]
        spram.mem[128] = {8'd2, 8'd1};  // B[1], B[0]
        spram.mem[129] = {8'd0, 8'd3};  // B[3]=0 (pad), B[2]

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000100);
        write16(REG_LEN_LO, 16'd4);  // Must be multiple of 4
        write_bias(32'd0);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = 140;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot(3 values + pad) = %0d", $signed(result));

        //======================================================================
        // Test 16: 2-wide (partial iteration, padded to 4)
        //======================================================================
        test_num = 16;
        $display("\n--- Test %0d: 2-wide (LEN=4 with padding) ---", test_num);
        // A = [100, 50, 0, 0], B = [3, 4, 0, 0]
        // dot = 100*3 + 50*4 = 300 + 200 = 500

        spram.mem[0] = {8'd50, 8'd100}; // A[1], A[0]
        spram.mem[1] = {8'd0, 8'd0};    // A[3]=0, A[2]=0 (pad)
        spram.mem[128] = {8'd4, 8'd3};  // B[1], B[0]
        spram.mem[129] = {8'd0, 8'd0};  // B[3]=0, B[2]=0 (pad)

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000100);
        write16(REG_LEN_LO, 16'd4);
        write_bias(32'd0);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = 500;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot(2 values + pad) = %0d", $signed(result));

        //======================================================================
        // Test 17: 1-wide (single value, padded to 4)
        //======================================================================
        test_num = 17;
        $display("\n--- Test %0d: 1-wide (LEN=4 with padding) ---", test_num);
        // A = [127, 0, 0, 0], B = [127, 0, 0, 0]
        // dot = 127*127 = 16129

        spram.mem[0] = {8'd0, 8'd127}; // A[1]=0, A[0]=127
        spram.mem[1] = {8'd0, 8'd0};   // A[3]=0, A[2]=0
        spram.mem[128] = {8'd0, 8'd127};
        spram.mem[129] = {8'd0, 8'd0};

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000100);
        write16(REG_LEN_LO, 16'd4);
        write_bias(32'd0);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = 16129;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot(1 value + pad) = %0d", $signed(result));

        //======================================================================
        // Test 18: Alternating signs
        //======================================================================
        test_num = 18;
        $display("\n--- Test %0d: Alternating signs ---", test_num);
        // A = [10, -10, 10, -10], B = [1, 1, 1, 1]
        // dot = 10 - 10 + 10 - 10 = 0

        spram.mem[0] = {8'hF6, 8'd10};  // A[1]=-10, A[0]=10
        spram.mem[1] = {8'hF6, 8'd10};  // A[3]=-10, A[2]=10
        spram.mem[128] = {8'd1, 8'd1};
        spram.mem[129] = {8'd1, 8'd1};

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000100);
        write16(REG_LEN_LO, 16'd4);
        write_bias(32'd0);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = 0;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot(alternating) = %0d", $signed(result));

        //======================================================================
        // Test 19: Large bias with small dot product
        //======================================================================
        test_num = 19;
        $display("\n--- Test %0d: Large positive bias ---", test_num);
        // dot = 4 (1*1+1*1+1*1+1*1), bias = 1000000
        // result = 1000004

        spram.mem[0] = {8'd1, 8'd1};
        spram.mem[1] = {8'd1, 8'd1};
        spram.mem[128] = {8'd1, 8'd1};
        spram.mem[129] = {8'd1, 8'd1};

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000100);
        write16(REG_LEN_LO, 16'd4);
        // 1000000 = 0x0F4240
        write_reg(REG_BIAS_0, 8'h40);
        write_reg(REG_BIAS_1, 8'h42);
        write_reg(REG_BIAS_2, 8'h0F);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = 1000004;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot + large_bias = %0d", $signed(result));

        //======================================================================
        // Test 20: Edge case - all -1 values
        //======================================================================
        test_num = 20;
        $display("\n--- Test %0d: All -1 values ---", test_num);
        // A = [-1, -1, -1, -1], B = [-1, -1, -1, -1]
        // dot = 4 * (-1) * (-1) = 4

        spram.mem[0] = {8'hFF, 8'hFF};  // -1, -1
        spram.mem[1] = {8'hFF, 8'hFF};
        spram.mem[128] = {8'hFF, 8'hFF};
        spram.mem[129] = {8'hFF, 8'hFF};

        write_ptr(REG_A_PTR_LO, 24'h000000);
        write_ptr(REG_B_PTR_LO, 24'h000100);
        write16(REG_LEN_LO, 16'd4);
        write_bias(32'd0);
        write_reg(REG_CTRL, CTRL_START);

        wait_done;
        read_acc(result);
        expected = 4;

        if ($signed(result) !== expected) begin
            $display("  FAIL: result=%0d, expected=%0d", $signed(result), expected);
            errors = errors + 1;
        end else $display("  PASS: dot(all -1) = %0d", $signed(result));

        //======================================================================
        // Summary
        //======================================================================
        $display("\n=== Test Summary ===");
        $display("Total tests: %0d", test_num);
        if (errors == 0)
            $display("All tests PASSED");
        else
            $display("%d tests FAILED", errors);

        $finish;
    end
endmodule
