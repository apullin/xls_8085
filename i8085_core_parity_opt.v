// i8085_core_parity_opt.v - XLS core with parity optimization
// Single parity calculation instead of 18 speculative ones
//
// Key change: Remove p__1 through p__20, compute parity once on final A result

module __i8085_core__execute_parity_opt(
  input wire [99:0] state,
  input wire [7:0] opcode,
  input wire [7:0] byte2,
  input wire [7:0] byte3,
  input wire [7:0] mem_read_data,
  input wire [7:0] stack_read_lo,
  input wire [7:0] stack_read_hi,
  input wire [7:0] io_read_data,
  input wire sid,
  input wire rst55_level,
  input wire rst65_level,
  output wire [175:0] out
);

  // Priority select functions (same as XLS)
  function automatic priority_sel_1b_7way (input reg [6:0] sel, input reg case0, input reg case1, input reg case2, input reg case3, input reg case4, input reg case5, input reg case6, input reg default_value);
    begin
      casez (sel)
        7'b??????1: priority_sel_1b_7way = case0;
        7'b?????10: priority_sel_1b_7way = case1;
        7'b????100: priority_sel_1b_7way = case2;
        7'b???1000: priority_sel_1b_7way = case3;
        7'b??10000: priority_sel_1b_7way = case4;
        7'b?100000: priority_sel_1b_7way = case5;
        7'b1000000: priority_sel_1b_7way = case6;
        7'b0000000: priority_sel_1b_7way = default_value;
        default: priority_sel_1b_7way = 1'dx;
      endcase
    end
  endfunction

  function automatic [15:0] priority_sel_16b_3way (input reg [2:0] sel, input reg [15:0] case0, input reg [15:0] case1, input reg [15:0] case2, input reg [15:0] default_value);
    begin
      casez (sel)
        3'b??1: priority_sel_16b_3way = case0;
        3'b?10: priority_sel_16b_3way = case1;
        3'b100: priority_sel_16b_3way = case2;
        3'b000: priority_sel_16b_3way = default_value;
        default: priority_sel_16b_3way = 16'dx;
      endcase
    end
  endfunction

  function automatic [7:0] priority_sel_8b_3way (input reg [2:0] sel, input reg [7:0] case0, input reg [7:0] case1, input reg [7:0] case2, input reg [7:0] default_value);
    begin
      casez (sel)
        3'b??1: priority_sel_8b_3way = case0;
        3'b?10: priority_sel_8b_3way = case1;
        3'b100: priority_sel_8b_3way = case2;
        3'b000: priority_sel_8b_3way = default_value;
        default: priority_sel_8b_3way = 8'dx;
      endcase
    end
  endfunction

  // State extraction
  wire [7:0] state_reg_b = state[99:92];
  wire [7:0] state_reg_c = state[91:84];
  wire [7:0] state_reg_d = state[83:76];
  wire [7:0] state_reg_e = state[75:68];
  wire [7:0] state_reg_h = state[67:60];
  wire [7:0] state_reg_l = state[59:52];
  wire [7:0] a = state[51:44];
  wire [15:0] state_sp = state[43:28];
  wire [15:0] state_pc = state[27:12];
  wire [4:0] state_flags = state[11:7];
  wire state_halted = state[6];
  wire state_inte = state[5];
  wire state_mask_55 = state[4];
  wire state_mask_65 = state[3];
  wire state_mask_75 = state[2];
  wire state_rst75_pending = state[1];
  wire state_sod_latch = state[0];

  // Flag extraction
  wire f_sign = state_flags[4];
  wire f_zero = state_flags[3];
  wire f_aux = state_flags[2];
  wire f_parity = state_flags[1];
  wire f_carry = state_flags[0];

  // Opcode fields
  wire [2:0] nnn = opcode[5:3];
  wire [2:0] sss = opcode[2:0];
  wire [1:0] rp = opcode[5:4];

  // Register pair encoding
  wire rp_is_bc = (rp == 2'b00);
  wire rp_is_de = (rp == 2'b01);
  wire rp_is_hl = (rp == 2'b10);
  wire rp_is_sp = (rp == 2'b11);

  // Register index encoding
  wire nnn_is_b = (nnn == 3'b000);
  wire nnn_is_c = (nnn == 3'b001);
  wire nnn_is_d = (nnn == 3'b010);
  wire nnn_is_e = (nnn == 3'b011);
  wire nnn_is_h = (nnn == 3'b100);
  wire nnn_is_l = (nnn == 3'b101);
  wire nnn_is_m = (nnn == 3'b110);
  wire nnn_is_a = (nnn == 3'b111);

  wire sss_is_b = (sss == 3'b000);
  wire sss_is_c = (sss == 3'b001);
  wire sss_is_d = (sss == 3'b010);
  wire sss_is_e = (sss == 3'b011);
  wire sss_is_h = (sss == 3'b100);
  wire sss_is_l = (sss == 3'b101);
  wire sss_is_m = (sss == 3'b110);
  wire sss_is_a = (sss == 3'b111);

  // Register file read (optimized mux using case)
  reg [7:0] val_nnn, val_sss;
  always @(*) begin
    case (nnn)
      3'b000: val_nnn = state_reg_b;
      3'b001: val_nnn = state_reg_c;
      3'b010: val_nnn = state_reg_d;
      3'b011: val_nnn = state_reg_e;
      3'b100: val_nnn = state_reg_h;
      3'b101: val_nnn = state_reg_l;
      3'b110: val_nnn = mem_read_data;  // M
      3'b111: val_nnn = a;
      default: val_nnn = 8'hxx;
    endcase
    case (sss)
      3'b000: val_sss = state_reg_b;
      3'b001: val_sss = state_reg_c;
      3'b010: val_sss = state_reg_d;
      3'b011: val_sss = state_reg_e;
      3'b100: val_sss = state_reg_h;
      3'b101: val_sss = state_reg_l;
      3'b110: val_sss = mem_read_data;  // M
      3'b111: val_sss = a;
      default: val_sss = 8'hxx;
    endcase
  end

  // Register pairs
  wire [15:0] hl = {state_reg_h, state_reg_l};
  wire [15:0] bc = {state_reg_b, state_reg_c};
  wire [15:0] de = {state_reg_d, state_reg_e};
  wire [15:0] immediate16 = {byte3, byte2};

  // Common opcode patterns
  wire [7:0] op_masked_c7 = opcode & 8'hc7;
  wire [7:0] op_masked_cf = opcode & 8'hcf;

  // ALU operations
  wire is_alu_r = (opcode[7:6] == 2'b10) & ~sss_is_m;
  wire is_alu_m = (opcode[7:6] == 2'b10) & sss_is_m;
  wire is_alu_i = (opcode[7:6] == 2'b11) & (opcode[2:0] == 3'b110);

  wire [2:0] alu_op = opcode[5:3];
  wire [7:0] alu_b = is_alu_i ? byte2 : val_sss;

  // Adder/subtractor
  wire alu_is_sub = alu_op[2] & ~alu_op[1];  // SUB, SBB, CMP
  wire alu_use_cy = alu_op[0] & ~alu_op[2];  // ADC, SBB
  wire [7:0] alu_b_inv = alu_is_sub ? ~alu_b : alu_b;
  wire alu_cin = alu_is_sub ? (alu_use_cy ? ~f_carry : 1'b1) :
                              (alu_use_cy ? f_carry : 1'b0);
  wire [8:0] alu_sum = {1'b0, a} + {1'b0, alu_b_inv} + {8'b0, alu_cin};
  wire [7:0] alu_add_result = alu_sum[7:0];
  wire alu_cout = alu_is_sub ? ~alu_sum[8] : alu_sum[8];

  // Low nibble for aux carry
  wire [4:0] alu_lo = {1'b0, a[3:0]} + {1'b0, alu_b_inv[3:0]} + {4'b0, alu_cin};
  wire alu_aux = alu_lo[4];

  // Logic ops
  wire [7:0] alu_and = a & alu_b;
  wire [7:0] alu_xor = a ^ alu_b;
  wire [7:0] alu_or = a | alu_b;

  // ALU result select
  reg [7:0] alu_result;
  always @(*) begin
    case (alu_op)
      3'b000, 3'b001: alu_result = alu_add_result;  // ADD, ADC
      3'b010, 3'b011, 3'b111: alu_result = alu_add_result;  // SUB, SBB, CMP
      3'b100: alu_result = alu_and;
      3'b101: alu_result = alu_xor;
      3'b110: alu_result = alu_or;
      default: alu_result = alu_add_result;
    endcase
  end

  wire is_cmp = (alu_op == 3'b111);

  // INR/DCR
  wire is_inr = (op_masked_c7 == 8'h04);
  wire is_dcr = (op_masked_c7 == 8'h05);
  wire [8:0] inr_sum = {1'b0, val_nnn} + 9'd1;
  wire [8:0] dcr_sum = {1'b0, val_nnn} + 9'h1ff;
  wire [7:0] inr_result = inr_sum[7:0];
  wire [7:0] dcr_result = dcr_sum[7:0];
  wire [4:0] inr_lo = {1'b0, val_nnn[3:0]} + 5'd1;
  wire [4:0] dcr_lo = {1'b0, val_nnn[3:0]} + 5'h1f;

  // Rotate operations
  wire is_rlc = (opcode == 8'h07);
  wire is_rrc = (opcode == 8'h0f);
  wire is_ral = (opcode == 8'h17);
  wire is_rar = (opcode == 8'h1f);
  wire is_rot = is_rlc | is_rrc | is_ral | is_rar;

  wire [7:0] rlc_result = {a[6:0], a[7]};
  wire [7:0] rrc_result = {a[0], a[7:1]};
  wire [7:0] ral_result = {a[6:0], f_carry};
  wire [7:0] rar_result = {f_carry, a[7:1]};
  wire rot_cout = is_rlc ? a[7] : is_rrc ? a[0] : is_ral ? a[7] : a[0];

  reg [7:0] rot_result;
  always @(*) begin
    case ({is_rar, is_ral, is_rrc, is_rlc})
      4'b0001: rot_result = rlc_result;
      4'b0010: rot_result = rrc_result;
      4'b0100: rot_result = ral_result;
      4'b1000: rot_result = rar_result;
      default: rot_result = a;
    endcase
  end

  // DAA
  wire is_daa = (opcode == 8'h27);
  wire daa_add_lo = (a[3:0] > 4'h9) | f_aux;
  wire [7:0] daa_tmp = daa_add_lo ? (a + 8'h06) : a;
  wire daa_add_hi = (daa_tmp[7:4] > 4'h9) | f_carry;
  wire [7:0] daa_result = daa_add_hi ? (daa_tmp + 8'h60) : daa_tmp;
  wire daa_cout = f_carry | daa_add_hi;

  // CMA, CMC, STC
  wire is_cma = (opcode == 8'h2f);
  wire is_cmc = (opcode == 8'h3f);
  wire is_stc = (opcode == 8'h37);

  // MOV, MVI, LXI
  wire is_mov = (opcode[7:6] == 2'b01) & (opcode != 8'h76);  // Not HLT
  wire is_mvi = (op_masked_c7 == 8'h06);
  wire is_lxi = (op_masked_cf == 8'h01);

  // Load/Store
  wire is_lda = (opcode == 8'h3a);
  wire is_sta = (opcode == 8'h32);
  wire is_lhld = (opcode == 8'h2a);
  wire is_shld = (opcode == 8'h22);
  wire is_ldax = (opcode == 8'h0a) | (opcode == 8'h1a);
  wire is_stax = (opcode == 8'h02) | (opcode == 8'h12);

  // INX/DCX/DAD
  wire is_inx = (op_masked_cf == 8'h03);
  wire is_dcx = (op_masked_cf == 8'h0b);
  wire is_dad = (op_masked_cf == 8'h09);

  // Register pair value for DAD/INX/DCX
  reg [15:0] rp_val;
  always @(*) begin
    case (rp)
      2'b00: rp_val = bc;
      2'b01: rp_val = de;
      2'b10: rp_val = hl;
      2'b11: rp_val = state_sp;
      default: rp_val = 16'hxxxx;
    endcase
  end

  wire [16:0] dad_sum = {1'b0, hl} + {1'b0, rp_val};
  wire [15:0] inx_result = rp_val + 16'd1;
  wire [15:0] dcx_result = rp_val - 16'd1;

  // Jump/Call/Return
  wire is_jmp = (opcode == 8'hc3);
  wire is_jcc = (opcode[7:6] == 2'b11) & (opcode[2:0] == 3'b010);
  wire is_call = (opcode == 8'hcd);
  wire is_ccc = (opcode[7:6] == 2'b11) & (opcode[2:0] == 3'b100);
  wire is_ret = (opcode == 8'hc9);
  wire is_rcc = (opcode[7:6] == 2'b11) & (opcode[2:0] == 3'b000);
  wire is_rst = (opcode[7:6] == 2'b11) & (opcode[2:0] == 3'b111);
  wire is_pchl = (opcode == 8'he9);

  // Condition evaluation
  reg cond_met;
  always @(*) begin
    case (nnn)
      3'b000: cond_met = ~f_zero;   // NZ
      3'b001: cond_met = f_zero;    // Z
      3'b010: cond_met = ~f_carry;  // NC
      3'b011: cond_met = f_carry;   // C
      3'b100: cond_met = ~f_parity; // PO
      3'b101: cond_met = f_parity;  // PE
      3'b110: cond_met = ~f_sign;   // P
      3'b111: cond_met = f_sign;    // M
      default: cond_met = 1'b1;
    endcase
  end

  // Stack operations
  wire is_push = (op_masked_cf == 8'hc5);
  wire is_pop = (op_masked_cf == 8'hc1);
  wire is_xthl = (opcode == 8'he3);
  wire is_sphl = (opcode == 8'hf9);

  // I/O
  wire is_in = (opcode == 8'hdb);
  wire is_out = (opcode == 8'hd3);

  // Interrupts
  wire is_ei = (opcode == 8'hfb);
  wire is_di = (opcode == 8'hf3);
  wire is_rim = (opcode == 8'h20);
  wire is_sim = (opcode == 8'h30);
  wire is_hlt = (opcode == 8'h76);
  wire is_nop = (opcode == 8'h00);
  wire is_xchg = (opcode == 8'heb);

  // Address calculations
  wire [15:0] pc_p1 = state_pc + 16'd1;
  wire [15:0] pc_p2 = state_pc + 16'd2;
  wire [15:0] pc_p3 = state_pc + 16'd3;
  wire [15:0] sp_m2 = state_sp - 16'd2;
  wire [15:0] sp_p2 = state_sp + 16'd2;
  wire [15:0] rst_vec = {10'b0, nnn, 3'b0};
  wire [15:0] ret_addr = {stack_read_hi, stack_read_lo};

  // =========================================================================
  // Result computation - final accumulator value
  // =========================================================================

  reg [7:0] next_a;
  always @(*) begin
    if (state_halted | is_nop | is_hlt)
      next_a = a;
    else if (is_alu_r | is_alu_m | is_alu_i)
      next_a = is_cmp ? a : alu_result;
    else if (is_rot)
      next_a = rot_result;
    else if (is_cma)
      next_a = ~a;
    else if (is_daa)
      next_a = daa_result;
    else if (is_lda | is_ldax)
      next_a = mem_read_data;
    else if (is_in)
      next_a = io_read_data;
    else if (is_rim)
      next_a = {sid, state_rst75_pending, rst65_level, rst55_level,
                state_inte, state_mask_75, state_mask_65, state_mask_55};
    else if (is_mov & nnn_is_a)
      next_a = val_sss;
    else if (is_mvi & nnn_is_a)
      next_a = byte2;
    else if (is_inr & nnn_is_a)
      next_a = inr_result;
    else if (is_dcr & nnn_is_a)
      next_a = dcr_result;
    else if (is_pop & rp_is_sp)  // POP PSW
      next_a = stack_read_hi;
    else
      next_a = a;
  end

  // =========================================================================
  // SINGLE PARITY CALCULATION (the optimization!)
  // =========================================================================

  // Determine the value that needs parity computed
  wire [7:0] parity_val = (is_alu_r | is_alu_m | is_alu_i) ? alu_result :
                          (is_inr & ~nnn_is_m) ? inr_result :
                          (is_dcr & ~nnn_is_m) ? dcr_result :
                          (is_daa) ? daa_result :
                          (is_pop & rp_is_sp) ? stack_read_lo :  // Flags from stack
                          a;

  // Single XOR tree for parity
  wire new_parity = ~(parity_val[0] ^ parity_val[1] ^ parity_val[2] ^ parity_val[3] ^
                      parity_val[4] ^ parity_val[5] ^ parity_val[6] ^ parity_val[7]);

  // =========================================================================
  // Flag computation
  // =========================================================================

  wire update_szp = is_alu_r | is_alu_m | is_alu_i | is_inr | is_dcr | is_daa;
  wire update_c = is_alu_r | is_alu_m | is_alu_i | is_daa | is_rot | is_cmc | is_stc | is_dad;
  wire update_a = is_alu_r | is_alu_m | is_alu_i | is_inr | is_dcr | is_daa;

  wire new_sign = parity_val[7];
  wire new_zero = (parity_val == 8'h00);

  wire new_aux = (is_alu_r | is_alu_m | is_alu_i) ? alu_aux :
                 is_inr ? inr_lo[4] :
                 is_dcr ? dcr_lo[4] :
                 is_daa ? daa_add_lo :
                 f_aux;

  wire new_carry = is_rot ? rot_cout :
                   is_cmc ? ~f_carry :
                   is_stc ? 1'b1 :
                   is_dad ? dad_sum[16] :
                   is_daa ? daa_cout :
                   (is_alu_r | is_alu_m | is_alu_i) ? alu_cout :
                   f_carry;

  // Flags from POP PSW
  wire [4:0] pop_flags = {stack_read_lo[7], stack_read_lo[6],
                          stack_read_lo[4], stack_read_lo[2], stack_read_lo[0]};

  wire [4:0] next_flags = (is_pop & rp_is_sp) ? pop_flags :
                          {update_szp ? new_sign : f_sign,
                           update_szp ? new_zero : f_zero,
                           update_a ? new_aux : f_aux,
                           update_szp ? new_parity : f_parity,
                           update_c ? new_carry : f_carry};

  // =========================================================================
  // Register outputs
  // =========================================================================

  // B register
  wire [7:0] next_b = (is_pop & rp_is_bc) ? stack_read_hi :
                      (is_lxi & rp_is_bc) ? byte3 :
                      (is_inx & rp_is_bc) ? inx_result[15:8] :
                      (is_dcx & rp_is_bc) ? dcx_result[15:8] :
                      (is_mov & nnn_is_b) ? val_sss :
                      (is_mvi & nnn_is_b) ? byte2 :
                      (is_inr & nnn_is_b) ? inr_result :
                      (is_dcr & nnn_is_b) ? dcr_result :
                      state_reg_b;

  // C register
  wire [7:0] next_c = (is_pop & rp_is_bc) ? stack_read_lo :
                      (is_lxi & rp_is_bc) ? byte2 :
                      (is_inx & rp_is_bc) ? inx_result[7:0] :
                      (is_dcx & rp_is_bc) ? dcx_result[7:0] :
                      (is_mov & nnn_is_c) ? val_sss :
                      (is_mvi & nnn_is_c) ? byte2 :
                      (is_inr & nnn_is_c) ? inr_result :
                      (is_dcr & nnn_is_c) ? dcr_result :
                      state_reg_c;

  // D register
  wire [7:0] next_d = (is_pop & rp_is_de) ? stack_read_hi :
                      (is_lxi & rp_is_de) ? byte3 :
                      (is_inx & rp_is_de) ? inx_result[15:8] :
                      (is_dcx & rp_is_de) ? dcx_result[15:8] :
                      (is_xchg) ? state_reg_h :
                      (is_mov & nnn_is_d) ? val_sss :
                      (is_mvi & nnn_is_d) ? byte2 :
                      (is_inr & nnn_is_d) ? inr_result :
                      (is_dcr & nnn_is_d) ? dcr_result :
                      state_reg_d;

  // E register
  wire [7:0] next_e = (is_pop & rp_is_de) ? stack_read_lo :
                      (is_lxi & rp_is_de) ? byte2 :
                      (is_inx & rp_is_de) ? inx_result[7:0] :
                      (is_dcx & rp_is_de) ? dcx_result[7:0] :
                      (is_xchg) ? state_reg_l :
                      (is_mov & nnn_is_e) ? val_sss :
                      (is_mvi & nnn_is_e) ? byte2 :
                      (is_inr & nnn_is_e) ? inr_result :
                      (is_dcr & nnn_is_e) ? dcr_result :
                      state_reg_e;

  // H register
  wire [7:0] next_h = (is_pop & rp_is_hl) ? stack_read_hi :
                      (is_xthl) ? stack_read_hi :
                      (is_lxi & rp_is_hl) ? byte3 :
                      (is_lhld) ? mem_read_data :  // Note: needs 2nd read
                      (is_inx & rp_is_hl) ? inx_result[15:8] :
                      (is_dcx & rp_is_hl) ? dcx_result[15:8] :
                      (is_dad) ? dad_sum[15:8] :
                      (is_xchg) ? state_reg_d :
                      (is_mov & nnn_is_h) ? val_sss :
                      (is_mvi & nnn_is_h) ? byte2 :
                      (is_inr & nnn_is_h) ? inr_result :
                      (is_dcr & nnn_is_h) ? dcr_result :
                      state_reg_h;

  // L register
  wire [7:0] next_l = (is_pop & rp_is_hl) ? stack_read_lo :
                      (is_xthl) ? stack_read_lo :
                      (is_lxi & rp_is_hl) ? byte2 :
                      (is_inx & rp_is_hl) ? inx_result[7:0] :
                      (is_dcx & rp_is_hl) ? dcx_result[7:0] :
                      (is_dad) ? dad_sum[7:0] :
                      (is_xchg) ? state_reg_e :
                      (is_mov & nnn_is_l) ? val_sss :
                      (is_mvi & nnn_is_l) ? byte2 :
                      (is_inr & nnn_is_l) ? inr_result :
                      (is_dcr & nnn_is_l) ? dcr_result :
                      state_reg_l;

  // SP
  wire [15:0] next_sp = (is_push | is_call | is_ccc | is_rst | is_xthl) ? sp_m2 :
                        (is_pop | is_ret | is_rcc) ? sp_p2 :
                        (is_lxi & rp_is_sp) ? immediate16 :
                        (is_inx & rp_is_sp) ? inx_result :
                        (is_dcx & rp_is_sp) ? dcx_result :
                        (is_sphl) ? hl :
                        state_sp;

  // PC
  wire [15:0] next_pc = state_halted ? state_pc :
                        is_jmp ? immediate16 :
                        (is_jcc & cond_met) ? immediate16 :
                        is_call ? immediate16 :
                        (is_ccc & cond_met) ? immediate16 :
                        is_ret ? ret_addr :
                        (is_rcc & cond_met) ? ret_addr :
                        is_rst ? rst_vec :
                        is_pchl ? hl :
                        // 3-byte instructions
                        (is_lxi | is_lda | is_sta | is_lhld | is_shld |
                         is_jcc | is_ccc) ? pc_p3 :
                        // 2-byte instructions
                        (is_mvi | is_in | is_out | is_alu_i) ? pc_p2 :
                        // 1-byte instructions
                        pc_p1;

  // Halted
  wire next_halted = is_hlt | state_halted;

  // INTE
  wire next_inte = is_ei ? 1'b1 : is_di ? 1'b0 : state_inte;

  // Interrupt masks (from SIM)
  wire [2:0] next_masks = (is_sim & byte2[3]) ?
                          {byte2[0], byte2[1], byte2[2]} :
                          {state_mask_55, state_mask_65, state_mask_75};

  // RST 7.5 pending
  wire next_rst75 = (is_sim & byte2[4]) ? 1'b0 : state_rst75_pending;

  // SOD latch
  wire next_sod = (is_sim & byte2[6]) ? byte2[7] : state_sod_latch;

  // =========================================================================
  // Memory bus outputs
  // =========================================================================

  wire do_mem_wr = is_sta | is_stax | is_shld |
                   ((is_mov | is_mvi | is_inr | is_dcr) & nnn_is_m);

  wire [15:0] mem_addr_out = is_sta ? immediate16 :
                             is_stax ? (opcode[4] ? de : bc) :
                             is_shld ? immediate16 :
                             ((is_mov | is_mvi | is_inr | is_dcr) & nnn_is_m) ? hl :
                             hl;  // Default for reads

  wire [7:0] mem_data_out = is_sta ? a :
                            is_stax ? a :
                            is_shld ? state_reg_l :
                            (is_mov & nnn_is_m) ? val_sss :
                            (is_mvi & nnn_is_m) ? byte2 :
                            (is_inr & nnn_is_m) ? inr_result :
                            (is_dcr & nnn_is_m) ? dcr_result :
                            8'h00;

  // =========================================================================
  // Stack bus outputs
  // =========================================================================

  wire do_stack_wr = is_push | is_call | (is_ccc & cond_met) | is_rst | is_xthl;

  // PUSH data
  wire [7:0] push_lo = rp_is_sp ? {f_sign, f_zero, 1'b0, f_aux, 1'b0, f_parity, 1'b1, f_carry} :
                       rp_is_bc ? state_reg_c :
                       rp_is_de ? state_reg_e : state_reg_l;
  wire [7:0] push_hi = rp_is_sp ? a :
                       rp_is_bc ? state_reg_b :
                       rp_is_de ? state_reg_d : state_reg_h;

  wire [15:0] stack_addr_out = sp_m2;
  wire [7:0] stack_lo_out = is_push ? push_lo :
                            is_xthl ? state_reg_l :
                            pc_p3[7:0];   // Return address for CALL
  wire [7:0] stack_hi_out = is_push ? push_hi :
                            is_xthl ? state_reg_h :
                            pc_p3[15:8];

  // =========================================================================
  // I/O bus outputs
  // =========================================================================

  wire [7:0] io_port_out = byte2;
  wire [7:0] io_data_out = a;
  wire do_io_rd = is_in;
  wire do_io_wr = is_out;

  // =========================================================================
  // Output packing (matches XLS format)
  // =========================================================================

  // Pack state output [175:76]
  wire [99:0] state_out = {
    next_b, next_c, next_d, next_e, next_h, next_l, next_a,
    next_sp,
    next_pc,
    next_flags,
    next_halted,
    next_inte,
    next_masks,
    next_rst75,
    next_sod
  };

  // Pack memory bus output [75:0]
  wire [75:0] membus_out = {
    mem_addr_out,      // [75:60]
    mem_data_out,      // [59:52]
    do_mem_wr,         // [51]
    stack_addr_out,    // [50:35]
    stack_lo_out,      // [34:27]
    stack_hi_out,      // [26:19]
    do_stack_wr,       // [18]
    io_port_out,       // [17:10]
    io_data_out,       // [9:2]
    do_io_rd,          // [1]
    do_io_wr           // [0]
  };

  assign out = {state_out, membus_out};

endmodule
