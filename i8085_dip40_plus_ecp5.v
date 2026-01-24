// Intel 8085 Enhanced DIP40 Configuration for Lattice ECP5 (OrangeCrab)
// Uses EBR (Embedded Block RAM) - ECP5-25F has 56 blocks = 126KB
//
// Memory Map:
//   0x0000-0x77FF: Internal EBR RAM (30KB)
//   0x7800-0x7FFF: EXTERNAL (2KB window for peripherals)
//   0x8000-0xFFFF: Internal SPI flash cache (32KB, banked)
//
// I/O Ports:
//   0xF0: ROM bank register (8-bit, 256 banks x 32KB = 8MB)

module i8085_dip40_plus_ecp5 #(
    parameter [15:0] EXT_WINDOW_BASE = 16'h7800,
    parameter [3:0]  EXT_WINDOW_SIZE = 4'd11      // 11=2KB
)(
    // Clock and Reset
    input  wire        clk,
    input  wire        reset_n,

    // Multiplexed Address/Data Bus
    inout  wire [7:0]  ad,
    output wire [2:0]  a_hi,         // A8-A10 only

    // Bus Control
    output wire        ale,
    output wire        rd_n,
    output wire        wr_n,
    output wire        io_m_n,

    // Status
    output wire        s0,
    output wire        s1,
    output wire        resout,

    // Interrupts
    input  wire        trap,
    input  wire        rst75,
    input  wire        rst65,
    input  wire        rst55,
    input  wire        intr,
    output wire        inta_n,

    // Serial I/O
    input  wire        sid,
    output wire        sod,

    // DMA
    input  wire        hold,
    output wire        hlda,

    // Wait State
    input  wire        ready,

    // SPI Flash Interface
    output wire        spi_sck,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso
);

    // =========================================================================
    // Reset Output
    // =========================================================================

    reg [3:0] reset_stretch;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            reset_stretch <= 4'hF;
        else if (reset_stretch != 0)
            reset_stretch <= reset_stretch - 1;
    end
    assign resout = (reset_stretch != 0);

    // =========================================================================
    // External Window Detection
    // =========================================================================

    wire [15:0] window_mask = (16'hFFFF << EXT_WINDOW_SIZE);

    function is_external;
        input [15:0] addr;
        begin
            is_external = ((addr & window_mask) == (EXT_WINDOW_BASE & window_mask));
        end
    endfunction

    // =========================================================================
    // EBR RAM - 30KB using inferred RAM
    // =========================================================================

    reg [7:0] ram [0:30719];  // 30KB (0x0000-0x77FF)
    reg [7:0] ram_rdata;
    reg [14:0] ram_addr_r;
    reg ram_we;
    reg [7:0] ram_wdata;
    reg ram_cs;

    always @(posedge clk) begin
        ram_addr_r <= fetch_addr[14:0];
        if (ram_we && ram_cs)
            ram[fetch_addr[14:0]] <= ram_wdata;
        ram_rdata <= ram[ram_addr_r];
    end

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
    // External Bus Control
    // =========================================================================

    reg         ext_cs;
    reg [15:0]  ext_addr_reg;
    reg [7:0]   ext_data_out_reg;
    reg         ext_ale_reg;
    reg         ext_rd_reg;
    reg         ext_wr_reg;
    reg         ext_io_m_reg;
    reg         ext_data_oe;

    assign ad = (ext_ale_reg) ? ext_addr_reg[7:0] :
                (ext_data_oe) ? ext_data_out_reg : 8'bZ;

    assign a_hi = ext_cs ? ext_addr_reg[10:8] : 3'b0;

    assign ale = ext_ale_reg;
    assign rd_n = ~ext_rd_reg;
    assign wr_n = ~ext_wr_reg;
    assign io_m_n = ext_cs ? ~ext_io_m_reg : 1'b1;

    assign s0 = ext_rd_reg;
    assign s1 = ~ext_wr_reg;

    wire [7:0] ext_data_in = ad;

    // =========================================================================
    // DMA Support
    // =========================================================================

    reg hold_ack;
    assign hlda = hold_ack;

    // =========================================================================
    // Interrupt Controller
    // =========================================================================

    reg rst75_prev, trap_prev;
    reg rst75_pending, trap_pending;
    reg intr_pending;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rst75_prev <= 1'b0;
            trap_prev <= 1'b0;
            rst75_pending <= 1'b0;
            trap_pending <= 1'b0;
            intr_pending <= 1'b0;
        end else begin
            rst75_prev <= rst75;
            trap_prev <= trap;

            if (rst75 && !rst75_prev)
                rst75_pending <= 1'b1;

            if ((trap && !trap_prev) || trap)
                trap_pending <= 1'b1;

            intr_pending <= intr;

            if (int_ack_pulse) begin
                if (trap_pending)
                    trap_pending <= 1'b0;
                else if (rst75_pending)
                    rst75_pending <= 1'b0;
            end
        end
    end

    reg int_ack_pulse;
    reg inta_reg;
    assign inta_n = ~inta_reg;

    // =========================================================================
    // CPU Interface Signals
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
    wire        cpu_sod;
    wire        cpu_mask_55, cpu_mask_65, cpu_mask_75;

    assign sod = cpu_sod;

    // =========================================================================
    // FSM States
    // =========================================================================

    localparam S_FETCH_OP       = 5'd0;
    localparam S_WAIT_OP        = 5'd1;
    localparam S_FETCH_IMM1     = 5'd2;
    localparam S_WAIT_IMM1      = 5'd3;
    localparam S_FETCH_IMM2     = 5'd4;
    localparam S_WAIT_IMM2      = 5'd5;
    localparam S_READ_MEM       = 5'd6;
    localparam S_WAIT_MEM       = 5'd7;
    localparam S_READ_STK_LO    = 5'd8;
    localparam S_WAIT_STK_LO    = 5'd9;
    localparam S_READ_STK_HI    = 5'd10;
    localparam S_WAIT_STK_HI    = 5'd11;
    localparam S_EXECUTE        = 5'd12;
    localparam S_WRITE_STK      = 5'd13;
    localparam S_HALTED         = 5'd14;
    localparam S_EXT_ALE        = 5'd15;
    localparam S_EXT_RD         = 5'd16;
    localparam S_EXT_RD_WAIT    = 5'd17;
    localparam S_EXT_WR         = 5'd18;
    localparam S_EXT_WR_WAIT    = 5'd19;
    localparam S_DMA_HOLD       = 5'd20;

    reg [4:0]  fsm_state;
    reg [4:0]  fsm_return;
    reg [15:0] fetch_addr;
    reg [7:0]  fetched_op;
    reg [7:0]  fetched_imm1;
    reg [7:0]  fetched_imm2;
    reg        execute_pulse;
    reg [7:0]  mem_rd_buf;
    reg [7:0]  stk_lo_buf, stk_hi_buf;
    reg [7:0]  io_rd_buf;
    reg [7:0]  ext_rd_buf;

    // =========================================================================
    // Instruction Decode Helpers
    // =========================================================================

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

    // =========================================================================
    // Data Mux
    // =========================================================================

    wire [7:0] mem_byte = rom_cs ? cache_rom_data :
                          ext_cs ? ext_rd_buf : ram_rdata;

    wire mem_ready = ext_cs ? ready :
                     rom_cs ? cache_rom_ready : 1'b1;

    // =========================================================================
    // Address Decode
    // =========================================================================

    task set_addr_decode;
        input [15:0] addr;
        begin
            fetch_addr <= addr;
            ext_addr_reg <= addr;

            if (is_external(addr)) begin
                ram_cs <= 1'b0;
                rom_cs <= 1'b0;
                ext_cs <= 1'b1;
            end else if (addr[15] == 1'b0) begin
                ram_cs <= 1'b1;
                rom_cs <= 1'b0;
                ext_cs <= 1'b0;
            end else begin
                ram_cs <= 1'b0;
                rom_cs <= 1'b1;
                rom_rd_reg <= 1'b1;
                ext_cs <= 1'b0;
            end
        end
    endtask

    // =========================================================================
    // FSM Logic
    // =========================================================================

    wire [15:0] direct_addr = {fetched_imm2, fetched_imm1};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            fsm_state <= S_FETCH_OP;
            fsm_return <= S_FETCH_OP;
            fetch_addr <= 16'h0000;
            fetched_op <= 8'h00;
            fetched_imm1 <= 8'h00;
            fetched_imm2 <= 8'h00;
            execute_pulse <= 1'b0;
            mem_rd_buf <= 8'h00;
            stk_lo_buf <= 8'h00;
            stk_hi_buf <= 8'h00;
            io_rd_buf <= 8'h00;
            ext_rd_buf <= 8'h00;
            ram_cs <= 1'b0;
            ram_we <= 1'b0;
            ram_wdata <= 8'h00;
            rom_cs <= 1'b0;
            rom_rd_reg <= 1'b0;
            ext_cs <= 1'b0;
            rom_bank_reg <= 8'h00;
            ext_ale_reg <= 1'b0;
            ext_rd_reg <= 1'b0;
            ext_wr_reg <= 1'b0;
            ext_io_m_reg <= 1'b0;
            ext_data_oe <= 1'b0;
            ext_data_out_reg <= 8'h00;
            hold_ack <= 1'b0;
            int_ack_pulse <= 1'b0;
            inta_reg <= 1'b0;
        end else begin
            execute_pulse <= 1'b0;
            ram_we <= 1'b0;
            rom_rd_reg <= 1'b0;
            ext_ale_reg <= 1'b0;
            ext_rd_reg <= 1'b0;
            ext_wr_reg <= 1'b0;
            ext_data_oe <= 1'b0;
            int_ack_pulse <= 1'b0;
            inta_reg <= 1'b0;

            if (hold && (fsm_state == S_FETCH_OP)) begin
                hold_ack <= 1'b1;
                fsm_state <= S_DMA_HOLD;
            end else begin
                hold_ack <= 1'b0;
            end

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
                    if (ext_cs) begin
                        ext_ale_reg <= 1'b1;
                        ext_io_m_reg <= 1'b0;
                        fsm_return <= S_WAIT_OP;
                        fsm_state <= S_EXT_ALE;
                    end else if (!mem_ready) begin
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
                    if (ext_cs) begin
                        ext_ale_reg <= 1'b1;
                        ext_io_m_reg <= 1'b0;
                        fsm_return <= S_WAIT_IMM1;
                        fsm_state <= S_EXT_ALE;
                    end else if (!mem_ready) begin
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
                    if (ext_cs) begin
                        ext_ale_reg <= 1'b1;
                        ext_io_m_reg <= 1'b0;
                        fsm_return <= S_WAIT_IMM2;
                        fsm_state <= S_EXT_ALE;
                    end else if (!mem_ready) begin
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
                    if (ext_cs) begin
                        ext_ale_reg <= 1'b1;
                        ext_io_m_reg <= 1'b0;
                        fsm_return <= S_WAIT_MEM;
                        fsm_state <= S_EXT_ALE;
                    end else if (!mem_ready) begin
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
                    if (ext_cs) begin
                        ext_ale_reg <= 1'b1;
                        ext_io_m_reg <= 1'b0;
                        fsm_return <= S_WAIT_STK_LO;
                        fsm_state <= S_EXT_ALE;
                    end else if (!mem_ready) begin
                        // Wait
                    end else begin
                        stk_lo_buf <= mem_byte;
                        set_addr_decode(fetch_addr + 16'd1);
                        fsm_state <= S_READ_STK_HI;
                    end
                end

                S_READ_STK_HI: fsm_state <= S_WAIT_STK_HI;

                S_WAIT_STK_HI: begin
                    if (ext_cs) begin
                        ext_ale_reg <= 1'b1;
                        ext_io_m_reg <= 1'b0;
                        fsm_return <= S_WAIT_STK_HI;
                        fsm_state <= S_EXT_ALE;
                    end else if (!mem_ready) begin
                        // Wait
                    end else begin
                        stk_hi_buf <= mem_byte;
                        fsm_state <= S_EXECUTE;
                    end
                end

                S_EXECUTE: begin
                    execute_pulse <= 1'b1;
                    if (cpu_stack_wr) begin
                        set_addr_decode(cpu_stack_wr_addr);
                        ram_wdata <= cpu_stack_wr_lo;
                        ram_we <= ram_cs;
                        fsm_state <= S_WRITE_STK;
                    end else if (cpu_mem_wr) begin
                        set_addr_decode(cpu_mem_addr);
                        if (is_external(cpu_mem_addr)) begin
                            ext_data_out_reg <= cpu_mem_data_out;
                            ext_ale_reg <= 1'b1;
                            ext_io_m_reg <= 1'b0;
                            fsm_return <= S_FETCH_OP;
                            fsm_state <= S_EXT_ALE;
                        end else begin
                            ram_wdata <= cpu_mem_data_out;
                            ram_we <= ram_cs;
                            fsm_state <= S_FETCH_OP;
                        end
                    end else if (cpu_io_wr) begin
                        if (cpu_io_port == 8'hF0)
                            rom_bank_reg <= cpu_io_data_out;
                        fsm_state <= S_FETCH_OP;
                    end else begin
                        fsm_state <= S_FETCH_OP;
                    end
                end

                S_WRITE_STK: begin
                    set_addr_decode(cpu_stack_wr_addr + 16'd1);
                    ram_wdata <= cpu_stack_wr_hi;
                    ram_we <= ram_cs;
                    fsm_state <= S_FETCH_OP;
                end

                S_HALTED: begin
                    if (trap_pending || (cpu_inte && (rst75_pending || rst65 || rst55 || intr_pending))) begin
                        fsm_state <= S_FETCH_OP;
                    end
                end

                S_DMA_HOLD: begin
                    if (!hold) begin
                        hold_ack <= 1'b0;
                        fsm_state <= S_FETCH_OP;
                    end
                end

                S_EXT_ALE: begin
                    ext_ale_reg <= 1'b0;
                    if (fsm_return == S_FETCH_OP && cpu_mem_wr) begin
                        ext_wr_reg <= 1'b1;
                        ext_data_oe <= 1'b1;
                        fsm_state <= S_EXT_WR;
                    end else begin
                        ext_rd_reg <= 1'b1;
                        fsm_state <= S_EXT_RD;
                    end
                end

                S_EXT_RD: begin
                    ext_rd_reg <= 1'b1;
                    fsm_state <= S_EXT_RD_WAIT;
                end

                S_EXT_RD_WAIT: begin
                    if (ready) begin
                        ext_rd_buf <= ext_data_in;
                        ext_rd_reg <= 1'b0;
                        fsm_state <= fsm_return;
                    end else begin
                        ext_rd_reg <= 1'b1;
                    end
                end

                S_EXT_WR: begin
                    ext_wr_reg <= 1'b1;
                    ext_data_oe <= 1'b1;
                    fsm_state <= S_EXT_WR_WAIT;
                end

                S_EXT_WR_WAIT: begin
                    if (ready) begin
                        ext_wr_reg <= 1'b0;
                        ext_data_oe <= 1'b0;
                        fsm_state <= fsm_return;
                    end else begin
                        ext_wr_reg <= 1'b1;
                        ext_data_oe <= 1'b1;
                    end
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
        .int_ack(int_ack_pulse),
        .int_vector(trap_pending ? 16'h0024 :
                    rst75_pending ? 16'h003C :
                    (rst65 && !cpu_mask_65) ? 16'h0034 :
                    (rst55 && !cpu_mask_55) ? 16'h002C :
                    16'h0000),
        .int_is_trap(trap_pending),
        .sid(sid),
        .rst55_level(rst55),
        .rst65_level(rst65),
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
        .mask_55(cpu_mask_55),
        .mask_65(cpu_mask_65),
        .mask_75(cpu_mask_75),
        .rst75_pending(),
        .sod(cpu_sod)
    );

endmodule
