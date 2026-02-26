// j8085_cpu.v - 3-stage pipelined 8085-compatible CPU core
//
// Pipeline: FETCH (IF) → DECODE/READ (ID) → EXECUTE/WRITEBACK (EX)
//
// Phase 1: Basic pipeline skeleton, instruction buffer, 8-bit fetch.
// Phase 2: Register + flag forwarding (EX→ID), full ALU ops.
// Phase 3: Branches (JMP, Jcc, PCHL) with pipeline flush.
// Phase 4: Memory ops (MOV r/M, LDA/STA, LDAX/STAX, INR/DCR M,
//           LHLD/SHLD, ALU M), multi-cycle EX, LXI, port arbitration.
// Phase 5: Stack + subroutines (PUSH/POP, CALL/RET, RST, Ccc/Rcc,
//           XTHL, SPHL), EX-stage branching for RET.
// Phase 6: 16-bit ops (INX/DCX/DAD/XCHG), I/O (IN/OUT),
//           EI/DI, RIM/SIM.
// Phase 7: Interrupts (maskable + TRAP), HLT wakeup, EI delay.
// Phase 8: Integration (bank register I/O capture, drop-in ready).
//
// Same external bus interface as i8085_cpu for drop-in compatibility.

`timescale 1ns / 1ps

module j8085_cpu (
    input  wire        clk,
    input  wire        reset_n,

    // Memory Bus (master interface)
    output reg  [15:0] bus_addr,
    output reg  [7:0]  bus_data_out,
    output reg         bus_rd,
    output reg         bus_wr,
    input  wire [7:0]  bus_data_in,
    input  wire        bus_ready,

    // Stack Write Bus
    output reg  [15:0] stack_wr_addr,
    output reg  [7:0]  stack_wr_data_lo,
    output reg  [7:0]  stack_wr_data_hi,
    output reg         stack_wr,

    // I/O Bus
    output wire [7:0]  io_port,
    output wire [7:0]  io_data_out,
    input  wire [7:0]  io_data_in,
    output wire        io_rd,
    output wire        io_wr,

    // Bank registers
    output reg  [7:0]  rom_bank,
    output reg  [2:0]  ram_bank,

    // Interrupts
    input  wire        int_req,
    input  wire [15:0] int_vector,
    input  wire        int_is_trap,
    output reg         int_ack,

    // Hardware inputs (for RIM)
    input  wire        sid,
    input  wire        rst55_level,
    input  wire        rst65_level,

    // Status / debug outputs
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
    output wire        mask_55,
    output wire        mask_65,
    output wire        mask_75,
    output wire        rst75_pending,
    output wire        sod
);

    // ================================================================
    // Register file (FF-based)
    // ================================================================
    reg [7:0]  r_a, r_b, r_c, r_d, r_e, r_h, r_l;
    reg [15:0] r_sp;
    reg [6:0]  r_flags;  // [6]=V, [5]=X5, [4]=S, [3]=Z, [2]=AC, [1]=P, [0]=CY
    reg        r_halted;
    reg        r_inte;
    reg        r_mask_55, r_mask_65, r_mask_75;
    reg        r_rst75_pending;
    reg        r_sod_latch;
    reg [15:0] r_halt_return_addr; // Return address saved at HLT

    // (Status output assigns are after all reg declarations below)

    // ================================================================
    // Register file read (combinational)
    // ================================================================
    function [7:0] reg_read;
        input [2:0] sel;
        case (sel)
            3'd0: reg_read = r_b;
            3'd1: reg_read = r_c;
            3'd2: reg_read = r_d;
            3'd3: reg_read = r_e;
            3'd4: reg_read = r_h;
            3'd5: reg_read = r_l;
            3'd6: reg_read = 8'h00;  // M — handled by memory path
            3'd7: reg_read = r_a;
        endcase
    endfunction

    // ================================================================
    // Pipeline control signals
    // ================================================================
    reg         if_stall;       // Stall IF stage
    reg         id_stall;       // Stall ID stage
    reg         id_flush;       // Flush ID stage (insert bubble)
    reg         ex_stall;       // EX needs more cycles

    // ================================================================
    // Instruction decode wires
    // ================================================================
    wire [1:0]  dec_inst_len;
    wire [3:0]  dec_alu_op;
    wire        dec_alu_use_imm;
    wire        dec_alu_use_a;
    wire [2:0]  dec_src_sel;
    wire [2:0]  dec_dst_sel;
    wire [1:0]  dec_rp_sel;
    wire        dec_writes_reg;
    wire        dec_writes_flags;
    wire [6:0]  dec_flag_mask;
    wire        dec_is_nop;
    wire        dec_is_hlt;
    wire        dec_is_mov;
    wire        dec_is_mvi;
    wire        dec_is_alu_reg;
    wire        dec_is_alu_imm;
    wire        dec_is_inr;
    wire        dec_is_dcr;
    wire        dec_is_load, dec_is_store;
    wire        dec_needs_hl_read, dec_needs_bc_read, dec_needs_de_read;
    wire        dec_needs_direct_read, dec_needs_stack_read;
    wire        dec_is_jmp, dec_is_jcc;
    wire [2:0]  dec_branch_cond;
    wire        dec_is_call, dec_is_ccc, dec_is_ret, dec_is_rcc;
    wire        dec_is_rst, dec_is_pchl;
    wire        dec_is_push, dec_is_pop, dec_is_xthl, dec_is_sphl;
    wire        dec_is_lxi, dec_is_inx, dec_is_dcx, dec_is_dad, dec_is_xchg;
    wire        dec_is_io_in, dec_is_io_out;
    wire        dec_is_ei, dec_is_di, dec_is_rim, dec_is_sim;
    wire        dec_is_stc, dec_is_cmc, dec_is_cma;
    wire        dec_is_sta, dec_is_lda, dec_is_shld, dec_is_lhld;
    wire        dec_is_stax, dec_is_ldax;

    // ================================================================
    // STAGE 1: FETCH (IF)
    // ================================================================
    // Instruction prefetch buffer (4 bytes)
    reg [7:0]  ibuf [0:3];
    reg [2:0]  ibuf_count;     // 0..4 valid bytes
    reg [15:0] fetch_pc;       // Next address to fetch from memory
    reg        fetch_pending;  // A read request is in flight (waiting for bus_ready)

    // Status outputs (placed after all reg declarations)
    assign pc  = fetch_pc;
    assign sp  = r_sp;
    assign reg_a = r_a;
    assign reg_b = r_b;
    assign reg_c = r_c;
    assign reg_d = r_d;
    assign reg_e = r_e;
    assign reg_h = r_h;
    assign reg_l = r_l;
    assign halted = r_halted;
    assign inte = r_inte;
    assign flag_z = r_flags[3];
    assign flag_c = r_flags[0];
    assign mask_55 = r_mask_55;
    assign mask_65 = r_mask_65;
    assign mask_75 = r_mask_75;
    assign rst75_pending = r_rst75_pending;
    assign sod = r_sod_latch;

    // Instruction length decode on ibuf[0] (quick decode for fetch)
    wire [1:0] ibuf_inst_len;
    wire [7:0] ibuf_opcode = ibuf[0];

    // Simple instruction length from opcode (same logic as i8085_decode.v)
    reg [1:0] quick_inst_len;
    always @(*) begin
        casez (ibuf_opcode)
            8'b00??0001, 8'b11000011, 8'b11???010,
            8'b11001101, 8'b11???100, 8'b0011?010, 8'b0010?010,
            8'hDD, 8'hFD:                          // JNX5, JX5
                quick_inst_len = 2'd3;
            8'b00???110, 8'b11???110, 8'b1101?011,
            8'h28, 8'h38:                          // LDHI, LDSI
                quick_inst_len = 2'd2;
            default:
                quick_inst_len = 2'd1;
        endcase
    end
    assign ibuf_inst_len = quick_inst_len;

    // Can ID consume an instruction from the buffer?
    wire ibuf_has_instruction = (ibuf_count >= {1'b0, ibuf_inst_len}) && (ibuf_count > 0);

    // IF wants the memory port to fetch
    wire if_wants_port = !fetch_pending && (ibuf_count <= 3'd2) && !r_halted;
    // ex_wants_port and if_granted declared after EX pipeline registers

    // ================================================================
    // STAGE 2: DECODE / REGISTER READ (ID)
    // ================================================================
    reg        id_valid;
    reg [15:0] id_pc;
    reg [7:0]  id_opcode;
    reg [7:0]  id_byte2;
    reg [7:0]  id_byte3;

    // Decoder instance (operates on id_opcode)
    j8085_decode decode (
        .opcode          (id_opcode),
        .inst_len        (dec_inst_len),
        .alu_op          (dec_alu_op),
        .alu_use_imm     (dec_alu_use_imm),
        .alu_use_a       (dec_alu_use_a),
        .src_sel         (dec_src_sel),
        .dst_sel         (dec_dst_sel),
        .rp_sel          (dec_rp_sel),
        .writes_reg      (dec_writes_reg),
        .writes_flags    (dec_writes_flags),
        .flag_mask       (dec_flag_mask),
        .is_nop          (dec_is_nop),
        .is_hlt          (dec_is_hlt),
        .is_mov          (dec_is_mov),
        .is_mvi          (dec_is_mvi),
        .is_alu_reg      (dec_is_alu_reg),
        .is_alu_imm      (dec_is_alu_imm),
        .is_inr          (dec_is_inr),
        .is_dcr          (dec_is_dcr),
        .is_load         (dec_is_load),
        .is_store        (dec_is_store),
        .needs_hl_read   (dec_needs_hl_read),
        .needs_bc_read   (dec_needs_bc_read),
        .needs_de_read   (dec_needs_de_read),
        .needs_direct_read(dec_needs_direct_read),
        .needs_stack_read(dec_needs_stack_read),
        .is_jmp          (dec_is_jmp),
        .is_jcc          (dec_is_jcc),
        .branch_cond     (dec_branch_cond),
        .is_call         (dec_is_call),
        .is_ccc          (dec_is_ccc),
        .is_ret          (dec_is_ret),
        .is_rcc          (dec_is_rcc),
        .is_rst          (dec_is_rst),
        .is_pchl         (dec_is_pchl),
        .is_push         (dec_is_push),
        .is_pop          (dec_is_pop),
        .is_xthl         (dec_is_xthl),
        .is_sphl         (dec_is_sphl),
        .is_lxi          (dec_is_lxi),
        .is_inx          (dec_is_inx),
        .is_dcx          (dec_is_dcx),
        .is_dad          (dec_is_dad),
        .is_xchg         (dec_is_xchg),
        .is_io_in        (dec_is_io_in),
        .is_io_out       (dec_is_io_out),
        .is_ei           (dec_is_ei),
        .is_di           (dec_is_di),
        .is_rim          (dec_is_rim),
        .is_sim          (dec_is_sim),
        .is_stc          (dec_is_stc),
        .is_cmc          (dec_is_cmc),
        .is_cma          (dec_is_cma),
        .is_sta          (dec_is_sta),
        .is_lda          (dec_is_lda),
        .is_shld         (dec_is_shld),
        .is_lhld         (dec_is_lhld),
        .is_stax         (dec_is_stax),
        .is_ldax         (dec_is_ldax),
        .is_dsub         (dec_is_dsub),
        .is_arhl         (dec_is_arhl),
        .is_rdel         (dec_is_rdel),
        .is_ldhi         (dec_is_ldhi),
        .is_ldsi         (dec_is_ldsi),
        .is_shlx         (dec_is_shlx),
        .is_lhlx         (dec_is_lhlx),
        .is_rstv         (dec_is_rstv),
        .is_jnx5         (dec_is_jnx5),
        .is_jx5          (dec_is_jx5)
    );

    // ================================================================
    // STAGE 3: EXECUTE / WRITEBACK (EX) — declarations
    // (Placed before ID forwarding muxes so signals are declared first)
    // ================================================================
    reg        ex_valid;
    reg [15:0] ex_pc;
    reg [7:0]  ex_opcode;
    reg [7:0]  ex_byte2;
    reg [7:0]  ex_byte3;

    // Decoded control signals (registered from ID)
    reg [3:0]  ex_alu_op;
    reg [2:0]  ex_src_sel;
    reg [2:0]  ex_dst_sel;
    reg [1:0]  ex_rp_sel;
    reg        ex_writes_reg;
    reg        ex_writes_flags;
    reg [6:0]  ex_flag_mask;
    reg [7:0]  ex_operand_a;
    reg [7:0]  ex_operand_b;
    reg        ex_is_hlt;
    reg        ex_is_mov;
    reg        ex_is_mvi;
    reg        ex_is_alu_reg;
    reg        ex_is_alu_imm;
    reg        ex_is_inr;
    reg        ex_is_dcr;
    reg        ex_is_cma;
    reg        ex_is_stc;
    reg        ex_is_cmc;
    reg        ex_is_load;
    reg        ex_is_store;
    reg        ex_is_lxi;
    reg        ex_is_lhld;
    reg        ex_is_shld;
    reg [15:0] ex_mem_addr;
    reg [1:0]  ex_phase;
    reg        ex_is_push;
    reg        ex_is_pop;
    reg        ex_is_call;
    reg        ex_is_ret;
    reg        ex_is_rst;
    reg        ex_is_xthl;
    reg        ex_is_sphl;
    reg [15:0] ex_ret_addr;   // Return address for CALL/RST
    reg [7:0]  ex_stack_lo;   // First byte read from stack (POP/RET/XTHL)
    reg [7:0]  ex_old_h, ex_old_l;  // Saved H,L for XTHL writeback
    reg        ex_is_inx, ex_is_dcx, ex_is_dad, ex_is_xchg;
    reg        ex_is_io_in, ex_is_io_out;
    reg        ex_is_ei, ex_is_di, ex_is_rim, ex_is_sim;
    reg        ex_is_dsub, ex_is_arhl, ex_is_rdel;
    reg        ex_is_ldhi, ex_is_ldsi;
    reg        ex_is_shlx, ex_is_lhlx;
    reg        ex_is_rstv;

    // I/O bus (combinational — single-cycle in EX)
    assign io_port     = ex_byte2;
    assign io_data_out = r_a;
    assign io_rd       = ex_valid && ex_is_io_in;
    assign io_wr       = ex_valid && ex_is_io_out;

    // EX wants the memory port (conservative: claim for entire mem op)
    wire ex_wants_port = ex_valid && (ex_is_load || ex_is_store || ex_is_shld
                                      || ex_is_pop || ex_is_ret || ex_is_xthl
                                      || ex_is_shlx || ex_is_lhlx);
    // Memory port grant
    wire if_granted = if_wants_port && !ex_wants_port;

    // Multi-cycle EX control signals
    wire ex_is_multicycle = ex_is_load || ex_is_shld
                            || ex_is_pop || ex_is_ret || ex_is_xthl
                            || ex_is_shlx || ex_is_lhlx;

    // EX-specific bus_ready: only valid when no IF fetch response is pending.
    // When fetch_pending is set, bus_ready belongs to IF's read, not EX's.
    wire ex_bus_ready = bus_ready && !fetch_pending;

    wire ex_use_mem_data = ex_valid && ex_is_load
                           && ex_phase != 2'd0 && ex_bus_ready;
    wire [7:0] alu_opb_final = ex_use_mem_data ? bus_data_in : ex_operand_b;

    // ex_completing: true on the final phase of a multi-cycle instruction
    wire ex_completing = ex_valid && ex_is_multicycle && (
        // 2-phase read ops (LHLD, LHLX): complete at phase 2
        ((ex_is_lhld || ex_is_lhlx) && ex_phase == 2'd2 && ex_bus_ready) ||
        // 2-phase write ops (SHLD, SHLX): complete at phase 1
        ((ex_is_shld || ex_is_shlx) && ex_phase == 2'd1) ||
        // Simple load/ALU M: complete at phase 1
        (!ex_is_lhld && !ex_is_lhlx && !ex_is_shld && !ex_is_shlx
         && !ex_is_pop && !ex_is_ret && !ex_is_xthl
         && ex_phase == 2'd1 && ex_bus_ready) ||
        // Stack ops (POP, RET, XTHL): complete at phase 2
        ((ex_is_pop || ex_is_ret || ex_is_xthl) && ex_phase == 2'd2 && ex_bus_ready)
    );

    // EX-stage branch signal (RET completing — target from stack)
    wire ex_ret_completing = ex_valid && ex_is_ret
                             && ex_phase == 2'd2 && ex_bus_ready;

    // Instruction completing (any instruction, single or multi-cycle)
    wire ex_instruction_completing = ex_valid && (!ex_is_multicycle || ex_completing);

    // Interrupt signals
    // Take interrupt when: instruction completes (excluding HLT/EI/DI) OR halted,
    // AND not during RET completion (return address conflict),
    // AND either maskable (INTE set + request) or TRAP (non-maskable).
    wire int_take = ((ex_instruction_completing && !ex_is_hlt && !ex_is_ei && !ex_is_di) || r_halted)
        && !ex_ret_completing
        && ((int_req && r_inte) || int_is_trap);
    wire [15:0] int_ret_addr = r_halted ? r_halt_return_addr :
                               id_valid ? id_pc :
                               (fetch_pc - {13'd0, ibuf_count} - {15'd0, fetch_pending});

    // ALU instance
    wire [7:0]  alu_result;
    wire [6:0]  alu_flags_out;

    j8085_alu alu (
        .alu_op    (ex_alu_op),
        .operand_a (ex_operand_a),
        .operand_b (alu_opb_final),
        .flags_in  (r_flags),
        .result    (alu_result),
        .flags_out (alu_flags_out)
    );

    // EX result mux (CMA uses operand_a which was forwarded in ID stage)
    wire [7:0] ex_result = ex_is_cma ? ~ex_operand_a : alu_result;

    // Flag result with masking
    wire [6:0] ex_flags_masked;
    assign ex_flags_masked[6] = ex_flag_mask[6] ? alu_flags_out[6] : r_flags[6]; // V
    assign ex_flags_masked[5] = ex_flag_mask[5] ? alu_flags_out[5] : r_flags[5]; // X5
    assign ex_flags_masked[4] = ex_flag_mask[4] ? alu_flags_out[4] : r_flags[4];
    assign ex_flags_masked[3] = ex_flag_mask[3] ? alu_flags_out[3] : r_flags[3];
    assign ex_flags_masked[2] = ex_flag_mask[2] ? alu_flags_out[2] : r_flags[2];
    assign ex_flags_masked[1] = ex_flag_mask[1] ? alu_flags_out[1] : r_flags[1];
    assign ex_flags_masked[0] = ex_is_stc ? 1'b1 :
                                ex_is_cmc ? ~r_flags[0] :
                                ex_flag_mask[0] ? alu_flags_out[0] : r_flags[0];

    // ── Forwarding muxes (EX → ID) ──────────────────────
    // If EX is writing register R this cycle and ID reads R, forward EX result.
    wire fwd_src_match = ex_valid && ex_writes_reg && (ex_dst_sel == dec_src_sel);
    wire fwd_a_match   = ex_valid && ex_writes_reg && (ex_dst_sel == 3'd7);

    // Source operand with forwarding
    wire [7:0] id_src_data = fwd_src_match ? ex_result : reg_read(dec_src_sel);
    // Accumulator with forwarding
    wire [7:0] id_fwd_a    = fwd_a_match ? ex_result : r_a;
    // Operand A (accumulator path)
    wire [7:0] id_operand_a = dec_alu_use_a ? id_fwd_a : 8'h00;
    // Operand B (source register or immediate)
    wire [7:0] id_operand_b = dec_alu_use_imm ? id_byte2 : id_src_data;

    // ── Flag forwarding (EX → ID) for branch condition evaluation ──
    // Only forward flags when EX result is valid (single-cycle or completing multi-cycle)
    wire ex_flags_ready = ex_valid && ex_writes_flags
                          && (!ex_is_multicycle || ex_completing);
    wire [6:0] id_fwd_flags = ex_flags_ready ? ex_flags_masked : r_flags;

    // ── Register forwarding for address computation ──────
    wire [7:0] id_fwd_b = (ex_valid && ex_writes_reg && ex_dst_sel == 3'd0) ? ex_result : r_b;
    wire [7:0] id_fwd_c = (ex_valid && ex_writes_reg && ex_dst_sel == 3'd1) ? ex_result : r_c;
    wire [7:0] id_fwd_d = (ex_valid && ex_writes_reg && ex_dst_sel == 3'd2) ? ex_result : r_d;
    wire [7:0] id_fwd_e = (ex_valid && ex_writes_reg && ex_dst_sel == 3'd3) ? ex_result : r_e;
    wire [7:0] id_fwd_h = (ex_valid && ex_writes_reg && ex_dst_sel == 3'd4) ? ex_result : r_h;
    wire [7:0] id_fwd_l = (ex_valid && ex_writes_reg && ex_dst_sel == 3'd5) ? ex_result : r_l;

    // ── Memory address computation ──────────────────────
    // Address source: HL (most ops), BC/DE (LDAX/STAX), direct (LDA/STA/LHLD/SHLD)
    wire id_addr_is_hl = dec_needs_hl_read ||
                         (dec_is_store && !dec_is_sta && !dec_is_stax && !dec_is_shld);
    wire id_addr_is_bc = dec_needs_bc_read || (dec_is_stax && dec_rp_sel == 2'b00);
    wire id_addr_is_de = dec_needs_de_read || (dec_is_stax && dec_rp_sel == 2'b01);
    wire id_addr_is_direct = dec_needs_direct_read || dec_is_sta || dec_is_shld;

    wire [15:0] id_mem_addr = id_addr_is_hl     ? {id_fwd_h, id_fwd_l} :
                              id_addr_is_bc     ? {id_fwd_b, id_fwd_c} :
                              id_addr_is_de     ? {id_fwd_d, id_fwd_e} :
                              id_addr_is_direct ? {id_byte3, id_byte2} :
                              16'h0000;

    // ── Branch condition evaluation ───────────────────────
    reg id_cond_met;
    always @(*) begin
        case (dec_branch_cond)
            3'd0: id_cond_met = !id_fwd_flags[3]; // NZ
            3'd1: id_cond_met =  id_fwd_flags[3]; // Z
            3'd2: id_cond_met = !id_fwd_flags[0]; // NC
            3'd3: id_cond_met =  id_fwd_flags[0]; // C
            3'd4: id_cond_met = !id_fwd_flags[1]; // PO
            3'd5: id_cond_met =  id_fwd_flags[1]; // PE
            3'd6: id_cond_met = !id_fwd_flags[4]; // P (positive)
            3'd7: id_cond_met =  id_fwd_flags[4]; // M (minus)
        endcase
    end

    // Branch taken signal
    wire id_branch_taken = id_valid && (
        dec_is_jmp ||
        (dec_is_jcc && id_cond_met) ||
        dec_is_pchl ||
        dec_is_call ||
        (dec_is_ccc && id_cond_met) ||
        dec_is_rst ||
        (dec_is_rstv && id_fwd_flags[6]) ||   // V flag set
        (dec_is_jnx5 && !id_fwd_flags[5]) ||  // X5 flag clear
        (dec_is_jx5 && id_fwd_flags[5])        // X5 flag set
    );

    // Branch target address
    wire [15:0] id_branch_target = dec_is_pchl ? {id_fwd_h, id_fwd_l} :
                                   dec_is_rst  ? {8'h00, 2'b00, id_opcode[5:3], 3'b000} :
                                   dec_is_rstv ? 16'h0040 :
                                                 {id_byte3, id_byte2};

    // Return address for CALL/RST (address of next instruction)
    wire [15:0] id_ret_addr = id_pc + {14'd0, dec_inst_len};

    // ================================================================
    // Pipeline control
    // ================================================================

    always @(*) begin
        if_stall = 1'b0;
        id_stall = 1'b0;
        id_flush = 1'b0;
        ex_stall = 1'b0;

        // EX stalls when multi-cycle instruction hasn't completed
        if (ex_valid && ex_is_multicycle && !ex_completing)
            ex_stall = 1'b1;

        // IF stalls if EX holds memory port
        if (ex_wants_port)
            if_stall = 1'b1;
    end

    // ================================================================
    // Pipeline state machine
    // ================================================================
    integer i_init;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // ── Reset ───────────────────────────────────
            // Register file
            r_a <= 8'h00; r_b <= 8'h00; r_c <= 8'h00; r_d <= 8'h00;
            r_e <= 8'h00; r_h <= 8'h00; r_l <= 8'h00;
            r_sp <= 16'h0000;
            r_flags <= 7'b0000000;
            r_halted <= 1'b0;
            r_inte <= 1'b0;
            r_mask_55 <= 1'b0; r_mask_65 <= 1'b0; r_mask_75 <= 1'b0;
            r_rst75_pending <= 1'b0;
            r_sod_latch <= 1'b0;
            r_halt_return_addr <= 16'h0000;

            // Fetch state
            fetch_pc <= 16'h0000;
            fetch_pending <= 1'b0;
            ibuf_count <= 3'd0;
            for (i_init = 0; i_init < 4; i_init = i_init + 1)
                ibuf[i_init] <= 8'h00;

            // Pipeline registers
            id_valid <= 1'b0;
            id_pc <= 16'h0000;
            id_opcode <= 8'h00;
            id_byte2 <= 8'h00;
            id_byte3 <= 8'h00;

            ex_valid <= 1'b0;
            ex_pc <= 16'h0000;
            ex_opcode <= 8'h00;
            ex_byte2 <= 8'h00;
            ex_byte3 <= 8'h00;
            ex_alu_op <= 4'd0;
            ex_src_sel <= 3'd0;
            ex_dst_sel <= 3'd0;
            ex_rp_sel <= 2'd0;
            ex_writes_reg <= 1'b0;
            ex_writes_flags <= 1'b0;
            ex_flag_mask <= 5'd0;
            ex_operand_a <= 8'h00;
            ex_operand_b <= 8'h00;
            ex_is_hlt <= 1'b0;
            ex_is_mov <= 1'b0;
            ex_is_mvi <= 1'b0;
            ex_is_alu_reg <= 1'b0;
            ex_is_alu_imm <= 1'b0;
            ex_is_inr <= 1'b0;
            ex_is_dcr <= 1'b0;
            ex_is_cma <= 1'b0;
            ex_is_stc <= 1'b0;
            ex_is_cmc <= 1'b0;
            ex_is_load <= 1'b0;
            ex_is_store <= 1'b0;
            ex_is_lxi <= 1'b0;
            ex_is_lhld <= 1'b0;
            ex_is_shld <= 1'b0;
            ex_mem_addr <= 16'h0000;
            ex_phase <= 2'd0;
            ex_is_push <= 1'b0;
            ex_is_pop <= 1'b0;
            ex_is_call <= 1'b0;
            ex_is_ret <= 1'b0;
            ex_is_rst <= 1'b0;
            ex_is_xthl <= 1'b0;
            ex_is_sphl <= 1'b0;
            ex_ret_addr <= 16'h0000;
            ex_stack_lo <= 8'h00;
            ex_old_h <= 8'h00;
            ex_old_l <= 8'h00;
            ex_is_inx <= 1'b0;
            ex_is_dcx <= 1'b0;
            ex_is_dad <= 1'b0;
            ex_is_xchg <= 1'b0;
            ex_is_io_in <= 1'b0;
            ex_is_io_out <= 1'b0;
            ex_is_ei <= 1'b0;
            ex_is_di <= 1'b0;
            ex_is_rim <= 1'b0;
            ex_is_sim <= 1'b0;

            // Bus
            bus_addr <= 16'h0000;
            bus_data_out <= 8'h00;
            bus_rd <= 1'b0;
            bus_wr <= 1'b0;
            stack_wr_addr <= 16'h0000;
            stack_wr_data_lo <= 8'h00;
            stack_wr_data_hi <= 8'h00;
            stack_wr <= 1'b0;
            int_ack <= 1'b0;
            rom_bank <= 8'h00;
            ram_bank <= 3'd0;

        end else begin
            // ── Default: deassert single-cycle signals ──
            bus_rd <= 1'b0;
            bus_wr <= 1'b0;
            stack_wr <= 1'b0;
            int_ack <= 1'b0;

            // ============================================
            // STAGE 1: FETCH (IF)
            // ============================================

            // Handle returning data from a pending fetch
            if (fetch_pending && bus_ready) begin
                // Insert byte into instruction buffer
                ibuf[ibuf_count] <= bus_data_in;
                ibuf_count <= ibuf_count + 3'd1;
                fetch_pending <= 1'b0;
            end

            // Issue new fetch if buffer needs data and port is free
            if (if_granted && !fetch_pending) begin
                bus_addr <= fetch_pc;
                bus_rd <= 1'b1;
                fetch_pc <= fetch_pc + 16'd1;
                fetch_pending <= 1'b1;
            end

            // ============================================
            // STAGE 2: IF → ID transfer
            // ============================================

            // Transfer instruction from buffer to ID (if buffer has enough bytes
            // and ID is free or moving to EX)
            if (ibuf_has_instruction && (!id_valid || !ex_stall)) begin
                id_valid   <= 1'b1;
                id_pc      <= fetch_pc - {13'd0, ibuf_count};  // PC of ibuf[0]
                id_opcode  <= ibuf[0];
                id_byte2   <= (ibuf_inst_len >= 2'd2) ? ibuf[1] : 8'h00;
                id_byte3   <= (ibuf_inst_len >= 2'd3) ? ibuf[2] : 8'h00;

                // Shift buffer: remove consumed bytes
                case (ibuf_inst_len)
                    2'd1: begin
                        ibuf[0] <= ibuf[1];
                        ibuf[1] <= ibuf[2];
                        ibuf[2] <= ibuf[3];
                        ibuf_count <= ibuf_count - 3'd1;
                    end
                    2'd2: begin
                        ibuf[0] <= ibuf[2];
                        ibuf[1] <= ibuf[3];
                        ibuf_count <= ibuf_count - 3'd2;
                    end
                    2'd3: begin
                        ibuf[0] <= ibuf[3];
                        ibuf_count <= ibuf_count - 3'd3;
                    end
                    default: ;
                endcase
            end else if (!ex_stall && id_valid) begin
                // ID moved to EX but no new instruction from buffer
                id_valid <= 1'b0;
            end

            // ============================================
            // STAGE 3: EXECUTE / WRITEBACK
            // ============================================

            if (ex_valid) begin
                if (!ex_is_multicycle) begin
                    // ── Single-cycle operations ─────────────

                    // Register writeback
                    if (ex_writes_reg) begin
                        case (ex_dst_sel)
                            3'd0: r_b <= ex_result;
                            3'd1: r_c <= ex_result;
                            3'd2: r_d <= ex_result;
                            3'd3: r_e <= ex_result;
                            3'd4: r_h <= ex_result;
                            3'd5: r_l <= ex_result;
                            3'd7: r_a <= ex_result;
                            default: ;
                        endcase
                    end

                    // Flag writeback
                    if (ex_writes_flags) begin
                        r_flags <= ex_flags_masked;
                    end

                    // Single-cycle memory write (MOV M,r / MVI M / STA / STAX)
                    if (ex_is_store && !ex_is_load) begin
                        bus_addr <= ex_mem_addr;
                        bus_data_out <= ex_operand_b;
                        bus_wr <= 1'b1;
                    end

                    // LXI rp, imm16
                    if (ex_is_lxi) begin
                        case (ex_rp_sel)
                            2'b00: begin r_b <= ex_byte3; r_c <= ex_byte2; end
                            2'b01: begin r_d <= ex_byte3; r_e <= ex_byte2; end
                            2'b10: begin r_h <= ex_byte3; r_l <= ex_byte2; end
                            2'b11: r_sp <= {ex_byte3, ex_byte2};
                        endcase
                    end

                    // PUSH rp (single-cycle via stack_wr bus)
                    if (ex_is_push) begin
                        stack_wr_addr <= r_sp - 16'd2;
                        case (ex_rp_sel)
                            2'b00: begin stack_wr_data_hi <= r_b; stack_wr_data_lo <= r_c; end
                            2'b01: begin stack_wr_data_hi <= r_d; stack_wr_data_lo <= r_e; end
                            2'b10: begin stack_wr_data_hi <= r_h; stack_wr_data_lo <= r_l; end
                            2'b11: begin  // PSW: {S,Z,X5,AC,0,P,V,CY}
                                stack_wr_data_hi <= r_a;
                                stack_wr_data_lo <= {r_flags[4], r_flags[3], r_flags[5],
                                                     r_flags[2], 1'b0, r_flags[1],
                                                     r_flags[6], r_flags[0]};
                            end
                        endcase
                        stack_wr <= 1'b1;
                        r_sp <= r_sp - 16'd2;
                    end

                    // CALL / RST (push return address, branch handled by ID)
                    if (ex_is_call || ex_is_rst) begin
                        stack_wr_addr <= r_sp - 16'd2;
                        stack_wr_data_hi <= ex_ret_addr[15:8];
                        stack_wr_data_lo <= ex_ret_addr[7:0];
                        stack_wr <= 1'b1;
                        r_sp <= r_sp - 16'd2;
                    end

                    // SPHL
                    if (ex_is_sphl) begin
                        r_sp <= {r_h, r_l};
                    end

                    // INX rp (16-bit increment, X5 flag)
                    if (ex_is_inx) begin : inx_block
                        reg [15:0] inx_val;
                        case (ex_rp_sel)
                            2'b00: inx_val = {r_b, r_c};
                            2'b01: inx_val = {r_d, r_e};
                            2'b10: inx_val = {r_h, r_l};
                            2'b11: inx_val = r_sp;
                        endcase
                        case (ex_rp_sel)
                            2'b00: {r_b, r_c} <= inx_val + 16'd1;
                            2'b01: {r_d, r_e} <= inx_val + 16'd1;
                            2'b10: {r_h, r_l} <= inx_val + 16'd1;
                            2'b11: r_sp <= inx_val + 16'd1;
                        endcase
                        r_flags[5] <= (inx_val == 16'hFFFF);  // X5: FFFF→0000
                    end

                    // DCX rp (16-bit decrement, X5 flag)
                    if (ex_is_dcx) begin : dcx_block
                        reg [15:0] dcx_val;
                        case (ex_rp_sel)
                            2'b00: dcx_val = {r_b, r_c};
                            2'b01: dcx_val = {r_d, r_e};
                            2'b10: dcx_val = {r_h, r_l};
                            2'b11: dcx_val = r_sp;
                        endcase
                        case (ex_rp_sel)
                            2'b00: {r_b, r_c} <= dcx_val - 16'd1;
                            2'b01: {r_d, r_e} <= dcx_val - 16'd1;
                            2'b10: {r_h, r_l} <= dcx_val - 16'd1;
                            2'b11: r_sp <= dcx_val - 16'd1;
                        endcase
                        r_flags[5] <= (dcx_val == 16'h0000);  // X5: 0000→FFFF
                    end

                    // DAD rp (HL += rp, CY only)
                    if (ex_is_dad) begin : dad_block
                        begin : dad_vars
                            reg [16:0] dad_sum;
                            case (ex_rp_sel)
                                2'b00: dad_sum = {1'b0, r_h, r_l} + {1'b0, r_b, r_c};
                                2'b01: dad_sum = {1'b0, r_h, r_l} + {1'b0, r_d, r_e};
                                2'b10: dad_sum = {1'b0, r_h, r_l} + {1'b0, r_h, r_l};
                                2'b11: dad_sum = {1'b0, r_h, r_l} + {1'b0, r_sp};
                            endcase
                            r_h <= dad_sum[15:8];
                            r_l <= dad_sum[7:0];
                            r_flags <= {r_flags[6:1], dad_sum[16]};
                        end
                    end

                    // XCHG (swap DE ↔ HL)
                    if (ex_is_xchg) begin
                        r_d <= r_h; r_e <= r_l;
                        r_h <= r_d; r_l <= r_e;
                    end

                    // IN port (capture io_data_in → A)
                    if (ex_is_io_in) begin
                        r_a <= io_data_in;
                    end
                    // OUT port: io_wr/io_port/io_data_out driven combinationally
                    // Bank register capture (internal ports F0h/F1h)
                    if (ex_is_io_out) begin
                        if (ex_byte2 == 8'hF0) rom_bank <= r_a;
                        if (ex_byte2 == 8'hF1) ram_bank <= r_a[2:0];
                    end

                    // EI / DI
                    if (ex_is_ei) r_inte <= 1'b1;
                    if (ex_is_di) r_inte <= 1'b0;

                    // RIM: read interrupt mask into A
                    if (ex_is_rim) begin
                        r_a <= {sid, r_rst75_pending, rst65_level, rst55_level,
                                r_inte, r_mask_75, r_mask_65, r_mask_55};
                    end

                    // SIM: set interrupt mask from A
                    if (ex_is_sim) begin
                        if (r_a[6]) r_sod_latch <= r_a[7];    // SOE: latch SOD
                        if (r_a[4]) r_rst75_pending <= 1'b0;   // R7.5: reset latch
                        if (r_a[3]) begin                      // MSE: update masks
                            r_mask_55 <= r_a[0];
                            r_mask_65 <= r_a[1];
                            r_mask_75 <= r_a[2];
                        end
                    end

                    // HLT
                    if (ex_is_hlt) begin
                        r_halted <= 1'b1;
                    end

                    // ── Undocumented 8085 instructions (single-cycle) ──

                    // DSUB: HL = HL - BC, all flags
                    if (ex_is_dsub) begin : dsub_block
                        reg [16:0] dsub_sum;
                        reg [7:0]  dsub_lo;
                        reg [4:0]  dsub_half;
                        dsub_sum = {1'b0, r_h, r_l} - {1'b0, r_b, r_c};
                        dsub_lo = dsub_sum[7:0];
                        dsub_half = {1'b0, r_l[3:0]} - {1'b0, r_c[3:0]};
                        r_h <= dsub_sum[15:8];
                        r_l <= dsub_lo;
                        r_flags <= {
                            // V: 2's complement overflow of 16-bit subtraction
                            (r_h[7] ^ r_b[7]) & (r_h[7] ^ dsub_sum[15]),
                            // X5
                            (r_h[7] & ~r_b[7] & ~dsub_sum[15]) | (~r_h[7] & r_b[7] & dsub_sum[15]),
                            // S,Z,AC,P from low byte; CY from 16-bit borrow
                            dsub_lo[7],
                            dsub_lo == 8'd0,
                            dsub_half[4],
                            ~(dsub_lo[0] ^ dsub_lo[1] ^ dsub_lo[2] ^ dsub_lo[3] ^
                              dsub_lo[4] ^ dsub_lo[5] ^ dsub_lo[6] ^ dsub_lo[7]),
                            dsub_sum[16]
                        };
                    end

                    // ARHL: arithmetic shift right HL, CY = L[0]
                    if (ex_is_arhl) begin
                        r_h <= {r_h[7], r_h[7:1]};
                        r_l <= {r_h[0], r_l[7:1]};
                        r_flags[0] <= r_l[0];  // CY
                    end

                    // RDEL: rotate DE left through carry
                    if (ex_is_rdel) begin
                        r_d <= {r_d[6:0], r_e[7]};
                        r_e <= {r_e[6:0], r_flags[0]};
                        r_flags[0] <= r_d[7];  // CY
                        r_flags[6] <= r_d[7] ^ r_d[6];  // V
                    end

                    // LDHI: DE = HL + imm8
                    if (ex_is_ldhi) begin
                        {r_d, r_e} <= {r_h, r_l} + {8'h00, ex_byte2};
                    end

                    // LDSI: DE = SP + imm8
                    if (ex_is_ldsi) begin
                        {r_d, r_e} <= r_sp + {8'h00, ex_byte2};
                    end

                    // RSTV: push return address (branch handled by ID)
                    // Only ex_is_rstv when V was set; if V=0 it's a NOP (ex_is_rstv=0)
                    if (ex_is_rstv) begin
                        stack_wr_addr <= r_sp - 16'd2;
                        stack_wr_data_hi <= ex_ret_addr[15:8];
                        stack_wr_data_lo <= ex_ret_addr[7:0];
                        stack_wr <= 1'b1;
                        r_sp <= r_sp - 16'd2;
                    end

                    ex_valid <= 1'b0;

                end else begin
                    // ── Multi-cycle operations ──────────────

                    case (ex_phase)
                        2'd0: begin
                            // Phase 0: Issue first memory access
                            if (ex_is_shlx) begin
                                // SHLX phase 0: write L to (DE)
                                bus_addr <= {r_d, r_e};
                                bus_data_out <= r_l;
                                bus_wr <= 1'b1;
                            end else if (ex_is_lhlx) begin
                                // LHLX phase 0: read from (DE)
                                bus_addr <= {r_d, r_e};
                                bus_rd <= 1'b1;
                            end else if (ex_is_load) begin
                                bus_addr <= ex_mem_addr;
                                bus_rd <= 1'b1;
                            end else if (ex_is_shld) begin
                                // SHLD phase 0: write L to addr
                                bus_addr <= ex_mem_addr;
                                bus_data_out <= r_l;
                                bus_wr <= 1'b1;
                            end else if (ex_is_pop || ex_is_ret || ex_is_xthl) begin
                                // Stack read phase 0: read lo byte from SP
                                bus_addr <= r_sp;
                                bus_rd <= 1'b1;
                            end
                            ex_phase <= 2'd1;
                        end

                        2'd1: begin
                            if (ex_is_shlx) begin
                                // SHLX phase 1: write H to (DE)+1
                                bus_addr <= {r_d, r_e} + 16'd1;
                                bus_data_out <= r_h;
                                bus_wr <= 1'b1;
                                ex_valid <= 1'b0;
                                ex_phase <= 2'd0;
                            end else if (ex_is_shld) begin
                                // SHLD phase 1: write H to addr+1
                                bus_addr <= ex_mem_addr + 16'd1;
                                bus_data_out <= r_h;
                                bus_wr <= 1'b1;
                                ex_valid <= 1'b0;
                                ex_phase <= 2'd0;
                            end else if (ex_bus_ready) begin
                                if (ex_is_pop || ex_is_ret || ex_is_xthl) begin
                                    // Stack read phase 1: capture lo, read hi
                                    ex_stack_lo <= bus_data_in;
                                    bus_addr <= r_sp + 16'd1;
                                    bus_rd <= 1'b1;
                                    ex_phase <= 2'd2;
                                end else if (ex_is_lhld) begin
                                    // LHLD phase 1: capture L, read H
                                    r_l <= bus_data_in;
                                    bus_addr <= ex_mem_addr + 16'd1;
                                    bus_rd <= 1'b1;
                                    ex_phase <= 2'd2;
                                end else if (ex_is_lhlx) begin
                                    // LHLX phase 1: capture L, read H from (DE)+1
                                    r_l <= bus_data_in;
                                    bus_addr <= {r_d, r_e} + 16'd1;
                                    bus_rd <= 1'b1;
                                    ex_phase <= 2'd2;
                                end else begin
                                    // Simple load / ALU M / INR M / DCR M
                                    // ALU has bus_data_in via alu_opb_final mux
                                    if (ex_writes_reg) begin
                                        case (ex_dst_sel)
                                            3'd0: r_b <= ex_result;
                                            3'd1: r_c <= ex_result;
                                            3'd2: r_d <= ex_result;
                                            3'd3: r_e <= ex_result;
                                            3'd4: r_h <= ex_result;
                                            3'd5: r_l <= ex_result;
                                            3'd7: r_a <= ex_result;
                                            default: ;
                                        endcase
                                    end
                                    if (ex_writes_flags) begin
                                        r_flags <= ex_flags_masked;
                                    end
                                    // INR M / DCR M: write ALU result back to memory
                                    if (ex_is_store) begin
                                        bus_addr <= ex_mem_addr;
                                        bus_data_out <= ex_result;
                                        bus_wr <= 1'b1;
                                    end
                                    ex_valid <= 1'b0;
                                    ex_phase <= 2'd0;
                                end
                            end
                            // else: wait for bus_ready
                        end

                        2'd2: begin
                            if (ex_bus_ready) begin
                                if (ex_is_pop) begin
                                    // POP: writeback register pair
                                    case (ex_rp_sel)
                                        2'b00: begin r_b <= bus_data_in; r_c <= ex_stack_lo; end
                                        2'b01: begin r_d <= bus_data_in; r_e <= ex_stack_lo; end
                                        2'b10: begin r_h <= bus_data_in; r_l <= ex_stack_lo; end
                                        2'b11: begin  // PSW
                                            r_a <= bus_data_in;
                                            // PSW byte: {S,Z,X5,AC,0,P,V,CY}
                                            r_flags <= {ex_stack_lo[1], ex_stack_lo[5],  // V, X5
                                                        ex_stack_lo[7], ex_stack_lo[6],  // S, Z
                                                        ex_stack_lo[4], ex_stack_lo[2],  // AC, P
                                                        ex_stack_lo[0]};                 // CY
                                        end
                                    endcase
                                    r_sp <= r_sp + 16'd2;
                                    ex_valid <= 1'b0;
                                    ex_phase <= 2'd0;
                                end else if (ex_is_ret) begin
                                    // RET: branch handled by ex_ret_completing block below
                                    // Just complete the multi-cycle; branch flush overrides
                                    ex_valid <= 1'b0;
                                    ex_phase <= 2'd0;
                                end else if (ex_is_xthl) begin
                                    // XTHL: load new H,L; write old H,L to stack
                                    r_l <= ex_stack_lo;
                                    r_h <= bus_data_in;
                                    stack_wr_addr <= r_sp;
                                    stack_wr_data_lo <= ex_old_l;
                                    stack_wr_data_hi <= ex_old_h;
                                    stack_wr <= 1'b1;
                                    ex_valid <= 1'b0;
                                    ex_phase <= 2'd0;
                                end else begin
                                    // LHLD phase 2: capture H
                                    r_h <= bus_data_in;
                                    ex_valid <= 1'b0;
                                    ex_phase <= 2'd0;
                                end
                            end
                            // else: wait for bus_ready
                        end

                        default: begin
                            ex_valid <= 1'b0;
                            ex_phase <= 2'd0;
                        end
                    endcase
                end
            end

            // ============================================
            // STAGE 2: ID → EX transfer
            // ============================================
            // Placed AFTER EX execution so that when both fire at the
            // same posedge (EX completing + new instruction from ID),
            // ID→EX's ex_valid<=1 wins over EX's ex_valid<=0.

            // Transfer ID to EX (if ID has a valid instruction and EX is not stalled)
            if (id_valid && !ex_stall) begin
                ex_valid       <= 1'b1;
                ex_pc          <= id_pc;
                ex_opcode      <= id_opcode;
                ex_byte2       <= id_byte2;
                ex_byte3       <= id_byte3;
                ex_alu_op      <= dec_alu_op;
                ex_src_sel     <= dec_src_sel;
                ex_dst_sel     <= dec_dst_sel;
                ex_rp_sel      <= dec_rp_sel;
                ex_writes_reg  <= dec_writes_reg && !dec_is_io_in && !dec_is_rim;
                ex_writes_flags <= dec_writes_flags && !dec_is_dad;
                ex_flag_mask   <= dec_flag_mask;
                ex_operand_a   <= id_operand_a;
                ex_operand_b   <= id_operand_b;
                ex_is_hlt      <= dec_is_hlt;
                ex_is_mov      <= dec_is_mov;
                ex_is_mvi      <= dec_is_mvi;
                ex_is_alu_reg  <= dec_is_alu_reg;
                ex_is_alu_imm  <= dec_is_alu_imm;
                ex_is_inr      <= dec_is_inr;
                ex_is_dcr      <= dec_is_dcr;
                ex_is_cma      <= dec_is_cma;
                ex_is_stc      <= dec_is_stc;
                ex_is_cmc      <= dec_is_cmc;
                ex_is_load     <= dec_is_load;
                ex_is_store    <= dec_is_store;
                ex_is_lxi      <= dec_is_lxi;
                ex_is_lhld     <= dec_is_lhld;
                ex_is_shld     <= dec_is_shld;
                ex_mem_addr    <= id_mem_addr;
                ex_phase       <= 2'd0;
                ex_is_push     <= dec_is_push;
                ex_is_pop      <= dec_is_pop;
                ex_is_call     <= dec_is_call || (dec_is_ccc && id_cond_met);
                ex_is_ret      <= dec_is_ret  || (dec_is_rcc && id_cond_met);
                ex_is_rst      <= dec_is_rst;
                ex_is_xthl     <= dec_is_xthl;
                ex_is_sphl     <= dec_is_sphl;
                ex_ret_addr    <= id_ret_addr;
                ex_old_h       <= id_fwd_h;
                ex_old_l       <= id_fwd_l;
                ex_is_inx      <= dec_is_inx;
                ex_is_dcx      <= dec_is_dcx;
                ex_is_dad      <= dec_is_dad;
                ex_is_xchg     <= dec_is_xchg;
                ex_is_io_in    <= dec_is_io_in;
                ex_is_io_out   <= dec_is_io_out;
                ex_is_ei       <= dec_is_ei;
                ex_is_di       <= dec_is_di;
                ex_is_rim      <= dec_is_rim;
                ex_is_sim      <= dec_is_sim;
                ex_is_dsub     <= dec_is_dsub;
                ex_is_arhl     <= dec_is_arhl;
                ex_is_rdel     <= dec_is_rdel;
                ex_is_ldhi     <= dec_is_ldhi;
                ex_is_ldsi     <= dec_is_ldsi;
                ex_is_shlx     <= dec_is_shlx;
                ex_is_lhlx     <= dec_is_lhlx;
                ex_is_rstv     <= dec_is_rstv && id_fwd_flags[6];  // Only active if V=1 at decode
            end else if (!ex_stall) begin
                // Bubble: no valid instruction from ID
                ex_valid <= 1'b0;
            end

            // ============================================
            // Pipeline flush on taken branch
            // ============================================
            // Must be last: overrides IF→ID transfer and ibuf updates.
            // Also cancels any bus_rd issued by IF on this same cycle,
            // preventing stale data from being captured into ibuf.
            // Gate with !ex_stall: during multi-cycle EX, ID is frozen
            // and forwarded flags may be stale.
            if (id_branch_taken && !ex_stall) begin
                ibuf_count    <= 3'd0;
                fetch_pc      <= id_branch_target;
                fetch_pending <= 1'b0;
                id_valid      <= 1'b0;
                bus_rd        <= 1'b0;
            end

            // ============================================
            // EX-stage branch (RET completing)
            // ============================================
            // Placed AFTER ID branch flush: NBA priority ensures
            // ex_valid<=0 overrides ID→EX transfer's ex_valid<=1.
            if (ex_ret_completing) begin
                fetch_pc      <= {bus_data_in, ex_stack_lo};
                ibuf_count    <= 3'd0;
                fetch_pending <= 1'b0;
                id_valid      <= 1'b0;
                ex_valid      <= 1'b0;
                bus_rd        <= 1'b0;
                r_sp          <= r_sp + 16'd2;
            end

            // ============================================
            // HLT: flush pipeline and save return address
            // ============================================
            if (ex_valid && !ex_is_multicycle && ex_is_hlt) begin
                r_halt_return_addr <= int_ret_addr;
                ibuf_count    <= 3'd0;
                fetch_pending <= 1'b0;
                id_valid      <= 1'b0;
                ex_valid      <= 1'b0;
                bus_rd        <= 1'b0;
            end

            // ============================================
            // Interrupt handling (highest NBA priority)
            // ============================================
            if (int_take) begin
                // Push return address to stack
                stack_wr_addr     <= r_sp - 16'd2;
                stack_wr_data_hi  <= int_ret_addr[15:8];
                stack_wr_data_lo  <= int_ret_addr[7:0];
                stack_wr          <= 1'b1;
                r_sp              <= r_sp - 16'd2;
                // Redirect fetch to interrupt vector
                fetch_pc      <= int_vector;
                ibuf_count    <= 3'd0;
                fetch_pending <= 1'b0;
                id_valid      <= 1'b0;
                ex_valid      <= 1'b0;
                bus_rd        <= 1'b0;
                // Disable interrupts and acknowledge
                r_inte        <= 1'b0;
                int_ack       <= 1'b1;
                // Wake from halt
                r_halted      <= 1'b0;
            end

        end // !reset
    end // always

endmodule
