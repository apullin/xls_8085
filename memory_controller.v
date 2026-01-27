// memory_controller.v - Unified memory routing for i8085sg
// Handles SPRAM banking, SPI flash cache, and peripheral routing
//
// Phase 3 of refactoring: extract memory handling from i8085sg.v

module memory_controller (
    input  wire        clk,
    input  wire        reset_n,

    // CPU Bus (slave interface)
    input  wire [15:0] cpu_addr,
    input  wire [7:0]  cpu_data_out,   // Data from CPU
    input  wire        cpu_rd,
    input  wire        cpu_wr,
    output wire [7:0]  cpu_data_in,    // Data to CPU
    output wire        cpu_ready,

    // Stack Write Bus (from CPU for CALL/PUSH/RST)
    input  wire [15:0] stack_wr_addr,
    input  wire [7:0]  stack_wr_data_lo,
    input  wire [7:0]  stack_wr_data_hi,
    input  wire        stack_wr,

    // Bank control (from CPU)
    input  wire [7:0]  rom_bank,
    input  wire [2:0]  ram_bank,

    // SPI Flash Interface
    output wire        spi_sck,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,

    // Peripheral Bus (directly routed)
    output wire [3:0]  periph_addr,
    output wire [7:0]  periph_wdata,
    output wire        periph_rd,
    output wire        periph_wr,
    output wire [3:0]  periph_slot,
    input  wire [7:0]  periph_rdata
);

    // =========================================================================
    // Address Decode
    // =========================================================================
    //
    // Memory map (16KB/16KB Game Boy style banking):
    //   0x0000-0x3EFF: Common RAM (16KB - 256B, always bank 0)
    //   0x3F00-0x3FFF: Peripheral registers (256B, in common)
    //   0x4000-0x7FFF: Banked RAM window (16KB, 7 banks)
    //   0x8000-0xFFFF: Banked ROM window (32KB, 256 banks)

    wire addr_is_periph = (cpu_addr[15:8] == 8'h3F);  // 0x3F00-0x3FFF
    wire addr_is_rom    = cpu_addr[15];               // 0x8000-0xFFFF
    wire addr_is_ram    = !addr_is_rom && !addr_is_periph;

    assign periph_slot = cpu_addr[7:4];
    assign periph_addr = cpu_addr[3:0];
    assign periph_wdata = cpu_data_out;
    assign periph_rd = cpu_rd && addr_is_periph;
    assign periph_wr = cpu_wr && addr_is_periph;

    // =========================================================================
    // SPRAM Banking
    // =========================================================================
    //
    // Physical layout (128KB total):
    //   SPRAM 0: Common (16KB) + Bank 1 (16KB)
    //   SPRAM 1: Bank 2 (16KB) + Bank 3 (16KB)
    //   SPRAM 2: Bank 4 (16KB) + Bank 5 (16KB)
    //   SPRAM 3: Bank 6 (16KB) + Bank 7 (16KB)
    //
    // Common region (addr[14]=0): physical_bank = 0
    // Banked region (addr[14]=1): physical_bank = bank_reg + 1 (1-7)

    wire [2:0] active_ram_bank = ram_bank + 3'd1;
    wire [2:0] physical_bank = {3{cpu_addr[14]}} & active_ram_bank;
    wire [1:0] ram_spram_sel = physical_bank[2:1];
    wire [13:0] ram_addr = {physical_bank[0], cpu_addr[13:1]};

    wire [3:0] ram_cs = (4'b0001 << ram_spram_sel);

    // SPRAM write data and write enable
    reg [15:0] ram_wdata;
    reg [3:0]  ram_we;

    wire [15:0] ram_rdata_0, ram_rdata_1, ram_rdata_2, ram_rdata_3;

    SB_SPRAM256KA ram_bank0 (
        .ADDRESS(ram_addr), .DATAIN(ram_wdata), .MASKWREN(ram_we),
        .WREN(|ram_we & ram_cs[0]), .CHIPSELECT(ram_cs[0]), .CLOCK(clk),
        .STANDBY(1'b0), .SLEEP(1'b0), .POWEROFF(1'b1), .DATAOUT(ram_rdata_0)
    );
    SB_SPRAM256KA ram_bank1 (
        .ADDRESS(ram_addr), .DATAIN(ram_wdata), .MASKWREN(ram_we),
        .WREN(|ram_we & ram_cs[1]), .CHIPSELECT(ram_cs[1]), .CLOCK(clk),
        .STANDBY(1'b0), .SLEEP(1'b0), .POWEROFF(1'b1), .DATAOUT(ram_rdata_1)
    );
    SB_SPRAM256KA ram_bank2 (
        .ADDRESS(ram_addr), .DATAIN(ram_wdata), .MASKWREN(ram_we),
        .WREN(|ram_we & ram_cs[2]), .CHIPSELECT(ram_cs[2]), .CLOCK(clk),
        .STANDBY(1'b0), .SLEEP(1'b0), .POWEROFF(1'b1), .DATAOUT(ram_rdata_2)
    );
    SB_SPRAM256KA ram_bank3 (
        .ADDRESS(ram_addr), .DATAIN(ram_wdata), .MASKWREN(ram_we),
        .WREN(|ram_we & ram_cs[3]), .CHIPSELECT(ram_cs[3]), .CLOCK(clk),
        .STANDBY(1'b0), .SLEEP(1'b0), .POWEROFF(1'b1), .DATAOUT(ram_rdata_3)
    );

    // Latch SPRAM select for read data mux (SPRAM has 1-cycle latency)
    reg [1:0] ram_spram_latch;
    always @(posedge clk) ram_spram_latch <= ram_spram_sel;

    wire [15:0] ram_rdata = ram_rdata_0 & {16{ram_spram_latch == 2'd0}} |
                            ram_rdata_1 & {16{ram_spram_latch == 2'd1}} |
                            ram_rdata_2 & {16{ram_spram_latch == 2'd2}} |
                            ram_rdata_3 & {16{ram_spram_latch == 2'd3}};

    // Select byte from 16-bit word
    reg addr_lsb_latch;
    always @(posedge clk) addr_lsb_latch <= cpu_addr[0];
    wire [7:0] ram_byte = addr_lsb_latch ? ram_rdata[15:8] : ram_rdata[7:0];

    // =========================================================================
    // SPI Flash Cache
    // =========================================================================

    reg        rom_rd_strobe;
    wire [7:0] cache_rom_data;
    wire       cache_rom_ready;

    spi_flash_cache flash_cache (
        .clk(clk), .reset_n(reset_n),
        .rom_addr(cpu_addr[14:0]), .rom_rd(rom_rd_strobe),
        .rom_data(cache_rom_data), .rom_ready(cache_rom_ready),
        .bank_sel(rom_bank),
        .spi_sck(spi_sck), .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi), .spi_miso(spi_miso)
    );

    // Trigger ROM read when CPU requests ROM address
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            rom_rd_strobe <= 1'b0;
        else
            rom_rd_strobe <= cpu_rd && addr_is_rom;
    end

    // =========================================================================
    // Read Data Mux
    // =========================================================================

    assign cpu_data_in = addr_is_rom    ? cache_rom_data :
                         addr_is_periph ? periph_rdata   :
                         ram_byte;

    // SPRAM has 1-cycle latency: address latched on cycle T, data valid cycle T+1
    // cpu_ready must account for this
    reg ram_ready_delay;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            ram_ready_delay <= 1'b0;
        else
            ram_ready_delay <= cpu_rd && addr_is_ram;
    end

    assign cpu_ready = addr_is_rom    ? cache_rom_ready :
                       addr_is_ram    ? ram_ready_delay :
                       1'b1;  // Peripherals are combinational

    // =========================================================================
    // Write Handling
    // =========================================================================

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ram_wdata <= 16'd0;
            ram_we <= 4'b0000;
        end else begin
            ram_we <= 4'b0000;  // Default: no write

            // Normal memory write
            if (cpu_wr && addr_is_ram) begin
                ram_wdata <= {cpu_data_out, cpu_data_out};
                ram_we <= cpu_addr[0] ? 4'b1100 : 4'b0011;
            end

            // Stack write (16-bit, lo then hi)
            else if (stack_wr) begin
                ram_wdata <= {stack_wr_data_hi, stack_wr_data_lo};
                ram_we <= stack_wr_addr[0] ? 4'b1100 : 4'b0011;
                // Note: Unaligned stack writes need a second cycle
                // This is handled by the FSM in i8085_cpu
            end
        end
    end

endmodule
