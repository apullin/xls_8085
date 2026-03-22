// Minimal top-level for timing analysis only
// Reduces IOs to fit UP5K sg48

module i8085_timing_top (
    input  wire        clk,
    input  wire        reset_n,

    // Minimal external interface
    input  wire [7:0]  io_in_data,
    output wire [7:0]  io_out_data,
    output wire        io_out_strobe,

    // Status (directly observable)
    output wire        halted
);

    // Internal wires for SoC
    wire [15:0] dbg_pc;
    wire [7:0]  dbg_a;
    wire        dbg_halted;
    wire        dbg_flag_z;
    wire        dbg_flag_c;
    wire [7:0]  io_out_port;

    i8085_soc soc (
        .clk(clk),
        .reset_n(reset_n),
        .io_in_data(io_in_data),
        .io_out_data(io_out_data),
        .io_out_port(io_out_port),
        .io_out_strobe(io_out_strobe),
        .dbg_pc(dbg_pc),
        .dbg_a(dbg_a),
        .dbg_halted(dbg_halted),
        .dbg_flag_z(dbg_flag_z),
        .dbg_flag_c(dbg_flag_c)
    );

    assign halted = dbg_halted;

endmodule
