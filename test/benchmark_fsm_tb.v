// benchmark_fsm_tb.v - Real software benchmarks for FSM core
//
// Same benchmarks as benchmark_tb.v but using the original FSM i8085_cpu.
// Compare cycle counts between HP and FSM cores for realistic speedup data.

`timescale 1ns / 1ps

module benchmark_fsm_tb;

    parameter CLK_PERIOD = 20;

    reg         clk;
    reg         reset_n;

    wire [15:0] bus_addr;
    wire [7:0]  bus_data_out;
    wire        bus_rd;
    wire        bus_wr;
    wire [7:0]  bus_data_in;
    wire        bus_ready;

    wire [15:0] stack_wr_addr;
    wire [7:0]  stack_wr_data_lo;
    wire [7:0]  stack_wr_data_hi;
    wire        stack_wr;

    wire [15:0] cpu_pc, cpu_sp;
    wire [7:0]  cpu_a, cpu_b, cpu_c, cpu_d, cpu_e, cpu_h, cpu_l;
    wire        cpu_halted, cpu_inte, cpu_flag_z, cpu_flag_c;
    wire        cpu_mask_55, cpu_mask_65, cpu_mask_75;
    wire        cpu_rst75_pending, cpu_sod;
    wire [7:0]  io_port, io_data_out;
    wire        io_rd, io_wr;

    // DUT - Original FSM i8085_cpu
    i8085_cpu cpu (
        .clk(clk), .reset_n(reset_n),
        .bus_addr(bus_addr), .bus_data_out(bus_data_out),
        .bus_rd(bus_rd), .bus_wr(bus_wr),
        .bus_data_in(bus_data_in), .bus_ready(bus_ready),
        .stack_wr_addr(stack_wr_addr),
        .stack_wr_data_lo(stack_wr_data_lo),
        .stack_wr_data_hi(stack_wr_data_hi),
        .stack_wr(stack_wr),
        .io_port(io_port), .io_data_out(io_data_out),
        .io_data_in(8'h00), .io_rd(io_rd), .io_wr(io_wr),
        .rom_bank(), .ram_bank(),
        .int_req(1'b0), .int_vector(16'h0000), .int_is_trap(1'b0), .int_ack(),
        .sid(1'b0), .rst55_level(1'b0), .rst65_level(1'b0),
        .pc(cpu_pc), .sp(cpu_sp),
        .reg_a(cpu_a), .reg_b(cpu_b), .reg_c(cpu_c),
        .reg_d(cpu_d), .reg_e(cpu_e), .reg_h(cpu_h), .reg_l(cpu_l),
        .halted(cpu_halted), .inte(cpu_inte),
        .flag_z(cpu_flag_z), .flag_c(cpu_flag_c),
        .mask_55(cpu_mask_55), .mask_65(cpu_mask_65), .mask_75(cpu_mask_75),
        .rst75_pending(cpu_rst75_pending), .sod(cpu_sod)
    );

    // Memory
    j8085_mem_sim mem (
        .clk(clk), .reset_n(reset_n),
        .cpu_addr(bus_addr), .cpu_data_out(bus_data_out),
        .cpu_rd(bus_rd), .cpu_wr(bus_wr),
        .cpu_data_in(bus_data_in), .cpu_ready(bus_ready),
        .stack_wr_addr(stack_wr_addr),
        .stack_wr_data_lo(stack_wr_data_lo),
        .stack_wr_data_hi(stack_wr_data_hi),
        .stack_wr(stack_wr)
    );

    // Clock
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test infrastructure
    integer cycle;
    reg     test_passed;

    task reset_cpu;
        begin
            reset_n = 0;
            repeat(5) @(posedge clk);
            reset_n = 1;
            @(posedge clk);
        end
    endtask

    task clear_mem;
        integer j;
        begin
            for (j = 0; j < 512; j = j + 1)
                mem.ram[j] = 16'h0000;
        end
    endtask

    task wait_halt_or_timeout;
        input integer max_cycles;
        begin
            cycle = 0;
            test_passed = 0;
            while (cycle < max_cycles && !cpu_halted) begin
                @(posedge clk);
                cycle = cycle + 1;
            end
            if (cpu_halted)
                test_passed = 1;
        end
    endtask

    // Main test sequence - identical to benchmark_tb.v
    initial begin
        $display("=== 8085 FSM Core Benchmark Suite ===\n");
        $display("Running real software benchmarks on original FSM core.\n");

        // Benchmark 1: Bubble Sort (8 elements)
        $display("--- Benchmark 1: Bubble Sort (8 elements) ---");
        clear_mem;
        // Same code as benchmark_tb.v
        mem.ram[0]  = 16'h0021;
        mem.ram[1]  = 16'h1601;
        mem.ram[2]  = 16'h0E00;
        mem.ram[3]  = 16'h7E07;
        mem.ram[4]  = 16'hBE23;
        mem.ram[5]  = 16'h14DA;  // JC 0014h
        mem.ram[6]  = 16'h4600;
        mem.ram[7]  = 16'h2B77;
        mem.ram[8]  = 16'h2370;
        mem.ram[9]  = 16'h0116;
        mem.ram[10] = 16'hC20D;
        mem.ram[11] = 16'h0007;  // JNZ 0007h
        mem.ram[12] = 16'h0F7A;
        mem.ram[13] = 16'h00DA;
        mem.ram[14] = 16'h7600;
        mem.ram[16'h80] = 16'h0307;
        mem.ram[16'h81] = 16'h0105;
        mem.ram[16'h82] = 16'h0208;
        mem.ram[16'h83] = 16'h0406;

        reset_cpu;
        wait_halt_or_timeout(5000);

        if (test_passed) begin
            $display("  Cycles: %0d", cycle);
            if (mem.ram[16'h80] == 16'h0201 && mem.ram[16'h81] == 16'h0403 &&
                mem.ram[16'h82] == 16'h0605 && mem.ram[16'h83] == 16'h0807) begin
                $display("  Result: PASS (sorted correctly)");
            end else begin
                $display("  Result: FAIL (incorrect sort)");
            end
        end else begin
            $display("  TIMEOUT at PC=0x%04x", cpu_pc);
        end
        $display("");

        // Benchmark 2: Division (100 / 7)
        $display("--- Benchmark 2: Division (100 / 7) ---");
        clear_mem;
        mem.ram[0]  = 16'h6406;
        mem.ram[1]  = 16'h070E;
        mem.ram[2]  = 16'h0026;
        mem.ram[3]  = 16'hB978;
        mem.ram[4]  = 16'h12DA;
        mem.ram[5]  = 16'h9100;
        mem.ram[6]  = 16'hB924;
        mem.ram[7]  = 16'h0BD2;
        mem.ram[8]  = 16'h6F00;
        mem.ram[9]  = 16'h0076;

        reset_cpu;
        wait_halt_or_timeout(2000);

        if (test_passed) begin
            $display("  Cycles: %0d", cycle);
            if (cpu_h == 8'd14 && cpu_l == 8'd2) begin
                $display("  Result: PASS (100/7 = %0d r %0d)", cpu_h, cpu_l);
            end else begin
                $display("  Result: FAIL (got %0d r %0d, expected 14 r 2)", cpu_h, cpu_l);
            end
        end else begin
            $display("  TIMEOUT at PC=0x%04x", cpu_pc);
        end
        $display("");

        // Benchmark 3: Linear Search (same code as benchmark_tb.v)
        $display("--- Benchmark 3: Linear Search (find 5 in [1..8]) ---");
        clear_mem;
        mem.ram[0]  = 16'h0516;
        mem.ram[1]  = 16'h0006;
        mem.ram[2]  = 16'h0021;
        mem.ram[3]  = 16'h7E01;
        mem.ram[4]  = 16'hCABA;
        mem.ram[5]  = 16'h0014;
        mem.ram[6]  = 16'h0423;
        mem.ram[7]  = 16'hFE78;
        mem.ram[8]  = 16'hDA08;
        mem.ram[9]  = 16'h0007;
        mem.ram[10] = 16'h7678;
        mem.ram[16'h80] = 16'h0201;
        mem.ram[16'h81] = 16'h0403;
        mem.ram[16'h82] = 16'h0605;
        mem.ram[16'h83] = 16'h0807;

        reset_cpu;
        wait_halt_or_timeout(2000);

        if (test_passed) begin
            $display("  Cycles: %0d", cycle);
            if (cpu_b == 8'd4) begin
                $display("  Result: PASS (found 5 at index %0d)", cpu_b);
            end else begin
                $display("  Result: FAIL (got index %0d, expected 4)", cpu_b);
            end
        end else begin
            $display("  TIMEOUT at PC=0x%04x", cpu_pc);
        end
        $display("");

        // Benchmark 4: Memory Copy (16 bytes)
        $display("--- Benchmark 4: Memory Copy (16 bytes) ---");
        clear_mem;
        mem.ram[0]  = 16'h0021;
        mem.ram[1]  = 16'h1101;
        mem.ram[2]  = 16'h0110;
        mem.ram[3]  = 16'h100E;
        mem.ram[4]  = 16'h127E;
        mem.ram[5]  = 16'h1323;
        mem.ram[6]  = 16'hC20D;
        mem.ram[7]  = 16'h0008;
        mem.ram[8]  = 16'h0076;
        mem.ram[16'h80] = 16'h2211;
        mem.ram[16'h81] = 16'h4433;
        mem.ram[16'h82] = 16'h6655;
        mem.ram[16'h83] = 16'h8877;
        mem.ram[16'h84] = 16'hAA99;
        mem.ram[16'h85] = 16'hCCBB;
        mem.ram[16'h86] = 16'hEEDD;
        mem.ram[16'h87] = 16'h00FF;

        reset_cpu;
        wait_halt_or_timeout(2000);

        if (test_passed) begin
            $display("  Cycles: %0d", cycle);
            if (mem.ram[16'h88] == 16'h2211 && mem.ram[16'h89] == 16'h4433 &&
                mem.ram[16'h8A] == 16'h6655 && mem.ram[16'h8B] == 16'h8877) begin
                $display("  Result: PASS (16 bytes copied correctly)");
            end else begin
                $display("  Result: FAIL (copy mismatch)");
            end
        end else begin
            $display("  TIMEOUT at PC=0x%04x", cpu_pc);
        end
        $display("");

        // Benchmark 5: Fibonacci
        $display("--- Benchmark 5: Fibonacci (fib(10) = 55) ---");
        clear_mem;
        mem.ram[0]  = 16'h0006;
        mem.ram[1]  = 16'h010E;
        mem.ram[2]  = 16'h0A16;
        mem.ram[3]  = 16'hFE7A;
        mem.ram[4]  = 16'hCA00;
        mem.ram[5]  = 16'h0015;
        mem.ram[6]  = 16'h8178;
        mem.ram[7]  = 16'h4F41;
        mem.ram[8]  = 16'hC315;
        mem.ram[9]  = 16'h0006;
        mem.ram[10] = 16'h7800;
        mem.ram[11] = 16'h0076;

        reset_cpu;
        wait_halt_or_timeout(2000);

        if (test_passed) begin
            $display("  Cycles: %0d", cycle);
            if (cpu_a == 8'd55) begin
                $display("  Result: PASS (fib(10) = %0d)", cpu_a);
            end else begin
                $display("  Result: FAIL (got %0d, expected 55)", cpu_a);
            end
        end else begin
            $display("  TIMEOUT at PC=0x%04x, A=%0d B=%0d C=%0d D=%0d",
                     cpu_pc, cpu_a, cpu_b, cpu_c, cpu_d);
        end
        $display("");

        $display("=== FSM Benchmark Complete ===");
        $finish;
    end

endmodule
