module __timer16__timer_tick(
  input wire [143:0] state,
  input wire [14:0] bus_in,
  output wire [152:0] out
);
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
  function automatic [7:0] priority_sel_8b_15way (input reg [14:0] sel, input reg [7:0] case0, input reg [7:0] case1, input reg [7:0] case2, input reg [7:0] case3, input reg [7:0] case4, input reg [7:0] case5, input reg [7:0] case6, input reg [7:0] case7, input reg [7:0] case8, input reg [7:0] case9, input reg [7:0] case10, input reg [7:0] case11, input reg [7:0] case12, input reg [7:0] case13, input reg [7:0] case14, input reg [7:0] default_value);
    begin
      casez (sel)
        15'b??????????????1: begin
          priority_sel_8b_15way = case0;
        end
        15'b?????????????10: begin
          priority_sel_8b_15way = case1;
        end
        15'b????????????100: begin
          priority_sel_8b_15way = case2;
        end
        15'b???????????1000: begin
          priority_sel_8b_15way = case3;
        end
        15'b??????????10000: begin
          priority_sel_8b_15way = case4;
        end
        15'b?????????100000: begin
          priority_sel_8b_15way = case5;
        end
        15'b????????1000000: begin
          priority_sel_8b_15way = case6;
        end
        15'b???????10000000: begin
          priority_sel_8b_15way = case7;
        end
        15'b??????100000000: begin
          priority_sel_8b_15way = case8;
        end
        15'b?????1000000000: begin
          priority_sel_8b_15way = case9;
        end
        15'b????10000000000: begin
          priority_sel_8b_15way = case10;
        end
        15'b???100000000000: begin
          priority_sel_8b_15way = case11;
        end
        15'b??1000000000000: begin
          priority_sel_8b_15way = case12;
        end
        15'b?10000000000000: begin
          priority_sel_8b_15way = case13;
        end
        15'b100000000000000: begin
          priority_sel_8b_15way = case14;
        end
        15'b000_0000_0000_0000: begin
          priority_sel_8b_15way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_8b_15way = 8'dx;
        end
      endcase
    end
  endfunction
  wire [3:0] bus_in_addr;
  wire [3:0] REG_CTRL;
  wire [3:0] REG_CNT_HI;
  wire [15:0] state_counter__1;
  wire [3:0] REG_CNT_LO;
  wire [3:0] REG_RELOAD_HI;
  wire [3:0] REG_RELOAD_LO;
  wire [15:0] state_reload__1;
  wire eq_2512;
  wire [7:0] state_ctrl__1;
  wire [7:0] bus_in_data_in;
  wire eq_2515;
  wire eq_2517;
  wire eq_2519;
  wire eq_2520;
  wire bus_in_wr;
  wire [7:0] state_after_write_ctrl__2;
  wire auto_reload;
  wire [3:0] REG_CMP0_HI;
  wire [3:0] REG_CMP0_LO;
  wire [15:0] state_cmp0__1;
  wire [7:0] state_status__1;
  wire [3:0] REG_CMP1_HI;
  wire [3:0] REG_CMP1_LO;
  wire [15:0] state_cmp1__1;
  wire [3:0] REG_CMP2_HI;
  wire [3:0] REG_CMP2_LO;
  wire [15:0] state_cmp2__1;
  wire [15:0] state_cmp3__1;
  wire [3:0] REG_CMP3_LO;
  wire [15:0] state_after_write_counter__3;
  wire [15:0] state_after_write_reload__1;
  wire eq_2555;
  wire eq_2556;
  wire [3:0] REG_STATUS;
  wire eq_2562;
  wire eq_2563;
  wire eq_2567;
  wire eq_2568;
  wire eq_2574;
  wire [3:0] REG_PRESCALE;
  wire eq_2577;
  wire [15:0] add_2578;
  wire [15:0] reload_val;
  wire eq_2580;
  wire [15:0] add_2581;
  wire eq_2585;
  wire eq_2596;
  wire [7:0] state_prescale__1;
  wire overflow;
  wire [15:0] new_counter;
  wire [15:0] state_after_write_cmp0;
  wire [7:0] state_after_write_status;
  wire [7:0] concat_2610;
  wire [7:0] FLAG_CMP0;
  wire [15:0] state_after_write_cmp1;
  wire [15:0] state_after_write_cmp2;
  wire [15:0] state_after_write_cmp3;
  wire [7:0] state_after_write_prescale_cnt;
  wire [7:0] state_after_write_prescale;
  wire [7:0] status_with_ovf;
  wire state_after_write_ctrl__2_bits_0_width_1;
  wire prescale_match;
  wire [7:0] status_with_cmp0;
  wire [3:0] REG_IRQ_EN;
  wire nand_2637;
  wire [7:0] new_status;
  wire eq_2639;
  wire [7:0] state_irq_en__1;
  wire bus_in_tick;
  wire [7:0] add_2646;
  wire [7:0] state_cnt_hi_latch__1;
  wire [7:0] state_after_count_status;
  wire [7:0] state_after_count_irq_en;
  wire [7:0] new_prescale_cnt;
  wire [6:0] state_after_write_ctrl__2_portion_1_width_7__1;
  wire bus_in_rd;
  wire [7:0] concat_2666;
  wire [7:0] data_out;
  wire irq;
  wire [143:0] state_after_count;
  assign bus_in_addr = bus_in[14:11];
  assign REG_CTRL = 4'h5;
  assign REG_CNT_HI = 4'h1;
  assign state_counter__1 = state[143:128];
  assign REG_CNT_LO = 4'h0;
  assign REG_RELOAD_HI = 4'h3;
  assign REG_RELOAD_LO = 4'h2;
  assign state_reload__1 = state[127:112];
  assign eq_2512 = bus_in_addr == REG_CTRL;
  assign state_ctrl__1 = state[95:88];
  assign bus_in_data_in = bus_in[10:3];
  assign eq_2515 = bus_in_addr == REG_CNT_HI;
  assign eq_2517 = bus_in_addr == REG_CNT_LO;
  assign eq_2519 = bus_in_addr == REG_RELOAD_HI;
  assign eq_2520 = bus_in_addr == REG_RELOAD_LO;
  assign bus_in_wr = bus_in[1:1];
  assign state_after_write_ctrl__2 = bus_in_wr ? (eq_2512 ? bus_in_data_in : state_ctrl__1) : state_ctrl__1;
  assign auto_reload = state_after_write_ctrl__2[1];
  assign REG_CMP0_HI = 4'h9;
  assign REG_CMP0_LO = 4'h8;
  assign state_cmp0__1 = state[71:56];
  assign state_status__1 = state[79:72];
  assign REG_CMP1_HI = 4'hb;
  assign REG_CMP1_LO = 4'ha;
  assign state_cmp1__1 = state[55:40];
  assign REG_CMP2_HI = 4'hd;
  assign REG_CMP2_LO = 4'hc;
  assign state_cmp2__1 = state[39:24];
  assign state_cmp3__1 = state[23:8];
  assign REG_CMP3_LO = 4'he;
  assign state_after_write_counter__3 = bus_in_wr ? {eq_2515 ? bus_in_data_in : state_counter__1[15:8], eq_2517 ? bus_in_data_in : state_counter__1[7:0]} : state_counter__1;
  assign state_after_write_reload__1 = bus_in_wr ? priority_sel_16b_3way({eq_2519, eq_2520, bus_in_addr[3:1] == 3'h0}, state_reload__1, {state_reload__1[15:8], bus_in_data_in}, {bus_in_data_in, state_reload__1[7:0]}, state_reload__1) : state_reload__1;
  assign eq_2555 = bus_in_addr == REG_CMP0_HI;
  assign eq_2556 = bus_in_addr == REG_CMP0_LO;
  assign REG_STATUS = 4'h7;
  assign eq_2562 = bus_in_addr == REG_CMP1_HI;
  assign eq_2563 = bus_in_addr == REG_CMP1_LO;
  assign eq_2567 = bus_in_addr == REG_CMP2_HI;
  assign eq_2568 = bus_in_addr == REG_CMP2_LO;
  assign eq_2574 = bus_in_addr == REG_CMP3_LO;
  assign REG_PRESCALE = 4'h4;
  assign eq_2577 = state_after_write_counter__3 == 16'hffff;
  assign add_2578 = state_after_write_counter__3 + 16'h0001;
  assign reload_val = state_after_write_reload__1 & {16{auto_reload}};
  assign eq_2580 = state_after_write_counter__3 == 16'h0000;
  assign add_2581 = state_after_write_counter__3 + 16'hffff;
  assign eq_2585 = bus_in_addr == REG_STATUS;
  assign eq_2596 = bus_in_addr == REG_PRESCALE;
  assign state_prescale__1 = state[111:104];
  assign overflow = state_after_write_ctrl__2[2] ? eq_2580 : eq_2577;
  assign new_counter = state_after_write_ctrl__2[2] ? (eq_2580 ? reload_val : add_2581) : (eq_2577 ? reload_val : add_2578);
  assign state_after_write_cmp0 = bus_in_wr ? priority_sel_16b_3way({eq_2555, eq_2556, ~bus_in_addr[3]}, state_cmp0__1, {state_cmp0__1[15:8], bus_in_data_in}, {bus_in_data_in, state_cmp0__1[7:0]}, state_cmp0__1) : state_cmp0__1;
  assign state_after_write_status = bus_in_wr ? (eq_2585 ? ~(~state_status__1 | bus_in_data_in) : state_status__1) : state_status__1;
  assign concat_2610 = {3'h0, overflow, REG_CNT_LO};
  assign FLAG_CMP0 = 8'h01;
  assign state_after_write_cmp1 = bus_in_wr ? priority_sel_16b_3way({eq_2562, eq_2563, bus_in_addr < REG_CMP1_LO}, state_cmp1__1, {state_cmp1__1[15:8], bus_in_data_in}, {bus_in_data_in, state_cmp1__1[7:0]}, state_cmp1__1) : state_cmp1__1;
  assign state_after_write_cmp2 = bus_in_wr ? priority_sel_16b_3way({eq_2567, eq_2568, bus_in_addr < REG_CMP2_LO}, state_cmp2__1, {state_cmp2__1[15:8], bus_in_data_in}, {bus_in_data_in, state_cmp2__1[7:0]}, state_cmp2__1) : state_cmp2__1;
  assign state_after_write_cmp3 = bus_in_wr ? {bus_in_addr != 4'hf ? state_cmp3__1[15:8] : bus_in_data_in, eq_2574 ? bus_in_data_in : state_cmp3__1[7:0]} : state_cmp3__1;
  assign state_after_write_prescale_cnt = state[103:96];
  assign state_after_write_prescale = bus_in_wr ? (eq_2596 ? bus_in_data_in : state_prescale__1) : state_prescale__1;
  assign status_with_ovf = state_after_write_status | concat_2610;
  assign state_after_write_ctrl__2_bits_0_width_1 = state_after_write_ctrl__2[0];
  assign prescale_match = state_after_write_prescale_cnt >= state_after_write_prescale;
  assign status_with_cmp0 = new_counter == state_after_write_cmp0 ? state_after_write_status | concat_2610 | FLAG_CMP0 : status_with_ovf;
  assign REG_IRQ_EN = 4'h6;
  assign nand_2637 = ~(state_after_write_ctrl__2_bits_0_width_1 & prescale_match);
  assign new_status = status_with_cmp0 | {6'h00, new_counter == state_after_write_cmp1, 1'h0} | {5'h00, new_counter == state_after_write_cmp2, 2'h0} | {REG_CNT_LO, new_counter == state_after_write_cmp3, 3'h0};
  assign eq_2639 = bus_in_addr == REG_IRQ_EN;
  assign state_irq_en__1 = state[87:80];
  assign bus_in_tick = bus_in[0:0];
  assign add_2646 = state_after_write_prescale_cnt + FLAG_CMP0;
  assign state_cnt_hi_latch__1 = state[7:0];
  assign state_after_count_status = bus_in_tick ? (nand_2637 ? state_after_write_status : new_status) : state_after_write_status;
  assign state_after_count_irq_en = bus_in_wr ? (eq_2639 ? bus_in_data_in : state_irq_en__1) : state_irq_en__1;
  assign new_prescale_cnt = add_2646 & {8{~prescale_match}};
  assign state_after_write_ctrl__2_portion_1_width_7__1 = state_after_write_ctrl__2[7:1];
  assign bus_in_rd = bus_in[2:2];
  assign concat_2666 = {state_after_write_ctrl__2_portion_1_width_7__1, bus_in_tick ? (~state_after_write_ctrl__2_bits_0_width_1 | ~(prescale_match & overflow & ~auto_reload)) & state_after_write_ctrl__2_bits_0_width_1 : state_after_write_ctrl__2_bits_0_width_1};
  assign data_out = bus_in_rd ? priority_sel_8b_15way({eq_2574, eq_2567, eq_2568, eq_2562, eq_2563, eq_2555, eq_2556, eq_2585, eq_2639, eq_2512, eq_2596, eq_2519, eq_2520, eq_2515, eq_2517}, state_counter__1[7:0], state_cnt_hi_latch__1, state_reload__1[7:0], state_reload__1[15:8], state_prescale__1, state_ctrl__1, state_irq_en__1, state_status__1, state_cmp0__1[7:0], state_cmp0__1[15:8], state_cmp1__1[7:0], state_cmp1__1[15:8], state_cmp2__1[7:0], state_cmp2__1[15:8], state_cmp3__1[7:0], state_cmp3__1[15:8]) : 8'hff;
  assign irq = (state_after_count_status & state_after_count_irq_en) != 8'h00;
  assign state_after_count = {bus_in_tick ? (nand_2637 ? state_after_write_counter__3 : new_counter) : state_after_write_counter__3, state_after_write_reload__1, state_after_write_prescale, ~(bus_in_tick & state_after_write_ctrl__2_bits_0_width_1) ? state_after_write_prescale_cnt : new_prescale_cnt, concat_2666, state_after_count_irq_en, state_after_count_status, state_after_write_cmp0, state_after_write_cmp1, state_after_write_cmp2, state_after_write_cmp3, bus_in_rd ? (eq_2517 ? state_counter__1[15:8] : state_cnt_hi_latch__1) : state_cnt_hi_latch__1};
  assign out = {state_after_count, {data_out, irq}};
endmodule
