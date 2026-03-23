// bin_runner_tb.v - Run flat binary programs on i8085 or j8085 cores
//
// Loads a 64KB binary image and runs to HLT, reporting cycle count.
// Binary format: flat image starting at address 0x0000.
// Expected layout (from llvm-8085 toolchain):
//   0x0000-0x003F  Vector table
//   0x0040-0x7FFF  RAM (data, BSS, stack grows down from 0x8000)
//   0x8000-0xFFFF  ROM (code, rodata)
//
// Usage:
//   iverilog -g2012 -DBIN_FILE=\"path/to/program.hex\" \
//       -DCORE=j8085 test/bin_runner_tb.v j8085/*.v
//   vvp a.out
//
// Convert .bin to .hex:
//   xxd -p program.bin | fold -w2 | nl -ba -v0 | \
//       awk '{printf "%04X %s\n", $1, toupper($2)}' > program.hex
//   (or use the provided bin2hex.py script)

`timescale 1ns / 1ps

`ifndef BIN_FILE
  `define BIN_FILE "program.hex"
`endif

`ifndef MAX_CYCLES
  `define MAX_CYCLES 10000000
`endif

module bin_runner_tb;

    parameter CLK_PERIOD = 20;

    reg         clk;
    reg         reset_n;

    wire [15:0] bus_addr;
    wire [7:0]  bus_data_out;
    wire        bus_rd;
    wire        bus_wr;
    wire [7:0]  bus_data_in;
    wire        bus_ready;

    wire [15:0] stack_wr_addr;
    wire [7:0]  stack_wr_data_lo;
    wire [7:0]  stack_wr_data_hi;
    wire        stack_wr;

    wire [7:0]  io_port, io_data_out;
    wire        io_rd, io_wr;

    wire [15:0] cpu_pc, cpu_sp;
    wire [7:0]  cpu_a, cpu_b, cpu_c, cpu_d, cpu_e, cpu_h, cpu_l;
    wire        cpu_halted;

    // ── Flat 64KB memory (byte-addressed internally) ────────
    reg [7:0] mem [0:65535];

    // Initialize from hex file
    initial begin
        $readmemh(`BIN_FILE, mem);
    end

    // 1-cycle read latency (matches SPRAM behavior)
    reg [7:0] read_data;
    reg       read_valid;

    always @(posedge clk) begin
        if (!reset_n) begin
            read_data  <= 8'h00;
            read_valid <= 1'b0;
        end else begin
            read_valid <= bus_rd;
            if (bus_rd)
                read_data <= mem[bus_addr];
        end
    end

    assign bus_data_in = read_data;
    assign bus_ready   = read_valid;

    // Synchronous byte write
    always @(posedge clk) begin
        if (bus_wr)
            mem[bus_addr] <= bus_data_out;
    end

    // Stack write (16-bit)
    always @(posedge clk) begin
        if (stack_wr) begin
            mem[stack_wr_addr]     <= stack_wr_data_lo;
            mem[stack_wr_addr + 1] <= stack_wr_data_hi;
        end
    end

    // ── DUT ─────────────────────────────────────────────────
`ifdef USE_I8085
    i8085_cpu cpu (
`else
    j8085_cpu cpu (
`endif
        .clk(clk), .reset_n(reset_n),
        .bus_addr(bus_addr), .bus_data_out(bus_data_out),
        .bus_rd(bus_rd), .bus_wr(bus_wr),
        .bus_data_in(bus_data_in), .bus_ready(bus_ready),
        .stack_wr_addr(stack_wr_addr),
        .stack_wr_data_lo(stack_wr_data_lo),
        .stack_wr_data_hi(stack_wr_data_hi),
        .stack_wr(stack_wr),
        .io_port(io_port), .io_data_out(io_data_out),
        .io_data_in(8'h00), .io_rd(io_rd), .io_wr(io_wr),
        .rom_bank(), .ram_bank(),
        .int_req(1'b0), .int_vector(16'h0000), .int_is_trap(1'b0), .int_ack(),
        .sid(1'b0), .rst55_level(1'b0), .rst65_level(1'b0),
        .pc(cpu_pc), .sp(cpu_sp),
        .reg_a(cpu_a), .reg_b(cpu_b), .reg_c(cpu_c),
        .reg_d(cpu_d), .reg_e(cpu_e), .reg_h(cpu_h), .reg_l(cpu_l),
        .halted(cpu_halted), .inte(), .flag_z(), .flag_c(),
        .mask_55(), .mask_65(), .mask_75(),
        .rst75_pending(), .sod()
    );

    // ── Clock ───────────────────────────────────────────────
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ── Run ─────────────────────────────────────────────────
    integer cycle;

    initial begin
        reset_n = 0;
        repeat(5) @(posedge clk);
        reset_n = 1;

        cycle = 0;
        while (cycle < `MAX_CYCLES && !cpu_halted) begin
            @(posedge clk);
            cycle = cycle + 1;
        end

        if (cpu_halted) begin
            $display("HALT after %0d cycles", cycle);
            $display("  PC=%04x SP=%04x", cpu_pc, cpu_sp);
            $display("  A=%02x B=%02x C=%02x D=%02x E=%02x H=%02x L=%02x",
                     cpu_a, cpu_b, cpu_c, cpu_d, cpu_e, cpu_h, cpu_l);
        end else begin
            $display("TIMEOUT after %0d cycles at PC=%04x", cycle, cpu_pc);
        end

        $finish;
    end

endmodule
