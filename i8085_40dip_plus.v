// Intel 8085 Enhanced 40-DIP Configuration for iCE40 UP5K
// Drop-in replacement with internal resources + configurable external window
//
// Parameters:
//   EXT_WINDOW_BASE - Start address of external window (default: 0x7C00)
//   EXT_WINDOW_SIZE - Window size in address bits: 10=1KB, 11=2KB, 12=4KB (default: 10)
//   ACTIVE_AD_BUS   - 0=external bus quiet, 1=external bus active (default: 1)
//
// Memory Map (default config):
//   0x0000-0x7BFF: Internal SPRAM (31KB per bank, 4 banks = 124KB via port 0xF1)
//   0x7C00-0x7FFF: EXTERNAL (1KB window for peripherals)
//   0x8000-0xFFFF: Internal SPI flash cache (32KB, banked 256 = 8MB via port 0xF0)
//
// I/O Ports:
//   0xF0: ROM bank register (8-bit, 256 banks × 32KB = 8MB)
//   0xF1: RAM bank register (2-bit, 4 banks × 31KB = 124KB)

module i8085_40dip_plus #(
    parameter [15:0] EXT_WINDOW_BASE = 16'h7C00,  // Default: top of RAM space
    parameter [3:0]  EXT_WINDOW_SIZE = 4'd10,     // 10=1KB, 11=2KB, 12=4KB
    parameter        ACTIVE_AD_BUS = 1            // 0=quiet, 1=active
)(
    // Clock and Reset
    input  wire        clk,
    input  wire        reset_n,

    // External Bus (active only within window when ACTIVE_AD_BUS=1)
    inout  wire [7:0]  ad,           // AD0-AD7 multiplexed address/data
    output wire [7:0]  a_hi,         // A8-A15 high address
    output wire        ale,          // Address Latch Enable
    output wire        rd_n,         // Read strobe (active low)
    output wire        wr_n,         // Write strobe (active low)
    output wire        io_m_n,       // IO/M (high=IO, low=Memory)
    input  wire        ready,        // External READY input

    // I/O ports (directly exposed, active for all I/O ops)
    output reg  [7:0]  io_out_data,
    output reg  [7:0]  io_out_port,
    output reg         io_out_strobe,
    input  wire [7:0]  io_in_data,

    // SPI Flash Interface
    output wire        spi_sck,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,

    // Debug
    output wire        dbg_halted
);

    // =========================================================================
    // External Window Detection
    // =========================================================================

    // Compute window mask based on size parameter
    wire [15:0] window_mask = (16'hFFFF << EXT_WINDOW_SIZE);

    // Check if address is within external window
    function is_external;
        input [15:0] addr;
        begin
            is_external = ((addr & window_mask) == (EXT_WINDOW_BASE & window_mask));
        end
    endfunction

    // =========================================================================
    // SPRAM - All 4 banks for 124KB total (banked as 4 × ~31KB)
    // =========================================================================

    reg  [13:0] ram_addr;
    reg  [15:0] ram_wdata;
    reg  [3:0]  ram_we;
    wire [15:0] ram_rdata;

    reg         ram_cs_0, ram_cs_1, ram_cs_2, ram_cs_3;
    wire [15:0] ram_rdata_0, ram_rdata_1, ram_rdata_2, ram_rdata_3;

    SB_SPRAM256KA ram_bank0 (
        .ADDRESS(ram_addr), .DATAIN(ram_wdata), .MASKWREN(ram_we),
        .WREN(|ram_we & ram_cs_0), .CHIPSELECT(ram_cs_0), .CLOCK(clk),
        .STANDBY(1'b0), .SLEEP(1'b0), .POWEROFF(1'b1), .DATAOUT(ram_rdata_0)
    );

    SB_SPRAM256KA ram_bank1 (
        .ADDRESS(ram_addr), .DATAIN(ram_wdata), .MASKWREN(ram_we),
        .WREN(|ram_we & ram_cs_1), .CHIPSELECT(ram_cs_1), .CLOCK(clk),
        .STANDBY(1'b0), .SLEEP(1'b0), .POWEROFF(1'b1), .DATAOUT(ram_rdata_1)
    );

    SB_SPRAM256KA ram_bank2 (
        .ADDRESS(ram_addr), .DATAIN(ram_wdata), .MASKWREN(ram_we),
        .WREN(|ram_we & ram_cs_2), .CHIPSELECT(ram_cs_2), .CLOCK(clk),
        .STANDBY(1'b0), .SLEEP(1'b0), .POWEROFF(1'b1), .DATAOUT(ram_rdata_2)
    );

    SB_SPRAM256KA ram_bank3 (
        .ADDRESS(ram_addr), .DATAIN(ram_wdata), .MASKWREN(ram_we),
        .WREN(|ram_we & ram_cs_3), .CHIPSELECT(ram_cs_3), .CLOCK(clk),
        .STANDBY(1'b0), .SLEEP(1'b0), .POWEROFF(1'b1), .DATAOUT(ram_rdata_3)
    );

    reg [1:0] ram_bank_latch;
    always @(posedge clk) ram_bank_latch <= ram_bank_reg;

    assign ram_rdata = (ram_bank_latch == 2'd0) ? ram_rdata_0 :
                       (ram_bank_latch == 2'd1) ? ram_rdata_1 :
                       (ram_bank_latch == 2'd2) ? ram_rdata_2 : ram_rdata_3;

    // ROM and external chip selects
    reg rom_cs;
    reg rom_rd_reg;
    reg ext_cs;

    // =========================================================================
    // Bank Registers
    // =========================================================================

    reg  [7:0]  rom_bank_reg;     // ROM bank (256 × 32KB = 8MB) - port 0xF0
    reg  [1:0]  ram_bank_reg;     // RAM bank (4 × ~31KB = 124KB) - port 0xF1

    // =========================================================================
    // SPI Flash Cache
    // =========================================================================

    wire [7:0]  cache_rom_data;
    wire        cache_rom_ready;

    spi_flash_cache flash_cache (
        .clk(clk), .reset_n(reset_n),
        .rom_addr(fetch_addr[14:0]), .rom_rd(rom_rd_reg),
        .rom_data(cache_rom_data), .rom_ready(cache_rom_ready),
        .bank_sel(rom_bank_reg),
        .spi_sck(spi_sck), .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi), .spi_miso(spi_miso)
    );

    wire rom_ready = cache_rom_ready;

    // =========================================================================
    // External Bus Control
    // =========================================================================

    reg [15:0] ext_addr_reg;
    reg [7:0]  ext_data_out_reg;
    reg        ext_ale_reg;
    reg        ext_rd_reg;
    reg        ext_wr_reg;
    reg        ext_io_m_reg;  // 0=memory, 1=I/O
    reg        ext_data_oe;   // Output enable for data phase

    // External bus active only when ACTIVE_AD_BUS=1 and accessing window
    wire ext_bus_active = ACTIVE_AD_BUS && ext_cs;

    // AD bus: address during ALE, data during RD/WR
    assign ad = (!ACTIVE_AD_BUS) ? 8'bZ :
                (ext_ale_reg) ? ext_addr_reg[7:0] :
                (ext_data_oe) ? ext_data_out_reg : 8'bZ;

    assign a_hi = (ACTIVE_AD_BUS && ext_cs) ? ext_addr_reg[15:8] : 8'b0;
    assign ale = (ACTIVE_AD_BUS) ? ext_ale_reg : 1'b0;
    assign rd_n = (ACTIVE_AD_BUS) ? ~ext_rd_reg : 1'b1;
    assign wr_n = (ACTIVE_AD_BUS) ? ~ext_wr_reg : 1'b1;
    assign io_m_n = (ACTIVE_AD_BUS) ? ~ext_io_m_reg : 1'b1;  // Active low for memory

    // Data input from external bus
    wire [7:0] ext_data_in = ad;

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
    // External bus states
    localparam S_EXT_ALE        = 5'd15;
    localparam S_EXT_RD         = 5'd16;
    localparam S_EXT_RD_WAIT    = 5'd17;
    localparam S_EXT_WR         = 5'd18;
    localparam S_EXT_WR_WAIT    = 5'd19;

    reg [4:0]  fsm_state;
    reg [4:0]  fsm_return;  // State to return to after external access
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
    // Data Mux: Internal RAM, ROM cache, or External
    // =========================================================================

    wire [7:0] ram_word_byte = fetch_addr[0] ? ram_rdata[15:8] : ram_rdata[7:0];
    wire [7:0] ram_byte = rom_cs ? cache_rom_data :
                          ext_cs ? ext_rd_buf : ram_word_byte;

    // Memory ready: internal always ready, external checks READY pin, ROM checks cache
    wire mem_ready = ext_cs ? (ACTIVE_AD_BUS ? ready : 1'b1) :
                     rom_cs ? rom_ready : 1'b1;

    // =========================================================================
    // Address Decode
    // =========================================================================

    task set_addr_decode;
        input [15:0] addr;
        begin
            ram_addr <= addr[14:1];
            ext_addr_reg <= addr;

            if (addr[15] == 1'b1) begin
                // Upper 32KB: ROM from SPI flash
                ram_cs_0 <= 1'b0; ram_cs_1 <= 1'b0;
                ram_cs_2 <= 1'b0; ram_cs_3 <= 1'b0;
                rom_cs <= 1'b1;
                rom_rd_reg <= 1'b1;
                ext_cs <= 1'b0;
            end else if (is_external(addr)) begin
                // External window
                ram_cs_0 <= 1'b0; ram_cs_1 <= 1'b0;
                ram_cs_2 <= 1'b0; ram_cs_3 <= 1'b0;
                rom_cs <= 1'b0;
                ext_cs <= 1'b1;
            end else begin
                // Internal RAM (banked)
                ram_cs_0 <= (ram_bank_reg == 2'd0);
                ram_cs_1 <= (ram_bank_reg == 2'd1);
                ram_cs_2 <= (ram_bank_reg == 2'd2);
                ram_cs_3 <= (ram_bank_reg == 2'd3);
                rom_cs <= 1'b0;
                ext_cs <= 1'b0;
            end
        end
    endtask

    // =========================================================================
    // FSM Logic
    // =========================================================================

    wire [15:0] direct_addr = {fetched_imm2, fetched_imm1};
    wire [7:0] cpu_wrapper_reg_b, cpu_wrapper_reg_c;

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
            ram_addr <= 14'd0;
            ram_wdata <= 16'd0;
            ram_we <= 4'b0000;
            ram_cs_0 <= 1'b0; ram_cs_1 <= 1'b0;
            ram_cs_2 <= 1'b0; ram_cs_3 <= 1'b0;
            rom_cs <= 1'b0;
            rom_rd_reg <= 1'b0;
            ext_cs <= 1'b0;
            rom_bank_reg <= 8'h00;
            ram_bank_reg <= 2'b00;
            io_out_data <= 8'h00;
            io_out_port <= 8'h00;
            io_out_strobe <= 1'b0;
            ext_ale_reg <= 1'b0;
            ext_rd_reg <= 1'b0;
            ext_wr_reg <= 1'b0;
            ext_io_m_reg <= 1'b0;
            ext_data_oe <= 1'b0;
            ext_data_out_reg <= 8'h00;
        end else begin
            execute_pulse <= 1'b0;
            ram_we <= 4'b0000;
            io_out_strobe <= 1'b0;
            rom_rd_reg <= 1'b0;
            ext_ale_reg <= 1'b0;
            ext_rd_reg <= 1'b0;
            ext_wr_reg <= 1'b0;
            ext_data_oe <= 1'b0;

            case (fsm_state)
                S_FETCH_OP: begin
                    if (cpu_halted) begin
                        fsm_state <= S_HALTED;
                    end else begin
                        fetch_addr <= cpu_pc;
                        set_addr_decode(cpu_pc);
                        fsm_state <= S_WAIT_OP;
                    end
                end

                S_WAIT_OP: begin
                    if (ext_cs && ACTIVE_AD_BUS) begin
                        // Start external read cycle
                        ext_ale_reg <= 1'b1;
                        ext_io_m_reg <= 1'b0;  // Memory
                        fsm_return <= S_WAIT_OP;
                        fsm_state <= S_EXT_ALE;
                    end else if (!mem_ready) begin
                        // Wait for ROM cache
                    end else begin
                        fetched_op <= ram_byte;
                        if (inst_len(ram_byte) >= 2'd2) begin
                            fetch_addr <= cpu_pc + 16'd1;
                            set_addr_decode(cpu_pc + 16'd1);
                            fsm_state <= S_FETCH_IMM1;
                        end else if (needs_hl_read(ram_byte) || needs_bc_read(ram_byte) || needs_de_read(ram_byte)) begin
                            fsm_state <= S_READ_MEM;
                        end else if (needs_stack_read(ram_byte)) begin
                            fetch_addr <= cpu_sp;
                            set_addr_decode(cpu_sp);
                            fsm_state <= S_READ_STK_LO;
                        end else begin
                            fsm_state <= S_EXECUTE;
                        end
                    end
                end

                S_FETCH_IMM1: fsm_state <= S_WAIT_IMM1;

                S_WAIT_IMM1: begin
                    if (ext_cs && ACTIVE_AD_BUS) begin
                        ext_ale_reg <= 1'b1;
                        ext_io_m_reg <= 1'b0;
                        fsm_return <= S_WAIT_IMM1;
                        fsm_state <= S_EXT_ALE;
                    end else if (!mem_ready) begin
                        // Wait
                    end else begin
                        fetched_imm1 <= ram_byte;
                        if (inst_len(fetched_op) >= 2'd3) begin
                            fetch_addr <= cpu_pc + 16'd2;
                            set_addr_decode(cpu_pc + 16'd2);
                            fsm_state <= S_FETCH_IMM2;
                        end else if (needs_io_read(fetched_op)) begin
                            io_rd_buf <= io_in_data;
                            fsm_state <= S_EXECUTE;
                        end else if (needs_hl_read(fetched_op) || needs_bc_read(fetched_op) || needs_de_read(fetched_op)) begin
                            fsm_state <= S_READ_MEM;
                        end else if (needs_stack_read(fetched_op)) begin
                            fetch_addr <= cpu_sp;
                            set_addr_decode(cpu_sp);
                            fsm_state <= S_READ_STK_LO;
                        end else begin
                            fsm_state <= S_EXECUTE;
                        end
                    end
                end

                S_FETCH_IMM2: fsm_state <= S_WAIT_IMM2;

                S_WAIT_IMM2: begin
                    if (ext_cs && ACTIVE_AD_BUS) begin
                        ext_ale_reg <= 1'b1;
                        ext_io_m_reg <= 1'b0;
                        fsm_return <= S_WAIT_IMM2;
                        fsm_state <= S_EXT_ALE;
                    end else if (!mem_ready) begin
                        // Wait
                    end else begin
                        fetched_imm2 <= ram_byte;
                        if (needs_direct_read(fetched_op)) begin
                            fetch_addr <= {ram_byte, fetched_imm1};
                            set_addr_decode({ram_byte, fetched_imm1});
                            fsm_state <= S_READ_MEM;
                        end else if (needs_stack_read(fetched_op)) begin
                            fetch_addr <= cpu_sp;
                            set_addr_decode(cpu_sp);
                            fsm_state <= S_READ_STK_LO;
                        end else begin
                            fsm_state <= S_EXECUTE;
                        end
                    end
                end

                S_READ_MEM: fsm_state <= S_WAIT_MEM;

                S_WAIT_MEM: begin
                    if (ext_cs && ACTIVE_AD_BUS) begin
                        ext_ale_reg <= 1'b1;
                        ext_io_m_reg <= 1'b0;
                        fsm_return <= S_WAIT_MEM;
                        fsm_state <= S_EXT_ALE;
                    end else if (!mem_ready) begin
                        // Wait
                    end else begin
                        mem_rd_buf <= ram_byte;
                        if (fetched_op == 8'h2A) begin
                            fetch_addr <= direct_addr + 16'd1;
                            set_addr_decode(direct_addr + 16'd1);
                            fsm_state <= S_READ_STK_LO;
                        end else if (needs_stack_read(fetched_op)) begin
                            fetch_addr <= cpu_sp;
                            set_addr_decode(cpu_sp);
                            fsm_state <= S_READ_STK_LO;
                        end else begin
                            fsm_state <= S_EXECUTE;
                        end
                    end
                end

                S_READ_STK_LO: fsm_state <= S_WAIT_STK_LO;

                S_WAIT_STK_LO: begin
                    if (ext_cs && ACTIVE_AD_BUS) begin
                        ext_ale_reg <= 1'b1;
                        ext_io_m_reg <= 1'b0;
                        fsm_return <= S_WAIT_STK_LO;
                        fsm_state <= S_EXT_ALE;
                    end else if (!mem_ready) begin
                        // Wait
                    end else begin
                        stk_lo_buf <= ram_byte;
                        fetch_addr <= fetch_addr + 16'd1;
                        set_addr_decode(fetch_addr + 16'd1);
                        fsm_state <= S_READ_STK_HI;
                    end
                end

                S_READ_STK_HI: fsm_state <= S_WAIT_STK_HI;

                S_WAIT_STK_HI: begin
                    if (ext_cs && ACTIVE_AD_BUS) begin
                        ext_ale_reg <= 1'b1;
                        ext_io_m_reg <= 1'b0;
                        fsm_return <= S_WAIT_STK_HI;
                        fsm_state <= S_EXT_ALE;
                    end else if (!mem_ready) begin
                        // Wait
                    end else begin
                        stk_hi_buf <= ram_byte;
                        fsm_state <= S_EXECUTE;
                    end
                end

                S_EXECUTE: begin
                    execute_pulse <= 1'b1;
                    if (cpu_stack_wr) begin
                        set_addr_decode(cpu_stack_wr_addr);
                        ram_wdata <= {cpu_stack_wr_hi, cpu_stack_wr_lo};
                        ram_we <= cpu_stack_wr_addr[0] ? 4'b1100 : 4'b0011;
                        fsm_state <= S_WRITE_STK;
                    end else if (cpu_mem_wr) begin
                        set_addr_decode(cpu_mem_addr);
                        if (ext_cs && ACTIVE_AD_BUS) begin
                            ext_data_out_reg <= cpu_mem_data_out;
                            ext_ale_reg <= 1'b1;
                            ext_io_m_reg <= 1'b0;
                            fsm_return <= S_FETCH_OP;
                            fsm_state <= S_EXT_ALE;
                        end else begin
                            ram_wdata <= {cpu_mem_data_out, cpu_mem_data_out};
                            ram_we <= cpu_mem_addr[0] ? 4'b1100 : 4'b0011;
                            fsm_state <= S_FETCH_OP;
                        end
                    end else if (cpu_io_wr) begin
                        io_out_port <= cpu_io_port;
                        io_out_data <= cpu_io_data_out;
                        io_out_strobe <= 1'b1;
                        if (cpu_io_port == 8'hF0)
                            rom_bank_reg <= cpu_io_data_out;
                        else if (cpu_io_port == 8'hF1)
                            ram_bank_reg <= cpu_io_data_out[1:0];
                        fsm_state <= S_FETCH_OP;
                    end else begin
                        fsm_state <= S_FETCH_OP;
                    end
                end

                S_WRITE_STK: begin
                    if (cpu_stack_wr_addr[0] == 1'b0) begin
                        set_addr_decode(cpu_stack_wr_addr + 16'd2);
                        ram_wdata <= {cpu_stack_wr_hi, cpu_stack_wr_hi};
                        ram_we <= 4'b0011;
                    end
                    fsm_state <= S_FETCH_OP;
                end

                S_HALTED: begin
                    // Stay halted
                end

                // External bus read cycle
                S_EXT_ALE: begin
                    ext_ale_reg <= 1'b0;
                    ext_rd_reg <= 1'b1;
                    fsm_state <= S_EXT_RD;
                end

                S_EXT_RD: begin
                    ext_rd_reg <= 1'b1;
                    fsm_state <= S_EXT_RD_WAIT;
                end

                S_EXT_RD_WAIT: begin
                    if (ready || !ACTIVE_AD_BUS) begin
                        ext_rd_buf <= ext_data_in;
                        ext_rd_reg <= 1'b0;
                        fsm_state <= fsm_return;
                    end else begin
                        ext_rd_reg <= 1'b1;  // Keep read active
                    end
                end

                S_EXT_WR: begin
                    ext_wr_reg <= 1'b1;
                    ext_data_oe <= 1'b1;
                    fsm_state <= S_EXT_WR_WAIT;
                end

                S_EXT_WR_WAIT: begin
                    if (ready || !ACTIVE_AD_BUS) begin
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
    // CPU Core (via wrapper)
    // =========================================================================

    i8085_wrapper cpu (
        .clk(clk),
        .reset_n(reset_n),
        .mem_addr(cpu_mem_addr),
        .mem_data_in(ram_byte),
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
        .int_ack(1'b0),
        .int_vector(16'h0000),
        .int_is_trap(1'b0),
        .sid(1'b0),
        .rst55_level(1'b0),
        .rst65_level(1'b0),
        .pc(cpu_pc),
        .sp(cpu_sp),
        .reg_a(),
        .reg_b(cpu_wrapper_reg_b),
        .reg_c(cpu_wrapper_reg_c),
        .reg_d(),
        .reg_e(),
        .reg_h(),
        .reg_l(),
        .halted(cpu_halted),
        .inte(),
        .flag_z(),
        .flag_c(),
        .mask_55(),
        .mask_65(),
        .mask_75(),
        .rst75_pending(),
        .sod()
    );

    assign dbg_halted = cpu_halted;

endmodule
