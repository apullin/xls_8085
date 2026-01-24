// Intel 8085 Test Configuration for Lattice ECP5 (OrangeCrab)
// Uses EBR (Embedded Block RAM) for internal memory
//
// ECP5-25F has 56 EBR blocks x 18Kbit = 1008Kbit = 126KB
// We'll use 112KB for RAM, leaving some for cache
//
// Memory Map:
//   0x0000-0x7FFF: Internal EBR RAM (32KB)
//   0x8000-0xFFFF: Internal SPI flash cache (32KB, banked)
//
// This is a minimal test config - no external bus

module i8085_test_ecp5 (
    input  wire        clk,
    input  wire        reset_n,

    // SPI Flash Interface
    output wire        spi_sck,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,

    // Debug outputs
    output wire        dbg_halted,
    output wire [7:0]  dbg_port_out,
    output wire        dbg_port_wr
);

    // =========================================================================
    // EBR RAM - 32KB using inferred RAM (Yosys will map to EBR)
    // =========================================================================

    reg [7:0] ram [0:32767];  // 32KB
    reg [7:0] ram_rdata;
    reg [14:0] ram_addr_r;

    always @(posedge clk) begin
        ram_addr_r <= fetch_addr[14:0];
        if (ram_we)
            ram[fetch_addr[14:0]] <= ram_wdata;
        ram_rdata <= ram[ram_addr_r];
    end

    reg ram_we;
    reg [7:0] ram_wdata;

    // =========================================================================
    // Bank Register
    // =========================================================================

    reg [7:0] rom_bank_reg;

    // =========================================================================
    // SPI Flash Cache
    // =========================================================================

    reg        rom_cs;
    reg        rom_rd_reg;
    wire [7:0] cache_rom_data;
    wire       cache_rom_ready;

    spi_flash_cache flash_cache (
        .clk(clk), .reset_n(reset_n),
        .rom_addr(fetch_addr[14:0]), .rom_rd(rom_rd_reg),
        .rom_data(cache_rom_data), .rom_ready(cache_rom_ready),
        .bank_sel(rom_bank_reg),
        .spi_sck(spi_sck), .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi), .spi_miso(spi_miso)
    );

    // =========================================================================
    // Debug Port Output
    // =========================================================================

    reg [7:0] port_out_reg;
    reg       port_wr_reg;

    assign dbg_port_out = port_out_reg;
    assign dbg_port_wr = port_wr_reg;

    // =========================================================================
    // CPU Interface
    // =========================================================================

    wire [15:0] cpu_mem_addr;
    wire [7:0]  cpu_mem_data_out;
    wire        cpu_mem_wr;
    wire [15:0] cpu_stack_wr_addr;
    wire [7:0]  cpu_stack_wr_lo, cpu_stack_wr_hi;
    wire        cpu_stack_wr;
    wire [7:0]  cpu_io_port;
    wire [7:0]  cpu_io_data_out;
    wire        cpu_io_rd, cpu_io_wr;
    wire [15:0] cpu_pc, cpu_sp;
    wire        cpu_halted;
    wire        cpu_inte;

    assign dbg_halted = cpu_halted;

    // =========================================================================
    // FSM
    // =========================================================================

    localparam S_FETCH_OP    = 4'd0;
    localparam S_WAIT_OP     = 4'd1;
    localparam S_FETCH_IMM1  = 4'd2;
    localparam S_WAIT_IMM1   = 4'd3;
    localparam S_FETCH_IMM2  = 4'd4;
    localparam S_WAIT_IMM2   = 4'd5;
    localparam S_READ_MEM    = 4'd6;
    localparam S_WAIT_MEM    = 4'd7;
    localparam S_READ_STK_LO = 4'd8;
    localparam S_WAIT_STK_LO = 4'd9;
    localparam S_READ_STK_HI = 4'd10;
    localparam S_WAIT_STK_HI = 4'd11;
    localparam S_EXECUTE     = 4'd12;
    localparam S_WRITE_STK   = 4'd13;
    localparam S_HALTED      = 4'd14;

    reg [3:0]  fsm_state;
    reg [15:0] fetch_addr;
    reg [7:0]  fetched_op;
    reg [7:0]  fetched_imm1;
    reg [7:0]  fetched_imm2;
    reg        execute_pulse;
    reg [7:0]  mem_rd_buf;
    reg [7:0]  stk_lo_buf, stk_hi_buf;
    reg [7:0]  io_rd_buf;

    // Instruction decode helpers
    function [1:0] inst_len;
        input [7:0] op;
        casez (op)
            8'b00??0001, 8'b11000011, 8'b11??0010,
            8'b11001101, 8'b11??0100, 8'b0011?010, 8'b0010?010:
                inst_len = 2'd3;
            8'b00???110, 8'b11???110, 8'b1101?011:
                inst_len = 2'd2;
            default:
                inst_len = 2'd1;
        endcase
    endfunction

    function needs_hl_read;
        input [7:0] op;
        casez (op)
            8'b01???110, 8'b10???110, 8'b00110100, 8'b00110101:
                needs_hl_read = 1'b1;
            default:
                needs_hl_read = 1'b0;
        endcase
    endfunction

    function needs_bc_read; input [7:0] op; needs_bc_read = (op == 8'h0A); endfunction
    function needs_de_read; input [7:0] op; needs_de_read = (op == 8'h1A); endfunction
    function needs_direct_read; input [7:0] op; needs_direct_read = (op == 8'h3A) || (op == 8'h2A); endfunction

    function needs_stack_read;
        input [7:0] op;
        casez (op)
            8'b11001001, 8'b11???000, 8'b11??0001, 8'b11100011:
                needs_stack_read = 1'b1;
            default:
                needs_stack_read = 1'b0;
        endcase
    endfunction

    function needs_io_read; input [7:0] op; needs_io_read = (op == 8'hDB); endfunction

    // Data mux
    wire [7:0] mem_byte = rom_cs ? cache_rom_data : ram_rdata;
    wire mem_ready = rom_cs ? cache_rom_ready : 1'b1;

    wire [15:0] direct_addr = {fetched_imm2, fetched_imm1};

    // Address decode
    task set_addr_decode;
        input [15:0] addr;
        begin
            fetch_addr <= addr;
            if (addr[15]) begin
                rom_cs <= 1'b1;
                rom_rd_reg <= 1'b1;
            end else begin
                rom_cs <= 1'b0;
            end
        end
    endtask

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            fsm_state <= S_FETCH_OP;
            fetch_addr <= 16'h0000;
            fetched_op <= 8'h00;
            fetched_imm1 <= 8'h00;
            fetched_imm2 <= 8'h00;
            execute_pulse <= 1'b0;
            mem_rd_buf <= 8'h00;
            stk_lo_buf <= 8'h00;
            stk_hi_buf <= 8'h00;
            io_rd_buf <= 8'h00;
            rom_cs <= 1'b0;
            rom_rd_reg <= 1'b0;
            rom_bank_reg <= 8'h00;
            ram_we <= 1'b0;
            ram_wdata <= 8'h00;
            port_out_reg <= 8'h00;
            port_wr_reg <= 1'b0;
        end else begin
            execute_pulse <= 1'b0;
            ram_we <= 1'b0;
            rom_rd_reg <= 1'b0;
            port_wr_reg <= 1'b0;

            case (fsm_state)
                S_FETCH_OP: begin
                    if (cpu_halted) begin
                        fsm_state <= S_HALTED;
                    end else begin
                        set_addr_decode(cpu_pc);
                        fsm_state <= S_WAIT_OP;
                    end
                end

                S_WAIT_OP: begin
                    if (!mem_ready) begin
                        // Wait
                    end else begin
                        fetched_op <= mem_byte;
                        if (inst_len(mem_byte) >= 2'd2) begin
                            set_addr_decode(cpu_pc + 16'd1);
                            fsm_state <= S_FETCH_IMM1;
                        end else if (needs_hl_read(mem_byte) || needs_bc_read(mem_byte) || needs_de_read(mem_byte)) begin
                            fsm_state <= S_READ_MEM;
                        end else if (needs_stack_read(mem_byte)) begin
                            set_addr_decode(cpu_sp);
                            fsm_state <= S_READ_STK_LO;
                        end else begin
                            fsm_state <= S_EXECUTE;
                        end
                    end
                end

                S_FETCH_IMM1: fsm_state <= S_WAIT_IMM1;

                S_WAIT_IMM1: begin
                    if (!mem_ready) begin
                        // Wait
                    end else begin
                        fetched_imm1 <= mem_byte;
                        if (inst_len(fetched_op) >= 2'd3) begin
                            set_addr_decode(cpu_pc + 16'd2);
                            fsm_state <= S_FETCH_IMM2;
                        end else if (needs_io_read(fetched_op)) begin
                            io_rd_buf <= 8'hFF;
                            fsm_state <= S_EXECUTE;
                        end else if (needs_hl_read(fetched_op) || needs_bc_read(fetched_op) || needs_de_read(fetched_op)) begin
                            fsm_state <= S_READ_MEM;
                        end else if (needs_stack_read(fetched_op)) begin
                            set_addr_decode(cpu_sp);
                            fsm_state <= S_READ_STK_LO;
                        end else begin
                            fsm_state <= S_EXECUTE;
                        end
                    end
                end

                S_FETCH_IMM2: fsm_state <= S_WAIT_IMM2;

                S_WAIT_IMM2: begin
                    if (!mem_ready) begin
                        // Wait
                    end else begin
                        fetched_imm2 <= mem_byte;
                        if (needs_direct_read(fetched_op)) begin
                            set_addr_decode({mem_byte, fetched_imm1});
                            fsm_state <= S_READ_MEM;
                        end else if (needs_stack_read(fetched_op)) begin
                            set_addr_decode(cpu_sp);
                            fsm_state <= S_READ_STK_LO;
                        end else begin
                            fsm_state <= S_EXECUTE;
                        end
                    end
                end

                S_READ_MEM: fsm_state <= S_WAIT_MEM;

                S_WAIT_MEM: begin
                    if (!mem_ready) begin
                        // Wait
                    end else begin
                        mem_rd_buf <= mem_byte;
                        if (fetched_op == 8'h2A) begin
                            set_addr_decode(direct_addr + 16'd1);
                            fsm_state <= S_READ_STK_LO;
                        end else if (needs_stack_read(fetched_op)) begin
                            set_addr_decode(cpu_sp);
                            fsm_state <= S_READ_STK_LO;
                        end else begin
                            fsm_state <= S_EXECUTE;
                        end
                    end
                end

                S_READ_STK_LO: fsm_state <= S_WAIT_STK_LO;

                S_WAIT_STK_LO: begin
                    if (!mem_ready) begin
                        // Wait
                    end else begin
                        stk_lo_buf <= mem_byte;
                        set_addr_decode(fetch_addr + 16'd1);
                        fsm_state <= S_READ_STK_HI;
                    end
                end

                S_READ_STK_HI: fsm_state <= S_WAIT_STK_HI;

                S_WAIT_STK_HI: begin
                    if (!mem_ready) begin
                        // Wait
                    end else begin
                        stk_hi_buf <= mem_byte;
                        fsm_state <= S_EXECUTE;
                    end
                end

                S_EXECUTE: begin
                    execute_pulse <= 1'b1;
                    if (cpu_stack_wr) begin
                        fetch_addr <= cpu_stack_wr_addr;
                        ram_wdata <= cpu_stack_wr_lo;
                        ram_we <= 1'b1;
                        fsm_state <= S_WRITE_STK;
                    end else if (cpu_mem_wr) begin
                        fetch_addr <= cpu_mem_addr;
                        ram_wdata <= cpu_mem_data_out;
                        ram_we <= !cpu_mem_addr[15];  // Only write to RAM, not ROM
                        fsm_state <= S_FETCH_OP;
                    end else if (cpu_io_wr) begin
                        if (cpu_io_port == 8'hF0)
                            rom_bank_reg <= cpu_io_data_out;
                        else begin
                            port_out_reg <= cpu_io_data_out;
                            port_wr_reg <= 1'b1;
                        end
                        fsm_state <= S_FETCH_OP;
                    end else begin
                        fsm_state <= S_FETCH_OP;
                    end
                end

                S_WRITE_STK: begin
                    fetch_addr <= cpu_stack_wr_addr + 16'd1;
                    ram_wdata <= cpu_stack_wr_hi;
                    ram_we <= 1'b1;
                    fsm_state <= S_FETCH_OP;
                end

                S_HALTED: begin
                    // Stay halted
                end

                default: fsm_state <= S_FETCH_OP;
            endcase
        end
    end

    // =========================================================================
    // CPU Core
    // =========================================================================

    i8085_wrapper cpu (
        .clk(clk),
        .reset_n(reset_n),
        .mem_addr(cpu_mem_addr),
        .mem_data_in(mem_byte),
        .mem_data_out(cpu_mem_data_out),
        .mem_rd(),
        .mem_wr(cpu_mem_wr),
        .stack_wr_addr(cpu_stack_wr_addr),
        .stack_wr_data_lo(cpu_stack_wr_lo),
        .stack_wr_data_hi(cpu_stack_wr_hi),
        .stack_wr(cpu_stack_wr),
        .io_port(cpu_io_port),
        .io_data_out(cpu_io_data_out),
        .io_data_in(io_rd_buf),
        .io_rd(cpu_io_rd),
        .io_wr(cpu_io_wr),
        .opcode(fetched_op),
        .imm1(fetched_imm1),
        .imm2(fetched_imm2),
        .mem_read_data(mem_rd_buf),
        .stack_lo(stk_lo_buf),
        .stack_hi(stk_hi_buf),
        .execute(execute_pulse),
        .int_ack(),
        .int_vector(16'h0000),
        .int_is_trap(1'b0),
        .sid(1'b0),
        .rst55_level(1'b0),
        .rst65_level(1'b0),
        .pc(cpu_pc),
        .sp(cpu_sp),
        .reg_a(),
        .reg_b(),
        .reg_c(),
        .reg_d(),
        .reg_e(),
        .reg_h(),
        .reg_l(),
        .halted(cpu_halted),
        .inte(cpu_inte),
        .flag_z(),
        .flag_c(),
        .mask_55(),
        .mask_65(),
        .mask_75(),
        .rst75_pending(),
        .sod()
    );

endmodule
