// Behavioral SB_SPRAM256KA model for testbench
// 16K x 16-bit = 256Kbit SPRAM
//
// This model uses combinational read (asynchronous) to match vmath_wrapper
// FSM timing expectations. Real SB_SPRAM256KA has registered output.

module SB_SPRAM256KA (
    input [13:0] ADDRESS,
    input [15:0] DATAIN,
    input [3:0]  MASKWREN,
    input        WREN,
    input        CHIPSELECT,
    input        CLOCK,
    input        STANDBY,
    input        SLEEP,
    input        POWEROFF,
    output [15:0] DATAOUT
);

    // 16K x 16-bit memory
    reg [15:0] mem [0:16383];

    // Initialize to zero for simulation
    integer i;
    initial begin
        for (i = 0; i < 16384; i = i + 1)
            mem[i] = 16'h0000;
    end

    // Synchronous write
    always @(posedge CLOCK) begin
        if (CHIPSELECT && !SLEEP && !STANDBY && POWEROFF) begin
            if (WREN) begin
                // Nibble-wise write with mask
                if (MASKWREN[0]) mem[ADDRESS][3:0]   <= DATAIN[3:0];
                if (MASKWREN[1]) mem[ADDRESS][7:4]   <= DATAIN[7:4];
                if (MASKWREN[2]) mem[ADDRESS][11:8]  <= DATAIN[11:8];
                if (MASKWREN[3]) mem[ADDRESS][15:12] <= DATAIN[15:12];
            end
        end
    end

    // Combinational (asynchronous) read
    assign DATAOUT = mem[ADDRESS];

endmodule
