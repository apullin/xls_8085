module __cache_logic__cache_lookup(
  input wire [14:0] addr,
  input wire [2:0] bank,
  input wire stored_valid,
  input wire [11:0] stored_tag,
  output wire [41:0] out
);
  wire [4:0] tag__2;
  wire [3:0] tag__1;
  wire hit;
  wire [11:0] tag;
  wire [4:0] index;
  wire [5:0] offset;
  wire [17:0] line_addr;
  assign tag__2 = 5'h00;
  assign tag__1 = addr[14:11];
  assign hit = stored_valid & bank == stored_tag[11:9] & stored_tag[8:4] == tag__2 & tag__1 == stored_tag[3:0];
  assign tag = {bank, tag__2, tag__1};
  assign index = addr[10:6];
  assign offset = addr[5:0];
  assign line_addr = {bank, addr[14:6], 6'h00};
  assign out = {hit, tag, index, offset, line_addr};
endmodule
