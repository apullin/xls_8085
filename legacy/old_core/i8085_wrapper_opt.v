// Auto-generated wrapper for i8085_core
// Provides clean named interface hiding XLS bit-packing
// Complete implementation with I/O, stack, and interrupt support

module i8085_wrapper (
    input  wire        clk,
    input  wire        reset_n,

    // Memory Bus
    output wire [15:0] mem_addr,
    input  wire [7:0]  mem_data_in,
    output wire [7:0]  mem_data_out,
    output wire        mem_rd,
    output wire        mem_wr,

    // Stack Write Bus (for CALL, PUSH, RST)
    output wire [15:0] stack_wr_addr,
    output wire [7:0]  stack_wr_data_lo,
    output wire [7:0]  stack_wr_data_hi,
    output wire        stack_wr,

    // I/O Bus
    output wire [7:0]  io_port,
    output wire [7:0]  io_data_out,
    input  wire [7:0]  io_data_in,
    output wire        io_rd,
    output wire        io_wr,

    // Instruction input
    input  wire [7:0]  opcode,
    input  wire [7:0]  imm1,
    input  wire [7:0]  imm2,

    // Memory read data (for instructions that read from HL, BC, DE, or direct addr)
    input  wire [7:0]  mem_read_data,

    // Stack read data (for RET/POP)
    input  wire [7:0]  stack_lo,
    input  wire [7:0]  stack_hi,

    // Control
    input  wire        execute,     // Pulse to execute instruction

    // Interrupt control (from DIP40 wrapper)
    input  wire        int_ack,     // Interrupt acknowledge - load vector, update SP, clear INTE
    input  wire [15:0] int_vector,  // Vector address to load into PC
    input  wire        int_is_trap, // If true, don't clear INTE (TRAP is NMI)

    // Interrupt inputs (directly wired to core for RIM)
    input  wire        sid,         // Serial input data
    input  wire        rst55_level, // RST 5.5 pin level
    input  wire        rst65_level, // RST 6.5 pin level

    // Status outputs
    output wire [15:0] pc,
    output wire [15:0] sp,
    output wire [7:0]  reg_a,
    output wire [7:0]  reg_b,
    output wire [7:0]  reg_c,
    output wire [7:0]  reg_d,
    output wire [7:0]  reg_e,
    output wire [7:0]  reg_h,
    output wire [7:0]  reg_l,
    output wire        halted,
    output wire        inte,
    output wire        flag_z,
    output wire        flag_c,

    // Interrupt mask/status outputs
    output wire        mask_55,
    output wire        mask_65,
    output wire        mask_75,
    output wire        rst75_pending,
    output wire        sod
);

    // =========================================================================
    // CPU State Registers
    // =========================================================================

    reg [7:0]  r_b, r_c, r_d, r_e, r_h, r_l, r_a;
    reg [15:0] r_sp, r_pc;
    reg        f_sign, f_zero, f_aux, f_parity, f_carry;
    reg        r_halted, r_inte;
    // Interrupt state
    reg        r_mask_55, r_mask_65, r_mask_75;
    reg        r_rst75_pending;
    reg        r_sod_latch;

    // =========================================================================
    // XLS Core - bit packing/unpacking
    // =========================================================================

    // Pack state for core input (MSB-first to match XLS struct order)
    // XLS unpacks: reg_b[99:92], reg_c[91:84], ..., sod_latch[0]
    // State: 100 bits = 7*8 + 2*16 + 5 + 1 + 1 + 5 new interrupt fields
    wire [99:0] core_state = {
        r_b, r_c, r_d, r_e, r_h, r_l, r_a,      // regs at MSB: [99:44]
        r_sp,                                    // sp: [43:28]
        r_pc,                                    // pc: [27:12]
        f_sign, f_zero, f_aux, f_parity, f_carry, // flags: [11:7]
        r_halted,                                // halted: [6]
        r_inte,                                  // inte: [5]
        r_mask_55, r_mask_65, r_mask_75,         // masks: [4:2]
        r_rst75_pending,                         // rst75_pending: [1]
        r_sod_latch                              // sod_latch: [0]
    };

    wire [175:0] core_out;

    __i8085_core__execute_parity_opt core (
        .state(core_state),
        .opcode(opcode),
        .byte2(imm1),
        .byte3(imm2),
        .mem_read_data(mem_read_data),
        .stack_read_lo(stack_lo),
        .stack_read_hi(stack_hi),
        .io_read_data(io_data_in),
        .sid(sid),
        .rst55_level(rst55_level),
        .rst65_level(rst65_level),
        .out(core_out)
    );

    // Unpack core output - State (100 bits at MSB, bits [175:76])
    // XLS packs: {State[99:0], MemBusOut[75:0]} with State at MSB
    wire [7:0]  next_b      = core_out[175:168];
    wire [7:0]  next_c      = core_out[167:160];
    wire [7:0]  next_d      = core_out[159:152];
    wire [7:0]  next_e      = core_out[151:144];
    wire [7:0]  next_h      = core_out[143:136];
    wire [7:0]  next_l      = core_out[135:128];
    wire [7:0]  next_a      = core_out[127:120];
    wire [15:0] next_sp     = core_out[119:104];
    wire [15:0] next_pc     = core_out[103:88];
    wire        next_f_sign = core_out[87];
    wire        next_f_zero = core_out[86];
    wire        next_f_aux  = core_out[85];
    wire        next_f_par  = core_out[84];
    wire        next_f_cry  = core_out[83];
    wire        next_halted = core_out[82];
    wire        next_inte   = core_out[81];
    wire        next_mask_55 = core_out[80];
    wire        next_mask_65 = core_out[79];
    wire        next_mask_75 = core_out[78];
    wire        next_rst75_pending = core_out[77];
    wire        next_sod_latch = core_out[76];

    // Unpack core output - MemBusOut (76 bits at LSB, bits [75:0])
    // XLS struct order: addr, write_data, write_enable, stack_addr,
    //                   stack_data_lo, stack_data_hi, stack_write,
    //                   io_port, io_data, io_read, io_write
    wire [15:0] core_mem_addr     = core_out[75:60];
    wire [7:0]  core_mem_data     = core_out[59:52];
    wire        core_mem_wr       = core_out[51];
    wire [15:0] core_stack_addr   = core_out[50:35];
    wire [7:0]  core_stack_lo     = core_out[34:27];
    wire [7:0]  core_stack_hi     = core_out[26:19];
    wire        core_stack_wr     = core_out[18];
    wire [7:0]  core_io_port      = core_out[17:10];
    wire [7:0]  core_io_data      = core_out[9:2];
    wire        core_io_rd        = core_out[1];
    wire        core_io_wr        = core_out[0];

    // =========================================================================
    // State Update
    // =========================================================================

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            r_b <= 8'h00; r_c <= 8'h00;
            r_d <= 8'h00; r_e <= 8'h00;
            r_h <= 8'h00; r_l <= 8'h00;
            r_a <= 8'h00;
            r_sp <= 16'hFFFF;
            r_pc <= 16'h0000;
            f_sign <= 1'b0; f_zero <= 1'b0;
            f_aux <= 1'b0; f_parity <= 1'b0; f_carry <= 1'b0;
            r_halted <= 1'b0;
            r_inte <= 1'b0;
            // Interrupt state reset
            r_mask_55 <= 1'b1;  // Masked by default
            r_mask_65 <= 1'b1;
            r_mask_75 <= 1'b1;
            r_rst75_pending <= 1'b0;
            r_sod_latch <= 1'b0;
        end else if (int_ack) begin
            // Interrupt acknowledge - load vector, decrement SP, clear INTE
            r_pc <= int_vector;
            r_sp <= r_sp - 16'd2;
            r_halted <= 1'b0;  // Wake from halt
            if (!int_is_trap)
                r_inte <= 1'b0;  // Clear INTE (except for TRAP which is NMI)
        end else if (execute && !r_halted) begin
            r_b <= next_b; r_c <= next_c;
            r_d <= next_d; r_e <= next_e;
            r_h <= next_h; r_l <= next_l;
            r_a <= next_a;
            r_sp <= next_sp;
            r_pc <= next_pc;
            f_sign <= next_f_sign;
            f_zero <= next_f_zero;
            f_aux <= next_f_aux;
            f_parity <= next_f_par;
            f_carry <= next_f_cry;
            r_halted <= next_halted;
            r_inte <= next_inte;
            // Interrupt state update
            r_mask_55 <= next_mask_55;
            r_mask_65 <= next_mask_65;
            r_mask_75 <= next_mask_75;
            r_rst75_pending <= next_rst75_pending;
            r_sod_latch <= next_sod_latch;
        end
    end

    // =========================================================================
    // Output assignments
    // =========================================================================

    // Memory bus
    // Note: The DIP40 FSM controls actual bus timing, so we don't gate with execute here
    assign mem_addr = core_mem_wr ? core_mem_addr : r_pc;
    assign mem_data_out = core_mem_data;
    assign mem_wr = core_mem_wr;  // Ungated - DIP40 FSM uses this to decide state transitions
    assign mem_rd = ~core_mem_wr & ~r_halted;

    // Stack write bus
    assign stack_wr_addr = core_stack_addr;
    assign stack_wr_data_lo = core_stack_lo;
    assign stack_wr_data_hi = core_stack_hi;
    assign stack_wr = core_stack_wr;  // Ungated - DIP40 FSM uses this to decide state transitions

    // I/O bus
    assign io_port = core_io_port;
    assign io_data_out = core_io_data;
    assign io_rd = core_io_rd;   // Ungated
    assign io_wr = core_io_wr;   // Ungated

    // Status outputs
    assign pc = r_pc;
    assign sp = r_sp;
    assign reg_a = r_a;
    assign reg_b = r_b;
    assign reg_c = r_c;
    assign reg_d = r_d;
    assign reg_e = r_e;
    assign reg_h = r_h;
    assign reg_l = r_l;
    assign halted = r_halted;
    assign inte = r_inte;
    assign flag_z = f_zero;
    assign flag_c = f_carry;

    // Interrupt status outputs
    assign mask_55 = r_mask_55;
    assign mask_65 = r_mask_65;
    assign mask_75 = r_mask_75;
    assign rst75_pending = r_rst75_pending;
    assign sod = r_sod_latch;

endmodule
