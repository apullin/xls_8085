// j8085_tb.v - Testbench for j8085 pipelined CPU core
//
// Phase 1 tests:
//   Test 1: NOP → HLT (basic pipeline flow)
//   Test 2: MVI A, 0x55 → HLT (immediate load)
//   Test 3: MVI A, 0x10 → NOP → MVI B, 0x20 → NOP → ADD B → HLT
//           (ALU with NOPs to avoid hazards)
//   Test 4: MVI A, 0xAA → NOP → MOV B, A → HLT
//   Test 5: MVI A, 0xFF → NOP → XRA A → HLT (Z flag)
//
// Phase 2 tests (forwarding, no NOPs needed):
//   Test 6: MVI A,10h; MVI B,20h; ADD B; HLT (back-to-back forwarding)
//   Test 7: MVI A,01h; MVI B,02h; ADD B; ADD B; HLT (ALU chain)
//   Test 8: MVI A,AAh; MOV B,A; HLT (MOV forwarding)
//   Test 9: MVI B,FFh; INR B; HLT (INR + forwarding, Z flag)
//   Test 10: MVI C,01h; DCR C; HLT (DCR + forwarding, Z flag)
//   Test 11: MVI A,55h; CMA; HLT (CMA + forwarding)
//   Test 12: STC; CMC; HLT (flag ops)
//   Test 13: STC; MVI A,10h; MVI B,20h; ADC B; HLT (ADC with carry)
//   Test 14: MVI A,85h; RLC; HLT (rotate + forwarding)
//   Test 15: MVI A,10h; MVI B,05h; ADD B; SUB B; HLT (ADD/SUB chain)
//
// Phase 3 tests (branches):
//   Test 16: JMP forward (skip instruction)
//   Test 17: JZ not taken (Z=0 at reset)
//   Test 18: JZ taken with flag forwarding (XRA A; JZ)
//   Test 19: Loop: MVI B,03h; DCR B; JNZ loop; HLT
//   Test 20: PCHL (jump to HL)
//
// Phase 4 tests (memory operations):
//   Test 21: LXI H + MVI M + MOV A,M (basic HL indirect)
//   Test 22: STA + LDA (direct address)
//   Test 23: LXI B + STAX B + LDAX B
//   Test 24: LXI D + STAX D + LDAX D
//   Test 25: ADD M (ALU with memory operand)
//   Test 26: CMP M (flags only, no register write)
//   Test 27: INR M (read-modify-write)
//   Test 28: DCR M (read-modify-write)
//   Test 29: LHLD (load HL from direct addr)
//   Test 30: SHLD (store HL to direct addr)
//   Test 31: SUB M chain (forwarding after mem load)
//
// Phase 5 tests (stack + subroutines):
//   Test 32: PUSH B + POP D (register pair via stack)
//   Test 33: CALL + RET (subroutine call and return)
//   Test 34: PUSH PSW + POP PSW (flags round-trip)
//   Test 35: RST 1 (restart vector + return)
//   Test 36: CC (conditional call, taken)
//   Test 37: SPHL (SP = HL)
//   Test 38: XTHL (swap HL with stack top)
//
// Phase 6 tests (16-bit ops, I/O, misc):
//   Test 39: INX H (16-bit increment with carry propagation)
//   Test 40: DCX D (16-bit decrement with borrow)
//   Test 41: DAD B (HL += BC with carry)
//   Test 42: XCHG (swap DE ↔ HL)
//   Test 43: EI / DI
//   Test 44: SIM + RIM (set/read interrupt masks)
//   Test 45: INX SP
//   Test 46: DAD H (HL *= 2)
//
// Phase 7 tests (interrupts):
//   Test 47: HLT wakeup by maskable interrupt
//   Test 48: EI delay (interrupt deferred past next instruction)
//   Test 49: TRAP (non-maskable, ignores DI)
//
// Phase 8 tests (integration):
//   Test 50: OUT F0h / OUT F1h (bank register capture)

`timescale 1ns / 1ps

module j8085_tb;

    parameter CLK_PERIOD = 20;  // 50 MHz for simulation

    reg         clk;
    reg         reset_n;

    // Memory bus
    wire [15:0] bus_addr;
    wire [7:0]  bus_data_out;
    wire        bus_rd;
    wire        bus_wr;
    wire [7:0]  bus_data_in;
    wire        bus_ready;

    // Stack write bus
    wire [15:0] stack_wr_addr;
    wire [7:0]  stack_wr_data_lo;
    wire [7:0]  stack_wr_data_hi;
    wire        stack_wr;

    // Status outputs
    wire [15:0] cpu_pc, cpu_sp;
    wire [7:0]  cpu_a, cpu_b, cpu_c, cpu_d, cpu_e, cpu_h, cpu_l;
    wire        cpu_halted, cpu_inte, cpu_flag_z, cpu_flag_c;
    wire        cpu_mask_55, cpu_mask_65, cpu_mask_75;
    wire        cpu_rst75_pending, cpu_sod;

    // Unused I/O
    wire [7:0]  io_port, io_data_out;
    wire        io_rd, io_wr;

    // Interrupt signals (directly driven by tests)
    reg         tb_int_req;
    reg  [15:0] tb_int_vector;
    reg         tb_int_is_trap;
    wire        cpu_int_ack;

    // ── DUT ────────────────────────────────────────────
    j8085_cpu cpu (
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
        .int_req(tb_int_req), .int_vector(tb_int_vector), .int_is_trap(tb_int_is_trap), .int_ack(cpu_int_ack),
        .sid(1'b0), .rst55_level(1'b0), .rst65_level(1'b0),
        .pc(cpu_pc), .sp(cpu_sp),
        .reg_a(cpu_a), .reg_b(cpu_b), .reg_c(cpu_c),
        .reg_d(cpu_d), .reg_e(cpu_e), .reg_h(cpu_h), .reg_l(cpu_l),
        .halted(cpu_halted), .inte(cpu_inte),
        .flag_z(cpu_flag_z), .flag_c(cpu_flag_c),
        .mask_55(cpu_mask_55), .mask_65(cpu_mask_65), .mask_75(cpu_mask_75),
        .rst75_pending(cpu_rst75_pending), .sod(cpu_sod)
    );

    // ── Memory ─────────────────────────────────────────
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

    // ── Clock ──────────────────────────────────────────
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ── Test infrastructure ────────────────────────────
    integer cycle;
    integer test_num;
    integer pass_count;
    integer fail_count;
    reg     test_passed;

    task reset_cpu;
        begin
            reset_n = 0;
            tb_int_req = 0;
            tb_int_vector = 16'h0000;
            tb_int_is_trap = 0;
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
                if (cycle <= 40 || cpu_halted) begin
                    $display("  cycle %3d: PC=%04x A=%02x B=%02x F=%05b ibuf_cnt=%0d id_v=%b id_op=%02x ex_v=%b ex_op=%02x halt=%b",
                             cycle, cpu_pc, cpu_a, cpu_b, cpu.r_flags,
                             cpu.ibuf_count, cpu.id_valid, cpu.id_opcode,
                             cpu.ex_valid, cpu.ex_opcode, cpu_halted);
                end
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
            end else begin
                $display("  OK:   %c = 0x%02x", name, actual);
            end
        end
    endtask

    task report;
        input integer tnum;
        begin
            if (test_passed) begin
                $display("  TEST %0d: PASS (%0d cycles)\n", tnum, cycle);
                pass_count = pass_count + 1;
            end else begin
                $display("  TEST %0d: FAIL\n", tnum);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ── Test programs ──────────────────────────────────
    initial begin
        $display("=== j8085 Pipeline Testbench (Phase 1-6) ===\n");
        pass_count = 0;
        fail_count = 0;

        // ────────────────────────────────────────────────
        // Test 1: NOP → HLT
        // ────────────────────────────────────────────────
        $display("--- Test 1: NOP -> HLT ---");
        clear_mem;
        // 0x00: 00 (NOP)
        // 0x01: 76 (HLT)
        mem.ram[0] = 16'h7600;  // byte 0 = 0x00 (NOP), byte 1 = 0x76 (HLT)
        reset_cpu;
        wait_halt_or_timeout(50);
        report(1);

        // ────────────────────────────────────────────────
        // Test 2: MVI A, 0x55 → HLT
        // ────────────────────────────────────────────────
        $display("--- Test 2: MVI A, 0x55 -> HLT ---");
        clear_mem;
        // 0x00: 3E (MVI A)
        // 0x01: 55 (immediate)
        // 0x02: 76 (HLT)
        mem.ram[0] = 16'h553E;  // bytes 0-1: 3E 55
        mem.ram[1] = 16'h0076;  // bytes 2-3: 76 00
        reset_cpu;
        wait_halt_or_timeout(50);
        check_reg("A", cpu_a, 8'h55);
        report(2);

        // ────────────────────────────────────────────────
        // Test 3: MVI A,10 → NOP → MVI B,20 → NOP → ADD B → HLT
        // (NOPs inserted to avoid data hazards in phase 1)
        // ────────────────────────────────────────────────
        $display("--- Test 3: MVI A,10h; NOP; MVI B,20h; NOP; ADD B; HLT ---");
        clear_mem;
        // 0x00: 3E (MVI A)
        // 0x01: 10 (immediate)
        // 0x02: 00 (NOP)
        // 0x03: 06 (MVI B)
        // 0x04: 20 (immediate)
        // 0x05: 00 (NOP)
        // 0x06: 80 (ADD B)
        // 0x07: 76 (HLT)
        mem.ram[0] = 16'h103E;  // bytes 0-1: 3E 10
        mem.ram[1] = 16'h0600;  // bytes 2-3: 00 06
        mem.ram[2] = 16'h0020;  // bytes 4-5: 20 00
        mem.ram[3] = 16'h7680;  // bytes 6-7: 80 76
        reset_cpu;
        wait_halt_or_timeout(80);
        check_reg("A", cpu_a, 8'h30);
        check_reg("B", cpu_b, 8'h20);
        report(3);

        // ────────────────────────────────────────────────
        // Test 4: MOV B, A (register transfer)
        // MVI A, 0xAA → NOP → MOV B, A → HLT
        // ────────────────────────────────────────────────
        $display("--- Test 4: MVI A,AAh; NOP; MOV B,A; HLT ---");
        clear_mem;
        // 0x00: 3E (MVI A)
        // 0x01: AA (immediate)
        // 0x02: 00 (NOP)
        // 0x03: 47 (MOV B,A)
        // 0x04: 76 (HLT)
        mem.ram[0] = 16'hAA3E;  // bytes 0-1: 3E AA
        mem.ram[1] = 16'h4700;  // bytes 2-3: 00 47
        mem.ram[2] = 16'h0076;  // bytes 4-5: 76 00
        reset_cpu;
        wait_halt_or_timeout(50);
        check_reg("A", cpu_a, 8'hAA);
        check_reg("B", cpu_b, 8'hAA);
        report(4);

        // ────────────────────────────────────────────────
        // Test 5: XRA A (zero accumulator, sets Z flag)
        // MVI A, 0xFF → NOP → XRA A → HLT
        // ────────────────────────────────────────────────
        $display("--- Test 5: MVI A,FFh; NOP; XRA A; HLT ---");
        clear_mem;
        // 0x00: 3E (MVI A)
        // 0x01: FF (immediate)
        // 0x02: 00 (NOP)
        // 0x03: AF (XRA A)
        // 0x04: 76 (HLT)
        mem.ram[0] = 16'hFF3E;  // bytes 0-1: 3E FF
        mem.ram[1] = 16'hAF00;  // bytes 2-3: 00 AF
        mem.ram[2] = 16'h0076;  // bytes 4-5: 76 00
        reset_cpu;
        wait_halt_or_timeout(50);
        check_reg("A", cpu_a, 8'h00);
        if (!cpu_flag_z) begin
            $display("  FAIL: Z flag should be set");
            test_passed = 0;
        end else begin
            $display("  OK:   Z flag = 1");
        end
        report(5);

        // ================================================================
        // Phase 2: Forwarding tests (back-to-back, no NOPs)
        // ================================================================

        // ────────────────────────────────────────────────
        // Test 6: Back-to-back forwarding
        // MVI A,10h; MVI B,20h; ADD B; HLT
        // ────────────────────────────────────────────────
        $display("--- Test 6: MVI A,10h; MVI B,20h; ADD B; HLT (no NOPs) ---");
        clear_mem;
        // 0x00: 3E 10  MVI A,10h
        // 0x02: 06 20  MVI B,20h
        // 0x04: 80     ADD B
        // 0x05: 76     HLT
        mem.ram[0] = 16'h103E;
        mem.ram[1] = 16'h2006;
        mem.ram[2] = 16'h7680;
        reset_cpu;
        wait_halt_or_timeout(50);
        check_reg("A", cpu_a, 8'h30);
        check_reg("B", cpu_b, 8'h20);
        report(6);

        // ────────────────────────────────────────────────
        // Test 7: ALU chain (3 dependent ops)
        // MVI A,01h; MVI B,02h; ADD B; ADD B; HLT
        // A = 1+2=3, then 3+2=5
        // ────────────────────────────────────────────────
        $display("--- Test 7: MVI A,01h; MVI B,02h; ADD B; ADD B; HLT ---");
        clear_mem;
        // 0x00: 3E 01  MVI A,01h
        // 0x02: 06 02  MVI B,02h
        // 0x04: 80     ADD B
        // 0x05: 80     ADD B
        // 0x06: 76     HLT
        mem.ram[0] = 16'h013E;
        mem.ram[1] = 16'h0206;
        mem.ram[2] = 16'h8080;
        mem.ram[3] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(50);
        check_reg("A", cpu_a, 8'h05);
        check_reg("B", cpu_b, 8'h02);
        report(7);

        // ────────────────────────────────────────────────
        // Test 8: MOV forwarding (no NOP)
        // MVI A,AAh; MOV B,A; HLT
        // ────────────────────────────────────────────────
        $display("--- Test 8: MVI A,AAh; MOV B,A; HLT (no NOP) ---");
        clear_mem;
        // 0x00: 3E AA  MVI A,AAh
        // 0x02: 47     MOV B,A
        // 0x03: 76     HLT
        mem.ram[0] = 16'hAA3E;
        mem.ram[1] = 16'h7647;
        reset_cpu;
        wait_halt_or_timeout(50);
        check_reg("A", cpu_a, 8'hAA);
        check_reg("B", cpu_b, 8'hAA);
        report(8);

        // ────────────────────────────────────────────────
        // Test 9: INR with forwarding
        // MVI B,FFh; INR B; HLT → B=0x00, Z=1
        // ────────────────────────────────────────────────
        $display("--- Test 9: MVI B,FFh; INR B; HLT ---");
        clear_mem;
        // 0x00: 06 FF  MVI B,FFh
        // 0x02: 04     INR B
        // 0x03: 76     HLT
        mem.ram[0] = 16'hFF06;
        mem.ram[1] = 16'h7604;
        reset_cpu;
        wait_halt_or_timeout(50);
        check_reg("B", cpu_b, 8'h00);
        if (!cpu_flag_z) begin
            $display("  FAIL: Z flag should be set");
            test_passed = 0;
        end else begin
            $display("  OK:   Z flag = 1");
        end
        report(9);

        // ────────────────────────────────────────────────
        // Test 10: DCR to zero
        // MVI C,01h; DCR C; HLT → C=0x00, Z=1
        // ────────────────────────────────────────────────
        $display("--- Test 10: MVI C,01h; DCR C; HLT ---");
        clear_mem;
        // 0x00: 0E 01  MVI C,01h
        // 0x02: 0D     DCR C
        // 0x03: 76     HLT
        mem.ram[0] = 16'h010E;
        mem.ram[1] = 16'h760D;
        reset_cpu;
        wait_halt_or_timeout(50);
        check_reg("C", cpu_c, 8'h00);
        if (!cpu_flag_z) begin
            $display("  FAIL: Z flag should be set");
            test_passed = 0;
        end else begin
            $display("  OK:   Z flag = 1");
        end
        report(10);

        // ────────────────────────────────────────────────
        // Test 11: CMA with forwarding
        // MVI A,55h; CMA; HLT → A=0xAA
        // ────────────────────────────────────────────────
        $display("--- Test 11: MVI A,55h; CMA; HLT ---");
        clear_mem;
        // 0x00: 3E 55  MVI A,55h
        // 0x02: 2F     CMA
        // 0x03: 76     HLT
        mem.ram[0] = 16'h553E;
        mem.ram[1] = 16'h762F;
        reset_cpu;
        wait_halt_or_timeout(50);
        check_reg("A", cpu_a, 8'hAA);
        report(11);

        // ────────────────────────────────────────────────
        // Test 12: STC + CMC
        // STC; CMC; HLT → CY=0
        // ────────────────────────────────────────────────
        $display("--- Test 12: STC; CMC; HLT ---");
        clear_mem;
        // 0x00: 37     STC
        // 0x01: 3F     CMC
        // 0x02: 76     HLT
        mem.ram[0] = 16'h3F37;
        mem.ram[1] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(50);
        if (cpu_flag_c) begin
            $display("  FAIL: CY flag should be clear");
            test_passed = 0;
        end else begin
            $display("  OK:   CY flag = 0");
        end
        report(12);

        // ────────────────────────────────────────────────
        // Test 13: ADC with carry
        // STC; MVI A,10h; MVI B,20h; ADC B; HLT
        // ADC B = A + B + CY = 10h + 20h + 1 = 31h
        // ────────────────────────────────────────────────
        $display("--- Test 13: STC; MVI A,10h; MVI B,20h; ADC B; HLT ---");
        clear_mem;
        // 0x00: 37     STC
        // 0x01: 3E 10  MVI A,10h
        // 0x03: 06 20  MVI B,20h
        // 0x05: 88     ADC B
        // 0x06: 76     HLT
        mem.ram[0] = 16'h3E37;
        mem.ram[1] = 16'h0610;
        mem.ram[2] = 16'h8820;
        mem.ram[3] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(50);
        check_reg("A", cpu_a, 8'h31);
        report(13);

        // ────────────────────────────────────────────────
        // Test 14: RLC with forwarding
        // MVI A,85h; RLC; HLT → A=0x0B, CY=1
        // 85h = 10000101, rotate left: 00001011, CY=1
        // ────────────────────────────────────────────────
        $display("--- Test 14: MVI A,85h; RLC; HLT ---");
        clear_mem;
        // 0x00: 3E 85  MVI A,85h
        // 0x02: 07     RLC
        // 0x03: 76     HLT
        mem.ram[0] = 16'h853E;
        mem.ram[1] = 16'h7607;
        reset_cpu;
        wait_halt_or_timeout(50);
        check_reg("A", cpu_a, 8'h0B);
        if (!cpu_flag_c) begin
            $display("  FAIL: CY flag should be set");
            test_passed = 0;
        end else begin
            $display("  OK:   CY flag = 1");
        end
        report(14);

        // ────────────────────────────────────────────────
        // Test 15: ADD/SUB chain
        // MVI A,10h; MVI B,05h; ADD B; SUB B; HLT
        // A = 10h+05h=15h, then 15h-05h=10h
        // ────────────────────────────────────────────────
        $display("--- Test 15: MVI A,10h; MVI B,05h; ADD B; SUB B; HLT ---");
        clear_mem;
        // 0x00: 3E 10  MVI A,10h
        // 0x02: 06 05  MVI B,05h
        // 0x04: 80     ADD B
        // 0x05: 90     SUB B
        // 0x06: 76     HLT
        mem.ram[0] = 16'h103E;
        mem.ram[1] = 16'h0506;
        mem.ram[2] = 16'h9080;
        mem.ram[3] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(50);
        check_reg("A", cpu_a, 8'h10);
        check_reg("B", cpu_b, 8'h05);
        report(15);

        // ================================================================
        // Phase 3: Branch tests
        // ================================================================

        // ────────────────────────────────────────────────
        // Test 16: JMP forward (skip an instruction)
        // MVI A,11h; JMP 0007h; MVI A,22h; HLT
        // ────────────────────────────────────────────────
        $display("--- Test 16: MVI A,11h; JMP 0007h; MVI A,22h (skip); HLT ---");
        clear_mem;
        // 0x00: 3E 11    MVI A, 11h
        // 0x02: C3 07 00 JMP 0007h
        // 0x05: 3E 22    MVI A, 22h (skipped)
        // 0x07: 76       HLT
        mem.ram[0] = 16'h113E;  // 3E 11
        mem.ram[1] = 16'h07C3;  // C3 07
        mem.ram[2] = 16'h3E00;  // 00 3E
        mem.ram[3] = 16'h7622;  // 22 76
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'h11);
        report(16);

        // ────────────────────────────────────────────────
        // Test 17: JZ not taken (Z=0 at reset)
        // MVI A,01h; JZ 0007h; MVI B,42h; HLT
        // Z=0 after reset, JZ not taken, MVI B executes
        // ────────────────────────────────────────────────
        $display("--- Test 17: MVI A,01h; JZ 0007h (not taken); MVI B,42h; HLT ---");
        clear_mem;
        // 0x00: 3E 01    MVI A, 01h
        // 0x02: CA 07 00 JZ 0007h (not taken, Z=0)
        // 0x05: 06 42    MVI B, 42h
        // 0x07: 76       HLT
        mem.ram[0] = 16'h013E;  // 3E 01
        mem.ram[1] = 16'h07CA;  // CA 07
        mem.ram[2] = 16'h0600;  // 00 06
        mem.ram[3] = 16'h7642;  // 42 76
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'h01);
        check_reg("B", cpu_b, 8'h42);
        report(17);

        // ────────────────────────────────────────────────
        // Test 18: JZ taken with flag forwarding
        // XRA A; JZ 0006h; MVI A,FFh; HLT
        // XRA A sets Z=1, JZ taken (flags forwarded from EX)
        // ────────────────────────────────────────────────
        $display("--- Test 18: XRA A; JZ 0006h (taken, flag fwd); HLT ---");
        clear_mem;
        // 0x00: AF       XRA A
        // 0x01: CA 06 00 JZ 0006h
        // 0x04: 3E FF    MVI A, FFh (skipped)
        // 0x06: 76       HLT
        mem.ram[0] = 16'hCAAF;  // AF CA
        mem.ram[1] = 16'h0006;  // 06 00
        mem.ram[2] = 16'hFF3E;  // 3E FF
        mem.ram[3] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'h00);
        if (!cpu_flag_z) begin
            $display("  FAIL: Z flag should be set");
            test_passed = 0;
        end else begin
            $display("  OK:   Z flag = 1");
        end
        report(18);

        // ────────────────────────────────────────────────
        // Test 19: Loop with DCR + JNZ
        // MVI B,03h; loop: DCR B; JNZ loop; HLT
        // B: 3→2→1→0 (3 iterations), Z=1 at end
        // ────────────────────────────────────────────────
        $display("--- Test 19: MVI B,03h; loop: DCR B; JNZ loop; HLT ---");
        clear_mem;
        // 0x00: 06 03    MVI B, 03h
        // 0x02: 05       DCR B
        // 0x03: C2 02 00 JNZ 0002h
        // 0x06: 76       HLT
        mem.ram[0] = 16'h0306;  // 06 03
        mem.ram[1] = 16'hC205;  // 05 C2
        mem.ram[2] = 16'h0002;  // 02 00
        mem.ram[3] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(200);
        check_reg("B", cpu_b, 8'h00);
        if (!cpu_flag_z) begin
            $display("  FAIL: Z flag should be set");
            test_passed = 0;
        end else begin
            $display("  OK:   Z flag = 1");
        end
        report(19);

        // ────────────────────────────────────────────────
        // Test 20: PCHL (jump to address in HL)
        // MVI A,42h; MVI H,00h; MVI L,09h; PCHL; MVI A,FFh; HLT
        // ────────────────────────────────────────────────
        $display("--- Test 20: MVI A,42h; MVI H,00h; MVI L,09h; PCHL; HLT ---");
        clear_mem;
        // 0x00: 3E 42    MVI A, 42h
        // 0x02: 26 00    MVI H, 00h
        // 0x04: 2E 09    MVI L, 09h
        // 0x06: E9       PCHL → jump to 0x0009
        // 0x07: 3E FF    MVI A, FFh (skipped)
        // 0x09: 76       HLT
        mem.ram[0] = 16'h423E;  // 3E 42
        mem.ram[1] = 16'h0026;  // 26 00
        mem.ram[2] = 16'h092E;  // 2E 09
        mem.ram[3] = 16'h3EE9;  // E9 3E
        mem.ram[4] = 16'h76FF;  // FF 76
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'h42);
        report(20);

        // ================================================================
        // Phase 4: Memory operation tests
        // ================================================================

        // ────────────────────────────────────────────────
        // Test 21: LXI H + MVI M + MOV A,M
        // LXI H,0100h; MVI M,42h; MOV A,M; HLT
        // → A=0x42, mem[0x100]=0x42
        // ────────────────────────────────────────────────
        $display("--- Test 21: LXI H,0100h; MVI M,42h; MOV A,M; HLT ---");
        clear_mem;
        // 0x00: 21 00 01  LXI H, 0100h
        // 0x03: 36 42     MVI M, 42h
        // 0x05: 7E        MOV A, M
        // 0x06: 76        HLT
        mem.ram[0] = 16'h0021;  // 21 00
        mem.ram[1] = 16'h3601;  // 01 36
        mem.ram[2] = 16'h7E42;  // 42 7E
        mem.ram[3] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(100);
        check_reg("A", cpu_a, 8'h42);
        // Check memory contents
        if (mem.ram[16'h80] !== 16'h0042) begin
            $display("  FAIL: mem[0x0080] = 0x%04x, expected 0x0042", mem.ram[16'h80]);
            test_passed = 0;
        end else begin
            $display("  OK:   mem[0x100] = 0x42");
        end
        report(21);

        // ────────────────────────────────────────────────
        // Test 22: STA + LDA (direct address)
        // MVI A,99h; STA 0100h; MVI A,00h; LDA 0100h; HLT
        // → A=0x99
        // ────────────────────────────────────────────────
        $display("--- Test 22: MVI A,99h; STA 0100h; MVI A,00h; LDA 0100h; HLT ---");
        clear_mem;
        // 0x00: 3E 99     MVI A, 99h
        // 0x02: 32 00 01  STA 0100h
        // 0x05: 3E 00     MVI A, 00h
        // 0x07: 3A 00 01  LDA 0100h
        // 0x0A: 76        HLT
        mem.ram[0] = 16'h993E;  // 3E 99
        mem.ram[1] = 16'h0032;  // 32 00
        mem.ram[2] = 16'h3E01;  // 01 3E
        mem.ram[3] = 16'h3A00;  // 00 3A
        mem.ram[4] = 16'h0100;  // 00 01
        mem.ram[5] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h99);
        report(22);

        // ────────────────────────────────────────────────
        // Test 23: LXI B + STAX B + LDAX B
        // LXI B,0100h; MVI A,ABh; STAX B; MVI A,00h; LDAX B; HLT
        // → A=0xAB
        // ────────────────────────────────────────────────
        $display("--- Test 23: LXI B; STAX B; LDAX B; HLT ---");
        clear_mem;
        // 0x00: 01 00 01  LXI B, 0100h
        // 0x03: 3E AB     MVI A, ABh
        // 0x05: 02        STAX B
        // 0x06: 3E 00     MVI A, 00h
        // 0x08: 0A        LDAX B
        // 0x09: 76        HLT
        mem.ram[0] = 16'h0001;  // 01 00
        mem.ram[1] = 16'h3E01;  // 01 3E
        mem.ram[2] = 16'h02AB;  // AB 02
        mem.ram[3] = 16'h003E;  // 3E 00
        mem.ram[4] = 16'h760A;  // 0A 76
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'hAB);
        report(23);

        // ────────────────────────────────────────────────
        // Test 24: LXI D + STAX D + LDAX D
        // LXI D,0100h; MVI A,CDh; STAX D; MVI A,00h; LDAX D; HLT
        // → A=0xCD
        // ────────────────────────────────────────────────
        $display("--- Test 24: LXI D; STAX D; LDAX D; HLT ---");
        clear_mem;
        // 0x00: 11 00 01  LXI D, 0100h
        // 0x03: 3E CD     MVI A, CDh
        // 0x05: 12        STAX D
        // 0x06: 3E 00     MVI A, 00h
        // 0x08: 1A        LDAX D
        // 0x09: 76        HLT
        mem.ram[0] = 16'h0011;  // 11 00
        mem.ram[1] = 16'h3E01;  // 01 3E
        mem.ram[2] = 16'h12CD;  // CD 12
        mem.ram[3] = 16'h003E;  // 3E 00
        mem.ram[4] = 16'h761A;  // 1A 76
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'hCD);
        report(24);

        // ────────────────────────────────────────────────
        // Test 25: ADD M (ALU with memory operand)
        // LXI H,0100h; MVI M,10h; MVI A,20h; ADD M; HLT
        // → A=0x30
        // ────────────────────────────────────────────────
        $display("--- Test 25: LXI H; MVI M,10h; MVI A,20h; ADD M; HLT ---");
        clear_mem;
        // 0x00: 21 00 01  LXI H, 0100h
        // 0x03: 36 10     MVI M, 10h
        // 0x05: 3E 20     MVI A, 20h
        // 0x07: 86        ADD M
        // 0x08: 76        HLT
        mem.ram[0] = 16'h0021;  // 21 00
        mem.ram[1] = 16'h3601;  // 01 36
        mem.ram[2] = 16'h3E10;  // 10 3E
        mem.ram[3] = 16'h8620;  // 20 86
        mem.ram[4] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h30);
        report(25);

        // ────────────────────────────────────────────────
        // Test 26: CMP M (flags only)
        // LXI H,0100h; MVI M,20h; MVI A,20h; CMP M; HLT
        // → A=0x20 (unchanged), Z=1 (equal)
        // ────────────────────────────────────────────────
        $display("--- Test 26: LXI H; MVI M,20h; MVI A,20h; CMP M; HLT ---");
        clear_mem;
        // 0x00: 21 00 01  LXI H, 0100h
        // 0x03: 36 20     MVI M, 20h
        // 0x05: 3E 20     MVI A, 20h
        // 0x07: BE        CMP M
        // 0x08: 76        HLT
        mem.ram[0] = 16'h0021;  // 21 00
        mem.ram[1] = 16'h3601;  // 01 36
        mem.ram[2] = 16'h3E20;  // 20 3E
        mem.ram[3] = 16'hBE20;  // 20 BE
        mem.ram[4] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h20);
        if (!cpu_flag_z) begin
            $display("  FAIL: Z flag should be set (A == M)");
            test_passed = 0;
        end else begin
            $display("  OK:   Z flag = 1");
        end
        report(26);

        // ────────────────────────────────────────────────
        // Test 27: INR M (read-modify-write)
        // LXI H,0100h; MVI M,FFh; INR M; MOV A,M; HLT
        // → A=0x00 (0xFF+1=0x00), Z=1
        // ────────────────────────────────────────────────
        $display("--- Test 27: LXI H; MVI M,FFh; INR M; MOV A,M; HLT ---");
        clear_mem;
        // 0x00: 21 00 01  LXI H, 0100h
        // 0x03: 36 FF     MVI M, FFh
        // 0x05: 34        INR M
        // 0x06: 7E        MOV A, M
        // 0x07: 76        HLT
        mem.ram[0] = 16'h0021;  // 21 00
        mem.ram[1] = 16'h3601;  // 01 36
        mem.ram[2] = 16'h34FF;  // FF 34
        mem.ram[3] = 16'h767E;  // 7E 76
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h00);
        if (!cpu_flag_z) begin
            $display("  FAIL: Z flag should be set");
            test_passed = 0;
        end else begin
            $display("  OK:   Z flag = 1");
        end
        report(27);

        // ────────────────────────────────────────────────
        // Test 28: DCR M (read-modify-write)
        // LXI H,0100h; MVI M,01h; DCR M; MOV A,M; HLT
        // → A=0x00 (0x01-1=0x00), Z=1
        // ────────────────────────────────────────────────
        $display("--- Test 28: LXI H; MVI M,01h; DCR M; MOV A,M; HLT ---");
        clear_mem;
        // 0x00: 21 00 01  LXI H, 0100h
        // 0x03: 36 01     MVI M, 01h
        // 0x05: 35        DCR M
        // 0x06: 7E        MOV A, M
        // 0x07: 76        HLT
        mem.ram[0] = 16'h0021;  // 21 00
        mem.ram[1] = 16'h3601;  // 01 36
        mem.ram[2] = 16'h3501;  // 01 35
        mem.ram[3] = 16'h767E;  // 7E 76
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h00);
        if (!cpu_flag_z) begin
            $display("  FAIL: Z flag should be set");
            test_passed = 0;
        end else begin
            $display("  OK:   Z flag = 1");
        end
        report(28);

        // ────────────────────────────────────────────────
        // Test 29: LHLD (load HL from direct address)
        // Pre-store 0xABCD at addr 0x100: mem[0x80]={CD,AB}
        // LHLD 0100h; HLT → H=0xAB, L=0xCD
        // ────────────────────────────────────────────────
        $display("--- Test 29: LHLD 0100h; HLT ---");
        clear_mem;
        // 0x00: 2A 00 01  LHLD 0100h
        // 0x03: 76        HLT
        mem.ram[0] = 16'h002A;  // 2A 00
        mem.ram[1] = 16'h7601;  // 01 76
        // Pre-store data at addr 0x0100 (word addr 0x80)
        mem.ram[16'h80] = 16'hABCD;  // byte 0x100=0xCD, byte 0x101=0xAB
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("H", cpu_h, 8'hAB);
        check_reg("L", cpu_l, 8'hCD);
        report(29);

        // ────────────────────────────────────────────────
        // Test 30: SHLD (store HL to direct address)
        // LXI H,1234h; SHLD 0100h; HLT
        // → mem[0x100]=0x34, mem[0x101]=0x12
        // ────────────────────────────────────────────────
        $display("--- Test 30: LXI H,1234h; SHLD 0100h; HLT ---");
        clear_mem;
        // 0x00: 21 34 12  LXI H, 1234h
        // 0x03: 22 00 01  SHLD 0100h
        // 0x06: 76        HLT
        mem.ram[0] = 16'h3421;  // 21 34
        mem.ram[1] = 16'h2212;  // 12 22
        mem.ram[2] = 16'h0100;  // 00 01
        mem.ram[3] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("H", cpu_h, 8'h12);
        check_reg("L", cpu_l, 8'h34);
        // Check memory: word addr 0x80 should have {0x12, 0x34}
        if (mem.ram[16'h80] !== 16'h1234) begin
            $display("  FAIL: mem[0x80] = 0x%04x, expected 0x1234", mem.ram[16'h80]);
            test_passed = 0;
        end else begin
            $display("  OK:   mem[0x100..0x101] = 34 12");
        end
        report(30);

        // ────────────────────────────────────────────────
        // Test 31: SUB M chain (forwarding after mem load)
        // LXI H,0100h; MVI M,05h; MVI A,10h; SUB M; HLT
        // → A = 10h - 05h = 0Bh
        // ────────────────────────────────────────────────
        $display("--- Test 31: LXI H; MVI M,05h; MVI A,10h; SUB M; HLT ---");
        clear_mem;
        // 0x00: 21 00 01  LXI H, 0100h
        // 0x03: 36 05     MVI M, 05h
        // 0x05: 3E 10     MVI A, 10h
        // 0x07: 96        SUB M
        // 0x08: 76        HLT
        mem.ram[0] = 16'h0021;  // 21 00
        mem.ram[1] = 16'h3601;  // 01 36
        mem.ram[2] = 16'h3E05;  // 05 3E
        mem.ram[3] = 16'h9610;  // 10 96
        mem.ram[4] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h0B);
        report(31);

        // ────────────────────────────────────────────────
        // Phase 5 tests: Stack + subroutines
        // ────────────────────────────────────────────────

        // ────────────────────────────────────────────────
        // Test 32: PUSH B + POP D
        // LXI SP,0100h; LXI B,1234h; PUSH B; POP D; HLT
        // → D=12h, E=34h, SP=0100h
        // ────────────────────────────────────────────────
        $display("--- Test 32: LXI SP,0100h; LXI B,1234h; PUSH B; POP D; HLT ---");
        clear_mem;
        // 0x00: 31 00 01  LXI SP, 0100h
        // 0x03: 01 34 12  LXI B, 1234h
        // 0x06: C5        PUSH B
        // 0x07: D1        POP D
        // 0x08: 76        HLT
        mem.ram[0] = 16'h0031;  // 31 00
        mem.ram[1] = 16'h0101;  // 01 01   (byte2=00, byte3=01 for LXI SP, then byte0=01 for LXI B)
        // Wait, let me be more careful with the byte layout.
        // ram[word_addr] = {byte_at_odd_addr, byte_at_even_addr}
        // addr 0x00=31, 0x01=00 → ram[0] = {00, 31} = 16'h0031
        // addr 0x02=01, 0x03=01 → ram[1] = {01, 01} = 16'h0101
        // addr 0x04=34, 0x05=12 → ram[2] = {12, 34} = 16'h1234
        // addr 0x06=C5, 0x07=D1 → ram[3] = {D1, C5} = 16'hD1C5
        // addr 0x08=76, 0x09=00 → ram[4] = {00, 76} = 16'h0076
        mem.ram[0] = 16'h0031;
        mem.ram[1] = 16'h0101;
        mem.ram[2] = 16'h1234;
        mem.ram[3] = 16'hD1C5;
        mem.ram[4] = 16'h0076;
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("D", cpu_d, 8'h12);
        check_reg("E", cpu_e, 8'h34);
        if (cpu_sp !== 16'h0100) begin
            $display("  FAIL: SP = 0x%04x, expected 0x0100", cpu_sp);
            test_passed = 0;
        end else begin
            $display("  OK:   SP = 0x0100");
        end
        report(32);

        // ────────────────────────────────────────────────
        // Test 33: CALL + RET
        // 0x00: LXI SP,0100h; CALL 0010h; HLT
        // 0x10: MVI A,99h; RET
        // → A=99h, SP=0100h
        // ────────────────────────────────────────────────
        $display("--- Test 33: CALL 0010h; (sub) MVI A,99h; RET ---");
        clear_mem;
        // 0x00: 31 00 01  LXI SP, 0100h
        // 0x03: CD 10 00  CALL 0010h
        // 0x06: 76        HLT
        mem.ram[0] = 16'h0031;  // 31 00
        mem.ram[1] = 16'hCD01;  // 01 CD
        mem.ram[2] = 16'h0010;  // 10 00
        mem.ram[3] = 16'h0076;  // 76 00
        // At 0x10: 3E 99  MVI A, 99h
        // At 0x12: C9     RET
        mem.ram[8]  = 16'h993E;  // 3E 99
        mem.ram[9]  = 16'h00C9;  // C9 00
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h99);
        if (cpu_sp !== 16'h0100) begin
            $display("  FAIL: SP = 0x%04x, expected 0x0100", cpu_sp);
            test_passed = 0;
        end else begin
            $display("  OK:   SP = 0x0100");
        end
        report(33);

        // ────────────────────────────────────────────────
        // Test 34: PUSH PSW + POP PSW
        // LXI SP,0100h; MVI A,AAh; STC; PUSH PSW; XRA A; POP PSW; HLT
        // → A=AAh, CY=1
        // ────────────────────────────────────────────────
        $display("--- Test 34: PUSH PSW; XRA A; POP PSW; HLT ---");
        clear_mem;
        // 0x00: 31 00 01  LXI SP, 0100h
        // 0x03: 3E AA     MVI A, AAh
        // 0x05: 37        STC
        // 0x06: F5        PUSH PSW
        // 0x07: AF        XRA A   (clears A and flags)
        // 0x08: F1        POP PSW
        // 0x09: 76        HLT
        mem.ram[0] = 16'h0031;  // 31 00
        mem.ram[1] = 16'h3E01;  // 01 3E
        mem.ram[2] = 16'h37AA;  // AA 37
        mem.ram[3] = 16'hAFF5;  // F5 AF
        mem.ram[4] = 16'h76F1;  // F1 76
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'hAA);
        if (!cpu_flag_c) begin
            $display("  FAIL: CY flag should be set");
            test_passed = 0;
        end else begin
            $display("  OK:   CY flag = 1");
        end
        report(34);

        // ────────────────────────────────────────────────
        // Test 35: RST 1
        // 0x00: LXI SP,0100h; RST 1; HLT
        // 0x08: MVI A,88h; RET
        // → A=88h
        // ────────────────────────────────────────────────
        $display("--- Test 35: RST 1; (at 0008h) MVI A,88h; RET ---");
        clear_mem;
        // 0x00: 31 00 01  LXI SP, 0100h
        // 0x03: CF        RST 1
        // 0x04: 76        HLT
        mem.ram[0] = 16'h0031;  // 31 00
        mem.ram[1] = 16'hCF01;  // 01 CF
        mem.ram[2] = 16'h0076;  // 76 00
        // At 0x08: 3E 88  MVI A, 88h
        // At 0x0A: C9     RET
        mem.ram[4]  = 16'h883E;  // 3E 88
        mem.ram[5]  = 16'h00C9;  // C9 00
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h88);
        report(35);

        // ────────────────────────────────────────────────
        // Test 36: CC (conditional call, CY=1)
        // LXI SP,0100h; STC; CC 0020h; HLT
        // 0x20: MVI A,77h; RET
        // → A=77h (CC taken because CY=1)
        // ────────────────────────────────────────────────
        $display("--- Test 36: STC; CC 0020h; (sub) MVI A,77h; RET ---");
        clear_mem;
        // 0x00: 31 00 01  LXI SP, 0100h
        // 0x03: 37        STC
        // 0x04: DC 20 00  CC 0020h
        // 0x07: 76        HLT
        mem.ram[0] = 16'h0031;  // 31 00
        mem.ram[1] = 16'h3701;  // 01 37
        mem.ram[2] = 16'h20DC;  // DC 20
        mem.ram[3] = 16'h7600;  // 00 76
        // At 0x20: 3E 77  MVI A, 77h
        // At 0x22: C9     RET
        mem.ram[16] = 16'h773E;  // 3E 77
        mem.ram[17] = 16'h00C9;  // C9 00
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("A", cpu_a, 8'h77);
        report(36);

        // ────────────────────────────────────────────────
        // Test 37: SPHL
        // LXI H,1234h; SPHL; HLT
        // → SP=1234h
        // ────────────────────────────────────────────────
        $display("--- Test 37: LXI H,1234h; SPHL; HLT ---");
        clear_mem;
        // 0x00: 21 34 12  LXI H, 1234h
        // 0x03: F9        SPHL
        // 0x04: 76        HLT
        mem.ram[0] = 16'h3421;  // 21 34
        mem.ram[1] = 16'hF912;  // 12 F9
        mem.ram[2] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(120);
        if (cpu_sp !== 16'h1234) begin
            $display("  FAIL: SP = 0x%04x, expected 0x1234", cpu_sp);
            test_passed = 0;
        end else begin
            $display("  OK:   SP = 0x1234");
        end
        report(37);

        // ────────────────────────────────────────────────
        // Test 38: XTHL
        // LXI SP,0100h; LXI H,ABCDh; pre-store 5678h at SP; XTHL; HLT
        // → H=56h, L=78h, mem[0x100]={AB,CD}
        // ────────────────────────────────────────────────
        $display("--- Test 38: XTHL (swap HL with stack top) ---");
        clear_mem;
        // 0x00: 31 00 01  LXI SP, 0100h
        // 0x03: 21 CD AB  LXI H, ABCDh
        // 0x06: E3        XTHL
        // 0x07: 76        HLT
        mem.ram[0] = 16'h0031;  // 31 00
        mem.ram[1] = 16'h2101;  // 01 21
        mem.ram[2] = 16'hABCD;  // CD AB
        mem.ram[3] = 16'h76E3;  // E3 76
        // Pre-store 5678h at addr 0x100 (word addr 0x80)
        // byte 0x100=78h (L), byte 0x101=56h (H)
        mem.ram[16'h80] = 16'h5678;  // {56, 78}
        reset_cpu;
        wait_halt_or_timeout(120);
        check_reg("H", cpu_h, 8'h56);
        check_reg("L", cpu_l, 8'h78);
        // Check memory: old HL (ABCD) should be at stack
        if (mem.ram[16'h80] !== 16'hABCD) begin
            $display("  FAIL: mem[0x80] = 0x%04x, expected 0xABCD", mem.ram[16'h80]);
            test_passed = 0;
        end else begin
            $display("  OK:   mem[0x100..0x101] = CD AB");
        end
        report(38);

        // ────────────────────────────────────────────────
        // Phase 6 tests: 16-bit ops, I/O, EI/DI, RIM/SIM
        // ────────────────────────────────────────────────

        // ────────────────────────────────────────────────
        // Test 39: INX H
        // LXI H,00FFh; INX H; HLT → H=01h, L=00h
        // ────────────────────────────────────────────────
        $display("--- Test 39: LXI H,00FFh; INX H; HLT ---");
        clear_mem;
        // 0x00: 21 FF 00  LXI H, 00FFh
        // 0x03: 23        INX H
        // 0x04: 76        HLT
        mem.ram[0] = 16'hFF21;  // 21 FF
        mem.ram[1] = 16'h2300;  // 00 23
        mem.ram[2] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("H", cpu_h, 8'h01);
        check_reg("L", cpu_l, 8'h00);
        report(39);

        // ────────────────────────────────────────────────
        // Test 40: DCX D
        // LXI D,0100h; DCX D; HLT → D=00h, E=FFh
        // ────────────────────────────────────────────────
        $display("--- Test 40: LXI D,0100h; DCX D; HLT ---");
        clear_mem;
        // 0x00: 11 00 01  LXI D, 0100h
        // 0x03: 1B        DCX D
        // 0x04: 76        HLT
        mem.ram[0] = 16'h0011;  // 11 00
        mem.ram[1] = 16'h1B01;  // 01 1B
        mem.ram[2] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("D", cpu_d, 8'h00);
        check_reg("E", cpu_e, 8'hFF);
        report(40);

        // ────────────────────────────────────────────────
        // Test 41: DAD B (HL += BC, CY)
        // LXI H,8000h; LXI B,8001h; DAD B; HLT
        // → HL=0001h, CY=1 (overflow)
        // ────────────────────────────────────────────────
        $display("--- Test 41: DAD B (overflow → CY=1) ---");
        clear_mem;
        // 0x00: 21 00 80  LXI H, 8000h
        // 0x03: 01 01 80  LXI B, 8001h
        // 0x06: 09        DAD B
        // 0x07: 76        HLT
        mem.ram[0] = 16'h0021;  // 21 00
        mem.ram[1] = 16'h0180;  // 80 01
        mem.ram[2] = 16'h8001;  // 01 80
        mem.ram[3] = 16'h7609;  // 09 76
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("H", cpu_h, 8'h00);
        check_reg("L", cpu_l, 8'h01);
        if (!cpu_flag_c) begin
            $display("  FAIL: CY flag should be set");
            test_passed = 0;
        end else begin
            $display("  OK:   CY flag = 1");
        end
        report(41);

        // ────────────────────────────────────────────────
        // Test 42: XCHG (swap DE ↔ HL)
        // LXI D,1234h; LXI H,5678h; XCHG; HLT
        // → D=56h, E=78h, H=12h, L=34h
        // ────────────────────────────────────────────────
        $display("--- Test 42: XCHG ---");
        clear_mem;
        // 0x00: 11 34 12  LXI D, 1234h
        // 0x03: 21 78 56  LXI H, 5678h
        // 0x06: EB        XCHG
        // 0x07: 76        HLT
        mem.ram[0] = 16'h3411;  // 11 34
        mem.ram[1] = 16'h2112;  // 12 21
        mem.ram[2] = 16'h5678;  // 78 56
        mem.ram[3] = 16'h76EB;  // EB 76
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("D", cpu_d, 8'h56);
        check_reg("E", cpu_e, 8'h78);
        check_reg("H", cpu_h, 8'h12);
        check_reg("L", cpu_l, 8'h34);
        report(42);

        // ────────────────────────────────────────────────
        // Test 43: EI / DI
        // DI; HLT → inte=0
        // EI; HLT → inte=1
        // ────────────────────────────────────────────────
        $display("--- Test 43: EI; DI; EI; HLT ---");
        clear_mem;
        // 0x00: FB        EI
        // 0x01: F3        DI
        // 0x02: FB        EI
        // 0x03: 76        HLT
        mem.ram[0] = 16'hF3FB;  // FB F3
        mem.ram[1] = 16'h76FB;  // FB 76
        reset_cpu;
        wait_halt_or_timeout(60);
        if (!cpu_inte) begin
            $display("  FAIL: INTE should be set");
            test_passed = 0;
        end else begin
            $display("  OK:   INTE = 1");
        end
        report(43);

        // ────────────────────────────────────────────────
        // Test 44: SIM + RIM (set mask, read back)
        // MVI A,0Dh (MSE=1, M7.5=1, M6.5=0, M5.5=1); SIM; RIM; HLT
        // RIM result: {SID=0, I7.5=0, I6.5=0, I5.5=0, IE=0, M7.5=1, M6.5=0, M5.5=1}
        //           = 0000_0101 = 05h
        // ────────────────────────────────────────────────
        $display("--- Test 44: SIM(0Dh); RIM; HLT ---");
        clear_mem;
        // 0x00: 3E 0D     MVI A, 0Dh  (MSE=1, masks: 7.5=1, 6.5=0, 5.5=1)
        // 0x02: 30        SIM
        // 0x03: 20        RIM
        // 0x04: 76        HLT
        mem.ram[0] = 16'h0D3E;  // 3E 0D
        mem.ram[1] = 16'h2030;  // 30 20
        mem.ram[2] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu_a, 8'h05);
        report(44);

        // ────────────────────────────────────────────────
        // Test 45: INX SP
        // LXI SP,00FEh; INX SP; INX SP; HLT → SP=0100h
        // ────────────────────────────────────────────────
        $display("--- Test 45: INX SP ---");
        clear_mem;
        // 0x00: 31 FE 00  LXI SP, 00FEh
        // 0x03: 33        INX SP
        // 0x04: 33        INX SP
        // 0x05: 76        HLT
        mem.ram[0] = 16'hFE31;  // 31 FE
        mem.ram[1] = 16'h3300;  // 00 33
        mem.ram[2] = 16'h7633;  // 33 76
        reset_cpu;
        wait_halt_or_timeout(60);
        if (cpu_sp !== 16'h0100) begin
            $display("  FAIL: SP = 0x%04x, expected 0x0100", cpu_sp);
            test_passed = 0;
        end else begin
            $display("  OK:   SP = 0x0100");
        end
        report(45);

        // ────────────────────────────────────────────────
        // Test 46: DAD H (HL = HL + HL = HL*2)
        // LXI H,1234h; DAD H; HLT → HL=2468h, CY=0
        // ────────────────────────────────────────────────
        $display("--- Test 46: DAD H (HL*2) ---");
        clear_mem;
        // 0x00: 21 34 12  LXI H, 1234h
        // 0x03: 29        DAD H
        // 0x04: 76        HLT
        mem.ram[0] = 16'h3421;  // 21 34
        mem.ram[1] = 16'h2912;  // 12 29
        mem.ram[2] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("H", cpu_h, 8'h24);
        check_reg("L", cpu_l, 8'h68);
        if (cpu_flag_c) begin
            $display("  FAIL: CY flag should be clear");
            test_passed = 0;
        end else begin
            $display("  OK:   CY flag = 0");
        end
        report(46);

        // ────────────────────────────────────────────────
        // Phase 7 tests: Interrupts
        // ────────────────────────────────────────────────

        // ────────────────────────────────────────────────
        // Test 47: HLT wakeup by maskable interrupt
        // LXI SP,0100h; EI; HLT; HLT
        // ISR at 0x0020: MVI A,42h; RET
        // → A=42h, SP=0100h
        // ────────────────────────────────────────────────
        $display("--- Test 47: HLT wakeup by interrupt ---");
        clear_mem;
        // 0x00: 31 00 01  LXI SP, 0100h
        // 0x03: FB        EI
        // 0x04: 76        HLT  (first halt, interrupt wakes us)
        // 0x05: 76        HLT  (return point after ISR)
        mem.ram[0] = 16'h0031;  // 31 00
        mem.ram[1] = 16'hFB01;  // 01 FB
        mem.ram[2] = 16'h7676;  // 76 76
        // ISR at 0x0020 (word addr 16):
        // 0x20: 3E 42  MVI A, 42h
        // 0x22: C9     RET
        mem.ram[16] = 16'h423E;  // 3E 42
        mem.ram[17] = 16'h00C9;  // C9 00
        reset_cpu;
        wait_halt_or_timeout(60);
        // CPU halted at first HLT. Inject interrupt.
        tb_int_vector = 16'h0020;
        tb_int_req = 1'b1;
        @(posedge clk);
        @(posedge clk);
        tb_int_req = 1'b0;
        // Wait for ISR to run and return to second HLT
        cycle = 0;
        test_passed = 0;
        while (cycle < 120) begin
            @(posedge clk);
            cycle = cycle + 1;
            if (cpu_halted) begin
                test_passed = 1;
                cycle = 120;  // exit loop
            end
        end
        check_reg("A", cpu_a, 8'h42);
        if (cpu_sp !== 16'h0100) begin
            $display("  FAIL: SP = 0x%04x, expected 0x0100", cpu_sp);
            test_passed = 0;
        end else begin
            $display("  OK:   SP = 0x0100");
        end
        report(47);

        // ────────────────────────────────────────────────
        // Test 48: EI delay — interrupt deferred by 1 instruction
        // MVI A,10h; EI; SUB A; HLT; HLT
        // int_req asserted continuously. ISR: MVI A,FFh; RET
        // With EI delay: EI→SUB A (A=0)→int taken→ISR (A=FF)→HLT. A=FFh
        // Without delay: EI→int taken→ISR (A=FF)→SUB A (A=FE)→HLT. A=FEh
        // ────────────────────────────────────────────────
        $display("--- Test 48: EI delay (deferred by 1 instruction) ---");
        clear_mem;
        // 0x00: 31 00 01  LXI SP, 0100h
        // 0x03: 3E 10     MVI A, 10h
        // 0x05: FB        EI
        // 0x06: 97        SUB A
        // 0x07: 76        HLT
        // 0x08: 76        HLT
        mem.ram[0]  = 16'h0031;  // 31 00
        mem.ram[1]  = 16'h3E01;  // 01 3E
        mem.ram[2]  = 16'hFB10;  // 10 FB
        mem.ram[3]  = 16'h7697;  // 97 76
        mem.ram[4]  = 16'h0076;  // 76 00
        // ISR at 0x0030 (word addr 24):
        // 0x30: 3E FF  MVI A, FFh
        // 0x32: C9     RET
        mem.ram[24] = 16'hFF3E;  // 3E FF
        mem.ram[25] = 16'h00C9;  // C9 00
        reset_cpu;
        // Assert int_req continuously from the start with vector 0x30
        tb_int_vector = 16'h0030;
        tb_int_req = 1'b1;
        // Wait for halt (interrupt should fire after SUB A, handler runs, returns to HLT)
        wait_halt_or_timeout(120);
        tb_int_req = 1'b0;
        // With correct EI delay: SUB A executes (A=0), then ISR sets A=FF
        check_reg("A", cpu_a, 8'hFF);
        report(48);

        // ────────────────────────────────────────────────
        // Test 49: TRAP (non-maskable interrupt, ignores DI)
        // LXI SP,0100h; NOP; HLT; HLT
        // TRAP handler at 0x0024: MVI A,99h; RET
        // No EI — interrupts disabled. TRAP should still fire.
        // ────────────────────────────────────────────────
        $display("--- Test 49: TRAP (non-maskable) ---");
        clear_mem;
        // 0x00: 31 00 01  LXI SP, 0100h
        // 0x03: 00        NOP
        // 0x04: 76        HLT
        // 0x05: 76        HLT (return after TRAP handler)
        mem.ram[0] = 16'h0031;  // 31 00
        mem.ram[1] = 16'h0001;  // 01 00
        mem.ram[2] = 16'h7676;  // 76 76
        // TRAP handler at 0x0024 (word addr 18):
        // 0x24: 3E 99  MVI A, 99h
        // 0x26: C9     RET
        mem.ram[18] = 16'h993E;  // 3E 99
        mem.ram[19] = 16'h00C9;  // C9 00
        reset_cpu;
        wait_halt_or_timeout(60);
        // CPU halted (INTE=0, no EI). Inject TRAP.
        tb_int_vector = 16'h0024;
        tb_int_is_trap = 1'b1;
        tb_int_req = 1'b1;
        @(posedge clk);
        @(posedge clk);
        tb_int_req = 1'b0;
        tb_int_is_trap = 1'b0;
        // Wait for TRAP handler to run and return to second HLT
        cycle = 0;
        test_passed = 0;
        while (cycle < 120) begin
            @(posedge clk);
            cycle = cycle + 1;
            if (cpu_halted) begin
                test_passed = 1;
                cycle = 120;
            end
        end
        check_reg("A", cpu_a, 8'h99);
        if (!cpu_inte) begin
            $display("  OK:   INTE = 0 (TRAP does not re-enable)");
        end else begin
            $display("  FAIL: INTE should be 0 after TRAP");
            test_passed = 0;
        end
        report(49);

        // ────────────────────────────────────────────────
        // Phase 8 tests: Integration
        // ────────────────────────────────────────────────

        // ────────────────────────────────────────────────
        // Test 50: OUT F0h / OUT F1h (bank register capture)
        // MVI A,42h; OUT F0h; MVI A,05h; OUT F1h; HLT
        // → rom_bank=42h, ram_bank=5
        // ────────────────────────────────────────────────
        $display("--- Test 50: OUT F0h/F1h (bank registers) ---");
        clear_mem;
        // 0x00: 3E 42     MVI A, 42h
        // 0x02: D3 F0     OUT F0h
        // 0x04: 3E 05     MVI A, 05h
        // 0x06: D3 F1     OUT F1h
        // 0x08: 76        HLT
        mem.ram[0] = 16'h423E;  // 3E 42
        mem.ram[1] = 16'hF0D3;  // D3 F0
        mem.ram[2] = 16'h053E;  // 3E 05
        mem.ram[3] = 16'hF1D3;  // D3 F1
        mem.ram[4] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(60);
        if (cpu.rom_bank !== 8'h42) begin
            $display("  FAIL: rom_bank = 0x%02x, expected 0x42", cpu.rom_bank);
            test_passed = 0;
        end else begin
            $display("  OK:   rom_bank = 0x42");
        end
        if (cpu.ram_bank !== 3'd5) begin
            $display("  FAIL: ram_bank = %0d, expected 5", cpu.ram_bank);
            test_passed = 0;
        end else begin
            $display("  OK:   ram_bank = 5");
        end
        report(50);

        // ════════════════════════════════════════════════
        // Phase 9: Undocumented 8085 Instructions
        // ════════════════════════════════════════════════

        // ── Test 51: DSUB (HL = HL - BC, no borrow) ──────────
        $display("\n--- Test 51: DSUB (no borrow) ---");
        test_passed = 1;
        // LXI H,1234h; LXI B,0034h; DSUB; HLT
        mem.ram[0] = 16'h3421;  // 21 34
        mem.ram[1] = 16'h0112;  // 12 01
        mem.ram[2] = 16'h0034;  // 34 00
        mem.ram[3] = 16'h7608;  // 08 76
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("H", cpu.r_h, 8'h12);
        check_reg("L", cpu.r_l, 8'h00);
        if (cpu.r_flags[0] !== 1'b0) begin
            $display("  FAIL: CY should be 0"); test_passed = 0;
        end else $display("  OK:   CY = 0");
        report(51);

        // ── Test 52: DSUB (HL = HL - BC, with borrow) ───────
        $display("\n--- Test 52: DSUB (borrow) ---");
        test_passed = 1;
        // LXI H,0010h; LXI B,0020h; DSUB; HLT
        mem.ram[0] = 16'h1021;  // 21 10
        mem.ram[1] = 16'h0100;  // 00 01
        mem.ram[2] = 16'h0020;  // 20 00
        mem.ram[3] = 16'h7608;  // 08 76
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("H", cpu.r_h, 8'hFF);
        check_reg("L", cpu.r_l, 8'hF0);
        if (cpu.r_flags[0] !== 1'b1) begin
            $display("  FAIL: CY should be 1"); test_passed = 0;
        end else $display("  OK:   CY = 1");
        report(52);

        // ── Test 53: ARHL (arithmetic shift right HL, negative) ─
        $display("\n--- Test 53: ARHL (negative) ---");
        test_passed = 1;
        // LXI H,8000h; ARHL; HLT
        mem.ram[0] = 16'h0021;  // 21 00
        mem.ram[1] = 16'h1080;  // 80 10
        mem.ram[2] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("H", cpu.r_h, 8'hC0);
        check_reg("L", cpu.r_l, 8'h00);
        if (cpu.r_flags[0] !== 1'b0) begin
            $display("  FAIL: CY should be 0"); test_passed = 0;
        end else $display("  OK:   CY = 0");
        report(53);

        // ── Test 54: ARHL (positive, CY=1) ───────────────────
        $display("\n--- Test 54: ARHL (positive) ---");
        test_passed = 1;
        // LXI H,0001h; ARHL; HLT
        mem.ram[0] = 16'h0121;  // 21 01
        mem.ram[1] = 16'h1000;  // 00 10
        mem.ram[2] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("H", cpu.r_h, 8'h00);
        check_reg("L", cpu.r_l, 8'h00);
        if (cpu.r_flags[0] !== 1'b1) begin
            $display("  FAIL: CY should be 1"); test_passed = 0;
        end else $display("  OK:   CY = 1");
        report(54);

        // ── Test 55: RDEL (rotate DE left through carry) ─────
        $display("\n--- Test 55: RDEL ---");
        test_passed = 1;
        // STC; LXI D,8001h; RDEL; HLT
        mem.ram[0] = 16'h1137;  // 37 11
        mem.ram[1] = 16'h8001;  // 01 80
        mem.ram[2] = 16'h7618;  // 18 76
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("D", cpu.r_d, 8'h00);
        check_reg("E", cpu.r_e, 8'h03);
        if (cpu.r_flags[0] !== 1'b1) begin
            $display("  FAIL: CY should be 1"); test_passed = 0;
        end else $display("  OK:   CY = 1");
        if (cpu.r_flags[6] !== 1'b1) begin
            $display("  FAIL: V should be 1"); test_passed = 0;
        end else $display("  OK:   V = 1");
        report(55);

        // ── Test 56: LDHI (DE = HL + imm8) ──────────────────
        $display("\n--- Test 56: LDHI ---");
        test_passed = 1;
        // LXI H,1000h; LDHI 5; HLT
        mem.ram[0] = 16'h0021;  // 21 00
        mem.ram[1] = 16'h2810;  // 10 28
        mem.ram[2] = 16'h7605;  // 05 76
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("D", cpu.r_d, 8'h10);
        check_reg("E", cpu.r_e, 8'h05);
        report(56);

        // ── Test 57: LDSI (DE = SP + imm8) ──────────────────
        $display("\n--- Test 57: LDSI ---");
        test_passed = 1;
        // LXI SP,2000h; LDSI 10h; HLT
        mem.ram[0] = 16'h0031;  // 31 00
        mem.ram[1] = 16'h3820;  // 20 38
        mem.ram[2] = 16'h7610;  // 10 76
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("D", cpu.r_d, 8'h20);
        check_reg("E", cpu.r_e, 8'h10);
        report(57);

        // ── Test 58: SHLX (store HL indirect via DE) ────────
        $display("\n--- Test 58: SHLX ---");
        test_passed = 1;
        // LXI D,0050h; LXI H,ABCDh; SHLX; HLT
        mem.ram[0] = 16'h5011;  // 11 50
        mem.ram[1] = 16'h2100;  // 00 21
        mem.ram[2] = 16'hABCD;  // CD AB
        mem.ram[3] = 16'h76D9;  // D9 76
        reset_cpu;
        wait_halt_or_timeout(60);
        if (mem.ram[8'h28][7:0] !== 8'hCD) begin
            $display("  FAIL: mem[0050] = 0x%02x, expected 0xCD", mem.ram[8'h28][7:0]);
            test_passed = 0;
        end else $display("  OK:   mem[0050] = 0xCD");
        if (mem.ram[8'h28][15:8] !== 8'hAB) begin
            $display("  FAIL: mem[0051] = 0x%02x, expected 0xAB", mem.ram[8'h28][15:8]);
            test_passed = 0;
        end else $display("  OK:   mem[0051] = 0xAB");
        report(58);

        // ── Test 59: LHLX (load HL indirect via DE) ────────
        $display("\n--- Test 59: LHLX ---");
        test_passed = 1;
        // LXI D,0050h; LHLX; HLT
        mem.ram[0] = 16'h5011;  // 11 50
        mem.ram[1] = 16'hED00;  // 00 ED
        mem.ram[2] = 16'h0076;  // 76 00
        mem.ram[8'h28] = 16'h3456;  // pre-store: addr 0x0050 = 56h, 0x0051 = 34h
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("H", cpu.r_h, 8'h34);
        check_reg("L", cpu.r_l, 8'h56);
        report(59);

        // ── Test 60: RSTV (V=1, taken) ──────────────────────
        $display("\n--- Test 60: RSTV (taken) ---");
        test_passed = 1;
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
        wait_halt_or_timeout(80);
        check_reg("A", cpu.r_a, 8'h99);
        report(60);

        // ── Test 61: RSTV (V=0, NOP) ────────────────────────
        $display("\n--- Test 61: RSTV (not taken) ---");
        test_passed = 1;
        // MVI A,01h; ADI 01h; RSTV; HLT
        mem.ram[0] = 16'h013E;   // 3E 01
        mem.ram[1] = 16'h01C6;   // C6 01
        mem.ram[2] = 16'h76CB;   // CB 76
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu.r_a, 8'h02);
        report(61);

        // ── Test 62: JX5 (X5=1, taken) ──────────────────────
        $display("\n--- Test 62: JX5 (taken) ---");
        test_passed = 1;
        // LXI H,FFFFh; INX H; JX5 0010h; HLT
        // At 0x0010: MVI A,55h; HLT
        mem.ram[0] = 16'hFF21;   // 21 FF
        mem.ram[1] = 16'h23FF;   // FF 23
        mem.ram[2] = 16'h10FD;   // FD 10
        mem.ram[3] = 16'h7600;   // 00 76
        mem.ram[8'h08] = 16'h553E;  // 3E 55
        mem.ram[8'h09] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu.r_a, 8'h55);
        report(62);

        // ── Test 63: JNX5 (X5=0, taken) ─────────────────────
        $display("\n--- Test 63: JNX5 (taken) ---");
        test_passed = 1;
        // LXI H,0000h; INX H; JNX5 0010h; HLT
        // At 0x0010: MVI A,66h; HLT
        mem.ram[0] = 16'h0021;   // 21 00
        mem.ram[1] = 16'h2300;   // 00 23
        mem.ram[2] = 16'h10DD;   // DD 10
        mem.ram[3] = 16'h7600;   // 00 76
        mem.ram[8'h08] = 16'h663E;  // 3E 66
        mem.ram[8'h09] = 16'h0076;  // 76 00
        reset_cpu;
        wait_halt_or_timeout(60);
        check_reg("A", cpu.r_a, 8'h66);
        report(63);

        // ── Test 64: PSW round-trip with V flag ──────────────
        $display("\n--- Test 64: PSW V flag round-trip ---");
        test_passed = 1;
        // LXI SP,0100h; MVI A,7Fh; ADI 01h; PUSH PSW; XRA A; POP PSW; HLT
        mem.ram[0] = 16'h0031;   // 31 00
        mem.ram[1] = 16'h3E01;   // 01 3E
        mem.ram[2] = 16'hC67F;   // 7F C6
        mem.ram[3] = 16'hF501;   // 01 F5
        mem.ram[4] = 16'hF1AF;   // AF F1
        mem.ram[5] = 16'h0076;   // 76 00
        reset_cpu;
        wait_halt_or_timeout(80);
        if (cpu.r_flags[6] !== 1'b1) begin
            $display("  FAIL: V should be 1"); test_passed = 0;
        end else $display("  OK:   V = 1");
        check_reg("A", cpu.r_a, 8'h80);
        report(64);

        // ── Test 65: POP then immediate register use (known bug) ──
        // POP PSW writes A, but a following MOV D,A reads stale A
        // because the multi-cycle completion and ID→EX transfer happen
        // on the same clock edge (NBA hasn't propagated yet).
        $display("\n--- Test 65: POP PSW; MOV D,A (multi-cycle forwarding) ---");
        test_passed = 1;
        // LXI SP,0100h; MVI A,42h; PUSH PSW; MVI A,00h; POP PSW; MOV D,A; HLT
        mem.ram[0] = 16'h0031;   // 31 00
        mem.ram[1] = 16'h3E01;   // 01 3E
        mem.ram[2] = 16'hF542;   // 42 F5
        mem.ram[3] = 16'h003E;   // 3E 00
        mem.ram[4] = 16'h57F1;   // F1 57
        mem.ram[5] = 16'h0076;   // 76 00
        reset_cpu;
        wait_halt_or_timeout(80);
        check_reg("A", cpu.r_a, 8'h42);
        check_reg("D", cpu.r_d, 8'h42);
        report(65);

        // ── Test 66: POP B; MOV A,B (same bug, different register pair) ──
        $display("\n--- Test 66: POP B; MOV A,B (multi-cycle forwarding) ---");
        test_passed = 1;
        // LXI SP,0100h; MVI B,99h; MVI C,88h; PUSH B; MVI B,00h; POP B; MOV A,B; HLT
        mem.ram[0] = 16'h0031;   // 31 00
        mem.ram[1] = 16'h0601;   // 01 06
        mem.ram[2] = 16'h0E99;   // 99 0E
        mem.ram[3] = 16'hC588;   // 88 C5
        mem.ram[4] = 16'h0006;   // 06 00
        mem.ram[5] = 16'h78C1;   // C1 78
        mem.ram[6] = 16'h0076;   // 76 00
        reset_cpu;
        wait_halt_or_timeout(80);
        check_reg("A", cpu.r_a, 8'h99);
        check_reg("B", cpu.r_b, 8'h99);
        check_reg("C", cpu.r_c, 8'h88);
        report(66);

        // ────────────────────────────────────────────────
        // Summary
        // ────────────────────────────────────────────────
        $display("=== Results: %0d PASS, %0d FAIL ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

endmodule
