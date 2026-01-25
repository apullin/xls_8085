// Timer16 Wrapper - Adds state registers around XLS-generated combinational logic
//
// This wrapper holds the TimerState in registers and presents a clean
// memory-mapped peripheral interface.

module timer16_wrapper (
    input  wire        clk,
    input  wire        reset_n,

    // Memory-mapped register interface
    input  wire [3:0]  addr,
    input  wire [7:0]  data_in,
    output wire [7:0]  data_out,
    input  wire        rd,
    input  wire        wr,

    // Timer tick input (directly from system clock if no external prescale)
    input  wire        tick,

    // Interrupt output
    output wire        irq
);

    // =========================================================================
    // State Registers
    // =========================================================================
    // TimerState layout (144 bits total):
    //   counter[15:0], reload[15:0], prescale[7:0], prescale_cnt[7:0],
    //   ctrl[7:0], irq_en[7:0], status[7:0],
    //   cmp0[15:0], cmp1[15:0], cmp2[15:0], cmp3[15:0],
    //   cnt_hi_latch[7:0]

    reg [15:0] r_counter;
    reg [15:0] r_reload;
    reg [7:0]  r_prescale;
    reg [7:0]  r_prescale_cnt;
    reg [7:0]  r_ctrl;
    reg [7:0]  r_irq_en;
    reg [7:0]  r_status;
    reg [15:0] r_cmp0;
    reg [15:0] r_cmp1;
    reg [15:0] r_cmp2;
    reg [15:0] r_cmp3;
    reg [7:0]  r_cnt_hi_latch;

    // Pack state for XLS core (MSB first based on struct order)
    wire [143:0] state_in = {
        r_counter,        // [143:128]
        r_reload,         // [127:112]
        r_prescale,       // [111:104]
        r_prescale_cnt,   // [103:96]
        r_ctrl,           // [95:88]
        r_irq_en,         // [87:80]
        r_status,         // [79:72]
        r_cmp0,           // [71:56]
        r_cmp1,           // [55:40]
        r_cmp2,           // [39:24]
        r_cmp3,           // [23:8]
        r_cnt_hi_latch    // [7:0]
    };

    // Pack input for XLS core
    // TimerInput: addr[3:0], data_in[7:0], rd, wr, tick
    wire [14:0] bus_in = {
        addr,      // [14:11]
        data_in,   // [10:3]
        rd,        // [2]
        wr,        // [1]
        tick       // [0]
    };

    // =========================================================================
    // XLS Combinational Core
    // =========================================================================

    wire [152:0] core_out;

    __timer16__timer_tick core (
        .state(state_in),
        .bus_in(bus_in),
        .out(core_out)
    );

    // Unpack output
    // Output: (TimerState[143:0], TimerOutput[8:0])
    // TimerOutput: data_out[7:0], irq
    wire [143:0] next_state = core_out[152:9];
    wire [7:0]   next_data_out = core_out[8:1];
    wire         next_irq = core_out[0];

    // Unpack next state
    wire [15:0] next_counter      = next_state[143:128];
    wire [15:0] next_reload       = next_state[127:112];
    wire [7:0]  next_prescale     = next_state[111:104];
    wire [7:0]  next_prescale_cnt = next_state[103:96];
    wire [7:0]  next_ctrl         = next_state[95:88];
    wire [7:0]  next_irq_en       = next_state[87:80];
    wire [7:0]  next_status       = next_state[79:72];
    wire [15:0] next_cmp0         = next_state[71:56];
    wire [15:0] next_cmp1         = next_state[55:40];
    wire [15:0] next_cmp2         = next_state[39:24];
    wire [15:0] next_cmp3         = next_state[23:8];
    wire [7:0]  next_cnt_hi_latch = next_state[7:0];

    // =========================================================================
    // State Update
    // =========================================================================

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            r_counter      <= 16'h0000;
            r_reload       <= 16'h0000;
            r_prescale     <= 8'h00;
            r_prescale_cnt <= 8'h00;
            r_ctrl         <= 8'h00;
            r_irq_en       <= 8'h00;
            r_status       <= 8'h00;
            r_cmp0         <= 16'h0000;
            r_cmp1         <= 16'h0000;
            r_cmp2         <= 16'h0000;
            r_cmp3         <= 16'h0000;
            r_cnt_hi_latch <= 8'h00;
        end else begin
            r_counter      <= next_counter;
            r_reload       <= next_reload;
            r_prescale     <= next_prescale;
            r_prescale_cnt <= next_prescale_cnt;
            r_ctrl         <= next_ctrl;
            r_irq_en       <= next_irq_en;
            r_status       <= next_status;
            r_cmp0         <= next_cmp0;
            r_cmp1         <= next_cmp1;
            r_cmp2         <= next_cmp2;
            r_cmp3         <= next_cmp3;
            r_cnt_hi_latch <= next_cnt_hi_latch;
        end
    end

    // =========================================================================
    // Output
    // =========================================================================

    assign data_out = next_data_out;
    assign irq = next_irq;

endmodule
