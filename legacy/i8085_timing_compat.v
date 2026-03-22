// Intel 8085 Timing Compatibility Wrapper
// Stretches bus signals to meet AC timing specifications
//
// This module sits between a fast-running 8085 core and the external bus,
// generating timing-compliant control signals (ALE, RD#, WR#).
//
// Strategy: Latch the CPU's bus request during ALE, then generate a complete
// properly-timed external bus cycle while holding the CPU with READY.
//
// Parameters:
//   CLK_PERIOD_NS - System clock period in nanoseconds

module i8085_timing_compat #(
    parameter real CLK_PERIOD_NS = 20.833,  // 48MHz default
    parameter real TARGET_MHZ = 5.0          // Not used directly, specs are fixed
)(
    input  wire        clk,
    input  wire        reset_n,

    // CPU-side signals
    input  wire        cpu_ale,
    input  wire        cpu_rd_n,
    input  wire        cpu_wr_n,
    input  wire        cpu_io_m_n,
    input  wire        cpu_s0,
    input  wire        cpu_s1,
    output reg         cpu_ready,

    // External bus signals
    output reg         ext_ale,
    output reg         ext_rd_n,
    output reg         ext_wr_n,
    output wire        ext_io_m_n,
    output wire        ext_s0,
    output wire        ext_s1,

    input  wire        ext_ready
);

    // =========================================================================
    // Timing Parameters - Clock cycles needed for each spec
    // =========================================================================

    // 8085 AC timing specs (in nanoseconds)
    localparam real T_AL_MIN  = 140.0;   // ALE pulse width minimum
    localparam real T_RD_MIN  = 400.0;   // RD pulse width minimum
    localparam real T_WR_MIN  = 400.0;   // WR pulse width minimum

    // Calculate cycles needed (ceiling)
    localparam integer ALE_CYCLES = (T_AL_MIN / CLK_PERIOD_NS) + 2;
    localparam integer RD_CYCLES  = (T_RD_MIN / CLK_PERIOD_NS) + 2;
    localparam integer WR_CYCLES  = (T_WR_MIN / CLK_PERIOD_NS) + 2;

    // =========================================================================
    // State Machine
    // =========================================================================

    localparam [2:0]
        S_IDLE       = 3'd0,
        S_ALE_HIGH   = 3'd1,
        S_RD_LOW     = 3'd2,
        S_WR_LOW     = 3'd3,
        S_WAIT_CPU   = 3'd4,
        S_RD_HOLD    = 3'd5,  // Hold RD one more cycle for CPU to sample
        S_WR_HOLD    = 3'd6;  // Hold WR one more cycle for data stability

    reg [2:0] state;
    reg [7:0] counter;

    // Latched cycle type from status signals
    // S1=1, S0=0: Memory/IO Read
    // S1=0, S0=1: Memory/IO Write
    // S1=1, S0=1: Opcode Fetch (also a read)
    // S1=0, S0=0: Halt/Hold
    reg is_read_cycle;
    reg is_write_cycle;
    reg latched_io_m;
    reg latched_s0, latched_s1;

    // Edge detection with synchronized status capture
    // We capture status signals at the same time as ALE so they're aligned
    reg cpu_ale_d1;
    reg cpu_s0_d1, cpu_s1_d1, cpu_io_m_d1;
    wire cpu_ale_rise = cpu_ale & ~cpu_ale_d1;  // Immediate edge detect (1 cycle earlier)

    // =========================================================================
    // Main FSM
    // =========================================================================

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_IDLE;
            counter <= 0;
            cpu_ready <= 1'b1;
            ext_ale <= 1'b0;
            ext_rd_n <= 1'b1;
            ext_wr_n <= 1'b1;
            cpu_ale_d1 <= 1'b0;
            cpu_s0_d1 <= 1'b0;
            cpu_s1_d1 <= 1'b0;
            cpu_io_m_d1 <= 1'b0;
            is_read_cycle <= 1'b0;
            is_write_cycle <= 1'b0;
            latched_io_m <= 1'b0;
            latched_s0 <= 1'b0;
            latched_s1 <= 1'b0;
        end else begin
            // Edge detection pipeline - capture status signals synchronized with ALE
            cpu_ale_d1 <= cpu_ale;
            cpu_s0_d1 <= cpu_s0;
            cpu_s1_d1 <= cpu_s1;
            cpu_io_m_d1 <= cpu_io_m_n;

            case (state)
                S_IDLE: begin
                    ext_ale <= 1'b0;
                    ext_rd_n <= 1'b1;
                    ext_wr_n <= 1'b1;
                    cpu_ready <= ext_ready;

                    // Detect start of bus cycle
                    if (cpu_ale_rise) begin
                        // Latch cycle type from status
                        latched_io_m <= cpu_io_m_n;
                        latched_s0 <= cpu_s0;
                        latched_s1 <= cpu_s1;

                        // Decode cycle type
                        is_read_cycle <= (cpu_s1 && !cpu_s0) || (cpu_s1 && cpu_s0);  // Read or Fetch
                        is_write_cycle <= (!cpu_s1 && cpu_s0);  // Write

                        // Assert external ALE
                        ext_ale <= 1'b1;

                        // Hold CPU to stretch timing
                        cpu_ready <= 1'b0;

                        counter <= ALE_CYCLES;
                        state <= S_ALE_HIGH;
                    end
                end

                S_ALE_HIGH: begin
                    // Keep ALE high for minimum time
                    if (counter > 0) begin
                        counter <= counter - 1;
                    end else begin
                        ext_ale <= 1'b0;

                        // Start RD or WR phase
                        if (is_read_cycle) begin
                            ext_rd_n <= 1'b0;
                            counter <= RD_CYCLES;
                            state <= S_RD_LOW;
                        end else if (is_write_cycle) begin
                            ext_wr_n <= 1'b0;
                            counter <= WR_CYCLES;
                            state <= S_WR_LOW;
                        end else begin
                            // Halt or other - just complete
                            cpu_ready <= ext_ready;
                            state <= S_WAIT_CPU;
                        end
                    end
                end

                S_RD_LOW: begin
                    // Keep RD low for minimum time
                    if (counter > 0) begin
                        counter <= counter - 1;
                    end else begin
                        // Release READY first, keep RD low for one more cycle
                        // so data is valid when CPU samples it
                        cpu_ready <= ext_ready;
                        state <= S_RD_HOLD;
                    end
                end

                S_RD_HOLD: begin
                    // Now deassert RD after CPU has had a chance to sample
                    ext_rd_n <= 1'b1;
                    state <= S_WAIT_CPU;
                end

                S_WR_LOW: begin
                    // Keep WR low for minimum time
                    if (counter > 0) begin
                        counter <= counter - 1;
                    end else begin
                        // Release READY first, keep WR low for one more cycle
                        cpu_ready <= ext_ready;
                        state <= S_WR_HOLD;
                    end
                end

                S_WR_HOLD: begin
                    // Now deassert WR after data has been latched
                    ext_wr_n <= 1'b1;
                    state <= S_WAIT_CPU;
                end

                S_WAIT_CPU: begin
                    // Wait for CPU to complete its internal cycle
                    cpu_ready <= ext_ready;

                    // Watch for next ALE (next bus cycle)
                    if (cpu_ale_rise) begin
                        latched_io_m <= cpu_io_m_n;
                        latched_s0 <= cpu_s0;
                        latched_s1 <= cpu_s1;
                        is_read_cycle <= (cpu_s1 && !cpu_s0) || (cpu_s1 && cpu_s0);
                        is_write_cycle <= (!cpu_s1 && cpu_s0);

                        ext_ale <= 1'b1;
                        cpu_ready <= 1'b0;
                        counter <= ALE_CYCLES;
                        state <= S_ALE_HIGH;
                    end else if (!cpu_ale && cpu_rd_n && cpu_wr_n) begin
                        // CPU cycle complete, back to idle
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Status outputs
    // =========================================================================

    assign ext_io_m_n = latched_io_m;
    assign ext_s0 = latched_s0;
    assign ext_s1 = latched_s1;

endmodule
