// Intel 8085 Timing-Compatible Variant Testbench
// Verifies that the timing wrapper produces spec-compliant bus signals
//
// This testbench is similar to i8085_timing_tb.v but tests the _compat
// variant which includes the timing stretching wrapper.

`timescale 1ns / 1ps

module i8085_compat_tb;

    // =========================================================================
    // 8085-AH AC Timing Specifications (5MHz version, in nanoseconds)
    // =========================================================================

    parameter real T_AL_MIN  = 140.0;    // ALE pulse width minimum
    parameter real T_LL_MIN  = 50.0;     // Address hold after ALE low
    parameter real T_RD_MIN  = 400.0;    // RD pulse width minimum
    parameter real T_WR_MIN  = 400.0;    // WR pulse width minimum
    parameter real T_DW_MIN  = 200.0;    // Data setup before WR high

    // =========================================================================
    // Test Configuration
    // =========================================================================

    parameter real CLK_PERIOD = 20.833;  // 48MHz system clock
    parameter MEMORY_SIZE = 65536;

    // =========================================================================
    // Timing Measurement Variables
    // =========================================================================

    real ale_rise_time, ale_fall_time;
    real rd_fall_time, rd_rise_time;
    real wr_fall_time, wr_rise_time;
    real addr_valid_time;

    integer ale_width_violations;
    integer rd_width_violations;
    integer wr_width_violations;
    integer total_bus_cycles;
    integer total_read_cycles;
    integer total_write_cycles;

    reg [15:0] latched_addr;
    reg addr_was_valid;

    // =========================================================================
    // DUT Signals
    // =========================================================================

    reg         clk;
    reg         reset_n;

    wire [7:0]  ad;
    wire [7:0]  a_hi;
    wire        ale;
    wire        rd_n;
    wire        wr_n;
    wire        io_m_n;
    wire        s0, s1;
    wire        resout;
    wire        inta_n;
    wire        sod;
    wire        hlda;

    reg         trap;
    reg         rst75, rst65, rst55;
    reg         intr;
    reg         sid;
    reg         hold;
    reg         ready;

    reg [7:0]   mem_data_out;
    reg         mem_driving;

    assign ad = mem_driving ? mem_data_out : 8'bZ;

    // =========================================================================
    // Test Memory
    // =========================================================================

    reg [7:0] memory [0:MEMORY_SIZE-1];

    // =========================================================================
    // DUT Instantiation - Using the _compat variant
    // =========================================================================

    i8085_dip40_compat #(
        .CLK_PERIOD_NS(CLK_PERIOD),
        .TARGET_MHZ(5.0)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .ad(ad),
        .a_hi(a_hi),
        .ale(ale),
        .rd_n(rd_n),
        .wr_n(wr_n),
        .io_m_n(io_m_n),
        .s0(s0),
        .s1(s1),
        .resout(resout),
        .trap(trap),
        .rst75(rst75),
        .rst65(rst65),
        .rst55(rst55),
        .intr(intr),
        .inta_n(inta_n),
        .sid(sid),
        .sod(sod),
        .hold(hold),
        .hlda(hlda),
        .ready(ready)
    );

    // =========================================================================
    // Clock Generation
    // =========================================================================

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // =========================================================================
    // ALE Timing Monitor
    // =========================================================================

    always @(posedge ale) begin
        ale_rise_time = $realtime;
        total_bus_cycles = total_bus_cycles + 1;
        latched_addr = {a_hi, ad};
        addr_valid_time = $realtime;
        addr_was_valid = 1;
    end

    real ale_width;
    always @(negedge ale) begin
        ale_fall_time = $realtime;
        if (ale_rise_time > 0) begin
            ale_width = ale_fall_time - ale_rise_time;
            if (ale_width < T_AL_MIN) begin
                $display("[%0t] *** TIMING VIOLATION: ALE width = %.1f ns (min %.1f ns)",
                         $realtime, ale_width, T_AL_MIN);
                ale_width_violations = ale_width_violations + 1;
            end
        end
    end

    // =========================================================================
    // Address Latch (like 74LS373)
    // =========================================================================

    reg [7:0] addr_latch;
    always @(negedge ale) begin
        addr_latch <= ad;
    end
    wire [15:0] full_addr = {a_hi, addr_latch};

    // =========================================================================
    // RD# Timing Monitor
    // =========================================================================

    always @(negedge rd_n) begin
        rd_fall_time = $realtime;
        total_read_cycles = total_read_cycles + 1;
    end

    // Memory response
    always @(*) begin
        if (!rd_n) begin
            if (!io_m_n) begin
                mem_data_out = memory[full_addr];
            end else begin
                mem_data_out = 8'hFF;
            end
            mem_driving = 1;
        end else begin
            mem_driving = 0;
        end
    end

    real rd_width;
    always @(posedge rd_n) begin
        rd_rise_time = $realtime;
        if (rd_fall_time > 0) begin
            rd_width = rd_rise_time - rd_fall_time;
            if (rd_width < T_RD_MIN) begin
                $display("[%0t] *** TIMING VIOLATION: RD width = %.1f ns (min %.1f ns)",
                         $realtime, rd_width, T_RD_MIN);
                rd_width_violations = rd_width_violations + 1;
            end
        end
    end

    // =========================================================================
    // WR# Timing Monitor
    // =========================================================================

    always @(negedge wr_n) begin
        wr_fall_time = $realtime;
        total_write_cycles = total_write_cycles + 1;
    end

    real wr_width;
    always @(posedge wr_n) begin
        wr_rise_time = $realtime;
        if (wr_fall_time > 0) begin
            wr_width = wr_rise_time - wr_fall_time;
            if (wr_width < T_WR_MIN) begin
                $display("[%0t] *** TIMING VIOLATION: WR width = %.1f ns (min %.1f ns)",
                         $realtime, wr_width, T_WR_MIN);
                wr_width_violations = wr_width_violations + 1;
            end
            // Write to memory
            if (!io_m_n) begin
                memory[full_addr] <= ad;
            end
        end
    end

    // =========================================================================
    // Test Program Loader
    // =========================================================================

    task load_test_program;
        integer i;
        begin
            for (i = 0; i < MEMORY_SIZE; i = i + 1)
                memory[i] = 8'h00;

            // Same test program as timing_tb
            memory[16'h0000] = 8'h31;  // LXI SP, 0100h
            memory[16'h0001] = 8'h00;
            memory[16'h0002] = 8'h01;

            memory[16'h0003] = 8'h3E;  // MVI A, 55h
            memory[16'h0004] = 8'h55;

            memory[16'h0005] = 8'h32;  // STA 0200h
            memory[16'h0006] = 8'h00;
            memory[16'h0007] = 8'h02;

            memory[16'h0008] = 8'h3A;  // LDA 0200h
            memory[16'h0009] = 8'h00;
            memory[16'h000A] = 8'h02;

            memory[16'h000B] = 8'h21;  // LXI H, 0200h
            memory[16'h000C] = 8'h00;
            memory[16'h000D] = 8'h02;

            memory[16'h000E] = 8'h46;  // MOV B, M

            memory[16'h000F] = 8'hC5;  // PUSH B

            memory[16'h0010] = 8'hC1;  // POP B

            memory[16'h0011] = 8'hD3;  // OUT 10h
            memory[16'h0012] = 8'h10;

            memory[16'h0013] = 8'hDB;  // IN 10h
            memory[16'h0014] = 8'h10;

            memory[16'h0015] = 8'hCD;  // CALL 0020h
            memory[16'h0016] = 8'h20;
            memory[16'h0017] = 8'h00;

            memory[16'h0018] = 8'h76;  // HLT

            // Subroutine at 0020h
            memory[16'h0020] = 8'h3C;  // INR A
            memory[16'h0021] = 8'hC9;  // RET
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================

    initial begin
        $display("==============================================");
        $display("8085 Timing-Compatible Variant Testbench");
        $display("System Clock: %.1f ns (%.2f MHz)", CLK_PERIOD, 1000.0/CLK_PERIOD);
        $display("Target Timing: 5.0 MHz (with stretching)");
        $display("==============================================");

        // Initialize counters
        ale_width_violations = 0;
        rd_width_violations = 0;
        wr_width_violations = 0;
        total_bus_cycles = 0;
        total_read_cycles = 0;
        total_write_cycles = 0;

        ale_rise_time = 0;
        ale_fall_time = 0;
        rd_fall_time = 0;
        rd_rise_time = 0;
        wr_fall_time = 0;
        wr_rise_time = 0;
        addr_was_valid = 0;

        // Initialize signals
        reset_n = 0;
        trap = 0;
        rst75 = 0;
        rst65 = 0;
        rst55 = 0;
        intr = 0;
        sid = 0;
        hold = 0;
        ready = 1;
        mem_driving = 0;
        mem_data_out = 8'hFF;

        load_test_program();

        // Release reset
        #(CLK_PERIOD * 10);
        reset_n = 1;
        $display("\n[%0t] Reset released\n", $realtime);

        // Wait for HLT - the CPU uses an internal state, check for halt condition
        // by watching for idle bus (no ALE for a while)
        fork
            begin
                // Timeout
                #(CLK_PERIOD * 50000);
                $display("\n*** TIMEOUT - Test did not complete ***\n");
            end
            begin
                // Wait for halt (watch for HLT opcode fetch at 0x0018)
                wait(full_addr == 16'h0018 && !rd_n);
                #(CLK_PERIOD * 100);
            end
        join_any
        disable fork;

        // Print summary
        $display("\n==============================================");
        $display("Timing Verification Summary");
        $display("==============================================");
        $display("Total bus cycles:    %0d", total_bus_cycles);
        $display("Total read cycles:   %0d", total_read_cycles);
        $display("Total write cycles:  %0d", total_write_cycles);
        $display("----------------------------------------------");
        $display("ALE width violations:    %0d", ale_width_violations);
        $display("RD width violations:     %0d", rd_width_violations);
        $display("WR width violations:     %0d", wr_width_violations);
        $display("----------------------------------------------");

        if (ale_width_violations == 0 && rd_width_violations == 0 &&
            wr_width_violations == 0) begin
            $display("RESULT: PASS - All timing specifications met");
        end else begin
            $display("RESULT: FAIL - Timing violations detected");
        end

        $display("==============================================\n");

        $finish;
    end

endmodule
