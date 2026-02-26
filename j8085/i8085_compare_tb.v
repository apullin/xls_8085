// i8085_compare_tb.v - Cycle count comparison testbench for i8085_cpu (old FSM design)
// Runs the same test programs as j8085_tb.v tests 1-46 and reports cycle counts.
// Skips interrupt tests (47-49) and bank reg test (50) for fair comparison.

`timescale 1ns / 1ps

module i8085_compare_tb;

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

    // ── DUT: old i8085_cpu ───────────────────────────────
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

    // ── Memory ──────────────────────────────────────────
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

    // ── Clock ───────────────────────────────────────────
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ── Test infrastructure ─────────────────────────────
    integer cycle;
    integer pass_count;
    integer fail_count;
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
            for (j = 0; j < 256; j = j + 1)
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

    task check_reg;
        input [7:0] name;
        input [7:0] actual;
        input [7:0] expected;
        begin
            if (actual !== expected) begin
                $display("  FAIL: %c = 0x%02x, expected 0x%02x", name, actual, expected);
                test_passed = 0;
            end
        end
    endtask

    task report;
        input integer tnum;
        begin
            if (test_passed) begin
                $display("  TEST %0d: PASS (%0d cycles)", tnum, cycle);
                pass_count = pass_count + 1;
            end else begin
                $display("  TEST %0d: FAIL", tnum);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ── Tests ───────────────────────────────────────────
    initial begin
        $display("=== i8085_cpu (old FSM) comparison run ===");
        pass_count = 0;
        fail_count = 0;

        // Test 1: NOP → HLT
        clear_mem;
        mem.ram[0] = 16'h7600; // 00 76
        reset_cpu;
        wait_halt_or_timeout(60);
        report(1);

        // Test 2: MVI A,55h → HLT
        clear_mem;
        mem.ram[0] = 16'h553E; mem.ram[1] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'h55);
        report(2);

        // Test 3: MVI A,10h; NOP; MVI B,20h; NOP; ADD B; HLT
        clear_mem;
        mem.ram[0] = 16'h103E; mem.ram[1] = 16'h0600;
        mem.ram[2] = 16'h0020; mem.ram[3] = 16'h7680;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'h30);
        report(3);

        // Test 4: MVI A,AAh; NOP; MOV B,A; HLT
        clear_mem;
        mem.ram[0] = 16'hAA3E; mem.ram[1] = 16'h4700;
        mem.ram[2] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'hAA);
        check_reg("B", cpu_b, 8'hAA);
        report(4);

        // Test 5: MVI A,FFh; NOP; XRA A; HLT
        clear_mem;
        mem.ram[0] = 16'hFF3E; mem.ram[1] = 16'hAF00;
        mem.ram[2] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'h00);
        report(5);

        // Test 6: MVI A,10h; MVI B,20h; ADD B; HLT
        clear_mem;
        mem.ram[0] = 16'h103E; mem.ram[1] = 16'h2006;
        mem.ram[2] = 16'h7680;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'h30);
        report(6);

        // Test 7: MVI A,01h; MVI B,02h; ADD B; ADD B; HLT
        clear_mem;
        mem.ram[0] = 16'h013E; mem.ram[1] = 16'h0206;
        mem.ram[2] = 16'h8080; mem.ram[3] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'h05);
        report(7);

        // Test 8: MVI A,AAh; MOV B,A; HLT
        clear_mem;
        mem.ram[0] = 16'hAA3E; mem.ram[1] = 16'h7647;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'hAA);
        check_reg("B", cpu_b, 8'hAA);
        report(8);

        // Test 9: MVI B,FFh; INR B; HLT
        clear_mem;
        mem.ram[0] = 16'hFF06; mem.ram[1] = 16'h7604;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("B", cpu_b, 8'h00);
        report(9);

        // Test 10: MVI C,01h; DCR C; HLT
        clear_mem;
        mem.ram[0] = 16'h010E; mem.ram[1] = 16'h760D;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("C", cpu_c, 8'h00);
        report(10);

        // Test 11: MVI A,55h; CMA; HLT
        clear_mem;
        mem.ram[0] = 16'h553E; mem.ram[1] = 16'h762F;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'hAA);
        report(11);

        // Test 12: STC; CMC; HLT
        clear_mem;
        mem.ram[0] = 16'h3F37; mem.ram[1] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(60);
        report(12);

        // Test 13: STC; MVI A,10h; MVI B,20h; ADC B; HLT
        clear_mem;
        mem.ram[0] = 16'h3E37; mem.ram[1] = 16'h0610;
        mem.ram[2] = 16'h8820; mem.ram[3] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'h31);
        report(13);

        // Test 14: MVI A,85h; RLC; HLT
        clear_mem;
        mem.ram[0] = 16'h853E; mem.ram[1] = 16'h7607;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'h0B);
        report(14);

        // Test 15: MVI A,10h; MVI B,05h; ADD B; SUB B; HLT
        clear_mem;
        mem.ram[0] = 16'h103E; mem.ram[1] = 16'h0506;
        mem.ram[2] = 16'h9080; mem.ram[3] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'h10);
        report(15);

        // Test 16: JMP forward
        clear_mem;
        mem.ram[0] = 16'h03C3; mem.ram[1] = 16'h3E00;
        mem.ram[2] = 16'h76FF; mem.ram[3] = 16'h0076;
        // JMP 0006h; MVI A,FFh; HLT; (at 0x06) HLT
        // Wait, let me match exactly: 0x00: C3 06 00  JMP 0006h
        //                             0x03: 3E FF     MVI A,FFh (skipped)
        //                             0x05: 76        HLT (skipped)
        //                             0x06: 76        HLT (landed here)
        mem.ram[0] = 16'h06C3;  // C3 06
        mem.ram[1] = 16'h3E00;  // 00 3E
        mem.ram[2] = 16'h76FF;  // FF 76
        mem.ram[3] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'h00);
        report(16);

        // Test 17: JZ not taken (Z=0 at reset)
        clear_mem;
        mem.ram[0] = 16'h06CA;  // CA 06
        mem.ram[1] = 16'h3E00;  // 00 3E
        mem.ram[2] = 16'h76AA;  // AA 76
        mem.ram[3] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'hAA);
        report(17);

        // Test 18: XRA A; JZ taken
        clear_mem;
        mem.ram[0] = 16'hCAAF;  // AF CA
        mem.ram[1] = 16'h0006;  // 06 00
        mem.ram[2] = 16'hFF3E;  // 3E FF
        mem.ram[3] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'h00);
        report(18);

        // Test 19: Loop: MVI B,03h; DCR B; JNZ loop; HLT
        clear_mem;
        mem.ram[0] = 16'h0306;  // 06 03
        mem.ram[1] = 16'hC205;  // 05 C2
        mem.ram[2] = 16'h0002;  // 02 00
        mem.ram[3] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(200);
        check_reg("B", cpu_b, 8'h00);
        report(19);

        // Test 20: PCHL
        clear_mem;
        mem.ram[0] = 16'h0621;  // 21 06
        mem.ram[1] = 16'hE900;  // 00 E9
        mem.ram[2] = 16'hFF3E;  // 3E FF
        mem.ram[3] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'h00);
        report(20);

        // Test 21: LXI H + MVI M + MOV A,M
        clear_mem;
        mem.ram[0] = 16'h0021;  // 21 00
        mem.ram[1] = 16'h3602;  // 02 36
        mem.ram[2] = 16'h7EAA;  // AA 7E
        mem.ram[3] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'hAA);
        report(21);

        // Test 22: STA + LDA
        clear_mem;
        mem.ram[0] = 16'h553E;  // 3E 55
        mem.ram[1] = 16'h0032;  // 32 00
        mem.ram[2] = 16'hAF02;  // 02 AF
        mem.ram[3] = 16'h003A;  // 3A 00
        mem.ram[4] = 16'h7602;  // 02 76
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h55);
        report(22);

        // Test 23: LXI B + STAX B + LDAX B
        clear_mem;
        mem.ram[0] = 16'h0001;  // 01 00
        mem.ram[1] = 16'h3E02;  // 02 3E
        mem.ram[2] = 16'h0277;  // 77 02
        mem.ram[3] = 16'h0AAF;  // AF 0A
        mem.ram[4] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h77);
        report(23);

        // Test 24: LXI D + STAX D + LDAX D
        clear_mem;
        mem.ram[0] = 16'h0011;  // 11 00
        mem.ram[1] = 16'h3E02;  // 02 3E
        mem.ram[2] = 16'h1288;  // 88 12
        mem.ram[3] = 16'h1AAF;  // AF 1A
        mem.ram[4] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h88);
        report(24);

        // Test 25: ADD M
        clear_mem;
        mem.ram[0] = 16'h0A3E;  // 3E 0A
        mem.ram[1] = 16'h0021;  // 21 00
        mem.ram[2] = 16'h8602;  // 02 86
        mem.ram[3] = 16'h0076;  // 76 00
        // Pre-store 0x14 at addr 0x0200
        mem.ram[16'h100] = 16'h0014;
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h1E);
        report(25);

        // Test 26: CMP M
        clear_mem;
        mem.ram[0] = 16'h0A3E;
        mem.ram[1] = 16'h0021;
        mem.ram[2] = 16'hBE02;
        mem.ram[3] = 16'h0076;
        mem.ram[16'h100] = 16'h000A;
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h0A);
        report(26);

        // Test 27: INR M
        clear_mem;
        mem.ram[0] = 16'h0021;
        mem.ram[1] = 16'h3402;
        mem.ram[2] = 16'h007E;
        mem.ram[3] = 16'h0076;
        mem.ram[16'h100] = 16'h00FE;
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'hFF);
        report(27);

        // Test 28: DCR M
        clear_mem;
        mem.ram[0] = 16'h0021;
        mem.ram[1] = 16'h3502;
        mem.ram[2] = 16'h007E;
        mem.ram[3] = 16'h0076;
        mem.ram[16'h100] = 16'h0001;
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h00);
        report(28);

        // Test 29: LHLD
        clear_mem;
        mem.ram[0] = 16'h002A;
        mem.ram[1] = 16'h7602;
        mem.ram[16'h100] = 16'h5634;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("H", cpu_h, 8'h56);
        check_reg("L", cpu_l, 8'h34);
        report(29);

        // Test 30: SHLD
        clear_mem;
        mem.ram[0] = 16'h3421;
        mem.ram[1] = 16'h2212;
        mem.ram[2] = 16'h0200;
        mem.ram[3] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(120);
        if (mem.ram[16'h100] !== 16'h1234) test_passed = 0;
        report(30);

        // Test 31: SUB M chain
        clear_mem;
        mem.ram[0] = 16'h0A3E;
        mem.ram[1] = 16'h0021;
        mem.ram[2] = 16'h9602;
        mem.ram[3] = 16'h0076;
        mem.ram[16'h100] = 16'h0003;
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h07);
        report(31);

        // Test 32: PUSH B + POP D
        clear_mem;
        mem.ram[0] = 16'h0031;
        mem.ram[1] = 16'h0101;
        mem.ram[2] = 16'h1234;
        mem.ram[3] = 16'hD1C5;
        mem.ram[4] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("D", cpu_d, 8'h12);
        check_reg("E", cpu_e, 8'h34);
        report(32);

        // Test 33: CALL + RET
        clear_mem;
        mem.ram[0] = 16'h0031;
        mem.ram[1] = 16'hCD01;
        mem.ram[2] = 16'h0010;
        mem.ram[3] = 16'h7600;
        mem.ram[8] = 16'h993E;
        mem.ram[9] = 16'h00C9;
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h99);
        report(33);

        // Test 34: PUSH PSW + POP PSW
        clear_mem;
        mem.ram[0] = 16'h0031;
        mem.ram[1] = 16'h3E01;
        mem.ram[2] = 16'h37AA;
        mem.ram[3] = 16'hAFF5;
        mem.ram[4] = 16'h76F1;
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'hAA);
        report(34);

        // Test 35: RST 1
        clear_mem;
        mem.ram[0] = 16'h0031;
        mem.ram[1] = 16'hCF01;
        mem.ram[2] = 16'h0076;
        mem.ram[4] = 16'h883E;
        mem.ram[5] = 16'h00C9;
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h88);
        report(35);

        // Test 36: CC (taken)
        clear_mem;
        mem.ram[0] = 16'h0031;
        mem.ram[1] = 16'h3701;
        mem.ram[2] = 16'h20DC;
        mem.ram[3] = 16'h7600;
        mem.ram[16] = 16'h773E;
        mem.ram[17] = 16'h00C9;
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h77);
        report(36);

        // Test 37: SPHL
        clear_mem;
        mem.ram[0] = 16'h3421;
        mem.ram[1] = 16'hF912;
        mem.ram[2] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(120);
        if (cpu_sp !== 16'h1234) test_passed = 0;
        report(37);

        // Test 38: XTHL
        clear_mem;
        mem.ram[0] = 16'h0031;
        mem.ram[1] = 16'h2101;
        mem.ram[2] = 16'hABCD;
        mem.ram[3] = 16'h76E3;
        mem.ram[16'h80] = 16'h5678;
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("H", cpu_h, 8'h56);
        check_reg("L", cpu_l, 8'h78);
        report(38);

        // Test 39: INX H
        clear_mem;
        mem.ram[0] = 16'hFF21;
        mem.ram[1] = 16'h2300;
        mem.ram[2] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("H", cpu_h, 8'h01);
        check_reg("L", cpu_l, 8'h00);
        report(39);

        // Test 40: DCX D
        clear_mem;
        mem.ram[0] = 16'h0011;
        mem.ram[1] = 16'h1B01;
        mem.ram[2] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("D", cpu_d, 8'h00);
        check_reg("E", cpu_e, 8'hFF);
        report(40);

        // Test 41: DAD B
        clear_mem;
        mem.ram[0] = 16'h0021;
        mem.ram[1] = 16'h0180;
        mem.ram[2] = 16'h8001;
        mem.ram[3] = 16'h7609;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("H", cpu_h, 8'h00);
        check_reg("L", cpu_l, 8'h01);
        report(41);

        // Test 42: XCHG
        clear_mem;
        mem.ram[0] = 16'h3411;
        mem.ram[1] = 16'h2112;
        mem.ram[2] = 16'h5678;
        mem.ram[3] = 16'h76EB;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("D", cpu_d, 8'h56);
        check_reg("E", cpu_e, 8'h78);
        check_reg("H", cpu_h, 8'h12);
        check_reg("L", cpu_l, 8'h34);
        report(42);

        // Test 43: EI / DI
        clear_mem;
        mem.ram[0] = 16'hF3FB;
        mem.ram[1] = 16'h76FB;
        reset_cpu;
        wait_halt_or_timeout(60);
        if (!cpu_inte) test_passed = 0;
        report(43);

        // Test 44: SIM + RIM
        clear_mem;
        mem.ram[0] = 16'h0D3E;
        mem.ram[1] = 16'h2030;
        mem.ram[2] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'h05);
        report(44);

        // Test 45: INX SP
        clear_mem;
        mem.ram[0] = 16'hFE31;
        mem.ram[1] = 16'h3300;
        mem.ram[2] = 16'h7633;
        reset_cpu;
        wait_halt_or_timeout(60);
        if (cpu_sp !== 16'h0100) test_passed = 0;
        report(45);

        // Test 46: DAD H
        clear_mem;
        mem.ram[0] = 16'h3421;
        mem.ram[1] = 16'h2912;
        mem.ram[2] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("H", cpu_h, 8'h24);
        check_reg("L", cpu_l, 8'h68);
        report(46);

        // ── Test 47: DSUB (no borrow) ──────────────────────
        $display("\n--- Test 47: DSUB (no borrow) ---");
        clear_mem;
        // LXI H,1234h; LXI B,0034h; DSUB; HLT
        mem.ram[0] = 16'h3421;  // 21 34
        mem.ram[1] = 16'h0112;  // 12 01
        mem.ram[2] = 16'h0034;  // 34 00
        mem.ram[3] = 16'h7608;  // 08 76
        reset_cpu;
        wait_halt_or_timeout(100);
        check_reg("H", cpu_h, 8'h12);
        check_reg("L", cpu_l, 8'h00);
        if (cpu.f_carry !== 1'b0) begin
            $display("  FAIL: CY should be 0"); test_passed = 0;
        end else $display("  OK:   CY = 0");
        report(47);

        // ── Test 48: DSUB (with borrow) ───────────────────
        $display("\n--- Test 48: DSUB (borrow) ---");
        clear_mem;
        // LXI H,0010h; LXI B,0020h; DSUB; HLT
        mem.ram[0] = 16'h1021;  // 21 10
        mem.ram[1] = 16'h0100;  // 00 01
        mem.ram[2] = 16'h0020;  // 20 00
        mem.ram[3] = 16'h7608;  // 08 76
        reset_cpu;
        wait_halt_or_timeout(100);
        check_reg("H", cpu_h, 8'hFF);
        check_reg("L", cpu_l, 8'hF0);
        if (cpu.f_carry !== 1'b1) begin
            $display("  FAIL: CY should be 1"); test_passed = 0;
        end else $display("  OK:   CY = 1");
        report(48);

        // ── Test 49: ARHL (negative) ──────────────────────
        $display("\n--- Test 49: ARHL (negative) ---");
        clear_mem;
        // LXI H,8000h; ARHL; HLT
        mem.ram[0] = 16'h0021;  // 21 00
        mem.ram[1] = 16'h1080;  // 80 10
        mem.ram[2] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(100);
        check_reg("H", cpu_h, 8'hC0);
        check_reg("L", cpu_l, 8'h00);
        if (cpu.f_carry !== 1'b0) begin
            $display("  FAIL: CY should be 0"); test_passed = 0;
        end else $display("  OK:   CY = 0");
        report(49);

        // ── Test 50: ARHL (positive, CY=1) ────────────────
        $display("\n--- Test 50: ARHL (positive) ---");
        clear_mem;
        // LXI H,0001h; ARHL; HLT
        mem.ram[0] = 16'h0121;  // 21 01
        mem.ram[1] = 16'h1000;  // 00 10
        mem.ram[2] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(100);
        check_reg("H", cpu_h, 8'h00);
        check_reg("L", cpu_l, 8'h00);
        if (cpu.f_carry !== 1'b1) begin
            $display("  FAIL: CY should be 1"); test_passed = 0;
        end else $display("  OK:   CY = 1");
        report(50);

        // ── Test 51: RDEL (rotate DE left through carry) ──
        $display("\n--- Test 51: RDEL ---");
        clear_mem;
        // STC; LXI D,8001h; RDEL; HLT
        mem.ram[0] = 16'h1137;  // 37 11
        mem.ram[1] = 16'h8001;  // 01 80
        mem.ram[2] = 16'h7618;  // 18 76
        reset_cpu;
        wait_halt_or_timeout(100);
        check_reg("D", cpu_d, 8'h00);
        check_reg("E", cpu_e, 8'h03);
        if (cpu.f_carry !== 1'b1) begin
            $display("  FAIL: CY should be 1"); test_passed = 0;
        end else $display("  OK:   CY = 1");
        if (cpu.f_v !== 1'b1) begin
            $display("  FAIL: V should be 1"); test_passed = 0;
        end else $display("  OK:   V = 1");
        report(51);

        // ── Test 52: LDHI (DE = HL + imm8) ────────────────
        $display("\n--- Test 52: LDHI ---");
        clear_mem;
        // LXI H,1000h; LDHI 5; HLT
        mem.ram[0] = 16'h0021;  // 21 00
        mem.ram[1] = 16'h2810;  // 10 28
        mem.ram[2] = 16'h7605;  // 05 76
        reset_cpu;
        wait_halt_or_timeout(100);
        check_reg("D", cpu_d, 8'h10);
        check_reg("E", cpu_e, 8'h05);
        report(52);

        // ── Test 53: LDSI (DE = SP + imm8) ────────────────
        $display("\n--- Test 53: LDSI ---");
        clear_mem;
        // LXI SP,2000h; LDSI 10h; HLT
        mem.ram[0] = 16'h0031;  // 31 00
        mem.ram[1] = 16'h3820;  // 20 38
        mem.ram[2] = 16'h7610;  // 10 76
        reset_cpu;
        wait_halt_or_timeout(100);
        check_reg("D", cpu_d, 8'h20);
        check_reg("E", cpu_e, 8'h10);
        report(53);

        // ── Test 54: SHLX (store HL indirect via DE) ──────
        $display("\n--- Test 54: SHLX ---");
        clear_mem;
        // LXI D,0050h; LXI H,ABCDh; SHLX; HLT
        mem.ram[0] = 16'h5011;  // 11 50
        mem.ram[1] = 16'h2100;  // 00 21
        mem.ram[2] = 16'hABCD;  // CD AB
        mem.ram[3] = 16'h76D9;  // D9 76
        reset_cpu;
        wait_halt_or_timeout(100);
        if (mem.ram[8'h28][7:0] !== 8'hCD) begin
            $display("  FAIL: mem[0050] = 0x%02x, expected 0xCD", mem.ram[8'h28][7:0]);
            test_passed = 0;
        end else $display("  OK:   mem[0050] = 0xCD");
        if (mem.ram[8'h28][15:8] !== 8'hAB) begin
            $display("  FAIL: mem[0051] = 0x%02x, expected 0xAB", mem.ram[8'h28][15:8]);
            test_passed = 0;
        end else $display("  OK:   mem[0051] = 0xAB");
        report(54);

        // ── Test 55: LHLX (load HL indirect via DE) ───────
        $display("\n--- Test 55: LHLX ---");
        clear_mem;
        // LXI D,0050h; LHLX; HLT
        mem.ram[0] = 16'h5011;  // 11 50
        mem.ram[1] = 16'hED00;  // 00 ED
        mem.ram[2] = 16'h0076;  // 76 00
        mem.ram[8'h28] = 16'h3456;  // pre-store: addr 0x0050 = 56h, 0x0051 = 34h
        reset_cpu;
        wait_halt_or_timeout(100);
        check_reg("H", cpu_h, 8'h34);
        check_reg("L", cpu_l, 8'h56);
        report(55);

        // ── Test 56: RSTV (V=1, taken) ────────────────────
        $display("\n--- Test 56: RSTV (taken) ---");
        clear_mem;
        // LXI SP,0100h; MVI A,7Fh; ADI 01h; RSTV; HLT
        // At 0x0040: MVI A,99h; RET
        mem.ram[0] = 16'h0031;   // 31 00
        mem.ram[1] = 16'h3E01;   // 01 3E
        mem.ram[2] = 16'hC67F;   // 7F C6
        mem.ram[3] = 16'hCB01;   // 01 CB
        mem.ram[4] = 16'h0076;   // 76 00
        mem.ram[8'h20] = 16'h993E;  // 3E 99
        mem.ram[8'h21] = 16'h00C9;  // C9 00
        reset_cpu;
        wait_halt_or_timeout(200);
        check_reg("A", cpu_a, 8'h99);
        report(56);

        // ── Test 57: RSTV (V=0, NOP) ──────────────────────
        $display("\n--- Test 57: RSTV (not taken) ---");
        clear_mem;
        // MVI A,01h; ADI 01h; RSTV; HLT
        mem.ram[0] = 16'h013E;   // 3E 01
        mem.ram[1] = 16'h01C6;   // C6 01
        mem.ram[2] = 16'h76CB;   // CB 76
        reset_cpu;
        wait_halt_or_timeout(100);
        check_reg("A", cpu_a, 8'h02);
        report(57);

        // ── Test 58: JX5 (X5=1, taken) ────────────────────
        $display("\n--- Test 58: JX5 (taken) ---");
        clear_mem;
        // LXI H,FFFFh; INX H; JX5 0010h; HLT
        // At 0x0010: MVI A,55h; HLT
        mem.ram[0] = 16'hFF21;   // 21 FF
        mem.ram[1] = 16'h23FF;   // FF 23
        mem.ram[2] = 16'h10FD;   // FD 10
        mem.ram[3] = 16'h7600;   // 00 76
        mem.ram[8'h08] = 16'h553E;  // 3E 55
        mem.ram[8'h09] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(100);
        check_reg("A", cpu_a, 8'h55);
        report(58);

        // ── Test 59: JNX5 (X5=0, taken) ───────────────────
        $display("\n--- Test 59: JNX5 (taken) ---");
        clear_mem;
        // LXI H,0000h; INX H; JNX5 0010h; HLT
        // At 0x0010: MVI A,66h; HLT
        mem.ram[0] = 16'h0021;   // 21 00
        mem.ram[1] = 16'h2300;   // 00 23
        mem.ram[2] = 16'h10DD;   // DD 10
        mem.ram[3] = 16'h7600;   // 00 76
        mem.ram[8'h08] = 16'h663E;  // 3E 66
        mem.ram[8'h09] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(100);
        check_reg("A", cpu_a, 8'h66);
        report(59);

        // ── Test 60: PSW round-trip with V flag ────────────
        $display("\n--- Test 60: PSW V flag round-trip ---");
        clear_mem;
        // LXI SP,0100h; MVI A,7Fh; ADI 01h; PUSH PSW; XRA A; POP PSW; HLT
        mem.ram[0] = 16'h0031;   // 31 00
        mem.ram[1] = 16'h3E01;   // 01 3E
        mem.ram[2] = 16'hC67F;   // 7F C6
        mem.ram[3] = 16'hF501;   // 01 F5
        mem.ram[4] = 16'hF1AF;   // AF F1
        mem.ram[5] = 16'h0076;   // 76 00
        reset_cpu;
        wait_halt_or_timeout(200);
        if (cpu.f_v !== 1'b1) begin
            $display("  FAIL: V should be 1"); test_passed = 0;
        end else $display("  OK:   V = 1");
        check_reg("A", cpu_a, 8'h80);
        report(60);

        $display("=== Old i8085: %0d PASS, %0d FAIL ===", pass_count, fail_count);
        $finish;
    end

endmodule
