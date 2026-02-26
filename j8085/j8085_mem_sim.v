// j8085_mem_sim.v - Behavioral 64KB memory for j8085 testbench
// Models iCE40 SPRAM timing: 16-bit wide, 1-cycle registered read
//
// Interface matches memory_controller CPU-side protocol:
//   - Read:  assert rd + addr on cycle N, data valid on cycle N+1 (ready=1)
//   - Write: assert wr + addr + data on cycle N, written on next posedge
//   - Stack write: 16-bit write via separate bus (single cycle)

`timescale 1ns / 1ps

module j8085_mem_sim (
    input  wire        clk,
    input  wire        reset_n,

    // CPU bus (same signals as memory_controller)
    input  wire [15:0] cpu_addr,
    input  wire [7:0]  cpu_data_out,
    input  wire        cpu_rd,
    input  wire        cpu_wr,
    output reg  [7:0]  cpu_data_in,
    output reg         cpu_ready,

    // Stack write bus
    input  wire [15:0] stack_wr_addr,
    input  wire [7:0]  stack_wr_data_lo,
    input  wire [7:0]  stack_wr_data_hi,
    input  wire        stack_wr
);

    // 32K x 16-bit storage (64KB total, word-addressed)
    reg [15:0] ram [0:32767];

    // Initialize to zero
    integer i;
    initial begin
        for (i = 0; i < 32768; i = i + 1)
            ram[i] = 16'h0000;
    end

    // Word address and byte select
    wire [14:0] word_addr = cpu_addr[15:1];
    wire        byte_sel  = cpu_addr[0];

    // 1-cycle read latency (registered output, models SPRAM)
    always @(posedge clk) begin
        if (!reset_n) begin
            cpu_data_in <= 8'h00;
            cpu_ready   <= 1'b0;
        end else begin
            cpu_ready <= cpu_rd;
            if (cpu_rd) begin
                cpu_data_in <= byte_sel ? ram[word_addr][15:8]
                                       : ram[word_addr][7:0];
            end
        end
    end

    // Synchronous write (byte-granular)
    always @(posedge clk) begin
        if (cpu_wr) begin
            if (byte_sel)
                ram[word_addr][15:8] <= cpu_data_out;
            else
                ram[word_addr][7:0]  <= cpu_data_out;
        end
    end

    // Stack write bus (16-bit, word-aligned)
    always @(posedge clk) begin
        if (stack_wr) begin
            ram[stack_wr_addr[15:1]] <= {stack_wr_data_hi, stack_wr_data_lo};
        end
    end

endmodule
