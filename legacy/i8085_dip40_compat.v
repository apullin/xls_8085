// Intel 8085 DIP40 Compatible - Timing-Compliant Variant
// Drop-in replacement for original 8085 with proper AC timing
//
// This module wraps i8085_dip40 with timing stretching logic to ensure
// all bus signals meet the 8085 AC timing specifications. Suitable for
// use with original 8085 peripherals on a breadboard.
//
// The internal CPU runs at full speed; the timing wrapper inserts
// wait states and stretches control signals (ALE, RD#, WR#) to meet specs.
// The AD bus passes through directly.

module i8085_dip40_compat #(
    parameter real CLK_PERIOD_NS = 20.833,  // System clock period (48MHz default)
    parameter real TARGET_MHZ = 5.0          // Target timing (5.0 or 2.5 MHz)
)(
    // Clock and Reset
    input  wire        clk,
    input  wire        reset_n,

    // Multiplexed Address/Data Bus (directly to pins)
    inout  wire [7:0]  ad,
    output wire [7:0]  a_hi,

    // Bus Control (directly to pins - directly timing-stretched)
    output wire        ale,
    output wire        rd_n,
    output wire        wr_n,
    output wire        io_m_n,

    // Status
    output wire        s0,
    output wire        s1,
    output wire        resout,

    // Interrupts
    input  wire        trap,
    input  wire        rst75,
    input  wire        rst65,
    input  wire        rst55,
    input  wire        intr,
    output wire        inta_n,

    // Serial I/O
    input  wire        sid,
    output wire        sod,

    // DMA
    input  wire        hold,
    output wire        hlda,

    // Wait State
    input  wire        ready
);

    // =========================================================================
    // Internal signals
    // =========================================================================

    // CPU control signals (directly before timing stretch)
    wire        cpu_ale;
    wire        cpu_rd_n;
    wire        cpu_wr_n;
    wire        cpu_io_m_n;
    wire        cpu_s0;
    wire        cpu_s1;
    wire        cpu_ready;

    // Internal AD bus - CPU connects here, we manage external ad
    wire [7:0]  cpu_ad;
    wire [7:0]  cpu_a_hi;

    // Address latch for extended ALE timing
    reg [7:0]   addr_latch;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            addr_latch <= 8'h00;
        end else begin
            // Latch address when CPU's ALE is high
            if (cpu_ale) begin
                addr_latch <= cpu_ad;
            end
        end
    end

    // External AD bus muxing:
    // During extended ALE phase (ext_ale high, cpu_ale low), we need to drive
    // the latched address so external 74LS373 can capture it.
    wire ext_ale_extending = ale && !cpu_ale;

    // External AD driver:
    // - During extended ALE: drive latched address
    // - During CPU ALE: pass CPU's address
    // - During writes: pass CPU's data
    // - Otherwise: tristate for reads
    assign ad = ext_ale_extending ? addr_latch :
                cpu_ale ? cpu_ad :
                !wr_n ? cpu_ad :
                8'bZ;

    // CPU AD input driver:
    // During reads (when rd_n low), route external ad to cpu_ad so CPU can sample it.
    // The CPU's internal driver goes high-Z during reads, so this won't conflict.
    assign cpu_ad = (!rd_n) ? ad : 8'bZ;

    // High address passes through directly (stays valid throughout cycle)
    assign a_hi = cpu_a_hi;

    // =========================================================================
    // CPU Core Instance
    // =========================================================================

    i8085_dip40 cpu (
        .clk(clk),
        .reset_n(reset_n),

        // AD bus connects to internal net
        .ad(cpu_ad),
        .a_hi(cpu_a_hi),

        // Control signals go to timing wrapper
        .ale(cpu_ale),
        .rd_n(cpu_rd_n),
        .wr_n(cpu_wr_n),
        .io_m_n(cpu_io_m_n),
        .s0(cpu_s0),
        .s1(cpu_s1),

        // READY comes from timing wrapper
        .ready(cpu_ready),

        // These pass through directly
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
        .hlda(hlda)
    );

    // =========================================================================
    // Timing Wrapper Instance
    // =========================================================================

    i8085_timing_compat #(
        .CLK_PERIOD_NS(CLK_PERIOD_NS),
        .TARGET_MHZ(TARGET_MHZ)
    ) timing (
        .clk(clk),
        .reset_n(reset_n),

        // CPU-side control signals
        .cpu_ale(cpu_ale),
        .cpu_rd_n(cpu_rd_n),
        .cpu_wr_n(cpu_wr_n),
        .cpu_io_m_n(cpu_io_m_n),
        .cpu_s0(cpu_s0),
        .cpu_s1(cpu_s1),
        .cpu_ready(cpu_ready),

        // External bus control (timing-stretched)
        .ext_ale(ale),
        .ext_rd_n(rd_n),
        .ext_wr_n(wr_n),
        .ext_io_m_n(io_m_n),
        .ext_s0(s0),
        .ext_s1(s1),

        // External ready
        .ext_ready(ready)
    );

endmodule
