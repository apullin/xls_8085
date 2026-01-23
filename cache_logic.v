module __cache_logic__cache_lookup(
  input wire [14:0] addr,
  input wire [7:0] bank,
  input wire stored_valid,
  input wire [11:0] stored_tag,
  output wire [46:0] out
);
  wire [3:0] tag__1;
  wire hit;
  wire [11:0] tag;
  wire [4:0] index;
  wire [5:0] offset;
  wire [22:0] line_addr;
  assign tag__1 = addr[14:11];
  assign hit = stored_valid & bank == stored_tag[11:4] & tag__1 == stored_tag[3:0];
  assign tag = {bank, tag__1};
  assign index = addr[10:6];
  assign offset = addr[5:0];
  assign line_addr = {bank, addr[14:6], 6'h00};
  assign out = {hit, tag, index, offset, line_addr};
endmodule
