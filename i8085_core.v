module __i8085_core__execute(
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
  function automatic logic priority_sel_1b_7way (input reg [6:0] sel, input reg case0, input reg case1, input reg case2, input reg case3, input reg case4, input reg case5, input reg case6, input reg default_value);
    begin
      unique casez (sel)
        7'b??????1: begin
          priority_sel_1b_7way = case0;
        end
        7'b?????10: begin
          priority_sel_1b_7way = case1;
        end
        7'b????100: begin
          priority_sel_1b_7way = case2;
        end
        7'b???1000: begin
          priority_sel_1b_7way = case3;
        end
        7'b??10000: begin
          priority_sel_1b_7way = case4;
        end
        7'b?100000: begin
          priority_sel_1b_7way = case5;
        end
        7'b1000000: begin
          priority_sel_1b_7way = case6;
        end
        7'b000_0000: begin
          priority_sel_1b_7way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_1b_7way = 'X;
        end
      endcase
    end
  endfunction
  function automatic [15:0] priority_sel_16b_3way (input reg [2:0] sel, input reg [15:0] case0, input reg [15:0] case1, input reg [15:0] case2, input reg [15:0] default_value);
    begin
      unique casez (sel)
        3'b??1: begin
          priority_sel_16b_3way = case0;
        end
        3'b?10: begin
          priority_sel_16b_3way = case1;
        end
        3'b100: begin
          priority_sel_16b_3way = case2;
        end
        3'b000: begin
          priority_sel_16b_3way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_16b_3way = 'X;
        end
      endcase
    end
  endfunction
  function automatic [7:0] priority_sel_8b_3way (input reg [2:0] sel, input reg [7:0] case0, input reg [7:0] case1, input reg [7:0] case2, input reg [7:0] default_value);
    begin
      unique casez (sel)
        3'b??1: begin
          priority_sel_8b_3way = case0;
        end
        3'b?10: begin
          priority_sel_8b_3way = case1;
        end
        3'b100: begin
          priority_sel_8b_3way = case2;
        end
        3'b000: begin
          priority_sel_8b_3way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_8b_3way = 'X;
        end
      endcase
    end
  endfunction
  wire [1:0] rp;
  wire [1:0] RP_HL__5;
  wire [1:0] RP_DE;
  wire eq_21489;
  wire eq_21490;
  wire nor_21491;
  wire [7:0] and_21492;
  wire ne_21494;
  wire [7:0] a;
  wire or_21496;
  wire [4:0] state_flags__22;
  wire eq_21499;
  wire [7:0] not_b__1;
  wire state_flags_carry__1;
  wire eq_21506;
  wire [7:0] result__20;
  wire [8:0] concat_21509;
  wire cin__1;
  wire eq_21514;
  wire [7:0] result__19;
  wire [8:0] add_21517;
  wire [8:0] concat_21518;
  wire eq_21520;
  wire [7:0] result__18;
  wire [8:0] diff9__1;
  wire eq_21527;
  wire [7:0] result__30;
  wire [8:0] diff9__2;
  wire [8:0] sum9__1;
  wire [8:0] concat_21532;
  wire eq_21534;
  wire [7:0] sel_21535;
  wire [7:0] result__31;
  wire [8:0] sum9;
  wire [2:0] nnn;
  wire [2:0] REG_A__1;
  wire [2:0] REG_L__1;
  wire [2:0] REG_H__1;
  wire [2:0] REG_E__1;
  wire [2:0] REG_D__1;
  wire [2:0] REG_C__1;
  wire [2:0] REG_B__1;
  wire eq_21547;
  wire [7:0] result__32;
  wire eq_21550;
  wire eq_21551;
  wire eq_21552;
  wire eq_21553;
  wire eq_21554;
  wire eq_21555;
  wire eq_21556;
  wire eq_21558;
  wire [7:0] result__33;
  wire [2:0] REG_M;
  wire [6:0] concat_21562;
  wire [7:0] state_reg_b__3;
  wire [7:0] state_reg_c__3;
  wire [7:0] state_reg_d;
  wire [7:0] state_reg_e;
  wire [7:0] state_reg_h__1;
  wire [7:0] state_reg_l__2;
  wire eq_21570;
  wire [6:0] result__21;
  wire eq_21574;
  wire eq_21577;
  wire [7:0] result__13;
  wire [6:0] result__24;
  wire [7:0] val;
  wire [2:0] sss;
  wire eq_21584;
  wire [7:0] result__12;
  wire bit0;
  wire [8:0] concat_21588;
  wire [8:0] diff9__3_associative_element;
  wire eq_21599;
  wire [7:0] sel_21600;
  wire [7:0] result__11;
  wire bit7;
  wire [8:0] diff9__3;
  wire [6:0] concat_21604;
  wire [7:0] and_21605;
  wire eq_21607;
  wire [7:0] result__10;
  wire [7:0] result__34;
  wire [8:0] sum9__2;
  wire [7:0] one_hot_sel_22460;
  wire eq_21615;
  wire [7:0] result__35;
  wire [7:0] src_val;
  wire eq_21622;
  wire [7:0] not_b__5;
  wire eq_21627;
  wire [7:0] result__7;
  wire [15:0] state_pc__54;
  wire [3:0] lo_nibble;
  wire eq_21635;
  wire [7:0] result__6;
  wire [8:0] add_21638;
  wire [4:0] concat_21642;
  wire eq_21645;
  wire [7:0] sel_21646;
  wire [7:0] result__5;
  wire [8:0] diff9__5;
  wire eq_21651;
  wire [14:0] add_21652;
  wire state_flags_aux_carry__1;
  wire [4:0] add_21657;
  wire eq_21661;
  wire [7:0] result__37;
  wire [8:0] diff9__6;
  wire [8:0] sum9__5;
  wire nor_21669;
  wire [15:0] concat_21670;
  wire [15:0] ret_addr__4;
  wire state_flags_zero__1;
  wire state_flags_parity__1;
  wire state_flags_sign__1;
  wire [4:0] low_diff__2;
  wire eq_21681;
  wire [7:0] result__38;
  wire [8:0] sum9__3;
  wire [6:0] sum9__7_bits_1_width_7;
  wire eq_21687;
  wire [15:0] hl;
  wire eq_21695;
  wire eq_21701;
  wire [7:0] result__39;
  wire add_lo;
  wire eq_21708;
  wire [15:0] rst_addr;
  wire priority_sel_21711;
  wire [15:0] ret_addr__3;
  wire eq_21719;
  wire [7:0] result__41;
  wire [3:0] tmp1_squeezed_portion_1_width_7__1;
  wire eq_21724;
  wire eq_21734;
  wire [2:0] concat_21736;
  wire [15:0] bc;
  wire [15:0] de;
  wire [15:0] state_sp__6;
  wire eq_21741;
  wire [2:0] tmp1_bits_5_width_3;
  wire eq_21747;
  wire [15:0] ret_addr;
  wire [15:0] immediate16;
  wire eq_21751;
  wire nor_21753;
  wire [4:0] concat_21754;
  wire [4:0] low_sum__1;
  wire [4:0] concat_21756;
  wire [4:0] concat_21757;
  wire [4:0] low_diff__3_associative_element;
  wire [4:0] add_21759;
  wire nor_21762;
  wire [15:0] val__2;
  wire eq_21766;
  wire [7:0] sel_21767;
  wire add_hi;
  wire [2:0] sum9__8_bits_5_width_3;
  wire eq_21774;
  wire [15:0] sel_21776;
  wire [4:0] low_diff__1;
  wire [4:0] low_sum;
  wire [4:0] low_diff__3;
  wire [4:0] low_sum__2;
  wire [4:0] low_diff__6;
  wire eq_21784;
  wire [5:0] concat_21786;
  wire eq_21794;
  wire [2:0] result_squeezed_portion_5_width_3;
  wire [3:0] sel_21797;
  wire eq_21800;
  wire [15:0] sel_21801;
  wire [7:0] concat_21802;
  wire eq_21813;
  wire [16:0] sum;
  wire eq_21818;
  wire [7:0] result;
  wire eq_21824;
  wire eq_21827;
  wire [4:0] concat_21831;
  wire and_21835;
  wire eq_21838;
  wire state_rst75_pending__1;
  wire state_inte;
  wire state_mask_75__1;
  wire state_mask_65__1;
  wire state_mask_55__1;
  wire eq_21846;
  wire eq_21847;
  wire eq_21848;
  wire or_21849;
  wire eq_21850;
  wire eq_21851;
  wire eq_21861;
  wire [14:0] state_sp__6_bits_1_width_15;
  wire eq_21867;
  wire [7:0] rim_result;
  wire [15:0] add_21870;
  wire [15:0] add_21871;
  wire nor_21872;
  wire or_21873;
  wire or_21874;
  wire nor_21878;
  wire [4:0] low_sum__5;
  wire not_22015;
  wire eq_22016;
  wire or_22017;
  wire eq_22020;
  wire eq_22021;
  wire [14:0] new_sp_bits_1_width_15;
  wire state_tup7_portion_0_width_1;
  wire eq_22032;
  wire eq_22033;
  wire eq_22034;
  wire [7:0] sel_22035;
  wire [14:0] add_22037;
  wire [15:0] sel_22448;
  wire [15:0] sel_22447;
  wire [15:0] sel_22446;
  wire [4:0] low_diff__5;
  wire [4:0] low_sum__3;
  wire p__5;
  wire p__1;
  wire p__2;
  wire p__3;
  wire p__4;
  wire p__6;
  wire p__7;
  wire p__8;
  wire p__9;
  wire p__15;
  wire p__11;
  wire p__12;
  wire p__13;
  wire p__14;
  wire p__16;
  wire p__18;
  wire p__20;
  wire [15:0] new_sp;
  wire state_halted;
  wire eq_22083;
  wire eq_22084;
  wire eq_22085;
  wire eq_22086;
  wire [7:0] high__1;
  wire [7:0] high__2;
  wire [7:0] low__1;
  wire [7:0] low__2;
  wire [8:0] concat_22100;
  wire [4:0] concat_22107;
  wire [18:0] concat_22113;
  wire [5:0] concat_22133;
  wire eq_22160;
  wire [7:0] sign_ext_22169;
  wire [7:0] sign_ext_22176;
  wire [8:0] concat_22235;
  wire [9:0] concat_22252;
  wire [12:0] concat_22269;
  wire [7:0] high;
  wire [7:0] low;
  wire [15:0] sel_22292;
  wire or_22293;
  wire r75;
  wire nor_22305;
  wire [5:0] concat_22306;
  wire [4:0] concat_22314;
  wire [7:0] lo;
  wire [7:0] hi;
  wire and_22323;
  wire or_22324;
  wire or_22329;
  wire or_22344;
  wire new_rst75_pending;
  wire state_sod_latch;
  wire [15:0] sel_22351;
  wire [7:0] sign_ext_22359;
  wire [4:0] tuple_22373;
  wire [15:0] and_22384;
  wire [7:0] one_hot_22455;
  wire [7:0] one_hot_22461;
  wire [99:0] tuple_22391;
  wire [175:0] tuple_22393;
  wire eq_22457;
  wire eq_22463;
  assign rp = opcode[5:4];
  assign RP_HL__5 = 2'h2;
  assign RP_DE = 2'h1;
  assign eq_21489 = rp == RP_HL__5;
  assign eq_21490 = rp == RP_DE;
  assign nor_21491 = ~(opcode[4] | opcode[5]);
  assign and_21492 = opcode & 8'hcf;
  assign ne_21494 = opcode != 8'hdb;
  assign a = state[51:44];
  assign or_21496 = eq_21489 | eq_21490 | nor_21491;
  assign state_flags__22 = state[11:7];
  assign eq_21499 = and_21492 == 8'hc1;
  assign not_b__1 = ~byte2;
  assign state_flags_carry__1 = state_flags__22[0:0];
  assign eq_21506 = opcode == 8'hf6;
  assign result__20 = a | byte2;
  assign concat_21509 = {1'h0, a};
  assign cin__1 = ~state_flags_carry__1;
  assign eq_21514 = opcode == 8'hee;
  assign result__19 = a ^ byte2;
  assign add_21517 = concat_21509 + {1'h0, not_b__1};
  assign concat_21518 = {8'h00, cin__1};
  assign eq_21520 = opcode == 8'he6;
  assign result__18 = a & byte2;
  assign diff9__1 = add_21517 + concat_21518;
  assign eq_21527 = opcode == 8'hde;
  assign result__30 = diff9__1[7:0];
  assign diff9__2 = add_21517 + 9'h001;
  assign sum9__1 = concat_21509 + {1'h0, byte2};
  assign concat_21532 = {8'h00, state_flags_carry__1};
  assign eq_21534 = opcode == 8'hd6;
  assign sel_21535 = eq_21527 ? result__30 : (eq_21520 ? result__18 : (eq_21514 ? result__19 : (eq_21506 ? result__20 : (eq_21499 ? (or_21496 ? a : stack_read_hi) : (ne_21494 ? a : io_read_data)))));
  assign result__31 = diff9__2[7:0];
  assign sum9 = sum9__1 + concat_21532;
  assign nnn = opcode[5:3];
  assign REG_A__1 = 3'h7;
  assign REG_L__1 = 3'h5;
  assign REG_H__1 = 3'h4;
  assign REG_E__1 = 3'h3;
  assign REG_D__1 = 3'h2;
  assign REG_C__1 = 3'h1;
  assign REG_B__1 = 3'h0;
  assign eq_21547 = opcode == 8'hce;
  assign result__32 = sum9[7:0];
  assign eq_21550 = nnn == REG_A__1;
  assign eq_21551 = nnn == REG_L__1;
  assign eq_21552 = nnn == REG_H__1;
  assign eq_21553 = nnn == REG_E__1;
  assign eq_21554 = nnn == REG_D__1;
  assign eq_21555 = nnn == REG_C__1;
  assign eq_21556 = nnn == REG_B__1;
  assign eq_21558 = opcode == 8'hc6;
  assign result__33 = sum9__1[7:0];
  assign REG_M = 3'h6;
  assign concat_21562 = {eq_21550, eq_21551, eq_21552, eq_21553, eq_21554, eq_21555, eq_21556};
  assign state_reg_b__3 = state[99:92];
  assign state_reg_c__3 = state[91:84];
  assign state_reg_d = state[83:76];
  assign state_reg_e = state[75:68];
  assign state_reg_h__1 = state[67:60];
  assign state_reg_l__2 = state[59:52];
  assign eq_21570 = opcode == 8'h2f;
  assign result__21 = a[7:1];
  assign eq_21574 = nnn == REG_M;
  assign eq_21577 = opcode == 8'h1f;
  assign result__13 = {state_flags_carry__1, result__21};
  assign result__24 = a[6:0];
  assign val = eq_21574 ? mem_read_data : state_reg_b__3 & {8{concat_21562[0]}} | state_reg_c__3 & {8{concat_21562[1]}} | state_reg_d & {8{concat_21562[2]}} | state_reg_e & {8{concat_21562[3]}} | state_reg_h__1 & {8{concat_21562[4]}} | state_reg_l__2 & {8{concat_21562[5]}} | a & {8{concat_21562[6]}};
  assign sss = opcode[2:0];
  assign eq_21584 = opcode == 8'h17;
  assign result__12 = {result__24, state_flags_carry__1};
  assign bit0 = a[0];
  assign concat_21588 = {1'h0, val};
  assign diff9__3_associative_element = 9'h0ff;
  assign eq_21599 = opcode == 8'h0f;
  assign sel_21600 = eq_21584 ? result__12 : (eq_21577 ? result__13 : (eq_21570 ? ~a : (eq_21558 ? result__33 : (eq_21547 ? result__32 : (eq_21534 ? result__31 : sel_21535)))));
  assign result__11 = {bit0, result__21};
  assign bit7 = a[7];
  assign diff9__3 = concat_21588 + diff9__3_associative_element;
  assign concat_21604 = {sss == REG_A__1, sss == REG_L__1, sss == REG_H__1, sss == REG_E__1, sss == REG_D__1, sss == REG_C__1, sss == REG_B__1};
  assign and_21605 = opcode & 8'hc7;
  assign eq_21607 = opcode == 8'h07;
  assign result__10 = {result__24, bit7};
  assign result__34 = diff9__3[7:0];
  assign sum9__2 = concat_21588 + 9'h001;
  assign one_hot_sel_22460 = state_reg_b__3 & {8{concat_21604[0]}} | state_reg_c__3 & {8{concat_21604[1]}} | state_reg_d & {8{concat_21604[2]}} | state_reg_e & {8{concat_21604[3]}} | state_reg_h__1 & {8{concat_21604[4]}} | state_reg_l__2 & {8{concat_21604[5]}} | a & {8{concat_21604[6]}};
  assign eq_21615 = and_21605 == 8'h05;
  assign result__35 = sum9__2[7:0];
  assign src_val = sss == REG_M ? mem_read_data : one_hot_sel_22460;
  assign eq_21622 = and_21605 == 8'h04;
  assign not_b__5 = ~src_val;
  assign eq_21627 = opcode[7:3] == 5'h16;
  assign result__7 = a | src_val;
  assign state_pc__54 = state[27:12];
  assign lo_nibble = a[3:0];
  assign eq_21635 = opcode[7:3] == 5'h15;
  assign result__6 = a ^ src_val;
  assign add_21638 = concat_21509 + {1'h0, not_b__5};
  assign concat_21642 = {1'h0, lo_nibble};
  assign eq_21645 = opcode[7:3] == 5'h14;
  assign sel_21646 = eq_21635 ? result__6 : (eq_21627 ? result__7 : (eq_21622 ? (eq_21550 ? result__35 : a) : (eq_21615 ? (eq_21550 ? result__34 : a) : (eq_21607 ? result__10 : (eq_21599 ? result__11 : sel_21600)))));
  assign result__5 = a & src_val;
  assign diff9__5 = add_21638 + concat_21518;
  assign eq_21651 = opcode == 8'hd3;
  assign add_21652 = state_pc__54[15:1] + 15'h0001;
  assign state_flags_aux_carry__1 = state_flags__22[2:2];
  assign add_21657 = concat_21642 + {1'h0, not_b__1[3:0]};
  assign eq_21661 = opcode[7:3] == 5'h13;
  assign result__37 = diff9__5[7:0];
  assign diff9__6 = add_21638 + 9'h001;
  assign sum9__5 = concat_21509 + {1'h0, src_val};
  assign nor_21669 = ~(~ne_21494 | eq_21651);
  assign concat_21670 = {add_21652, state_pc__54[0]};
  assign ret_addr__4 = state_pc__54 + 16'h0001;
  assign state_flags_zero__1 = state_flags__22[3:3];
  assign state_flags_parity__1 = state_flags__22[1:1];
  assign state_flags_sign__1 = state_flags__22[4:4];
  assign low_diff__2 = add_21657 + 5'h01;
  assign eq_21681 = opcode[7:3] == 5'h12;
  assign result__38 = diff9__6[7:0];
  assign sum9__3 = sum9__5 + concat_21532;
  assign sum9__7_bits_1_width_7 = result__21 + 7'h03;
  assign eq_21687 = opcode == 8'he9;
  assign hl = {state_reg_h__1, state_reg_l__2};
  assign eq_21695 = opcode == 8'hfe;
  assign eq_21701 = opcode[7:3] == 5'h11;
  assign result__39 = sum9__3[7:0];
  assign add_lo = lo_nibble > 4'h9 | state_flags_aux_carry__1;
  assign eq_21708 = and_21605 == 8'hc7;
  assign rst_addr = {10'h000, nnn, REG_B__1};
  assign priority_sel_21711 = priority_sel_1b_7way({eq_21574, eq_21551, eq_21552, eq_21553, eq_21554, eq_21555, eq_21556}, ~state_flags_zero__1, state_flags_zero__1, cin__1, state_flags_carry__1, ~state_flags_parity__1, state_flags_parity__1, ~state_flags_sign__1, state_flags_sign__1);
  assign ret_addr__3 = {stack_read_hi, stack_read_lo};
  assign eq_21719 = opcode[7:3] == 5'h10;
  assign result__41 = sum9__5[7:0];
  assign tmp1_squeezed_portion_1_width_7__1 = add_lo ? sum9__7_bits_1_width_7[6:3] : a[7:4];
  assign eq_21724 = and_21605 == 8'hc0;
  assign eq_21734 = opcode == 8'h3f;
  assign concat_21736 = {eq_21489, eq_21490, nor_21491};
  assign bc = {state_reg_b__3, state_reg_c__3};
  assign de = {state_reg_d, state_reg_e};
  assign state_sp__6 = state[43:28];
  assign eq_21741 = and_21605 == 8'h06;
  assign tmp1_bits_5_width_3 = tmp1_squeezed_portion_1_width_7__1[3:1];
  assign eq_21747 = opcode == 8'hc9;
  assign ret_addr = state_pc__54 + 16'h0003;
  assign immediate16 = {byte3, byte2};
  assign eq_21751 = opcode[7:3] == 5'h17;
  assign nor_21753 = ~(eq_21514 | eq_21506 | ~(eq_21695 ? low_diff__2[4] : (eq_21499 ? (or_21496 ? state_flags_aux_carry__1 : stack_read_lo[4]) : state_flags_aux_carry__1)));
  assign concat_21754 = {4'h0, cin__1};
  assign low_sum__1 = concat_21642 + {1'h0, byte2[3:0]};
  assign concat_21756 = {4'h0, state_flags_carry__1};
  assign concat_21757 = {1'h0, val[3:0]};
  assign low_diff__3_associative_element = 5'h0f;
  assign add_21759 = concat_21642 + {1'h0, not_b__5[3:0]};
  assign nor_21762 = ~(eq_21514 | eq_21506 | ~(eq_21695 ? ~diff9__2[8] : (eq_21499 ? (or_21496 ? state_flags_carry__1 : stack_read_lo[0]) : state_flags_carry__1)));
  assign val__2 = priority_sel_16b_3way(concat_21736, bc, de, hl, state_sp__6);
  assign eq_21766 = opcode[7:6] == RP_DE;
  assign sel_21767 = eq_21741 ? (eq_21550 ? byte2 : a) : (eq_21719 ? result__41 : (eq_21701 ? result__39 : (eq_21681 ? result__38 : (eq_21661 ? result__37 : (eq_21645 ? result__5 : sel_21646)))));
  assign add_hi = tmp1_squeezed_portion_1_width_7__1 > 4'h9 | state_flags_carry__1;
  assign sum9__8_bits_5_width_3 = tmp1_bits_5_width_3 + REG_E__1;
  assign eq_21774 = and_21605 == 8'hc4;
  assign sel_21776 = priority_sel_21711 ? immediate16 : ret_addr;
  assign low_diff__1 = add_21657 + concat_21754;
  assign low_sum = low_sum__1 + concat_21756;
  assign low_diff__3 = concat_21757 + low_diff__3_associative_element;
  assign low_sum__2 = concat_21757 + 5'h01;
  assign low_diff__6 = add_21759 + 5'h01;
  assign eq_21784 = and_21492 == 8'h09;
  assign concat_21786 = {eq_21734, eq_21558, eq_21547, eq_21534, eq_21527, ~(eq_21734 | eq_21558 | eq_21547 | eq_21534 | eq_21527)};
  assign eq_21794 = opcode == 8'h3a;
  assign result_squeezed_portion_5_width_3 = add_hi ? sum9__8_bits_5_width_3 : tmp1_bits_5_width_3;
  assign sel_21797 = add_lo ? sum9__7_bits_1_width_7[3:0] : a[4:1];
  assign eq_21800 = opcode == 8'hcd;
  assign sel_21801 = eq_21774 ? sel_21776 : (eq_21747 ? ret_addr__3 : (eq_21724 ? (priority_sel_21711 ? ret_addr__3 : ret_addr__4) : (eq_21708 ? rst_addr : (eq_21687 ? hl : (nor_21669 ? ret_addr__4 : concat_21670)))));
  assign concat_21802 = {eq_21751, eq_21622, eq_21615, eq_21558, eq_21547, eq_21534, eq_21527, ~(eq_21751 | eq_21622 | eq_21615 | eq_21558 | eq_21547 | eq_21534 | eq_21527)};
  assign eq_21813 = opcode == 8'h37;
  assign sum = {1'h0, state_reg_h__1, state_reg_l__2} + {1'h0, val__2};
  assign eq_21818 = opcode == 8'h27;
  assign result = {result_squeezed_portion_5_width_3, sel_21797, bit0};
  assign eq_21824 = and_21492 == 8'hc5;
  assign eq_21827 = and_21605 == 8'hc2;
  assign concat_21831 = {eq_21751, eq_21784, eq_21584 | eq_21607, eq_21577 | eq_21599, ~(eq_21751 | eq_21784 | eq_21607 | eq_21599 | eq_21584 | eq_21577)};
  assign and_21835 = eq_21615 & eq_21574;
  assign eq_21838 = opcode == 8'h22;
  assign state_rst75_pending__1 = state[1:1];
  assign state_inte = state[5:5];
  assign state_mask_75__1 = state[2:2];
  assign state_mask_65__1 = state[3:3];
  assign state_mask_55__1 = state[4:4];
  assign eq_21846 = and_21492 == 8'h01;
  assign eq_21847 = and_21492 == 8'h03;
  assign eq_21848 = and_21492 == 8'h0b;
  assign or_21849 = eq_21708 | eq_21824;
  assign eq_21850 = opcode == 8'hf9;
  assign eq_21851 = opcode == 8'hc3;
  assign eq_21861 = opcode == 8'he3;
  assign state_sp__6_bits_1_width_15 = state_sp__6[15:1];
  assign eq_21867 = opcode == 8'h20;
  assign rim_result = {sid, state_rst75_pending__1, rst65_level, rst55_level, state_inte, state_mask_75__1, state_mask_65__1, state_mask_55__1};
  assign add_21870 = val__2 + 16'hffff;
  assign add_21871 = val__2 + 16'h0001;
  assign nor_21872 = ~(eq_21846 | eq_21847 | eq_21848 | eq_21800 | eq_21774 | eq_21747 | eq_21724 | or_21849 | eq_21499 | eq_21850);
  assign or_21873 = eq_21499 | eq_21747;
  assign or_21874 = eq_21708 | eq_21824 | eq_21800;
  assign nor_21878 = ~(eq_21635 | eq_21627 | ~((eq_21520 | ~eq_21520 & nor_21753) & concat_21802[0] | low_diff__1[4] & concat_21802[1] | low_diff__2[4] & concat_21802[2] | low_sum[4] & concat_21802[3] | low_sum__1[4] & concat_21802[4] | low_diff__3[4] & concat_21802[5] | low_sum__2[4] & concat_21802[6] | low_diff__6[4] & concat_21802[7]));
  assign low_sum__5 = concat_21642 + {1'h0, src_val[3:0]};
  assign not_22015 = ~((eq_21813 | (~eq_21520 & nor_21762 & concat_21786[0] | ~diff9__1[8] & concat_21786[1] | ~diff9__2[8] & concat_21786[2] | sum9[8] & concat_21786[3] | sum9__1[8] & concat_21786[4] | cin__1 & concat_21786[5])) & concat_21831[0] | bit0 & concat_21831[1] | bit7 & concat_21831[2] | sum[16] & concat_21831[3] | ~diff9__6[8] & concat_21831[4]);
  assign eq_22016 = opcode == 8'h32;
  assign or_22017 = eq_21766 | eq_21741 | eq_21622;
  assign eq_22020 = opcode == 8'h02;
  assign eq_22021 = opcode == 8'h12;
  assign new_sp_bits_1_width_15 = state_sp__6_bits_1_width_15 + 15'h7fff;
  assign state_tup7_portion_0_width_1 = state_sp__6[0];
  assign eq_22032 = opcode == 8'heb;
  assign eq_22033 = opcode == 8'h2a;
  assign eq_22034 = opcode == 8'h1a;
  assign sel_22035 = eq_21867 ? rim_result : (eq_21838 ? a : (eq_21818 ? result : (eq_21794 ? mem_read_data : (eq_21766 ? (eq_21550 ? src_val : a) : sel_21767))));
  assign add_22037 = state_sp__6_bits_1_width_15 + 15'h0001;
  assign sel_22448 = or_21496 ? state_sp__6 : add_21870;
  assign sel_22447 = or_21496 ? state_sp__6 : add_21871;
  assign sel_22446 = or_21496 ? state_sp__6 : immediate16;
  assign low_diff__5 = add_21759 + concat_21754;
  assign low_sum__3 = low_sum__5 + concat_21756;
  assign p__5 = diff9__2[0] ^ diff9__2[1] ^ diff9__2[2] ^ diff9__2[3] ^ diff9__2[4] ^ diff9__2[5] ^ diff9__2[6] ^ diff9__2[7];
  assign p__1 = result__20[0] ^ result__20[1] ^ result__20[2] ^ result__20[3] ^ result__20[4] ^ result__20[5] ^ result__20[6] ^ result__20[7];
  assign p__2 = result__19[0] ^ result__19[1] ^ result__19[2] ^ result__19[3] ^ result__19[4] ^ result__19[5] ^ result__19[6] ^ result__19[7];
  assign p__3 = result__18[0] ^ result__18[1] ^ result__18[2] ^ result__18[3] ^ result__18[4] ^ result__18[5] ^ result__18[6] ^ result__18[7];
  assign p__4 = diff9__1[0] ^ diff9__1[1] ^ diff9__1[2] ^ diff9__1[3] ^ diff9__1[4] ^ diff9__1[5] ^ diff9__1[6] ^ diff9__1[7];
  assign p__6 = sum9[0] ^ sum9[1] ^ sum9[2] ^ sum9[3] ^ sum9[4] ^ sum9[5] ^ sum9[6] ^ sum9[7];
  assign p__7 = sum9__1[0] ^ sum9__1[1] ^ sum9__1[2] ^ sum9__1[3] ^ sum9__1[4] ^ sum9__1[5] ^ sum9__1[6] ^ sum9__1[7];
  assign p__8 = diff9__3[0] ^ diff9__3[1] ^ diff9__3[2] ^ diff9__3[3] ^ diff9__3[4] ^ diff9__3[5] ^ diff9__3[6] ^ diff9__3[7];
  assign p__9 = sum9__2[0] ^ sum9__2[1] ^ sum9__2[2] ^ sum9__2[3] ^ sum9__2[4] ^ sum9__2[5] ^ sum9__2[6] ^ sum9__2[7];
  assign p__15 = diff9__6[0] ^ diff9__6[1] ^ diff9__6[2] ^ diff9__6[3] ^ diff9__6[4] ^ diff9__6[5] ^ diff9__6[6] ^ diff9__6[7];
  assign p__11 = result__7[0] ^ result__7[1] ^ result__7[2] ^ result__7[3] ^ result__7[4] ^ result__7[5] ^ result__7[6] ^ result__7[7];
  assign p__12 = result__6[0] ^ result__6[1] ^ result__6[2] ^ result__6[3] ^ result__6[4] ^ result__6[5] ^ result__6[6] ^ result__6[7];
  assign p__13 = result__5[0] ^ result__5[1] ^ result__5[2] ^ result__5[3] ^ result__5[4] ^ result__5[5] ^ result__5[6] ^ result__5[7];
  assign p__14 = diff9__5[0] ^ diff9__5[1] ^ diff9__5[2] ^ diff9__5[3] ^ diff9__5[4] ^ diff9__5[5] ^ diff9__5[6] ^ diff9__5[7];
  assign p__16 = sum9__3[0] ^ sum9__3[1] ^ sum9__3[2] ^ sum9__3[3] ^ sum9__3[4] ^ sum9__3[5] ^ sum9__3[6] ^ sum9__3[7];
  assign p__18 = sum9__5[0] ^ sum9__5[1] ^ sum9__5[2] ^ sum9__5[3] ^ sum9__5[4] ^ sum9__5[5] ^ sum9__5[6] ^ sum9__5[7];
  assign p__20 = bit0 ^ sel_21797[0] ^ sel_21797[1] ^ sel_21797[2] ^ sel_21797[3] ^ result_squeezed_portion_5_width_3[0] ^ result_squeezed_portion_5_width_3[1] ^ result_squeezed_portion_5_width_3[2];
  assign new_sp = {new_sp_bits_1_width_15, state_tup7_portion_0_width_1};
  assign state_halted = state[6:6];
  assign eq_22083 = opcode == 8'h00;
  assign eq_22084 = opcode == 8'h76;
  assign eq_22085 = opcode == 8'h0a;
  assign eq_22086 = opcode == 8'h30;
  assign high__1 = add_21870[15:8];
  assign high__2 = add_21871[15:8];
  assign low__1 = add_21870[7:0];
  assign low__2 = add_21871[7:0];
  assign concat_22100 = {eq_21846, eq_21847, eq_21848, eq_21774, eq_21724, or_21874, or_21873, eq_21850, nor_21872};
  assign concat_22107 = {eq_21846, eq_21847, eq_21848, eq_21850, nor_21872 | or_21873 | or_21874 | eq_21724 | eq_21774};
  assign concat_22113 = {eq_21818, eq_21719, eq_21701, eq_21661, eq_21645, eq_21635, eq_21627, eq_21751 | eq_21681, eq_21622, eq_21615, eq_21558, eq_21547, eq_21527, eq_21520, eq_21514, eq_21506, eq_21695 | eq_21534, eq_21499, ~(eq_21818 | eq_21719 | eq_21701 | eq_21681 | eq_21661 | eq_21645 | eq_21635 | eq_21627 | eq_21751 | eq_21622 | eq_21615 | eq_21558 | eq_21547 | eq_21534 | eq_21527 | eq_21520 | eq_21514 | eq_21506 | eq_21695 | eq_21499)};
  assign concat_22133 = {eq_21818, eq_21719, eq_21701, eq_21681, eq_21661, ~(eq_21818 | eq_21719 | eq_21701 | eq_21681 | eq_21661)};
  assign eq_22160 = opcode == 8'hfb;
  assign sign_ext_22169 = {8{eq_21574}};
  assign sign_ext_22176 = {8{priority_sel_21711}};
  assign concat_22235 = {eq_21766, eq_21741, eq_21846, eq_21622, eq_21615, eq_21847, eq_21848, eq_21499, ~(eq_21766 | eq_21741 | eq_21846 | eq_21622 | eq_21615 | eq_21847 | eq_21848 | eq_21499)};
  assign concat_22252 = {eq_21766, eq_21741, eq_21846, eq_21622, eq_21615, eq_21847, eq_21848, eq_21499, eq_22032, ~(eq_21766 | eq_21741 | eq_21846 | eq_21622 | eq_21615 | eq_21847 | eq_21848 | eq_21499 | eq_22032)};
  assign concat_22269 = {eq_22033, eq_21766, eq_21741, eq_21846, eq_21622, eq_21615, eq_21847, eq_21848, eq_21784, eq_21499, eq_21861, eq_22032, ~(eq_22033 | eq_21766 | eq_21741 | eq_21846 | eq_21622 | eq_21615 | eq_21847 | eq_21848 | eq_21784 | eq_21499 | eq_21861 | eq_22032)};
  assign high = sum[15:8];
  assign low = sum[7:0];
  assign sel_22292 = eq_21741 ? concat_21670 : (eq_21846 ? ret_addr : (eq_21558 | eq_21547 | eq_21534 | eq_21527 | eq_21520 | eq_21514 | eq_21506 | eq_21695 ? concat_21670 : (eq_21851 ? immediate16 : (eq_21827 ? sel_21776 : (eq_21800 ? immediate16 : sel_21801)))));
  assign or_22293 = state_halted | eq_22083 | eq_22084 | eq_22020 | eq_22085 | eq_22021 | eq_22034 | eq_21867 | eq_21838;
  assign r75 = a[5];
  assign nor_22305 = ~(state_halted | eq_22083 | eq_22084);
  assign concat_22306 = {eq_21838, eq_22016 | eq_22020 | eq_22021, eq_21766, eq_21741, eq_21622, ~(eq_22020 | eq_22021 | eq_21838 | eq_22016 | eq_21766 | eq_21741 | eq_21622)};
  assign concat_22314 = {eq_21800, eq_21774, eq_21708, eq_21824, eq_21861};
  assign lo = priority_sel_8b_3way(concat_21736, state_reg_c__3, state_reg_e, state_reg_l__2, {state_flags_sign__1, 7'h00} | {1'h0, state_flags_zero__1, 6'h00} | {REG_B__1, state_flags_aux_carry__1, 4'h0} | {5'h00, state_flags_parity__1, 2'h0} | 8'h02 | {7'h00, state_flags_carry__1});
  assign hi = priority_sel_8b_3way(concat_21736, state_reg_b__3, state_reg_d, state_reg_h__1, a);
  assign and_22323 = ~state_halted & ~eq_22083 & ~eq_22084 & ~eq_22020 & ~eq_22085 & ~eq_22021 & ~eq_22034 & ~eq_21867 & ~eq_21838 & ~eq_21818 & ~eq_22033 & ~eq_22086 & ~eq_22016 & ~eq_21794 & ~eq_21766 & ~eq_21741 & ~eq_21846 & ~eq_21719 & ~eq_21701 & ~eq_21681 & ~eq_21661 & ~eq_21645 & ~eq_21635 & ~eq_21627 & ~eq_21751 & ~eq_21622 & ~eq_21615 & ~eq_21847 & ~eq_21848 & ~eq_21784 & ~eq_21607 & ~eq_21599 & ~eq_21584 & ~eq_21577 & ~eq_21570 & ~eq_21813 & ~eq_21734 & ~eq_21558 & ~eq_21547 & ~eq_21534 & ~eq_21527 & ~eq_21520 & ~eq_21514 & ~eq_21506 & ~eq_21695 & ~eq_21851 & ~eq_21827 & ~eq_21800 & ~eq_21774 & ~eq_21747 & ~eq_21724 & ~eq_21708 & ~eq_21824 & ~eq_21499 & ~eq_21687 & ~eq_21861 & ~eq_22032 & eq_21651;
  assign or_22324 = state_halted | eq_22083 | eq_22084 | eq_22020 | eq_22085 | eq_22021 | eq_22034 | eq_21867 | eq_21838 | eq_21818 | eq_22033 | eq_22086 | eq_22016 | eq_21794;
  assign or_22329 = state_halted | eq_22083 | eq_22084 | eq_22020 | eq_22085 | eq_22021 | eq_22034 | eq_21867 | eq_21838 | eq_21818;
  assign or_22344 = state_halted | eq_22083 | eq_22084 | eq_22020 | eq_22085 | eq_22021 | eq_22034 | eq_21867 | eq_21838 | eq_21818 | eq_22033 | ~(eq_22086 & a[4]);
  assign new_rst75_pending = ~(r75 | ~state_rst75_pending__1);
  assign state_sod_latch = state[0:0];
  assign sel_22351 = eq_22020 ? bc : (eq_22021 ? de : (eq_21838 | eq_22016 ? immediate16 : (or_22017 ? hl & {16{eq_21574}} : hl & {16{and_21835}})));
  assign sign_ext_22359 = {8{~(state_halted | eq_22083 | eq_22084 | eq_22020 | eq_22085 | eq_22021 | eq_22034 | eq_21867 | eq_21838 | eq_21818 | eq_22033 | eq_22086 | eq_22016 | eq_21794 | eq_21766 | eq_21741 | eq_21846 | eq_21719 | eq_21701 | eq_21681 | eq_21661 | eq_21645 | eq_21635 | eq_21627 | eq_21751 | eq_21622 | eq_21615 | eq_21847 | eq_21848 | eq_21784 | eq_21607 | eq_21599 | eq_21584 | eq_21577 | eq_21570 | eq_21813 | eq_21734 | eq_21558 | eq_21547 | eq_21534 | eq_21527 | eq_21520 | eq_21514 | eq_21506 | eq_21695 | eq_21851 | eq_21827)}};
  assign tuple_22373 = {or_22293 ? state_flags_sign__1 : state_flags_sign__1 & concat_22113[0] | (or_21496 ? state_flags_sign__1 : stack_read_lo[7]) & concat_22113[1] | diff9__2[7] & concat_22113[2] | result__20[7] & concat_22113[3] | result__19[7] & concat_22113[4] | result__18[7] & concat_22113[5] | diff9__1[7] & concat_22113[6] | sum9[7] & concat_22113[7] | sum9__1[7] & concat_22113[8] | diff9__3[7] & concat_22113[9] | sum9__2[7] & concat_22113[10] | diff9__6[7] & concat_22113[11] | result__7[7] & concat_22113[12] | result__6[7] & concat_22113[13] | result__5[7] & concat_22113[14] | diff9__5[7] & concat_22113[15] | sum9__3[7] & concat_22113[16] | sum9__5[7] & concat_22113[17] | result_squeezed_portion_5_width_3[2] & concat_22113[18], or_22293 ? state_flags_zero__1 : state_flags_zero__1 & concat_22113[0] | (or_21496 ? state_flags_zero__1 : stack_read_lo[6]) & concat_22113[1] | result__31 == 8'h00 & concat_22113[2] | result__20 == 8'h00 & concat_22113[3] | result__19 == 8'h00 & concat_22113[4] | result__18 == 8'h00 & concat_22113[5] | result__30 == 8'h00 & concat_22113[6] | result__32 == 8'h00 & concat_22113[7] | result__33 == 8'h00 & concat_22113[8] | result__34 == 8'h00 & concat_22113[9] | result__35 == 8'h00 & concat_22113[10] | result__38 == 8'h00 & concat_22113[11] | result__7 == 8'h00 & concat_22113[12] | result__6 == 8'h00 & concat_22113[13] | result__5 == 8'h00 & concat_22113[14] | result__37 == 8'h00 & concat_22113[15] | result__39 == 8'h00 & concat_22113[16] | result__41 == 8'h00 & concat_22113[17] | ~(result_squeezed_portion_5_width_3 != REG_B__1 | sel_21797 != 4'h0 | bit0) & concat_22113[18], or_22293 ? state_flags_aux_carry__1 : (eq_21645 | ~eq_21645 & nor_21878) & concat_22133[0] | low_diff__5[4] & concat_22133[1] | low_diff__6[4] & concat_22133[2] | low_sum__3[4] & concat_22133[3] | low_sum__5[4] & concat_22133[4] | add_lo & concat_22133[5], or_22293 ? state_flags_parity__1 : state_flags_parity__1 & concat_22113[0] | (or_21496 ? state_flags_parity__1 : stack_read_lo[2]) & concat_22113[1] | ~p__5 & concat_22113[2] | ~p__1 & concat_22113[3] | ~p__2 & concat_22113[4] | ~p__3 & concat_22113[5] | ~p__4 & concat_22113[6] | ~p__6 & concat_22113[7] | ~p__7 & concat_22113[8] | ~p__8 & concat_22113[9] | ~p__9 & concat_22113[10] | ~p__15 & concat_22113[11] | ~p__11 & concat_22113[12] | ~p__12 & concat_22113[13] | ~p__13 & concat_22113[14] | ~p__14 & concat_22113[15] | ~p__16 & concat_22113[16] | ~p__18 & concat_22113[17] | ~p__20 & concat_22113[18], or_22293 ? state_flags_carry__1 : ~eq_21645 & ~(eq_21635 | eq_21627 | not_22015) & concat_22133[0] | ~diff9__5[8] & concat_22133[1] | ~diff9__6[8] & concat_22133[2] | sum9__3[8] & concat_22133[3] | sum9__5[8] & concat_22133[4] | add_hi & concat_22133[5]};
  assign and_22384 = (eq_21800 ? new_sp : (eq_21774 ? new_sp & {16{priority_sel_21711}} : (or_21849 ? new_sp : state_sp__6 & {16{eq_21861}}))) & {16{~(state_halted | eq_22083 | eq_22084 | eq_22020 | eq_22085 | eq_22021 | eq_22034 | eq_21867 | eq_21838 | eq_21818 | eq_22033 | eq_22086 | eq_22016 | eq_21794 | eq_21766 | eq_21741 | eq_21846 | eq_21719 | eq_21701 | eq_21681 | eq_21661 | eq_21645 | eq_21635 | eq_21627 | eq_21751 | eq_21622 | eq_21615 | eq_21847 | eq_21848 | eq_21784 | eq_21607 | eq_21599 | eq_21584 | eq_21577 | eq_21570 | eq_21813 | eq_21734 | eq_21558 | eq_21547 | eq_21534 | eq_21527 | eq_21520 | eq_21514 | eq_21506 | eq_21695 | eq_21851 | eq_21827)}};
  assign one_hot_22455 = {concat_21604[6:0] == 7'h00, concat_21604[6] && concat_21604[5:0] == 6'h00, concat_21604[5] && concat_21604[4:0] == 5'h00, concat_21604[4] && concat_21604[3:0] == 4'h0, concat_21604[3] && concat_21604[2:0] == 3'h0, concat_21604[2] && concat_21604[1:0] == 2'h0, concat_21604[1] && !concat_21604[0], concat_21604[0]};
  assign one_hot_22461 = {concat_21562[6:0] == 7'h00, concat_21562[6] && concat_21562[5:0] == 6'h00, concat_21562[5] && concat_21562[4:0] == 5'h00, concat_21562[4] && concat_21562[3:0] == 4'h0, concat_21562[3] && concat_21562[2:0] == 3'h0, concat_21562[2] && concat_21562[1:0] == 2'h0, concat_21562[1] && !concat_21562[0], concat_21562[0]};
  assign tuple_22391 = {or_22324 ? state_reg_b__3 : state_reg_b__3 & {8{concat_22235[0]}} | (nor_21491 ? stack_read_hi : state_reg_b__3) & {8{concat_22235[1]}} | (nor_21491 ? high__1 : state_reg_b__3) & {8{concat_22235[2]}} | (nor_21491 ? high__2 : state_reg_b__3) & {8{concat_22235[3]}} | (eq_21556 ? result__34 : state_reg_b__3) & {8{concat_22235[4]}} | (eq_21556 ? result__35 : state_reg_b__3) & {8{concat_22235[5]}} | (nor_21491 ? byte3 : state_reg_b__3) & {8{concat_22235[6]}} | (eq_21556 ? byte2 : state_reg_b__3) & {8{concat_22235[7]}} | (eq_21556 ? src_val : state_reg_b__3) & {8{concat_22235[8]}}, or_22324 ? state_reg_c__3 : state_reg_c__3 & {8{concat_22235[0]}} | (nor_21491 ? stack_read_lo : state_reg_c__3) & {8{concat_22235[1]}} | (nor_21491 ? low__1 : state_reg_c__3) & {8{concat_22235[2]}} | (nor_21491 ? low__2 : state_reg_c__3) & {8{concat_22235[3]}} | (eq_21555 ? result__34 : state_reg_c__3) & {8{concat_22235[4]}} | (eq_21555 ? result__35 : state_reg_c__3) & {8{concat_22235[5]}} | (nor_21491 ? byte2 : state_reg_c__3) & {8{concat_22235[6]}} | (eq_21555 ? byte2 : state_reg_c__3) & {8{concat_22235[7]}} | (eq_21555 ? src_val : state_reg_c__3) & {8{concat_22235[8]}}, or_22324 ? state_reg_d : state_reg_d & {8{concat_22252[0]}} | state_reg_h__1 & {8{concat_22252[1]}} | (eq_21490 ? stack_read_hi : state_reg_d) & {8{concat_22252[2]}} | (eq_21490 ? high__1 : state_reg_d) & {8{concat_22252[3]}} | (eq_21490 ? high__2 : state_reg_d) & {8{concat_22252[4]}} | (eq_21554 ? result__34 : state_reg_d) & {8{concat_22252[5]}} | (eq_21554 ? result__35 : state_reg_d) & {8{concat_22252[6]}} | (eq_21490 ? byte3 : state_reg_d) & {8{concat_22252[7]}} | (eq_21554 ? byte2 : state_reg_d) & {8{concat_22252[8]}} | (eq_21554 ? src_val : state_reg_d) & {8{concat_22252[9]}}, or_22324 ? state_reg_e : state_reg_e & {8{concat_22252[0]}} | state_reg_l__2 & {8{concat_22252[1]}} | (eq_21490 ? stack_read_lo : state_reg_e) & {8{concat_22252[2]}} | (eq_21490 ? low__1 : state_reg_e) & {8{concat_22252[3]}} | (eq_21490 ? low__2 : state_reg_e) & {8{concat_22252[4]}} | (eq_21553 ? result__34 : state_reg_e) & {8{concat_22252[5]}} | (eq_21553 ? result__35 : state_reg_e) & {8{concat_22252[6]}} | (eq_21490 ? byte2 : state_reg_e) & {8{concat_22252[7]}} | (eq_21553 ? byte2 : state_reg_e) & {8{concat_22252[8]}} | (eq_21553 ? src_val : state_reg_e) & {8{concat_22252[9]}}, or_22329 ? state_reg_h__1 : state_reg_h__1 & {8{concat_22269[0]}} | state_reg_d & {8{concat_22269[1]}} | stack_read_hi & {8{concat_22269[2]}} | (eq_21489 ? stack_read_hi : state_reg_h__1) & {8{concat_22269[3]}} | high & {8{concat_22269[4]}} | (eq_21489 ? high__1 : state_reg_h__1) & {8{concat_22269[5]}} | (eq_21489 ? high__2 : state_reg_h__1) & {8{concat_22269[6]}} | (eq_21552 ? result__34 : state_reg_h__1) & {8{concat_22269[7]}} | (eq_21552 ? result__35 : state_reg_h__1) & {8{concat_22269[8]}} | (eq_21489 ? byte3 : state_reg_h__1) & {8{concat_22269[9]}} | (eq_21552 ? byte2 : state_reg_h__1) & {8{concat_22269[10]}} | (eq_21552 ? src_val : state_reg_h__1) & {8{concat_22269[11]}} | stack_read_lo & {8{concat_22269[12]}}, or_22329 ? state_reg_l__2 : state_reg_l__2 & {8{concat_22269[0]}} | state_reg_e & {8{concat_22269[1]}} | stack_read_lo & {8{concat_22269[2]}} | (eq_21489 ? stack_read_lo : state_reg_l__2) & {8{concat_22269[3]}} | low & {8{concat_22269[4]}} | (eq_21489 ? low__1 : state_reg_l__2) & {8{concat_22269[5]}} | (eq_21489 ? low__2 : state_reg_l__2) & {8{concat_22269[6]}} | (eq_21551 ? result__34 : state_reg_l__2) & {8{concat_22269[7]}} | (eq_21551 ? result__35 : state_reg_l__2) & {8{concat_22269[8]}} | (eq_21489 ? byte2 : state_reg_l__2) & {8{concat_22269[9]}} | (eq_21551 ? byte2 : state_reg_l__2) & {8{concat_22269[10]}} | (eq_21551 ? src_val : state_reg_l__2) & {8{concat_22269[11]}} | mem_read_data & {8{concat_22269[12]}}, state_halted | eq_22083 | eq_22084 | eq_22020 ? a : (eq_22085 ? mem_read_data : (eq_22021 ? a : (eq_22034 ? mem_read_data : sel_22035))), state_halted | eq_22083 | eq_22084 | eq_22020 | eq_22085 | eq_22021 | eq_22034 | eq_21867 | eq_21838 | eq_21818 | eq_22033 | eq_22086 | eq_22016 | eq_21794 | eq_21766 | eq_21741 ? state_sp__6 : {state_sp__6_bits_1_width_15 & {15{concat_22100[0]}} | {state_reg_h__1, state_reg_l__2[7:1]} & {15{concat_22100[1]}} | add_22037 & {15{concat_22100[2]}} | new_sp_bits_1_width_15 & {15{concat_22100[3]}} | (priority_sel_21711 ? add_22037 : state_sp__6_bits_1_width_15) & {15{concat_22100[4]}} | (priority_sel_21711 ? new_sp_bits_1_width_15 : state_sp__6_bits_1_width_15) & {15{concat_22100[5]}} | sel_22448[15:1] & {15{concat_22100[6]}} | sel_22447[15:1] & {15{concat_22100[7]}} | sel_22446[15:1] & {15{concat_22100[8]}}, state_tup7_portion_0_width_1 & concat_22107[0] | state_reg_l__2[0] & concat_22107[1] | sel_22448[0] & concat_22107[2] | sel_22447[0] & concat_22107[3] | sel_22446[0] & concat_22107[4]}, state_halted ? state_pc__54 : (eq_21838 | eq_22033 | eq_22016 | eq_21794 ? ret_addr : sel_22292), tuple_22373, eq_22084 | state_halted, state_halted | eq_22083 | eq_22084 | eq_22020 | eq_22085 | eq_22021 | eq_22034 | eq_21867 | eq_21838 | eq_21818 | eq_22033 | eq_22086 | eq_22016 | eq_21794 | eq_21766 | eq_21741 | eq_21846 | eq_21719 | eq_21701 | eq_21681 | eq_21661 | eq_21645 | eq_21635 | eq_21627 | eq_21751 | eq_21622 | eq_21615 | eq_21847 | eq_21848 | eq_21784 | eq_21607 | eq_21599 | eq_21584 | eq_21577 | eq_21570 | eq_21813 | eq_21734 | eq_21558 | eq_21547 | eq_21534 | eq_21527 | eq_21520 | eq_21514 | eq_21506 | eq_21695 | eq_21851 | eq_21827 | eq_21800 | eq_21774 | eq_21747 | eq_21724 | eq_21708 | eq_21824 | eq_21499 | eq_21687 | eq_21861 | eq_22032 | eq_21850 | ~ne_21494 | eq_21651 ? state_inte : eq_22160 | ~(eq_22160 | opcode == 8'hf3 | ~state_inte), or_22344 ? state_mask_55__1 : bit0, or_22344 ? state_mask_65__1 : a[1], or_22344 ? state_mask_75__1 : a[2], state_halted | eq_22083 | eq_22084 | eq_22020 | eq_22085 | eq_22021 | eq_22034 | eq_21867 | eq_21838 | eq_21818 | eq_22033 | ~eq_22086 ? state_rst75_pending__1 : new_rst75_pending, state_halted | eq_22083 | eq_22084 | eq_22020 | eq_22085 | eq_22021 | eq_22034 | eq_21867 | eq_21838 | eq_21818 | eq_22033 | ~(eq_22086 & a[6]) ? state_sod_latch : bit7};
  assign tuple_22393 = {tuple_22391, {sel_22351 & {16{nor_22305}}, (result__34 & {8{and_21835}} & {8{concat_22306[0]}} | result__35 & sign_ext_22169 & {8{concat_22306[1]}} | byte2 & sign_ext_22169 & {8{concat_22306[2]}} | one_hot_sel_22460 & sign_ext_22169 & {8{concat_22306[3]}} | a & {8{concat_22306[4]}} | state_reg_l__2 & {8{concat_22306[5]}}) & {8{nor_22305}}, ~state_halted & ~eq_22084 & (eq_22020 | eq_22021 | eq_21838 | eq_22016 | eq_21574 & (or_22017 | eq_21615)), and_22384, (state_reg_l__2 & {8{concat_22314[0]}} | lo & {8{concat_22314[1]}} | ret_addr__4[7:0] & {8{concat_22314[2]}} | ret_addr[7:0] & sign_ext_22176 & {8{concat_22314[3]}} | ret_addr[7:0] & {8{concat_22314[4]}}) & sign_ext_22359, (state_reg_h__1 & {8{concat_22314[0]}} | hi & {8{concat_22314[1]}} | ret_addr__4[15:8] & {8{concat_22314[2]}} | ret_addr[15:8] & sign_ext_22176 & {8{concat_22314[3]}} | ret_addr[15:8] & {8{concat_22314[4]}}) & sign_ext_22359, ~state_halted & ~eq_22083 & ~eq_22084 & ~eq_22020 & ~eq_22085 & ~eq_22021 & ~eq_22034 & ~eq_21867 & ~eq_21838 & ~eq_21818 & ~eq_22033 & ~eq_22086 & ~eq_22016 & ~eq_21794 & ~eq_21766 & ~eq_21741 & ~eq_21846 & ~eq_21719 & ~eq_21701 & ~eq_21681 & ~eq_21661 & ~eq_21645 & ~eq_21635 & ~eq_21627 & ~eq_21751 & ~eq_21622 & ~eq_21615 & ~eq_21847 & ~eq_21848 & ~eq_21784 & ~eq_21607 & ~eq_21599 & ~eq_21584 & ~eq_21577 & ~eq_21570 & ~eq_21813 & ~eq_21734 & ~eq_21558 & ~eq_21547 & ~eq_21534 & ~eq_21527 & ~eq_21520 & ~eq_21514 & ~eq_21506 & ~eq_21695 & ~eq_21851 & ~eq_21827 & (eq_21800 | (eq_21774 ? priority_sel_21711 : eq_21708 | eq_21824 | eq_21861)), byte2 & {8{~(state_halted | eq_22083 | eq_22084 | eq_22020 | eq_22085 | eq_22021 | eq_22034 | eq_21867 | eq_21838 | eq_21818 | eq_22033 | eq_22086 | eq_22016 | eq_21794 | eq_21766 | eq_21741 | eq_21846 | eq_21719 | eq_21701 | eq_21681 | eq_21661 | eq_21645 | eq_21635 | eq_21627 | eq_21751 | eq_21622 | eq_21615 | eq_21847 | eq_21848 | eq_21784 | eq_21607 | eq_21599 | eq_21584 | eq_21577 | eq_21570 | eq_21813 | eq_21734 | eq_21558 | eq_21547 | eq_21534 | eq_21527 | eq_21520 | eq_21514 | eq_21506 | eq_21695 | eq_21851 | eq_21827 | eq_21800 | eq_21774 | eq_21747 | eq_21724 | eq_21708 | eq_21824 | eq_21499 | eq_21687 | nor_21669)}}, a & {8{and_22323}}, ~state_halted & ~eq_22083 & ~eq_22084 & ~eq_22020 & ~eq_22085 & ~eq_22021 & ~eq_22034 & ~eq_21867 & ~eq_21838 & ~eq_21818 & ~eq_22033 & ~eq_22086 & ~eq_22016 & ~eq_21794 & ~eq_21766 & ~eq_21741 & ~eq_21846 & ~eq_21719 & ~eq_21701 & ~eq_21681 & ~eq_21661 & ~eq_21645 & ~eq_21635 & ~eq_21627 & ~eq_21751 & ~eq_21622 & ~eq_21615 & ~eq_21847 & ~eq_21848 & ~eq_21784 & ~eq_21607 & ~eq_21599 & ~eq_21584 & ~eq_21577 & ~eq_21570 & ~eq_21813 & ~eq_21734 & ~eq_21558 & ~eq_21547 & ~eq_21534 & ~eq_21527 & ~eq_21520 & ~eq_21514 & ~eq_21506 & ~eq_21695 & ~eq_21851 & ~eq_21827 & ~eq_21800 & ~eq_21774 & ~eq_21747 & ~eq_21724 & ~eq_21708 & ~eq_21824 & ~eq_21499 & ~eq_21687 & ~eq_21861 & ~ne_21494, and_22323}};
  assign eq_22457 = concat_21604 == one_hot_22455[6:0];
  assign eq_22463 = concat_21562 == one_hot_22461[6:0];
  assign out = tuple_22393;
  `ifdef ASSERT_ON
  __xls_invariant_priority_sel_21613_selector_one_hot_A: assert final ($isunknown(eq_22457) || eq_22457) else $fatal(0, "Selector concat.21604 was expected to be one-hot, and is not.");
  __xls_invariant_priority_sel_21575_selector_one_hot_A: assert final ($isunknown(eq_22463) || eq_22463) else $fatal(0, "Selector concat.21562 was expected to be one-hot, and is not.");
  `endif  // ASSERT_ON
endmodule
