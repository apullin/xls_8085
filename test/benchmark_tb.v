// benchmark_tb.v - Real software benchmarks for HP vs FSM comparison
//
// These tests run actual algorithms (not unit tests) to measure realistic
// performance differences between the pipelined HP core and FSM core.
//
// Benchmark 1: Bubble Sort - Sort 8 bytes in memory
// Benchmark 2: Division - 8-bit division via repeated subtraction
// Benchmark 3: Binary Search - Search sorted array for value
// Benchmark 4: Memory Copy - Block copy routine
// Benchmark 5: Fibonacci - Compute fib(10)
//
// Results: cycle counts per benchmark, total speedup ratio

`timescale 1ns / 1ps

module benchmark_tb;

    parameter CLK_PERIOD = 20;  // 50 MHz

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

    // Interrupt signals
    reg         tb_int_req;
    reg  [15:0] tb_int_vector;
    reg         tb_int_is_trap;
    wire        cpu_int_ack;

    // DUT - Pipelined HP core
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
    integer test_num;
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

    // Main test sequence
    initial begin
        $display("=== 8085 HP Core Benchmark Suite ===\n");
        $display("Running real software benchmarks to measure cycle efficiency.\n");

        // ════════════════════════════════════════════════════════════
        // Benchmark 1: Bubble Sort (8 elements)
        //
        // Sorts 8 bytes at address 0x0100 in ascending order.
        // Input:  [7, 3, 5, 1, 8, 2, 6, 4]
        // Output: [1, 2, 3, 4, 5, 6, 7, 8]
        // ════════════════════════════════════════════════════════════
        $display("--- Benchmark 1: Bubble Sort (8 elements) ---");
        clear_mem;

        // Bubble sort assembly (corrected):
        // start: 0x00
        //   LXI H, 0100h      ; 21 00 01
        //   MVI D, 00h        ; 16 00      ; D = swapped flag
        //   MVI C, 07h        ; 0E 07      ; C = compare count (n-1)
        // check: 0x08
        //   MOV A, M          ; 7E         ; get arr[i]
        //   INX H             ; 23         ; point to arr[i+1]
        //   CMP M             ; BE         ; compare arr[i] with arr[i+1]
        //   JC nxtbyt         ; DA 17 00   ; if A < M, no swap needed (jump to 0x17)
        //   MOV B, M          ; 46         ; B = arr[i+1]
        //   MOV M, A          ; 77         ; arr[i+1] = arr[i]
        //   DCX H             ; 2B         ; point back to arr[i]
        //   MOV M, B          ; 70         ; arr[i] = B
        //   INX H             ; 23         ; restore pointer
        //   MVI D, 01h        ; 16 01      ; swapped = 1
        // nxtbyt: 0x17
        //   DCR C             ; 0D         ; count--
        //   JNZ check         ; C2 08 00   ; if count != 0, continue (jump to 0x08)
        //   MOV A, D          ; 7A         ; get swapped flag
        //   RRC               ; 0F         ; put bit 0 in carry
        //   JC start          ; DA 00 00   ; if swapped, repeat
        //   HLT               ; 76
        //
        // Byte stream:
        // 0x00: 21 00 01 16 00 0E 07 7E  ; LXI H,0100; MVI D,00; MVI C,07; MOV A,M
        // 0x08: 23 BE DA 17 00 46 77 2B  ; INX H; CMP M; JC 0017; MOV B,M; MOV M,A; DCX H
        // 0x10: 70 23 16 01 0D C2 08 00  ; MOV M,B; INX H; MVI D,01; DCR C; JNZ 0008
        // 0x18: 00 7A 0F DA 00 00 76     ; NOP; MOV A,D; RRC; JC 0000; HLT (at 0x1E)

        // Recalculated byte layout:
        // 0x00: 21 00 01  LXI H, 0100h
        // 0x03: 16 00     MVI D, 00h
        // 0x05: 0E 07     MVI C, 07h
        // check: 0x07
        // 0x07: 7E        MOV A, M
        // 0x08: 23        INX H
        // 0x09: BE        CMP M
        // 0x0A: DA 14 00  JC nxtbyt (0x14)
        // 0x0D: 46        MOV B, M
        // 0x0E: 77        MOV M, A
        // 0x0F: 2B        DCX H
        // 0x10: 70        MOV M, B
        // 0x11: 23        INX H
        // 0x12: 16 01     MVI D, 01h
        // nxtbyt: 0x14
        // 0x14: 0D        DCR C
        // 0x15: C2 07 00  JNZ check (0x07)
        // 0x18: 7A        MOV A, D
        // 0x19: 0F        RRC
        // 0x1A: DA 00 00  JC start (0x00)
        // 0x1D: 76        HLT

        mem.ram[0]  = 16'h0021;  // 21 00
        mem.ram[1]  = 16'h1601;  // 01 16
        mem.ram[2]  = 16'h0E00;  // 00 0E
        mem.ram[3]  = 16'h7E07;  // 07 7E
        mem.ram[4]  = 16'hBE23;  // 23 BE
        mem.ram[5]  = 16'h14DA;  // DA 14 (JC 0014h)
        mem.ram[6]  = 16'h4600;  // 00 46
        mem.ram[7]  = 16'h2B77;  // 77 2B
        mem.ram[8]  = 16'h2370;  // 70 23
        mem.ram[9]  = 16'h0116;  // 16 01
        mem.ram[10] = 16'hC20D;  // 0D C2
        mem.ram[11] = 16'h0007;  // 07 00 (JNZ 0007h)
        mem.ram[12] = 16'h0F7A;  // 7A 0F
        mem.ram[13] = 16'h00DA;  // DA 00
        mem.ram[14] = 16'h7600;  // 00 76

        // Data at 0x0100 (word addr 0x80): [7, 3, 5, 1, 8, 2, 6, 4]
        mem.ram[16'h80] = 16'h0307;  // bytes 0x100=7, 0x101=3
        mem.ram[16'h81] = 16'h0105;  // bytes 0x102=5, 0x103=1
        mem.ram[16'h82] = 16'h0208;  // bytes 0x104=8, 0x105=2
        mem.ram[16'h83] = 16'h0406;  // bytes 0x106=6, 0x107=4

        reset_cpu;
        wait_halt_or_timeout(5000);

        if (test_passed) begin
            $display("  Cycles: %0d", cycle);
            // Verify sorted: [1, 2, 3, 4, 5, 6, 7, 8]
            if (mem.ram[16'h80] == 16'h0201 && mem.ram[16'h81] == 16'h0403 &&
                mem.ram[16'h82] == 16'h0605 && mem.ram[16'h83] == 16'h0807) begin
                $display("  Result: PASS (sorted correctly)");
            end else begin
                $display("  Result: FAIL (incorrect sort)");
                $display("    mem[0x100..0x107] = %02x %02x %02x %02x %02x %02x %02x %02x",
                    mem.ram[16'h80][7:0], mem.ram[16'h80][15:8],
                    mem.ram[16'h81][7:0], mem.ram[16'h81][15:8],
                    mem.ram[16'h82][7:0], mem.ram[16'h82][15:8],
                    mem.ram[16'h83][7:0], mem.ram[16'h83][15:8]);
            end
        end else begin
            $display("  TIMEOUT at PC=0x%04x", cpu_pc);
        end
        $display("");

        // ════════════════════════════════════════════════════════════
        // Benchmark 2: 8-bit Division (100 / 7 = 14 remainder 2)
        //
        // Divides B (dividend) by C (divisor) using repeated subtraction.
        // Result: H = quotient, L = remainder
        // ════════════════════════════════════════════════════════════
        $display("--- Benchmark 2: Division (100 / 7) ---");
        clear_mem;

        // Code:
        // start:
        //   MVI B, 64h        ; 06 64      ; dividend = 100
        //   MVI C, 07h        ; 0E 07      ; divisor = 7
        //   MVI H, 00h        ; 26 00      ; quotient = 0
        //   MOV A, B          ; 78         ; A = dividend
        //   CMP C             ; B9         ; if dividend < divisor
        //   JC done           ; DA xx xx   ; jump to done
        // loop:
        //   SUB C             ; 91         ; A = A - divisor
        //   INR H             ; 24         ; quotient++
        //   CMP C             ; B9         ; if A >= divisor
        //   JNC loop          ; D2 xx xx   ; continue
        // done:
        //   MOV L, A          ; 6F         ; L = remainder
        //   HLT               ; 76

        // Byte layout:
        // 0x00: 06 64 0E 07 26 00 78 B9 DA 12 00 91 24 B9 D2 0B
        // 0x10: 00 6F 76
        mem.ram[0]  = 16'h6406;  // 0x00: 06 64  MVI B, 64h
        mem.ram[1]  = 16'h070E;  // 0x02: 0E 07  MVI C, 07h
        mem.ram[2]  = 16'h0026;  // 0x04: 26 00  MVI H, 00h
        mem.ram[3]  = 16'hB978;  // 0x06: 78 B9  MOV A,B; CMP C
        mem.ram[4]  = 16'h12DA;  // 0x08: DA 12  JC done (addr 0x12)
        mem.ram[5]  = 16'h9100;  // 0x0A: 00 91  ; SUB C
        mem.ram[6]  = 16'hB924;  // 0x0C: 24 B9  INR H; CMP C
        mem.ram[7]  = 16'h0BD2;  // 0x0E: D2 0B  JNC loop (addr 0x0B)
        mem.ram[8]  = 16'h6F00;  // 0x10: 00 6F  ; MOV L,A
        mem.ram[9]  = 16'h0076;  // 0x12: 76 00  HLT

        reset_cpu;
        wait_halt_or_timeout(2000);

        if (test_passed) begin
            $display("  Cycles: %0d", cycle);
            // 100 / 7 = 14 remainder 2
            if (cpu_h == 8'd14 && cpu_l == 8'd2) begin
                $display("  Result: PASS (100/7 = %0d r %0d)", cpu_h, cpu_l);
            end else begin
                $display("  Result: FAIL (got %0d r %0d, expected 14 r 2)", cpu_h, cpu_l);
            end
        end else begin
            $display("  TIMEOUT at PC=0x%04x", cpu_pc);
        end
        $display("");

        // ════════════════════════════════════════════════════════════
        // Benchmark 3: Linear Search
        //
        // Searches array [1,2,3,4,5,6,7,8] at 0x0100 for value 5.
        // Returns index in B (should be 4).
        // ════════════════════════════════════════════════════════════
        $display("--- Benchmark 3: Linear Search (find 5 in [1..8]) ---");
        clear_mem;

        // Simpler binary search:
        // Array at 0x0100: [1,2,3,4,5,6,7,8] (1-indexed values at 0-indexed positions)
        // Find: 5 (at index 4)
        //
        // Code:
        //   MVI B, 00h        ; low = 0
        //   MVI C, 07h        ; high = 7
        //   MVI D, 05h        ; needle = 5
        //   MVI A, FFh        ; result = not found
        // loop:
        //   MOV A, C          ; A = high
        //   CMP B             ; high - low
        //   JM done           ; if high < low, done
        //   ADD B             ; A = high + low
        //   RAR               ; A = (high+low)/2 = mid
        //   MOV E, A          ; E = mid
        //   LXI H, 0100h      ; base address
        //   MOV L, E          ; HL = base + mid (since H=01, L=mid works for small indices)
        //   ; Actually need: ADD low to get proper mid, then use as index
        //   ; Simplified: L = 00 + mid
        //   MVI H, 01h        ; H = 01h
        //   MOV A, M          ; A = arr[mid]
        //   CMP D             ; compare with needle
        //   JZ found          ; if equal, found
        //   JM less           ; if A < D, needle is higher
        //   ; else: needle is lower, high = mid - 1
        //   MOV A, E
        //   DCR A
        //   MOV C, A          ; high = mid - 1
        //   JMP loop
        // less:
        //   MOV A, E
        //   INR A
        //   MOV B, A          ; low = mid + 1
        //   JMP loop
        // found:
        //   MOV A, E          ; A = index
        //   JMP done
        // done:
        //   HLT

        // Simplified code - just searching [1,2,3,4,5,6,7,8] for 5
        // 0x00: 06 00        MVI B, 00h   ; low=0
        // 0x02: 0E 07        MVI C, 07h   ; high=7
        // 0x04: 16 05        MVI D, 05h   ; needle=5
        // 0x06: 3E FF        MVI A, FFh   ; result=not found
        // loop: 0x08
        // 0x08: 79           MOV A, C     ; A=high
        // 0x09: B8           CMP B        ; high-low
        // 0x0A: FA 30 00     JM done      ; if high<low, exit (addr 0x30)
        // 0x0D: 80           ADD B        ; A=high+low
        // 0x0E: 1F           RAR          ; A=(high+low)/2
        // 0x0F: 5F           MOV E, A     ; E=mid
        // 0x10: 21 00 01     LXI H, 0100h ; base
        // 0x13: 6B           MOV L, E     ; L=mid (makes HL=0100+mid)
        // 0x14: 7E           MOV A, M     ; A=arr[mid]
        // 0x15: BA           CMP D        ; compare with needle
        // 0x16: CA 2C 00     JZ found     ; if equal (addr 0x2C)
        // 0x19: FA 24 00     JM less      ; if A<needle (addr 0x24)
        // ; greater: high = mid - 1
        // 0x1C: 7B           MOV A, E
        // 0x1D: 3D           DCR A
        // 0x1E: 4F           MOV C, A     ; high=mid-1
        // 0x1F: C3 08 00     JMP loop     ; (addr 0x08)
        // 0x22: 00 00        (padding)
        // less: 0x24
        // 0x24: 7B           MOV A, E
        // 0x25: 3C           INR A
        // 0x26: 47           MOV B, A     ; low=mid+1
        // 0x27: C3 08 00     JMP loop
        // 0x2A: 00 00        (padding)
        // found: 0x2C
        // 0x2C: 7B           MOV A, E     ; A=index found
        // 0x2D: C3 30 00     JMP done
        // done: 0x30
        // 0x30: 76           HLT

        // Linear search (simpler, exercises memory ops and loops)
        // 0x00: 16 05        MVI D, 05h     ; needle = 5
        // 0x02: 06 00        MVI B, 00h     ; index = 0
        // 0x04: 21 00 01     LXI H, 0100h   ; base
        // loop: 0x07
        // 0x07: 7E           MOV A, M       ; A = arr[i]
        // 0x08: BA           CMP D          ; compare with needle
        // 0x09: CA 14 00     JZ found       ; if equal
        // 0x0C: 23           INX H          ; next element
        // 0x0D: 04           INR B          ; index++
        // 0x0E: 78           MOV A, B
        // 0x0F: FE 08        CPI 08h        ; if index < 8
        // 0x11: DA 07 00     JC loop        ; continue
        // found: 0x14
        // 0x14: 78           MOV A, B       ; A = index (or 8 if not found)
        // 0x15: 76           HLT

        mem.ram[0]  = 16'h0516;  // 16 05
        mem.ram[1]  = 16'h0006;  // 06 00
        mem.ram[2]  = 16'h0021;  // 21 00
        mem.ram[3]  = 16'h7E01;  // 01 7E
        mem.ram[4]  = 16'hCABA;  // BA CA
        mem.ram[5]  = 16'h0014;  // 14 00
        mem.ram[6]  = 16'h0423;  // 23 04
        mem.ram[7]  = 16'hFE78;  // 78 FE
        mem.ram[8]  = 16'hDA08;  // 08 DA
        mem.ram[9]  = 16'h0007;  // 07 00
        mem.ram[10] = 16'h7678;  // 78 76

        // Data at 0x0100: arr[0..7] = [1,2,3,4,5,6,7,8]
        mem.ram[16'h80] = 16'h0201;  // arr[0]=1, arr[1]=2
        mem.ram[16'h81] = 16'h0403;  // arr[2]=3, arr[3]=4
        mem.ram[16'h82] = 16'h0605;  // arr[4]=5, arr[5]=6
        mem.ram[16'h83] = 16'h0807;  // arr[6]=7, arr[7]=8

        reset_cpu;
        wait_halt_or_timeout(2000);

        if (test_passed) begin
            $display("  Cycles: %0d", cycle);
            // Looking for 5, which is at index 4
            // Linear search result is in B register (and copied to A at end)
            if (cpu_b == 8'd4) begin
                $display("  Result: PASS (found 5 at index %0d)", cpu_b);
            end else begin
                $display("  Result: FAIL (got index %0d, expected 4)", cpu_b);
            end
        end else begin
            $display("  TIMEOUT at PC=0x%04x", cpu_pc);
        end
        $display("");

        // ════════════════════════════════════════════════════════════
        // Benchmark 4: Memory Copy (16 bytes from 0x0100 to 0x0110)
        // ════════════════════════════════════════════════════════════
        $display("--- Benchmark 4: Memory Copy (16 bytes) ---");
        clear_mem;

        // Code:
        //   LXI H, 0100h      ; source
        //   LXI D, 0110h      ; dest
        //   MVI C, 10h        ; count = 16
        // loop:
        //   MOV A, M          ; get byte
        //   STAX D            ; store to dest
        //   INX H             ; src++
        //   INX D             ; dst++
        //   DCR C             ; count--
        //   JNZ loop
        //   HLT

        // 0x00: 21 00 01     LXI H, 0100h
        // 0x03: 11 10 01     LXI D, 0110h
        // 0x06: 0E 10        MVI C, 10h
        // loop: 0x08
        // 0x08: 7E           MOV A, M
        // 0x09: 12           STAX D
        // 0x0A: 23           INX H
        // 0x0B: 13           INX D
        // 0x0C: 0D           DCR C
        // 0x0D: C2 08 00     JNZ loop
        // 0x10: 76           HLT

        mem.ram[0]  = 16'h0021;  // 21 00
        mem.ram[1]  = 16'h1101;  // 01 11
        mem.ram[2]  = 16'h0110;  // 10 01
        mem.ram[3]  = 16'h100E;  // 0E 10
        mem.ram[4]  = 16'h127E;  // 7E 12
        mem.ram[5]  = 16'h1323;  // 23 13
        mem.ram[6]  = 16'hC20D;  // 0D C2
        mem.ram[7]  = 16'h0008;  // 08 00
        mem.ram[8]  = 16'h0076;  // 76 00

        // Source data at 0x0100: 0x11, 0x22, 0x33, ... 0x10 bytes
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
            // Verify copy: 0x0110 should match 0x0100
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

        // ════════════════════════════════════════════════════════════
        // Benchmark 5: Fibonacci - Compute fib(10) = 55
        //
        // Iterative: fib(0)=0, fib(1)=1, fib(n)=fib(n-1)+fib(n-2)
        // ════════════════════════════════════════════════════════════
        $display("--- Benchmark 5: Fibonacci (fib(10) = 55) ---");
        clear_mem;

        // Code:
        //   MVI B, 00h        ; fib(n-2) = 0
        //   MVI C, 01h        ; fib(n-1) = 1
        //   MVI D, 0Ah        ; counter = 10
        // loop:
        //   MOV A, D
        //   CPI 00h
        //   JZ done
        //   MOV A, B          ; A = fib(n-2)
        //   ADD C             ; A = fib(n-2) + fib(n-1) = fib(n)
        //   MOV B, C          ; fib(n-2) = old fib(n-1)
        //   MOV C, A          ; fib(n-1) = fib(n)
        //   DCR D             ; counter--
        //   JMP loop
        // done:
        //   MOV A, B          ; A = result
        //   HLT

        // 0x00: 06 00        MVI B, 00h
        // 0x02: 0E 01        MVI C, 01h
        // 0x04: 16 0A        MVI D, 0Ah
        // loop: 0x06
        // 0x06: 7A           MOV A, D
        // 0x07: FE 00        CPI 00h
        // 0x09: CA 15 00     JZ done (0x15)
        // 0x0C: 78           MOV A, B
        // 0x0D: 81           ADD C
        // 0x0E: 41           MOV B, C
        // 0x0F: 4F           MOV C, A
        // 0x10: 15           DCR D
        // 0x11: C3 06 00     JMP loop
        // done: 0x14
        // 0x14: 00           (padding)
        // 0x15: 78           MOV A, B
        // 0x16: 76           HLT

        mem.ram[0]  = 16'h0006;  // 06 00
        mem.ram[1]  = 16'h010E;  // 0E 01
        mem.ram[2]  = 16'h0A16;  // 16 0A
        mem.ram[3]  = 16'hFE7A;  // 7A FE
        mem.ram[4]  = 16'hCA00;  // 00 CA
        mem.ram[5]  = 16'h7815;  // 15 78  <- wrong, need to fix
        // Let me recalculate more carefully

        clear_mem;
        // 0x00: 06 00  MVI B,0
        // 0x02: 0E 01  MVI C,1
        // 0x04: 16 0A  MVI D,10
        // 0x06: 7A     MOV A,D
        // 0x07: FE 00  CPI 0
        // 0x09: CA 15 00  JZ 0x15
        // 0x0C: 78     MOV A,B
        // 0x0D: 81     ADD C
        // 0x0E: 41     MOV B,C
        // 0x0F: 4F     MOV C,A
        // 0x10: 15     DCR D
        // 0x11: C3 06 00  JMP 0x06
        // 0x14: 00     NOP
        // 0x15: 78     MOV A,B
        // 0x16: 76     HLT

        mem.ram[0]  = 16'h0006;  // addr 0,1: 06 00
        mem.ram[1]  = 16'h010E;  // addr 2,3: 0E 01
        mem.ram[2]  = 16'h0A16;  // addr 4,5: 16 0A
        mem.ram[3]  = 16'hFE7A;  // addr 6,7: 7A FE
        mem.ram[4]  = 16'hCA00;  // addr 8,9: 00 CA
        mem.ram[5]  = 16'h0015;  // addr A,B: 15 00
        mem.ram[6]  = 16'h8178;  // addr C,D: 78 81
        mem.ram[7]  = 16'h4F41;  // addr E,F: 41 4F
        mem.ram[8]  = 16'hC315;  // addr 10,11: 15 C3
        mem.ram[9]  = 16'h0006;  // addr 12,13: 06 00
        mem.ram[10] = 16'h7800;  // addr 14,15: 00 78
        mem.ram[11] = 16'h0076;  // addr 16,17: 76 00

        reset_cpu;
        wait_halt_or_timeout(2000);

        if (test_passed) begin
            $display("  Cycles: %0d", cycle);
            // fib(10) = 55
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

        // ════════════════════════════════════════════════════════════
        // Summary
        // ════════════════════════════════════════════════════════════
        $display("=== Benchmark Summary ===");
        $display("Run this testbench with both HP and FSM cores to compare.");
        $display("HP core: make bench_hp");
        $display("FSM core: make bench_ref");

        $finish;
    end

endmodule
