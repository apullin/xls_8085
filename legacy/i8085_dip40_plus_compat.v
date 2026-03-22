// Intel 8085 Enhanced DIP40 Compatible - Timing-Compliant Variant
// Drop-in replacement for i8085_dip40_plus with proper AC timing
//
// This module wraps i8085_dip40_plus with timing stretching logic to ensure
// external bus signals meet the 8085 AC timing specifications.
//
// Note: Internal SPRAM and SPI flash accesses are not stretched - only
// external window accesses (default 0x7C00-0x7FFF) are timing-stretched.
// This allows internal operations to run at full speed while maintaining
// compatibility with external peripherals.

module i8085_dip40_plus_compat #(
    parameter [15:0] EXT_WINDOW_BASE = 16'h7C00,  // External window start
    parameter [3:0]  EXT_WINDOW_SIZE = 4'd10,     // 10=1KB, 11=2KB, 12=4KB
    parameter real   CLK_PERIOD_NS = 20.833,      // System clock period (48MHz default)
    parameter real   TARGET_MHZ = 5.0             // Target timing (5.0 or 2.5 MHz)
)(
    // Clock and Reset
    input  wire        clk,
    input  wire        reset_n,

    // Multiplexed Address/Data Bus
    inout  wire [7:0]  ad,
    output wire [2:0]  a_hi,         // A8-A10 only

    // Bus Control (timing-stretched)
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
    input  wire        ready,

    // SPI Flash Interface
    output wire        spi_sck,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso
);

    // =========================================================================
    // Internal signals
    // =========================================================================

    // CPU control signals (before timing stretch)
    wire        cpu_ale;
    wire        cpu_rd_n;
    wire        cpu_wr_n;
    wire        cpu_io_m_n;
    wire        cpu_s0;
    wire        cpu_s1;
    wire        cpu_ready;

    // Internal AD bus
    wire [7:0]  cpu_ad;
    wire [2:0]  cpu_a_hi;

    // Address latch for extended ALE timing
    reg [7:0]   addr_latch;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            addr_latch <= 8'h00;
        end else begin
            if (cpu_ale) begin
                addr_latch <= cpu_ad;
            end
        end
    end

    // External AD bus muxing
    wire ext_ale_extending = ale && !cpu_ale;

    assign ad = ext_ale_extending ? addr_latch :
                cpu_ale ? cpu_ad :
                !wr_n ? cpu_ad :
                8'bZ;

    // CPU AD input driver
    assign cpu_ad = (!rd_n) ? ad : 8'bZ;

    // High address passes through
    assign a_hi = cpu_a_hi;

    // =========================================================================
    // CPU Core Instance (Plus variant)
    // =========================================================================

    i8085_dip40_plus #(
        .EXT_WINDOW_BASE(EXT_WINDOW_BASE),
        .EXT_WINDOW_SIZE(EXT_WINDOW_SIZE)
    ) cpu (
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
        .hlda(hlda),

        // SPI passes through
        .spi_sck(spi_sck),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso)
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
