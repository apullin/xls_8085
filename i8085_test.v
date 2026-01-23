// Intel 8085 Test/Validation Configuration for iCE40 UP5K
// Self-contained system for CPU validation and benchmarking
//
// This configuration has minimal external pins (unconstrained for max Fmax).
// Use for: CPU verification, running test programs, timing analysis.
//
// Memory Map:
//   0x0000-0x7FFF: RAM (32KB window into 128KB, 4 banks via port 0xF1)
//   0x8000-0xFFFF: ROM (32KB window into 8MB SPI flash, 256 banks via port 0xF0)
//
// I/O Ports:
//   0xF0: ROM bank register (8-bit, 256 banks × 32KB = 8MB)
//   0xF1: RAM bank register (2-bit, 4 banks × 32KB = 128KB)

module i8085_test (
    input  wire        clk,
    input  wire        reset_n,

    // I/O ports
    output reg  [7:0]  io_out_data,
    output reg  [7:0]  io_out_port,
    output reg         io_out_strobe,
    input  wire [7:0]  io_in_data,

    // SPI Flash Interface
    output wire        spi_sck,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,

    // Debug output (directly exposed to LED or similar)
    output wire        dbg_halted
);

    // =========================================================================
    // SPRAM - All 4 banks for 128KB total (banked as 4 × 32KB)
    // =========================================================================

    reg  [13:0] ram_addr;
    reg  [15:0] ram_wdata;
    reg  [3:0]  ram_we;
    wire [15:0] ram_rdata;

    // RAM chip selects - one per SPRAM bank
    reg         ram_cs_0;   // Bank 0
    reg         ram_cs_1;   // Bank 1
    reg         ram_cs_2;   // Bank 2
    reg         ram_cs_3;   // Bank 3

    wire [15:0] ram_rdata_0;
    wire [15:0] ram_rdata_1;
    wire [15:0] ram_rdata_2;
    wire [15:0] ram_rdata_3;

    // Bank 0 SPRAM (32KB)
    SB_SPRAM256KA ram_bank0 (
        .ADDRESS(ram_addr),
        .DATAIN(ram_wdata),
        .MASKWREN(ram_we),
        .WREN(|ram_we & ram_cs_0),
        .CHIPSELECT(ram_cs_0),
        .CLOCK(clk),
        .STANDBY(1'b0),
        .SLEEP(1'b0),
        .POWEROFF(1'b1),
        .DATAOUT(ram_rdata_0)
    );

    // Bank 1 SPRAM (32KB)
    SB_SPRAM256KA ram_bank1 (
        .ADDRESS(ram_addr),
        .DATAIN(ram_wdata),
        .MASKWREN(ram_we),
        .WREN(|ram_we & ram_cs_1),
        .CHIPSELECT(ram_cs_1),
        .CLOCK(clk),
        .STANDBY(1'b0),
        .SLEEP(1'b0),
        .POWEROFF(1'b1),
        .DATAOUT(ram_rdata_1)
    );

    // Bank 2 SPRAM (32KB)
    SB_SPRAM256KA ram_bank2 (
        .ADDRESS(ram_addr),
        .DATAIN(ram_wdata),
        .MASKWREN(ram_we),
        .WREN(|ram_we & ram_cs_2),
        .CHIPSELECT(ram_cs_2),
        .CLOCK(clk),
        .STANDBY(1'b0),
        .SLEEP(1'b0),
        .POWEROFF(1'b1),
        .DATAOUT(ram_rdata_2)
    );

    // Bank 3 SPRAM (32KB)
    SB_SPRAM256KA ram_bank3 (
        .ADDRESS(ram_addr),
        .DATAIN(ram_wdata),
        .MASKWREN(ram_we),
        .WREN(|ram_we & ram_cs_3),
        .CHIPSELECT(ram_cs_3),
        .CLOCK(clk),
        .STANDBY(1'b0),
        .SLEEP(1'b0),
        .POWEROFF(1'b1),
        .DATAOUT(ram_rdata_3)
    );

    // Mux RAM read data based on selected bank
    reg [1:0] ram_bank_latch;  // Latched bank for read mux
    always @(posedge clk) begin
        ram_bank_latch <= ram_bank_reg;
    end

    assign ram_rdata = (ram_bank_latch == 2'd0) ? ram_rdata_0 :
                       (ram_bank_latch == 2'd1) ? ram_rdata_1 :
                       (ram_bank_latch == 2'd2) ? ram_rdata_2 : ram_rdata_3;

    // ROM chip select (active when accessing upper 32KB: 0x8000-0xFFFF)
    reg rom_cs;
    reg rom_rd_reg;

    // =========================================================================
    // Bank Registers
    // =========================================================================

    reg  [7:0]  rom_bank_reg;     // ROM bank (256 banks × 32KB = 8MB) - port 0xF0
    reg  [1:0]  ram_bank_reg;     // RAM bank (4 banks × 32KB = 128KB) - port 0xF1

    // =========================================================================
    // SPI Flash Cache
    // =========================================================================

    wire [7:0]  cache_rom_data;
    wire        cache_rom_ready;

    spi_flash_cache flash_cache (
        .clk(clk),
        .reset_n(reset_n),
        .rom_addr(fetch_addr[14:0]),
        .rom_rd(rom_rd_reg),
        .rom_data(cache_rom_data),
        .rom_ready(cache_rom_ready),
        .bank_sel(rom_bank_reg),
        .spi_sck(spi_sck),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso)
    );

    // ROM ready signal from cache
    wire rom_ready = cache_rom_ready;

    // =========================================================================
    // CPU Interface Signals
    // =========================================================================

    wire [15:0] cpu_mem_addr;
    wire [7:0]  cpu_mem_data_out;
    wire        cpu_mem_wr;

    wire [15:0] cpu_stack_wr_addr;
    wire [7:0]  cpu_stack_wr_lo;
    wire [7:0]  cpu_stack_wr_hi;
    wire        cpu_stack_wr;

    wire [7:0]  cpu_io_port;
    wire [7:0]  cpu_io_data_out;
    wire        cpu_io_rd;
    wire        cpu_io_wr;

    wire [15:0] cpu_pc;
    wire [15:0] cpu_sp;
    wire        cpu_halted;

    // =========================================================================
    // FSM States
    // =========================================================================

    localparam S_FETCH_OP       = 4'd0;
    localparam S_WAIT_OP        = 4'd1;
    localparam S_FETCH_IMM1     = 4'd2;
    localparam S_WAIT_IMM1      = 4'd3;
    localparam S_FETCH_IMM2     = 4'd4;
    localparam S_WAIT_IMM2      = 4'd5;
    localparam S_READ_MEM       = 4'd6;   // Read from HL/BC/DE/addr
    localparam S_WAIT_MEM       = 4'd7;
    localparam S_READ_STK_LO    = 4'd8;
    localparam S_WAIT_STK_LO    = 4'd9;
    localparam S_READ_STK_HI    = 4'd10;
    localparam S_WAIT_STK_HI    = 4'd11;
    localparam S_EXECUTE        = 4'd12;
    localparam S_WRITE_STK      = 4'd13;
    localparam S_HALTED         = 4'd14;

    reg [3:0]  fsm_state;
    reg [15:0] fetch_addr;
    reg [7:0]  fetched_op;
    reg [7:0]  fetched_imm1;
    reg [7:0]  fetched_imm2;
    reg        execute_pulse;

    // Memory/stack read buffers
    reg [7:0]  mem_rd_buf;
    reg [7:0]  stk_lo_buf;
    reg [7:0]  stk_hi_buf;

    // I/O read buffer
    reg [7:0]  io_rd_buf;

    // =========================================================================
    // Instruction Decode Helpers
    // =========================================================================

    // Instruction length
    function [1:0] inst_len;
        input [7:0] op;
        casez (op)
            8'b00??0001,                        // LXI
            8'b11000011, 8'b11??0010,           // JMP, Jcond
            8'b11001101, 8'b11??0100,           // CALL, Ccond
            8'b0011?010, 8'b0010?010:           // STA/LDA, SHLD/LHLD
                inst_len = 2'd3;
            8'b00???110, 8'b11???110,           // MVI, imm ALU
            8'b1101?011:                        // IN/OUT
                inst_len = 2'd2;
            default:
                inst_len = 2'd1;
        endcase
    endfunction

    // Needs memory read from HL?
    function needs_hl_read;
        input [7:0] op;
        casez (op)
            8'b01???110,                        // MOV r,M
            8'b10???110,                        // ALU M (ADD/ADC/SUB/SBB/ANA/XRA/ORA/CMP M)
            8'b00110100, 8'b00110101:           // INR M, DCR M
                needs_hl_read = 1'b1;
            default:
                needs_hl_read = 1'b0;
        endcase
    endfunction

    // Needs memory read from BC?
    function needs_bc_read;
        input [7:0] op;
        needs_bc_read = (op == 8'h0A);  // LDAX BC
    endfunction

    // Needs memory read from DE?
    function needs_de_read;
        input [7:0] op;
        needs_de_read = (op == 8'h1A);  // LDAX DE
    endfunction

    // Needs memory read from direct address?
    function needs_direct_read;
        input [7:0] op;
        needs_direct_read = (op == 8'h3A) || (op == 8'h2A);  // LDA, LHLD
    endfunction

    // Needs stack read?
    function needs_stack_read;
        input [7:0] op;
        casez (op)
            8'b11001001,                        // RET
            8'b11???000,                        // Rcond
            8'b11??0001,                        // POP
            8'b11100011:                        // XTHL
                needs_stack_read = 1'b1;
            default:
                needs_stack_read = 1'b0;
        endcase
    endfunction

    // Needs I/O read?
    function needs_io_read;
        input [7:0] op;
        needs_io_read = (op == 8'hDB);  // IN
    endfunction

    // =========================================================================
    // Byte select from 16-bit RAM word or ROM data
    // =========================================================================

    wire [7:0] ram_word_byte = fetch_addr[0] ? ram_rdata[15:8] : ram_rdata[7:0];
    wire [7:0] ram_byte = rom_cs ? cache_rom_data : ram_word_byte;

    // =========================================================================
    // Address Decode Helper Task
    // =========================================================================

    // Set chip selects based on address and bank registers
    task set_addr_decode;
        input [15:0] addr;
        begin
            ram_addr <= addr[14:1];
            if (addr[15] == 1'b0) begin
                // Lower 32KB: RAM (banked via ram_bank_reg)
                ram_cs_0 <= (ram_bank_reg == 2'd0);
                ram_cs_1 <= (ram_bank_reg == 2'd1);
                ram_cs_2 <= (ram_bank_reg == 2'd2);
                ram_cs_3 <= (ram_bank_reg == 2'd3);
                rom_cs <= 1'b0;
            end else begin
                // Upper 32KB: ROM from SPI flash
                ram_cs_0 <= 1'b0;
                ram_cs_1 <= 1'b0;
                ram_cs_2 <= 1'b0;
                ram_cs_3 <= 1'b0;
                rom_cs <= 1'b1;
                rom_rd_reg <= 1'b1;
            end
        end
    endtask

    // =========================================================================
    // FSM Logic
    // =========================================================================

    // Compute memory read address based on opcode
    wire [15:0] hl_addr = {cpu_wrapper_reg_h, cpu_wrapper_reg_l};
    wire [15:0] bc_addr = {cpu_wrapper_reg_b, cpu_wrapper_reg_c};
    wire [15:0] de_addr = {cpu_wrapper_reg_d, cpu_wrapper_reg_e};
    wire [15:0] direct_addr = {fetched_imm2, fetched_imm1};

    // CPU register access (exposed from wrapper for address calculation)
    wire [7:0] cpu_wrapper_reg_b, cpu_wrapper_reg_c;
    wire [7:0] cpu_wrapper_reg_h = 8'h00;  // Will connect later if needed
    wire [7:0] cpu_wrapper_reg_l = 8'h00;
    wire [7:0] cpu_wrapper_reg_d = 8'h00;
    wire [7:0] cpu_wrapper_reg_e = 8'h00;

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
            ram_addr <= 14'd0;
            ram_wdata <= 16'd0;
            ram_we <= 4'b0000;
            ram_cs_0 <= 1'b0;
            ram_cs_1 <= 1'b0;
            ram_cs_2 <= 1'b0;
            ram_cs_3 <= 1'b0;
            rom_cs <= 1'b0;
            rom_rd_reg <= 1'b0;
            rom_bank_reg <= 8'h00;
            ram_bank_reg <= 2'b00;
            io_out_data <= 8'h00;
            io_out_port <= 8'h00;
            io_out_strobe <= 1'b0;
        end else begin
            execute_pulse <= 1'b0;
            ram_we <= 4'b0000;
            io_out_strobe <= 1'b0;
            rom_rd_reg <= 1'b0;

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
                    // Wait for ROM ready if accessing ROM space
                    if (rom_cs && !rom_ready) begin
                        // Stay waiting for cache
                    end else begin
                        fetched_op <= ram_byte;
                        if (inst_len(ram_byte) >= 2'd2) begin
                            fetch_addr <= cpu_pc + 16'd1;
                            set_addr_decode(cpu_pc + 16'd1);
                            fsm_state <= S_FETCH_IMM1;
                        end else begin
                            // Check if we need memory/stack reads
                            if (needs_hl_read(ram_byte) || needs_bc_read(ram_byte) || needs_de_read(ram_byte)) begin
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
                end

                S_FETCH_IMM1: begin
                    fsm_state <= S_WAIT_IMM1;
                end

                S_WAIT_IMM1: begin
                    // Wait for ROM ready if accessing ROM space
                    if (rom_cs && !rom_ready) begin
                        // Stay waiting for cache
                    end else begin
                        fetched_imm1 <= ram_byte;
                        if (inst_len(fetched_op) >= 2'd3) begin
                            fetch_addr <= cpu_pc + 16'd2;
                            set_addr_decode(cpu_pc + 16'd2);
                            fsm_state <= S_FETCH_IMM2;
                        end else begin
                            // Check for I/O read (IN instruction)
                            if (needs_io_read(fetched_op)) begin
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
                end

                S_FETCH_IMM2: begin
                    fsm_state <= S_WAIT_IMM2;
                end

                S_WAIT_IMM2: begin
                    // Wait for ROM ready if accessing ROM space
                    if (rom_cs && !rom_ready) begin
                        // Stay waiting for cache
                    end else begin
                        fetched_imm2 <= ram_byte;
                        // Check for direct memory read (LDA, LHLD)
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

                S_READ_MEM: begin
                    fsm_state <= S_WAIT_MEM;
                end

                S_WAIT_MEM: begin
                    // Wait for ROM ready if accessing ROM space
                    if (rom_cs && !rom_ready) begin
                        // Stay waiting for cache
                    end else begin
                        mem_rd_buf <= ram_byte;
                        // For LHLD, we need to read second byte
                        if (fetched_op == 8'h2A) begin
                            // LHLD: read H from addr+1
                            fetch_addr <= direct_addr + 16'd1;
                            set_addr_decode(direct_addr + 16'd1);
                            fsm_state <= S_READ_STK_LO;  // Reuse for second byte
                        end else if (needs_stack_read(fetched_op)) begin
                            fetch_addr <= cpu_sp;
                            set_addr_decode(cpu_sp);
                            fsm_state <= S_READ_STK_LO;
                        end else begin
                            fsm_state <= S_EXECUTE;
                        end
                    end
                end

                S_READ_STK_LO: begin
                    fsm_state <= S_WAIT_STK_LO;
                end

                S_WAIT_STK_LO: begin
                    // Wait for ROM ready if accessing ROM space
                    if (rom_cs && !rom_ready) begin
                        // Stay waiting for cache
                    end else begin
                        stk_lo_buf <= ram_byte;
                        fetch_addr <= fetch_addr + 16'd1;
                        set_addr_decode(fetch_addr + 16'd1);
                        fsm_state <= S_READ_STK_HI;
                    end
                end

                S_READ_STK_HI: begin
                    fsm_state <= S_WAIT_STK_HI;
                end

                S_WAIT_STK_HI: begin
                    // Wait for ROM ready if accessing ROM space
                    if (rom_cs && !rom_ready) begin
                        // Stay waiting for cache
                    end else begin
                        stk_hi_buf <= ram_byte;
                        fsm_state <= S_EXECUTE;
                    end
                end

                S_EXECUTE: begin
                    execute_pulse <= 1'b1;

                    // Handle stack write from CPU
                    if (cpu_stack_wr) begin
                        // Write low byte to SP, high byte to SP+1
                        set_addr_decode(cpu_stack_wr_addr);
                        ram_wdata <= {cpu_stack_wr_hi, cpu_stack_wr_lo};
                        ram_we <= cpu_stack_wr_addr[0] ? 4'b1100 : 4'b0011;
                        fsm_state <= S_WRITE_STK;
                    end
                    // Handle memory write from CPU
                    else if (cpu_mem_wr) begin
                        set_addr_decode(cpu_mem_addr);
                        ram_wdata <= {cpu_mem_data_out, cpu_mem_data_out};
                        ram_we <= cpu_mem_addr[0] ? 4'b1100 : 4'b0011;
                        fsm_state <= S_FETCH_OP;
                    end
                    // Handle I/O write
                    else if (cpu_io_wr) begin
                        io_out_port <= cpu_io_port;
                        io_out_data <= cpu_io_data_out;
                        io_out_strobe <= 1'b1;
                        // Check for bank register writes
                        if (cpu_io_port == 8'hF0) begin
                            rom_bank_reg <= cpu_io_data_out;  // ROM bank (8-bit)
                        end else if (cpu_io_port == 8'hF1) begin
                            ram_bank_reg <= cpu_io_data_out[1:0];  // RAM bank (2-bit)
                        end
                        fsm_state <= S_FETCH_OP;
                    end
                    else begin
                        fsm_state <= S_FETCH_OP;
                    end
                end

                S_WRITE_STK: begin
                    // Write second byte of stack (hi byte to SP+1)
                    if (cpu_stack_wr_addr[0] == 1'b0) begin
                        // First write was aligned, now write hi byte
                        set_addr_decode(cpu_stack_wr_addr + 16'd2);
                        ram_wdata <= {cpu_stack_wr_hi, cpu_stack_wr_hi};
                        ram_we <= 4'b0011;
                    end
                    fsm_state <= S_FETCH_OP;
                end

                S_HALTED: begin
                    // Stay halted until reset
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

        // Memory bus
        .mem_addr(cpu_mem_addr),
        .mem_data_in(ram_byte),
        .mem_data_out(cpu_mem_data_out),
        .mem_rd(),
        .mem_wr(cpu_mem_wr),

        // Stack write bus
        .stack_wr_addr(cpu_stack_wr_addr),
        .stack_wr_data_lo(cpu_stack_wr_lo),
        .stack_wr_data_hi(cpu_stack_wr_hi),
        .stack_wr(cpu_stack_wr),

        // I/O bus
        .io_port(cpu_io_port),
        .io_data_out(cpu_io_data_out),
        .io_data_in(io_rd_buf),
        .io_rd(cpu_io_rd),
        .io_wr(cpu_io_wr),

        // Instruction bytes
        .opcode(fetched_op),
        .imm1(fetched_imm1),
        .imm2(fetched_imm2),

        // Memory read data
        .mem_read_data(mem_rd_buf),

        // Stack read data
        .stack_lo(stk_lo_buf),
        .stack_hi(stk_hi_buf),

        // Execute pulse
        .execute(execute_pulse),

        // Interrupt control (directly tie off for basic SoC - no IRQ support yet)
        .int_ack(1'b0),
        .int_vector(16'h0000),
        .int_is_trap(1'b0),

        // Interrupt inputs (directly wired for RIM instruction)
        .sid(1'b0),
        .rst55_level(1'b0),
        .rst65_level(1'b0),

        // Status
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

        // Interrupt status (directly tie off for basic SoC)
        .mask_55(),
        .mask_65(),
        .mask_75(),
        .rst75_pending(),
        .sod()
    );

    // Debug output
    assign dbg_halted = cpu_halted;

endmodule
