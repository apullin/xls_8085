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
  function automatic priority_sel_1b_7way (input reg [6:0] sel, input reg case0, input reg case1, input reg case2, input reg case3, input reg case4, input reg case5, input reg case6, input reg default_value);
    begin
      casez (sel)
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
          priority_sel_1b_7way = 1'dx;
        end
      endcase
    end
  endfunction
  function automatic [15:0] priority_sel_16b_3way (input reg [2:0] sel, input reg [15:0] case0, input reg [15:0] case1, input reg [15:0] case2, input reg [15:0] default_value);
    begin
      casez (sel)
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
          priority_sel_16b_3way = 16'dx;
        end
      endcase
    end
  endfunction
  function automatic [7:0] priority_sel_8b_3way (input reg [2:0] sel, input reg [7:0] case0, input reg [7:0] case1, input reg [7:0] case2, input reg [7:0] default_value);
    begin
      casez (sel)
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
          priority_sel_8b_3way = 8'dx;
        end
      endcase
    end
  endfunction
  wire [1:0] rp;
  wire [1:0] RP_HL__5;
  wire [1:0] RP_DE;
  wire eq_21496;
  wire eq_21497;
  wire nor_21498;
  wire [7:0] and_21499;
  wire ne_21501;
  wire [7:0] a;
  wire or_21503;
  wire [4:0] state_flags__22;
  wire eq_21506;
  wire [7:0] not_b__1;
  wire state_flags_carry__1;
  wire eq_21513;
  wire [7:0] result__20;
  wire [8:0] concat_21516;
  wire cin__1;
  wire eq_21521;
  wire [7:0] result__19;
  wire [8:0] add_21524;
  wire [8:0] concat_21525;
  wire eq_21527;
  wire [7:0] result__18;
  wire [8:0] diff9__1;
  wire eq_21534;
  wire [7:0] result__30;
  wire [8:0] diff9__2;
  wire [8:0] sum9__1;
  wire [8:0] concat_21539;
  wire eq_21541;
  wire [7:0] sel_21542;
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
  wire eq_21554;
  wire [7:0] result__32;
  wire eq_21557;
  wire eq_21558;
  wire eq_21559;
  wire eq_21560;
  wire eq_21561;
  wire eq_21562;
  wire eq_21563;
  wire eq_21565;
  wire [7:0] result__33;
  wire [2:0] REG_M;
  wire [6:0] concat_21569;
  wire [7:0] state_reg_b__3;
  wire [7:0] state_reg_c__3;
  wire [7:0] state_reg_d;
  wire [7:0] state_reg_e;
  wire [7:0] state_reg_h__1;
  wire [7:0] state_reg_l__2;
  wire eq_21577;
  wire [6:0] result__21;
  wire eq_21581;
  wire eq_21584;
  wire [7:0] result__13;
  wire [6:0] result__24;
  wire [7:0] val;
  wire [2:0] sss;
  wire eq_21591;
  wire [7:0] result__12;
  wire bit0;
  wire [8:0] concat_21595;
  wire [8:0] diff9__3_associative_element;
  wire eq_21606;
  wire [7:0] sel_21607;
  wire [7:0] result__11;
  wire bit7;
  wire [8:0] diff9__3;
  wire [6:0] concat_21611;
  wire [7:0] and_21612;
  wire eq_21614;
  wire [7:0] result__10;
  wire [7:0] result__34;
  wire [8:0] sum9__2;
  wire [7:0] one_hot_sel_22469;
  wire eq_21622;
  wire [7:0] result__35;
  wire [7:0] src_val;
  wire eq_21629;
  wire [7:0] not_b__5;
  wire eq_21634;
  wire [7:0] result__7;
  wire [15:0] state_pc__54;
  wire [3:0] lo_nibble;
  wire eq_21642;
  wire [7:0] result__6;
  wire [8:0] add_21645;
  wire [4:0] concat_21649;
  wire eq_21652;
  wire [7:0] sel_21653;
  wire [7:0] result__5;
  wire [8:0] diff9__5;
  wire eq_21658;
  wire [14:0] add_21659;
  wire state_flags_aux_carry__1;
  wire [4:0] add_21664;
  wire eq_21668;
  wire [7:0] result__37;
  wire [8:0] diff9__6;
  wire [8:0] sum9__5;
  wire nor_21677;
  wire [15:0] concat_21678;
  wire [15:0] ret_addr__4;
  wire state_flags_zero__1;
  wire state_flags_parity__1;
  wire state_flags_sign__1;
  wire [4:0] low_diff__2;
  wire eq_21689;
  wire [7:0] result__38;
  wire [8:0] sum9__3;
  wire [6:0] sum9__7_bits_1_width_7;
  wire eq_21696;
  wire [15:0] hl;
  wire eq_21704;
  wire eq_21710;
  wire [7:0] result__39;
  wire add_lo;
  wire eq_21717;
  wire [15:0] rst_addr;
  wire priority_sel_21720;
  wire [15:0] ret_addr__3;
  wire eq_21728;
  wire [7:0] result__41;
  wire [3:0] tmp1_squeezed_portion_1_width_7__1;
  wire eq_21733;
  wire eq_21743;
  wire [2:0] concat_21745;
  wire [15:0] bc;
  wire [15:0] de;
  wire [15:0] state_sp__6;
  wire eq_21750;
  wire [2:0] tmp1_bits_5_width_3;
  wire eq_21756;
  wire [15:0] ret_addr;
  wire [15:0] immediate16;
  wire eq_21760;
  wire nor_21762;
  wire [4:0] concat_21763;
  wire [4:0] low_sum__1;
  wire [4:0] concat_21765;
  wire [4:0] concat_21766;
  wire [4:0] low_diff__3_associative_element;
  wire [4:0] add_21768;
  wire nor_21771;
  wire [15:0] val__2;
  wire eq_21775;
  wire [7:0] sel_21776;
  wire add_hi;
  wire [2:0] sum9__8_bits_5_width_3;
  wire eq_21783;
  wire [15:0] sel_21785;
  wire [4:0] low_diff__1;
  wire [4:0] low_sum;
  wire [4:0] low_diff__3;
  wire [4:0] low_sum__2;
  wire [4:0] low_diff__6;
  wire eq_21793;
  wire [5:0] concat_21795;
  wire eq_21803;
  wire [2:0] result_squeezed_portion_5_width_3;
  wire [3:0] sel_21806;
  wire eq_21809;
  wire [15:0] sel_21810;
  wire [7:0] concat_21811;
  wire eq_21822;
  wire [16:0] sum;
  wire eq_21827;
  wire [7:0] result;
  wire eq_21833;
  wire eq_21836;
  wire [4:0] concat_21840;
  wire and_21844;
  wire eq_21847;
  wire state_rst75_pending__1;
  wire state_inte;
  wire state_mask_75__1;
  wire state_mask_65__1;
  wire state_mask_55__1;
  wire eq_21855;
  wire eq_21856;
  wire eq_21857;
  wire or_21858;
  wire eq_21859;
  wire eq_21860;
  wire eq_21870;
  wire [14:0] state_sp__6_bits_1_width_15;
  wire eq_21876;
  wire [7:0] rim_result;
  wire [15:0] add_21879;
  wire [15:0] add_21880;
  wire nor_21881;
  wire or_21882;
  wire or_21883;
  wire nor_21887;
  wire [4:0] low_sum__5;
  wire not_22024;
  wire eq_22025;
  wire or_22026;
  wire eq_22029;
  wire eq_22030;
  wire [14:0] new_sp_bits_1_width_15;
  wire state_tup7_portion_0_width_1;
  wire eq_22041;
  wire eq_22042;
  wire eq_22043;
  wire [7:0] sel_22044;
  wire [14:0] add_22046;
  wire [15:0] sel_22457;
  wire [15:0] sel_22456;
  wire [15:0] sel_22455;
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
  wire eq_22092;
  wire eq_22093;
  wire eq_22094;
  wire eq_22095;
  wire [7:0] high__1;
  wire [7:0] high__2;
  wire [7:0] low__1;
  wire [7:0] low__2;
  wire [8:0] concat_22109;
  wire [4:0] concat_22116;
  wire [18:0] concat_22122;
  wire [5:0] concat_22142;
  wire eq_22169;
  wire [7:0] sign_ext_22178;
  wire [7:0] sign_ext_22185;
  wire [8:0] concat_22244;
  wire [9:0] concat_22261;
  wire [12:0] concat_22278;
  wire [7:0] high;
  wire [7:0] low;
  wire [15:0] sel_22301;
  wire or_22302;
  wire r75;
  wire nor_22314;
  wire [5:0] concat_22315;
  wire [4:0] concat_22323;
  wire [7:0] lo;
  wire [7:0] hi;
  wire and_22332;
  wire or_22333;
  wire or_22338;
  wire or_22353;
  wire new_rst75_pending;
  wire state_sod_latch;
  wire [15:0] sel_22360;
  wire [7:0] sign_ext_22368;
  wire [4:0] tuple_22382;
  wire [15:0] and_22393;
  wire [7:0] one_hot_22464;
  wire [7:0] one_hot_22470;
  wire [99:0] tuple_22400;
  wire [175:0] tuple_22402;
  wire eq_22466;
  wire eq_22472;
  assign rp = opcode[5:4];
  assign RP_HL__5 = 2'h2;
  assign RP_DE = 2'h1;
  assign eq_21496 = rp == RP_HL__5;
  assign eq_21497 = rp == RP_DE;
  assign nor_21498 = ~(opcode[4] | opcode[5]);
  assign and_21499 = opcode & 8'hcf;
  assign ne_21501 = opcode != 8'hdb;
  assign a = state[51:44];
  assign or_21503 = eq_21496 | eq_21497 | nor_21498;
  assign state_flags__22 = state[11:7];
  assign eq_21506 = and_21499 == 8'hc1;
  assign not_b__1 = ~byte2;
  assign state_flags_carry__1 = state_flags__22[0:0];
  assign eq_21513 = opcode == 8'hf6;
  assign result__20 = a | byte2;
  assign concat_21516 = {1'h0, a};
  assign cin__1 = ~state_flags_carry__1;
  assign eq_21521 = opcode == 8'hee;
  assign result__19 = a ^ byte2;
  assign add_21524 = concat_21516 + {1'h0, not_b__1};
  assign concat_21525 = {8'h00, cin__1};
  assign eq_21527 = opcode == 8'he6;
  assign result__18 = a & byte2;
  assign diff9__1 = add_21524 + concat_21525;
  assign eq_21534 = opcode == 8'hde;
  assign result__30 = diff9__1[7:0];
  assign diff9__2 = add_21524 + 9'h001;
  assign sum9__1 = concat_21516 + {1'h0, byte2};
  assign concat_21539 = {8'h00, state_flags_carry__1};
  assign eq_21541 = opcode == 8'hd6;
  assign sel_21542 = eq_21534 ? result__30 : (eq_21527 ? result__18 : (eq_21521 ? result__19 : (eq_21513 ? result__20 : (eq_21506 ? (or_21503 ? a : stack_read_hi) : (ne_21501 ? a : io_read_data)))));
  assign result__31 = diff9__2[7:0];
  assign sum9 = sum9__1 + concat_21539;
  assign nnn = opcode[5:3];
  assign REG_A__1 = 3'h7;
  assign REG_L__1 = 3'h5;
  assign REG_H__1 = 3'h4;
  assign REG_E__1 = 3'h3;
  assign REG_D__1 = 3'h2;
  assign REG_C__1 = 3'h1;
  assign REG_B__1 = 3'h0;
  assign eq_21554 = opcode == 8'hce;
  assign result__32 = sum9[7:0];
  assign eq_21557 = nnn == REG_A__1;
  assign eq_21558 = nnn == REG_L__1;
  assign eq_21559 = nnn == REG_H__1;
  assign eq_21560 = nnn == REG_E__1;
  assign eq_21561 = nnn == REG_D__1;
  assign eq_21562 = nnn == REG_C__1;
  assign eq_21563 = nnn == REG_B__1;
  assign eq_21565 = opcode == 8'hc6;
  assign result__33 = sum9__1[7:0];
  assign REG_M = 3'h6;
  assign concat_21569 = {eq_21557, eq_21558, eq_21559, eq_21560, eq_21561, eq_21562, eq_21563};
  assign state_reg_b__3 = state[99:92];
  assign state_reg_c__3 = state[91:84];
  assign state_reg_d = state[83:76];
  assign state_reg_e = state[75:68];
  assign state_reg_h__1 = state[67:60];
  assign state_reg_l__2 = state[59:52];
  assign eq_21577 = opcode == 8'h2f;
  assign result__21 = a[7:1];
  assign eq_21581 = nnn == REG_M;
  assign eq_21584 = opcode == 8'h1f;
  assign result__13 = {state_flags_carry__1, result__21};
  assign result__24 = a[6:0];
  assign val = eq_21581 ? mem_read_data : state_reg_b__3 & {8{concat_21569[0]}} | state_reg_c__3 & {8{concat_21569[1]}} | state_reg_d & {8{concat_21569[2]}} | state_reg_e & {8{concat_21569[3]}} | state_reg_h__1 & {8{concat_21569[4]}} | state_reg_l__2 & {8{concat_21569[5]}} | a & {8{concat_21569[6]}};
  assign sss = opcode[2:0];
  assign eq_21591 = opcode == 8'h17;
  assign result__12 = {result__24, state_flags_carry__1};
  assign bit0 = a[0];
  assign concat_21595 = {1'h0, val};
  assign diff9__3_associative_element = 9'h0ff;
  assign eq_21606 = opcode == 8'h0f;
  assign sel_21607 = eq_21591 ? result__12 : (eq_21584 ? result__13 : (eq_21577 ? ~a : (eq_21565 ? result__33 : (eq_21554 ? result__32 : (eq_21541 ? result__31 : sel_21542)))));
  assign result__11 = {bit0, result__21};
  assign bit7 = a[7];
  assign diff9__3 = concat_21595 + diff9__3_associative_element;
  assign concat_21611 = {sss == REG_A__1, sss == REG_L__1, sss == REG_H__1, sss == REG_E__1, sss == REG_D__1, sss == REG_C__1, sss == REG_B__1};
  assign and_21612 = opcode & 8'hc7;
  assign eq_21614 = opcode == 8'h07;
  assign result__10 = {result__24, bit7};
  assign result__34 = diff9__3[7:0];
  assign sum9__2 = concat_21595 + 9'h001;
  assign one_hot_sel_22469 = state_reg_b__3 & {8{concat_21611[0]}} | state_reg_c__3 & {8{concat_21611[1]}} | state_reg_d & {8{concat_21611[2]}} | state_reg_e & {8{concat_21611[3]}} | state_reg_h__1 & {8{concat_21611[4]}} | state_reg_l__2 & {8{concat_21611[5]}} | a & {8{concat_21611[6]}};
  assign eq_21622 = and_21612 == 8'h05;
  assign result__35 = sum9__2[7:0];
  assign src_val = sss == REG_M ? mem_read_data : one_hot_sel_22469;
  assign eq_21629 = and_21612 == 8'h04;
  assign not_b__5 = ~src_val;
  assign eq_21634 = opcode[7:3] == 5'h16;
  assign result__7 = a | src_val;
  assign state_pc__54 = state[27:12];
  assign lo_nibble = a[3:0];
  assign eq_21642 = opcode[7:3] == 5'h15;
  assign result__6 = a ^ src_val;
  assign add_21645 = concat_21516 + {1'h0, not_b__5};
  assign concat_21649 = {1'h0, lo_nibble};
  assign eq_21652 = opcode[7:3] == 5'h14;
  assign sel_21653 = eq_21642 ? result__6 : (eq_21634 ? result__7 : (eq_21629 ? (eq_21557 ? result__35 : a) : (eq_21622 ? (eq_21557 ? result__34 : a) : (eq_21614 ? result__10 : (eq_21606 ? result__11 : sel_21607)))));
  assign result__5 = a & src_val;
  assign diff9__5 = add_21645 + concat_21525;
  assign eq_21658 = opcode == 8'hd3;
  assign add_21659 = state_pc__54[15:1] + 15'h0001;
  assign state_flags_aux_carry__1 = state_flags__22[2:2];
  assign add_21664 = concat_21649 + {1'h0, not_b__1[3:0]};
  assign eq_21668 = opcode[7:3] == 5'h13;
  assign result__37 = diff9__5[7:0];
  assign diff9__6 = add_21645 + 9'h001;
  assign sum9__5 = concat_21516 + {1'h0, src_val};
  assign nor_21677 = ~(~ne_21501 | eq_21658);
  assign concat_21678 = {add_21659, state_pc__54[0]};
  assign ret_addr__4 = state_pc__54 + 16'h0001;
  assign state_flags_zero__1 = state_flags__22[3:3];
  assign state_flags_parity__1 = state_flags__22[1:1];
  assign state_flags_sign__1 = state_flags__22[4:4];
  assign low_diff__2 = add_21664 + 5'h01;
  assign eq_21689 = opcode[7:3] == 5'h12;
  assign result__38 = diff9__6[7:0];
  assign sum9__3 = sum9__5 + concat_21539;
  assign sum9__7_bits_1_width_7 = result__21 + 7'h03;
  assign eq_21696 = opcode == 8'he9;
  assign hl = {state_reg_h__1, state_reg_l__2};
  assign eq_21704 = opcode == 8'hfe;
  assign eq_21710 = opcode[7:3] == 5'h11;
  assign result__39 = sum9__3[7:0];
  assign add_lo = lo_nibble > 4'h9 | state_flags_aux_carry__1;
  assign eq_21717 = ~(opcode | 8'h38) == 8'h00;
  assign rst_addr = {10'h000, nnn, REG_B__1};
  assign priority_sel_21720 = priority_sel_1b_7way({eq_21581, eq_21558, eq_21559, eq_21560, eq_21561, eq_21562, eq_21563}, ~state_flags_zero__1, state_flags_zero__1, cin__1, state_flags_carry__1, ~state_flags_parity__1, state_flags_parity__1, ~state_flags_sign__1, state_flags_sign__1);
  assign ret_addr__3 = {stack_read_hi, stack_read_lo};
  assign eq_21728 = opcode[7:3] == 5'h10;
  assign result__41 = sum9__5[7:0];
  assign tmp1_squeezed_portion_1_width_7__1 = add_lo ? sum9__7_bits_1_width_7[6:3] : a[7:4];
  assign eq_21733 = and_21612 == 8'hc0;
  assign eq_21743 = opcode == 8'h3f;
  assign concat_21745 = {eq_21496, eq_21497, nor_21498};
  assign bc = {state_reg_b__3, state_reg_c__3};
  assign de = {state_reg_d, state_reg_e};
  assign state_sp__6 = state[43:28];
  assign eq_21750 = and_21612 == 8'h06;
  assign tmp1_bits_5_width_3 = tmp1_squeezed_portion_1_width_7__1[3:1];
  assign eq_21756 = opcode == 8'hc9;
  assign ret_addr = state_pc__54 + 16'h0003;
  assign immediate16 = {byte3, byte2};
  assign eq_21760 = opcode[7:3] == 5'h17;
  assign nor_21762 = ~(eq_21521 | eq_21513 | ~(eq_21704 ? low_diff__2[4] : (eq_21506 ? (or_21503 ? state_flags_aux_carry__1 : stack_read_lo[4]) : state_flags_aux_carry__1)));
  assign concat_21763 = {4'h0, cin__1};
  assign low_sum__1 = concat_21649 + {1'h0, byte2[3:0]};
  assign concat_21765 = {4'h0, state_flags_carry__1};
  assign concat_21766 = {1'h0, val[3:0]};
  assign low_diff__3_associative_element = 5'h0f;
  assign add_21768 = concat_21649 + {1'h0, not_b__5[3:0]};
  assign nor_21771 = ~(eq_21521 | eq_21513 | ~(eq_21704 ? ~diff9__2[8] : (eq_21506 ? (or_21503 ? state_flags_carry__1 : stack_read_lo[0]) : state_flags_carry__1)));
  assign val__2 = priority_sel_16b_3way(concat_21745, bc, de, hl, state_sp__6);
  assign eq_21775 = opcode[7:6] == RP_DE;
  assign sel_21776 = eq_21750 ? (eq_21557 ? byte2 : a) : (eq_21728 ? result__41 : (eq_21710 ? result__39 : (eq_21689 ? result__38 : (eq_21668 ? result__37 : (eq_21652 ? result__5 : sel_21653)))));
  assign add_hi = tmp1_squeezed_portion_1_width_7__1 > 4'h9 | state_flags_carry__1;
  assign sum9__8_bits_5_width_3 = tmp1_bits_5_width_3 + REG_E__1;
  assign eq_21783 = and_21612 == 8'hc4;
  assign sel_21785 = priority_sel_21720 ? immediate16 : ret_addr;
  assign low_diff__1 = add_21664 + concat_21763;
  assign low_sum = low_sum__1 + concat_21765;
  assign low_diff__3 = concat_21766 + low_diff__3_associative_element;
  assign low_sum__2 = concat_21766 + 5'h01;
  assign low_diff__6 = add_21768 + 5'h01;
  assign eq_21793 = and_21499 == 8'h09;
  assign concat_21795 = {eq_21743, eq_21565, eq_21554, eq_21541, eq_21534, ~(eq_21743 | eq_21565 | eq_21554 | eq_21541 | eq_21534)};
  assign eq_21803 = opcode == 8'h3a;
  assign result_squeezed_portion_5_width_3 = add_hi ? sum9__8_bits_5_width_3 : tmp1_bits_5_width_3;
  assign sel_21806 = add_lo ? sum9__7_bits_1_width_7[3:0] : a[4:1];
  assign eq_21809 = opcode == 8'hcd;
  assign sel_21810 = eq_21783 ? sel_21785 : (eq_21756 ? ret_addr__3 : (eq_21733 ? (priority_sel_21720 ? ret_addr__3 : ret_addr__4) : (eq_21717 ? rst_addr : (eq_21696 ? hl : (nor_21677 ? ret_addr__4 : concat_21678)))));
  assign concat_21811 = {eq_21760, eq_21629, eq_21622, eq_21565, eq_21554, eq_21541, eq_21534, ~(eq_21760 | eq_21629 | eq_21622 | eq_21565 | eq_21554 | eq_21541 | eq_21534)};
  assign eq_21822 = opcode == 8'h37;
  assign sum = {1'h0, state_reg_h__1, state_reg_l__2} + {1'h0, val__2};
  assign eq_21827 = opcode == 8'h27;
  assign result = {result_squeezed_portion_5_width_3, sel_21806, bit0};
  assign eq_21833 = and_21499 == 8'hc5;
  assign eq_21836 = and_21612 == 8'hc2;
  assign concat_21840 = {eq_21760, eq_21793, eq_21591 | eq_21614, eq_21584 | eq_21606, ~(eq_21760 | eq_21793 | eq_21614 | eq_21606 | eq_21591 | eq_21584)};
  assign and_21844 = eq_21622 & eq_21581;
  assign eq_21847 = opcode == 8'h22;
  assign state_rst75_pending__1 = state[1:1];
  assign state_inte = state[5:5];
  assign state_mask_75__1 = state[2:2];
  assign state_mask_65__1 = state[3:3];
  assign state_mask_55__1 = state[4:4];
  assign eq_21855 = and_21499 == 8'h01;
  assign eq_21856 = and_21499 == 8'h03;
  assign eq_21857 = and_21499 == 8'h0b;
  assign or_21858 = eq_21717 | eq_21833;
  assign eq_21859 = opcode == 8'hf9;
  assign eq_21860 = opcode == 8'hc3;
  assign eq_21870 = opcode == 8'he3;
  assign state_sp__6_bits_1_width_15 = state_sp__6[15:1];
  assign eq_21876 = opcode == 8'h20;
  assign rim_result = {sid, state_rst75_pending__1, rst65_level, rst55_level, state_inte, state_mask_75__1, state_mask_65__1, state_mask_55__1};
  assign add_21879 = val__2 + 16'hffff;
  assign add_21880 = val__2 + 16'h0001;
  assign nor_21881 = ~(eq_21855 | eq_21856 | eq_21857 | eq_21809 | eq_21783 | eq_21756 | eq_21733 | or_21858 | eq_21506 | eq_21859);
  assign or_21882 = eq_21506 | eq_21756;
  assign or_21883 = eq_21717 | eq_21833 | eq_21809;
  assign nor_21887 = ~(eq_21642 | eq_21634 | ~((eq_21527 | ~eq_21527 & nor_21762) & concat_21811[0] | low_diff__1[4] & concat_21811[1] | low_diff__2[4] & concat_21811[2] | low_sum[4] & concat_21811[3] | low_sum__1[4] & concat_21811[4] | low_diff__3[4] & concat_21811[5] | low_sum__2[4] & concat_21811[6] | low_diff__6[4] & concat_21811[7]));
  assign low_sum__5 = concat_21649 + {1'h0, src_val[3:0]};
  assign not_22024 = ~((eq_21822 | (~eq_21527 & nor_21771 & concat_21795[0] | ~diff9__1[8] & concat_21795[1] | ~diff9__2[8] & concat_21795[2] | sum9[8] & concat_21795[3] | sum9__1[8] & concat_21795[4] | cin__1 & concat_21795[5])) & concat_21840[0] | bit0 & concat_21840[1] | bit7 & concat_21840[2] | sum[16] & concat_21840[3] | ~diff9__6[8] & concat_21840[4]);
  assign eq_22025 = opcode == 8'h32;
  assign or_22026 = eq_21775 | eq_21750 | eq_21629;
  assign eq_22029 = opcode == 8'h02;
  assign eq_22030 = opcode == 8'h12;
  assign new_sp_bits_1_width_15 = state_sp__6_bits_1_width_15 + 15'h7fff;
  assign state_tup7_portion_0_width_1 = state_sp__6[0];
  assign eq_22041 = opcode == 8'heb;
  assign eq_22042 = opcode == 8'h2a;
  assign eq_22043 = opcode == 8'h1a;
  assign sel_22044 = eq_21876 ? rim_result : (eq_21847 ? a : (eq_21827 ? result : (eq_21803 ? mem_read_data : (eq_21775 ? (eq_21557 ? src_val : a) : sel_21776))));
  assign add_22046 = state_sp__6_bits_1_width_15 + 15'h0001;
  assign sel_22457 = or_21503 ? state_sp__6 : add_21879;
  assign sel_22456 = or_21503 ? state_sp__6 : add_21880;
  assign sel_22455 = or_21503 ? state_sp__6 : immediate16;
  assign low_diff__5 = add_21768 + concat_21763;
  assign low_sum__3 = low_sum__5 + concat_21765;
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
  assign p__20 = bit0 ^ sel_21806[0] ^ sel_21806[1] ^ sel_21806[2] ^ sel_21806[3] ^ result_squeezed_portion_5_width_3[0] ^ result_squeezed_portion_5_width_3[1] ^ result_squeezed_portion_5_width_3[2];
  assign new_sp = {new_sp_bits_1_width_15, state_tup7_portion_0_width_1};
  assign state_halted = state[6:6];
  assign eq_22092 = opcode == 8'h00;
  assign eq_22093 = opcode == 8'h76;
  assign eq_22094 = opcode == 8'h0a;
  assign eq_22095 = opcode == 8'h30;
  assign high__1 = add_21879[15:8];
  assign high__2 = add_21880[15:8];
  assign low__1 = add_21879[7:0];
  assign low__2 = add_21880[7:0];
  assign concat_22109 = {eq_21855, eq_21856, eq_21857, eq_21783, eq_21733, or_21883, or_21882, eq_21859, nor_21881};
  assign concat_22116 = {eq_21855, eq_21856, eq_21857, eq_21859, nor_21881 | or_21882 | or_21883 | eq_21733 | eq_21783};
  assign concat_22122 = {eq_21827, eq_21728, eq_21710, eq_21668, eq_21652, eq_21642, eq_21634, eq_21760 | eq_21689, eq_21629, eq_21622, eq_21565, eq_21554, eq_21534, eq_21527, eq_21521, eq_21513, eq_21704 | eq_21541, eq_21506, ~(eq_21827 | eq_21728 | eq_21710 | eq_21689 | eq_21668 | eq_21652 | eq_21642 | eq_21634 | eq_21760 | eq_21629 | eq_21622 | eq_21565 | eq_21554 | eq_21541 | eq_21534 | eq_21527 | eq_21521 | eq_21513 | eq_21704 | eq_21506)};
  assign concat_22142 = {eq_21827, eq_21728, eq_21710, eq_21689, eq_21668, ~(eq_21827 | eq_21728 | eq_21710 | eq_21689 | eq_21668)};
  assign eq_22169 = opcode == 8'hfb;
  assign sign_ext_22178 = {8{eq_21581}};
  assign sign_ext_22185 = {8{priority_sel_21720}};
  assign concat_22244 = {eq_21775, eq_21750, eq_21855, eq_21629, eq_21622, eq_21856, eq_21857, eq_21506, ~(eq_21775 | eq_21750 | eq_21855 | eq_21629 | eq_21622 | eq_21856 | eq_21857 | eq_21506)};
  assign concat_22261 = {eq_21775, eq_21750, eq_21855, eq_21629, eq_21622, eq_21856, eq_21857, eq_21506, eq_22041, ~(eq_21775 | eq_21750 | eq_21855 | eq_21629 | eq_21622 | eq_21856 | eq_21857 | eq_21506 | eq_22041)};
  assign concat_22278 = {eq_22042, eq_21775, eq_21750, eq_21855, eq_21629, eq_21622, eq_21856, eq_21857, eq_21793, eq_21506, eq_21870, eq_22041, ~(eq_22042 | eq_21775 | eq_21750 | eq_21855 | eq_21629 | eq_21622 | eq_21856 | eq_21857 | eq_21793 | eq_21506 | eq_21870 | eq_22041)};
  assign high = sum[15:8];
  assign low = sum[7:0];
  assign sel_22301 = eq_21750 ? concat_21678 : (eq_21855 ? ret_addr : (eq_21565 | eq_21554 | eq_21541 | eq_21534 | eq_21527 | eq_21521 | eq_21513 | eq_21704 ? concat_21678 : (eq_21860 ? immediate16 : (eq_21836 ? sel_21785 : (eq_21809 ? immediate16 : sel_21810)))));
  assign or_22302 = state_halted | eq_22092 | eq_22093 | eq_22029 | eq_22094 | eq_22030 | eq_22043 | eq_21876 | eq_21847;
  assign r75 = a[5];
  assign nor_22314 = ~(state_halted | eq_22092 | eq_22093);
  assign concat_22315 = {eq_21847, eq_22025 | eq_22029 | eq_22030, eq_21775, eq_21750, eq_21629, ~(eq_22029 | eq_22030 | eq_21847 | eq_22025 | eq_21775 | eq_21750 | eq_21629)};
  assign concat_22323 = {eq_21809, eq_21783, eq_21717, eq_21833, eq_21870};
  assign lo = priority_sel_8b_3way(concat_21745, state_reg_c__3, state_reg_e, state_reg_l__2, {state_flags_sign__1, 7'h00} | {1'h0, state_flags_zero__1, 6'h00} | {REG_B__1, state_flags_aux_carry__1, 4'h0} | {5'h00, state_flags_parity__1, 2'h0} | 8'h02 | {7'h00, state_flags_carry__1});
  assign hi = priority_sel_8b_3way(concat_21745, state_reg_b__3, state_reg_d, state_reg_h__1, a);
  assign and_22332 = ~state_halted & ~eq_22092 & ~eq_22093 & ~eq_22029 & ~eq_22094 & ~eq_22030 & ~eq_22043 & ~eq_21876 & ~eq_21847 & ~eq_21827 & ~eq_22042 & ~eq_22095 & ~eq_22025 & ~eq_21803 & ~eq_21775 & ~eq_21750 & ~eq_21855 & ~eq_21728 & ~eq_21710 & ~eq_21689 & ~eq_21668 & ~eq_21652 & ~eq_21642 & ~eq_21634 & ~eq_21760 & ~eq_21629 & ~eq_21622 & ~eq_21856 & ~eq_21857 & ~eq_21793 & ~eq_21614 & ~eq_21606 & ~eq_21591 & ~eq_21584 & ~eq_21577 & ~eq_21822 & ~eq_21743 & ~eq_21565 & ~eq_21554 & ~eq_21541 & ~eq_21534 & ~eq_21527 & ~eq_21521 & ~eq_21513 & ~eq_21704 & ~eq_21860 & ~eq_21836 & ~eq_21809 & ~eq_21783 & ~eq_21756 & ~eq_21733 & ~eq_21717 & ~eq_21833 & ~eq_21506 & ~eq_21696 & ~eq_21870 & ~eq_22041 & eq_21658;
  assign or_22333 = state_halted | eq_22092 | eq_22093 | eq_22029 | eq_22094 | eq_22030 | eq_22043 | eq_21876 | eq_21847 | eq_21827 | eq_22042 | eq_22095 | eq_22025 | eq_21803;
  assign or_22338 = state_halted | eq_22092 | eq_22093 | eq_22029 | eq_22094 | eq_22030 | eq_22043 | eq_21876 | eq_21847 | eq_21827;
  assign or_22353 = state_halted | eq_22092 | eq_22093 | eq_22029 | eq_22094 | eq_22030 | eq_22043 | eq_21876 | eq_21847 | eq_21827 | eq_22042 | ~(eq_22095 & a[4]);
  assign new_rst75_pending = ~(r75 | ~state_rst75_pending__1);
  assign state_sod_latch = state[0:0];
  assign sel_22360 = eq_22029 ? bc : (eq_22030 ? de : (eq_21847 | eq_22025 ? immediate16 : (or_22026 ? hl & {16{eq_21581}} : hl & {16{and_21844}})));
  assign sign_ext_22368 = {8{~(state_halted | eq_22092 | eq_22093 | eq_22029 | eq_22094 | eq_22030 | eq_22043 | eq_21876 | eq_21847 | eq_21827 | eq_22042 | eq_22095 | eq_22025 | eq_21803 | eq_21775 | eq_21750 | eq_21855 | eq_21728 | eq_21710 | eq_21689 | eq_21668 | eq_21652 | eq_21642 | eq_21634 | eq_21760 | eq_21629 | eq_21622 | eq_21856 | eq_21857 | eq_21793 | eq_21614 | eq_21606 | eq_21591 | eq_21584 | eq_21577 | eq_21822 | eq_21743 | eq_21565 | eq_21554 | eq_21541 | eq_21534 | eq_21527 | eq_21521 | eq_21513 | eq_21704 | eq_21860 | eq_21836)}};
  assign tuple_22382 = {or_22302 ? state_flags_sign__1 : state_flags_sign__1 & concat_22122[0] | (or_21503 ? state_flags_sign__1 : stack_read_lo[7]) & concat_22122[1] | diff9__2[7] & concat_22122[2] | result__20[7] & concat_22122[3] | result__19[7] & concat_22122[4] | result__18[7] & concat_22122[5] | diff9__1[7] & concat_22122[6] | sum9[7] & concat_22122[7] | sum9__1[7] & concat_22122[8] | diff9__3[7] & concat_22122[9] | sum9__2[7] & concat_22122[10] | diff9__6[7] & concat_22122[11] | result__7[7] & concat_22122[12] | result__6[7] & concat_22122[13] | result__5[7] & concat_22122[14] | diff9__5[7] & concat_22122[15] | sum9__3[7] & concat_22122[16] | sum9__5[7] & concat_22122[17] | result_squeezed_portion_5_width_3[2] & concat_22122[18], or_22302 ? state_flags_zero__1 : state_flags_zero__1 & concat_22122[0] | (or_21503 ? state_flags_zero__1 : stack_read_lo[6]) & concat_22122[1] | result__31 == 8'h00 & concat_22122[2] | result__20 == 8'h00 & concat_22122[3] | result__19 == 8'h00 & concat_22122[4] | result__18 == 8'h00 & concat_22122[5] | result__30 == 8'h00 & concat_22122[6] | result__32 == 8'h00 & concat_22122[7] | result__33 == 8'h00 & concat_22122[8] | result__34 == 8'h00 & concat_22122[9] | result__35 == 8'h00 & concat_22122[10] | result__38 == 8'h00 & concat_22122[11] | result__7 == 8'h00 & concat_22122[12] | result__6 == 8'h00 & concat_22122[13] | result__5 == 8'h00 & concat_22122[14] | result__37 == 8'h00 & concat_22122[15] | result__39 == 8'h00 & concat_22122[16] | result__41 == 8'h00 & concat_22122[17] | ~(result_squeezed_portion_5_width_3 != REG_B__1 | sel_21806 != 4'h0 | bit0) & concat_22122[18], or_22302 ? state_flags_aux_carry__1 : (eq_21652 | ~eq_21652 & nor_21887) & concat_22142[0] | low_diff__5[4] & concat_22142[1] | low_diff__6[4] & concat_22142[2] | low_sum__3[4] & concat_22142[3] | low_sum__5[4] & concat_22142[4] | add_lo & concat_22142[5], or_22302 ? state_flags_parity__1 : state_flags_parity__1 & concat_22122[0] | (or_21503 ? state_flags_parity__1 : stack_read_lo[2]) & concat_22122[1] | ~p__5 & concat_22122[2] | ~p__1 & concat_22122[3] | ~p__2 & concat_22122[4] | ~p__3 & concat_22122[5] | ~p__4 & concat_22122[6] | ~p__6 & concat_22122[7] | ~p__7 & concat_22122[8] | ~p__8 & concat_22122[9] | ~p__9 & concat_22122[10] | ~p__15 & concat_22122[11] | ~p__11 & concat_22122[12] | ~p__12 & concat_22122[13] | ~p__13 & concat_22122[14] | ~p__14 & concat_22122[15] | ~p__16 & concat_22122[16] | ~p__18 & concat_22122[17] | ~p__20 & concat_22122[18], or_22302 ? state_flags_carry__1 : ~eq_21652 & ~(eq_21642 | eq_21634 | not_22024) & concat_22142[0] | ~diff9__5[8] & concat_22142[1] | ~diff9__6[8] & concat_22142[2] | sum9__3[8] & concat_22142[3] | sum9__5[8] & concat_22142[4] | add_hi & concat_22142[5]};
  assign and_22393 = (eq_21809 ? new_sp : (eq_21783 ? new_sp & {16{priority_sel_21720}} : (or_21858 ? new_sp : state_sp__6 & {16{eq_21870}}))) & {16{~(state_halted | eq_22092 | eq_22093 | eq_22029 | eq_22094 | eq_22030 | eq_22043 | eq_21876 | eq_21847 | eq_21827 | eq_22042 | eq_22095 | eq_22025 | eq_21803 | eq_21775 | eq_21750 | eq_21855 | eq_21728 | eq_21710 | eq_21689 | eq_21668 | eq_21652 | eq_21642 | eq_21634 | eq_21760 | eq_21629 | eq_21622 | eq_21856 | eq_21857 | eq_21793 | eq_21614 | eq_21606 | eq_21591 | eq_21584 | eq_21577 | eq_21822 | eq_21743 | eq_21565 | eq_21554 | eq_21541 | eq_21534 | eq_21527 | eq_21521 | eq_21513 | eq_21704 | eq_21860 | eq_21836)}};
  assign one_hot_22464 = {concat_21611[6:0] == 7'h00, concat_21611[6] && concat_21611[5:0] == 6'h00, concat_21611[5] && concat_21611[4:0] == 5'h00, concat_21611[4] && concat_21611[3:0] == 4'h0, concat_21611[3] && concat_21611[2:0] == 3'h0, concat_21611[2] && concat_21611[1:0] == 2'h0, concat_21611[1] && !concat_21611[0], concat_21611[0]};
  assign one_hot_22470 = {concat_21569[6:0] == 7'h00, concat_21569[6] && concat_21569[5:0] == 6'h00, concat_21569[5] && concat_21569[4:0] == 5'h00, concat_21569[4] && concat_21569[3:0] == 4'h0, concat_21569[3] && concat_21569[2:0] == 3'h0, concat_21569[2] && concat_21569[1:0] == 2'h0, concat_21569[1] && !concat_21569[0], concat_21569[0]};
  assign tuple_22400 = {or_22333 ? state_reg_b__3 : state_reg_b__3 & {8{concat_22244[0]}} | (nor_21498 ? stack_read_hi : state_reg_b__3) & {8{concat_22244[1]}} | (nor_21498 ? high__1 : state_reg_b__3) & {8{concat_22244[2]}} | (nor_21498 ? high__2 : state_reg_b__3) & {8{concat_22244[3]}} | (eq_21563 ? result__34 : state_reg_b__3) & {8{concat_22244[4]}} | (eq_21563 ? result__35 : state_reg_b__3) & {8{concat_22244[5]}} | (nor_21498 ? byte3 : state_reg_b__3) & {8{concat_22244[6]}} | (eq_21563 ? byte2 : state_reg_b__3) & {8{concat_22244[7]}} | (eq_21563 ? src_val : state_reg_b__3) & {8{concat_22244[8]}}, or_22333 ? state_reg_c__3 : state_reg_c__3 & {8{concat_22244[0]}} | (nor_21498 ? stack_read_lo : state_reg_c__3) & {8{concat_22244[1]}} | (nor_21498 ? low__1 : state_reg_c__3) & {8{concat_22244[2]}} | (nor_21498 ? low__2 : state_reg_c__3) & {8{concat_22244[3]}} | (eq_21562 ? result__34 : state_reg_c__3) & {8{concat_22244[4]}} | (eq_21562 ? result__35 : state_reg_c__3) & {8{concat_22244[5]}} | (nor_21498 ? byte2 : state_reg_c__3) & {8{concat_22244[6]}} | (eq_21562 ? byte2 : state_reg_c__3) & {8{concat_22244[7]}} | (eq_21562 ? src_val : state_reg_c__3) & {8{concat_22244[8]}}, or_22333 ? state_reg_d : state_reg_d & {8{concat_22261[0]}} | state_reg_h__1 & {8{concat_22261[1]}} | (eq_21497 ? stack_read_hi : state_reg_d) & {8{concat_22261[2]}} | (eq_21497 ? high__1 : state_reg_d) & {8{concat_22261[3]}} | (eq_21497 ? high__2 : state_reg_d) & {8{concat_22261[4]}} | (eq_21561 ? result__34 : state_reg_d) & {8{concat_22261[5]}} | (eq_21561 ? result__35 : state_reg_d) & {8{concat_22261[6]}} | (eq_21497 ? byte3 : state_reg_d) & {8{concat_22261[7]}} | (eq_21561 ? byte2 : state_reg_d) & {8{concat_22261[8]}} | (eq_21561 ? src_val : state_reg_d) & {8{concat_22261[9]}}, or_22333 ? state_reg_e : state_reg_e & {8{concat_22261[0]}} | state_reg_l__2 & {8{concat_22261[1]}} | (eq_21497 ? stack_read_lo : state_reg_e) & {8{concat_22261[2]}} | (eq_21497 ? low__1 : state_reg_e) & {8{concat_22261[3]}} | (eq_21497 ? low__2 : state_reg_e) & {8{concat_22261[4]}} | (eq_21560 ? result__34 : state_reg_e) & {8{concat_22261[5]}} | (eq_21560 ? result__35 : state_reg_e) & {8{concat_22261[6]}} | (eq_21497 ? byte2 : state_reg_e) & {8{concat_22261[7]}} | (eq_21560 ? byte2 : state_reg_e) & {8{concat_22261[8]}} | (eq_21560 ? src_val : state_reg_e) & {8{concat_22261[9]}}, or_22338 ? state_reg_h__1 : state_reg_h__1 & {8{concat_22278[0]}} | state_reg_d & {8{concat_22278[1]}} | stack_read_hi & {8{concat_22278[2]}} | (eq_21496 ? stack_read_hi : state_reg_h__1) & {8{concat_22278[3]}} | high & {8{concat_22278[4]}} | (eq_21496 ? high__1 : state_reg_h__1) & {8{concat_22278[5]}} | (eq_21496 ? high__2 : state_reg_h__1) & {8{concat_22278[6]}} | (eq_21559 ? result__34 : state_reg_h__1) & {8{concat_22278[7]}} | (eq_21559 ? result__35 : state_reg_h__1) & {8{concat_22278[8]}} | (eq_21496 ? byte3 : state_reg_h__1) & {8{concat_22278[9]}} | (eq_21559 ? byte2 : state_reg_h__1) & {8{concat_22278[10]}} | (eq_21559 ? src_val : state_reg_h__1) & {8{concat_22278[11]}} | stack_read_lo & {8{concat_22278[12]}}, or_22338 ? state_reg_l__2 : state_reg_l__2 & {8{concat_22278[0]}} | state_reg_e & {8{concat_22278[1]}} | stack_read_lo & {8{concat_22278[2]}} | (eq_21496 ? stack_read_lo : state_reg_l__2) & {8{concat_22278[3]}} | low & {8{concat_22278[4]}} | (eq_21496 ? low__1 : state_reg_l__2) & {8{concat_22278[5]}} | (eq_21496 ? low__2 : state_reg_l__2) & {8{concat_22278[6]}} | (eq_21558 ? result__34 : state_reg_l__2) & {8{concat_22278[7]}} | (eq_21558 ? result__35 : state_reg_l__2) & {8{concat_22278[8]}} | (eq_21496 ? byte2 : state_reg_l__2) & {8{concat_22278[9]}} | (eq_21558 ? byte2 : state_reg_l__2) & {8{concat_22278[10]}} | (eq_21558 ? src_val : state_reg_l__2) & {8{concat_22278[11]}} | mem_read_data & {8{concat_22278[12]}}, state_halted | eq_22092 | eq_22093 | eq_22029 ? a : (eq_22094 ? mem_read_data : (eq_22030 ? a : (eq_22043 ? mem_read_data : sel_22044))), state_halted | eq_22092 | eq_22093 | eq_22029 | eq_22094 | eq_22030 | eq_22043 | eq_21876 | eq_21847 | eq_21827 | eq_22042 | eq_22095 | eq_22025 | eq_21803 | eq_21775 | eq_21750 ? state_sp__6 : {state_sp__6_bits_1_width_15 & {15{concat_22109[0]}} | {state_reg_h__1, state_reg_l__2[7:1]} & {15{concat_22109[1]}} | add_22046 & {15{concat_22109[2]}} | new_sp_bits_1_width_15 & {15{concat_22109[3]}} | (priority_sel_21720 ? add_22046 : state_sp__6_bits_1_width_15) & {15{concat_22109[4]}} | (priority_sel_21720 ? new_sp_bits_1_width_15 : state_sp__6_bits_1_width_15) & {15{concat_22109[5]}} | sel_22457[15:1] & {15{concat_22109[6]}} | sel_22456[15:1] & {15{concat_22109[7]}} | sel_22455[15:1] & {15{concat_22109[8]}}, state_tup7_portion_0_width_1 & concat_22116[0] | state_reg_l__2[0] & concat_22116[1] | sel_22457[0] & concat_22116[2] | sel_22456[0] & concat_22116[3] | sel_22455[0] & concat_22116[4]}, state_halted ? state_pc__54 : (eq_21847 | eq_22042 | eq_22025 | eq_21803 ? ret_addr : sel_22301), tuple_22382, eq_22093 | state_halted, state_halted | eq_22092 | eq_22093 | eq_22029 | eq_22094 | eq_22030 | eq_22043 | eq_21876 | eq_21847 | eq_21827 | eq_22042 | eq_22095 | eq_22025 | eq_21803 | eq_21775 | eq_21750 | eq_21855 | eq_21728 | eq_21710 | eq_21689 | eq_21668 | eq_21652 | eq_21642 | eq_21634 | eq_21760 | eq_21629 | eq_21622 | eq_21856 | eq_21857 | eq_21793 | eq_21614 | eq_21606 | eq_21591 | eq_21584 | eq_21577 | eq_21822 | eq_21743 | eq_21565 | eq_21554 | eq_21541 | eq_21534 | eq_21527 | eq_21521 | eq_21513 | eq_21704 | eq_21860 | eq_21836 | eq_21809 | eq_21783 | eq_21756 | eq_21733 | eq_21717 | eq_21833 | eq_21506 | eq_21696 | eq_21870 | eq_22041 | eq_21859 | ~ne_21501 | eq_21658 ? state_inte : eq_22169 | ~(eq_22169 | opcode == 8'hf3 | ~state_inte), or_22353 ? state_mask_55__1 : bit0, or_22353 ? state_mask_65__1 : a[1], or_22353 ? state_mask_75__1 : a[2], state_halted | eq_22092 | eq_22093 | eq_22029 | eq_22094 | eq_22030 | eq_22043 | eq_21876 | eq_21847 | eq_21827 | eq_22042 | ~eq_22095 ? state_rst75_pending__1 : new_rst75_pending, state_halted | eq_22092 | eq_22093 | eq_22029 | eq_22094 | eq_22030 | eq_22043 | eq_21876 | eq_21847 | eq_21827 | eq_22042 | ~(eq_22095 & a[6]) ? state_sod_latch : bit7};
  assign tuple_22402 = {tuple_22400, {sel_22360 & {16{nor_22314}}, (result__34 & {8{and_21844}} & {8{concat_22315[0]}} | result__35 & sign_ext_22178 & {8{concat_22315[1]}} | byte2 & sign_ext_22178 & {8{concat_22315[2]}} | one_hot_sel_22469 & sign_ext_22178 & {8{concat_22315[3]}} | a & {8{concat_22315[4]}} | state_reg_l__2 & {8{concat_22315[5]}}) & {8{nor_22314}}, ~state_halted & ~eq_22093 & (eq_22029 | eq_22030 | eq_21847 | eq_22025 | eq_21581 & (or_22026 | eq_21622)), and_22393, (state_reg_l__2 & {8{concat_22323[0]}} | lo & {8{concat_22323[1]}} | ret_addr__4[7:0] & {8{concat_22323[2]}} | ret_addr[7:0] & sign_ext_22185 & {8{concat_22323[3]}} | ret_addr[7:0] & {8{concat_22323[4]}}) & sign_ext_22368, (state_reg_h__1 & {8{concat_22323[0]}} | hi & {8{concat_22323[1]}} | ret_addr__4[15:8] & {8{concat_22323[2]}} | ret_addr[15:8] & sign_ext_22185 & {8{concat_22323[3]}} | ret_addr[15:8] & {8{concat_22323[4]}}) & sign_ext_22368, ~state_halted & ~eq_22092 & ~eq_22093 & ~eq_22029 & ~eq_22094 & ~eq_22030 & ~eq_22043 & ~eq_21876 & ~eq_21847 & ~eq_21827 & ~eq_22042 & ~eq_22095 & ~eq_22025 & ~eq_21803 & ~eq_21775 & ~eq_21750 & ~eq_21855 & ~eq_21728 & ~eq_21710 & ~eq_21689 & ~eq_21668 & ~eq_21652 & ~eq_21642 & ~eq_21634 & ~eq_21760 & ~eq_21629 & ~eq_21622 & ~eq_21856 & ~eq_21857 & ~eq_21793 & ~eq_21614 & ~eq_21606 & ~eq_21591 & ~eq_21584 & ~eq_21577 & ~eq_21822 & ~eq_21743 & ~eq_21565 & ~eq_21554 & ~eq_21541 & ~eq_21534 & ~eq_21527 & ~eq_21521 & ~eq_21513 & ~eq_21704 & ~eq_21860 & ~eq_21836 & (eq_21809 | (eq_21783 ? priority_sel_21720 : eq_21717 | eq_21833 | eq_21870)), byte2 & {8{~(state_halted | eq_22092 | eq_22093 | eq_22029 | eq_22094 | eq_22030 | eq_22043 | eq_21876 | eq_21847 | eq_21827 | eq_22042 | eq_22095 | eq_22025 | eq_21803 | eq_21775 | eq_21750 | eq_21855 | eq_21728 | eq_21710 | eq_21689 | eq_21668 | eq_21652 | eq_21642 | eq_21634 | eq_21760 | eq_21629 | eq_21622 | eq_21856 | eq_21857 | eq_21793 | eq_21614 | eq_21606 | eq_21591 | eq_21584 | eq_21577 | eq_21822 | eq_21743 | eq_21565 | eq_21554 | eq_21541 | eq_21534 | eq_21527 | eq_21521 | eq_21513 | eq_21704 | eq_21860 | eq_21836 | eq_21809 | eq_21783 | eq_21756 | eq_21733 | eq_21717 | eq_21833 | eq_21506 | eq_21696 | nor_21677)}}, a & {8{and_22332}}, ~state_halted & ~eq_22092 & ~eq_22093 & ~eq_22029 & ~eq_22094 & ~eq_22030 & ~eq_22043 & ~eq_21876 & ~eq_21847 & ~eq_21827 & ~eq_22042 & ~eq_22095 & ~eq_22025 & ~eq_21803 & ~eq_21775 & ~eq_21750 & ~eq_21855 & ~eq_21728 & ~eq_21710 & ~eq_21689 & ~eq_21668 & ~eq_21652 & ~eq_21642 & ~eq_21634 & ~eq_21760 & ~eq_21629 & ~eq_21622 & ~eq_21856 & ~eq_21857 & ~eq_21793 & ~eq_21614 & ~eq_21606 & ~eq_21591 & ~eq_21584 & ~eq_21577 & ~eq_21822 & ~eq_21743 & ~eq_21565 & ~eq_21554 & ~eq_21541 & ~eq_21534 & ~eq_21527 & ~eq_21521 & ~eq_21513 & ~eq_21704 & ~eq_21860 & ~eq_21836 & ~eq_21809 & ~eq_21783 & ~eq_21756 & ~eq_21733 & ~eq_21717 & ~eq_21833 & ~eq_21506 & ~eq_21696 & ~eq_21870 & ~ne_21501, and_22332}};
  assign eq_22466 = concat_21611 == one_hot_22464[6:0];
  assign eq_22472 = concat_21569 == one_hot_22470[6:0];
  assign out = tuple_22402;
endmodule
