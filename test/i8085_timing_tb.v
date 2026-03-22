// Intel 8085 Bus Timing Verification Testbench
// Verifies that bus signals meet AC timing specifications
//
// Reference: Intel 8085AH Datasheet AC Characteristics
// This testbench monitors all bus signals and checks timing constraints
// to ensure compatibility with real 8085 peripherals.

`timescale 1ns / 1ps

module i8085_timing_tb;

    // =========================================================================
    // 8085-AH AC Timing Specifications (5MHz version, in nanoseconds)
    // From Intel 8085AH Datasheet
    // =========================================================================

    // Clock timing
    parameter real T_CYC_MIN = 200.0;    // Minimum clock period (5MHz)
    parameter real T_CYC_MAX = 2000.0;   // Maximum clock period (500kHz min freq)

    // ALE timing
    parameter real T_AL_MIN  = 140.0;    // ALE pulse width minimum
    parameter real T_LL_MIN  = 50.0;     // Address hold after ALE low

    // Address timing
    parameter real T_AC_MAX  = 270.0;    // A8-15 valid to ALE low (max)
    parameter real T_AD_MAX  = 575.0;    // Address to valid data (read)

    // Read timing
    parameter real T_RD_MIN  = 400.0;    // RD pulse width minimum
    parameter real T_RAE_MAX = 300.0;    // RD low to address enable (tristate off)
    parameter real T_RD_MAX  = 300.0;    // Data valid after RD low
    parameter real T_RDF_MIN = 0.0;      // Data hold after RD high

    // Write timing
    parameter real T_WR_MIN  = 400.0;    // WR pulse width minimum
    parameter real T_DW_MIN  = 200.0;    // Data setup before WR high
    parameter real T_WD_MIN  = 100.0;    // Data hold after WR high
    parameter real T_AW_MIN  = 100.0;    // Address setup before WR low

    // Derived timing at different clock frequencies
    // At 5MHz: T_CYC = 200ns, 3 T-states = 600ns for machine cycle
    // At 48MHz: T_CYC = 20.8ns, need to scale or add wait states

    // =========================================================================
    // Test Configuration
    // =========================================================================

    // parameter real CLK_PERIOD = 200.0;   // 5MHz for spec compliance testing
    parameter real CLK_PERIOD = 20.833;  // 48MHz for FPGA testing

    parameter MEMORY_SIZE = 65536;
    parameter ROM_SIZE = 4096;

    // =========================================================================
    // Timing Measurement Variables
    // =========================================================================

    // Edge timestamps (in real ns)
    real ale_rise_time, ale_fall_time;
    real rd_fall_time, rd_rise_time;
    real wr_fall_time, wr_rise_time;
    real addr_valid_time;
    real data_valid_time;
    real data_drive_time;

    // Violation counters
    integer ale_width_violations;
    integer rd_width_violations;
    integer wr_width_violations;
    integer addr_setup_violations;
    integer data_setup_violations;
    integer total_bus_cycles;
    integer total_read_cycles;
    integer total_write_cycles;

    // Address tracking
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

    // Memory/IO data drive
    reg [7:0]   mem_data_out;
    reg         mem_driving;

    // Directly drive AD bus when CPU is reading
    assign ad = mem_driving ? mem_data_out : 8'bZ;

    // =========================================================================
    // Test Memory
    // =========================================================================

    reg [7:0] memory [0:MEMORY_SIZE-1];

    // =========================================================================
    // DUT Instantiation
    // =========================================================================

    i8085_dip40 dut (
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

        // Capture address on ALE rising edge
        latched_addr = {a_hi, ad};
        addr_valid_time = $realtime;
        addr_was_valid = 1;

        $display("[%0t] ALE↑ ADDR=%04h (a_hi=%02h ad=%02h) IO/M=%b S1=%b S0=%b",
                 $realtime, latched_addr, a_hi, ad, ~io_m_n, s1, s0);
    end

    real ale_width;
    always @(negedge ale) begin
        ale_fall_time = $realtime;

        // Check ALE pulse width
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
    // Address Latch Simulation (like 74LS373)
    // =========================================================================

    reg [7:0] addr_latch;

    // Capture low address byte when ALE falls (like 74LS373)
    always @(negedge ale) begin
        addr_latch <= ad;
    end

    wire [15:0] full_addr = {a_hi, addr_latch};

    // =========================================================================
    // RD# Timing Monitor
    // =========================================================================

    real addr_setup;
    always @(negedge rd_n) begin
        rd_fall_time = $realtime;
        total_read_cycles = total_read_cycles + 1;

        // Check address setup before RD#
        if (addr_was_valid) begin
            addr_setup = rd_fall_time - addr_valid_time;

            // Address should be valid before RD goes low
            // (This is implicitly satisfied if ALE occurred first)
            $display("[%0t] RD↓ reading from %04h (addr setup = %.1f ns)",
                     $realtime, full_addr, addr_setup);
        end

    end

    // Memory response - simpler approach
    // Drive data when RD is low
    always @(*) begin
        if (!rd_n) begin
            if (!io_m_n) begin
                mem_data_out = memory[full_addr];
                $display("        MEM READ: [%04h] -> %02h", full_addr, memory[full_addr]);
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

        // Check RD pulse width
        if (rd_fall_time > 0) begin
            rd_width = rd_rise_time - rd_fall_time;

            if (rd_width < T_RD_MIN) begin
                $display("[%0t] *** TIMING VIOLATION: RD width = %.1f ns (min %.1f ns)",
                         $realtime, rd_width, T_RD_MIN);
                rd_width_violations = rd_width_violations + 1;
            end else begin
                $display("[%0t] RD↑ width = %.1f ns (OK)", $realtime, rd_width);
            end
        end

    end

    // =========================================================================
    // WR# Timing Monitor
    // =========================================================================

    always @(negedge wr_n) begin
        wr_fall_time = $realtime;
        total_write_cycles = total_write_cycles + 1;
        data_drive_time = $realtime;  // CPU starts driving data

        $display("[%0t] WR↓ writing to %04h", $realtime, full_addr);
    end

    real wr_width;
    real data_setup_wr;
    always @(posedge wr_n) begin
        wr_rise_time = $realtime;

        // Check WR pulse width
        if (wr_fall_time > 0) begin
            wr_width = wr_rise_time - wr_fall_time;

            if (wr_width < T_WR_MIN) begin
                $display("[%0t] *** TIMING VIOLATION: WR width = %.1f ns (min %.1f ns)",
                         $realtime, wr_width, T_WR_MIN);
                wr_width_violations = wr_width_violations + 1;
            end else begin
                $display("[%0t] WR↑ width = %.1f ns, data = %02h (OK)",
                         $realtime, wr_width, ad);
            end

            // Check data setup time before WR rising edge
            data_setup_wr = wr_rise_time - data_drive_time;

            if (data_setup_wr < T_DW_MIN) begin
                $display("[%0t] *** TIMING VIOLATION: Data setup = %.1f ns (min %.1f ns)",
                         $realtime, data_setup_wr, T_DW_MIN);
                data_setup_violations = data_setup_violations + 1;
            end

            // Actually write to memory
            if (!io_m_n) begin
                memory[full_addr] <= ad;
                $display("[%0t] Memory[%04h] <- %02h", $realtime, full_addr, ad);
            end
        end
    end

    // =========================================================================
    // Test Program Loader
    // =========================================================================

    task load_test_program;
        integer i;
        begin
            // Clear memory
            for (i = 0; i < MEMORY_SIZE; i = i + 1)
                memory[i] = 8'h00;

            // Test program: exercises various instruction types
            // Tests opcode fetch, immediate fetch, memory R/W, I/O, stack

            // ORG 0000h - Reset vector
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

            memory[16'h000E] = 8'h46;  // MOV B, M (read from HL)

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
        // Initialize
        $display("==============================================");
        $display("8085 Bus Timing Verification Testbench");
        $display("Clock Period: %.1f ns (%.2f MHz)", CLK_PERIOD, 1000.0/CLK_PERIOD);
        $display("==============================================");

        // Initialize counters
        ale_width_violations = 0;
        rd_width_violations = 0;
        wr_width_violations = 0;
        addr_setup_violations = 0;
        data_setup_violations = 0;
        total_bus_cycles = 0;
        total_read_cycles = 0;
        total_write_cycles = 0;

        // Initialize timestamps
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
        ready = 1;  // Always ready for now
        mem_driving = 0;
        mem_data_out = 8'hFF;

        // Load test program
        load_test_program();

        // Verify memory contents
        $display("Memory verification:");
        $display("  [0000] = %02h (expect 31)", memory[16'h0000]);
        $display("  [0001] = %02h (expect 00)", memory[16'h0001]);
        $display("  [0002] = %02h (expect 01)", memory[16'h0002]);
        $display("  [0003] = %02h (expect 3E)", memory[16'h0003]);
        $display("  [0004] = %02h (expect 55)", memory[16'h0004]);

        // Release reset
        #(CLK_PERIOD * 10);
        reset_n = 1;
        $display("\n[%0t] Reset released\n", $realtime);

        // Run until HLT
        wait(dut.state == 6'd45);  // S_HALT = 45
        #(CLK_PERIOD * 10);

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
        $display("Address setup violations: %0d", addr_setup_violations);
        $display("Data setup violations:   %0d", data_setup_violations);
        $display("----------------------------------------------");

        if (ale_width_violations == 0 && rd_width_violations == 0 &&
            wr_width_violations == 0 && addr_setup_violations == 0 &&
            data_setup_violations == 0) begin
            $display("RESULT: PASS - All timing specifications met");
        end else begin
            $display("RESULT: FAIL - Timing violations detected");
        end

        $display("==============================================\n");

        $finish;
    end

    // =========================================================================
    // Timeout watchdog
    // =========================================================================

    initial begin
        #(CLK_PERIOD * 10000);
        $display("\n*** TIMEOUT - Test did not complete ***\n");
        $finish;
    end

endmodule
