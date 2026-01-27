// i8085sg.v - "System General" MCU variant
// 2x userial (UART/SPI), 12 GPIO, 4 PWM (center-aligned), imath_lite, I2C
// Uses: timer-v-pwm.v, gpio-v.v, gpio4-v.v, userial-v.v
//
// Build-time config (inclusive):
//   -DHAS_GPIO1     Enable 4-bit GPIO1 (~60 LCs)
//   -DHAS_USERIAL1  Enable second userial as full UART/SPI (~500 LCs)
//   -DHAS_SPI1      Enable second serial as SPI-only (~230 LCs, mutually exclusive with USERIAL1)

module i8085sg (
    input  wire        clk,
    input  wire        reset_n,

    // Interrupts
    input  wire        trap,
    input  wire        rst75,
    input  wire        rst65,
    input  wire        rst55,

    // Serial I/O
    input  wire        sid,
    output wire        sod,

    // SPI Flash
    output wire        spi_sck,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,

    // Timer (4 PWM channels, center-aligned in up-down mode)
    output wire        timer0_irq,
    output wire        pwm0,
    output wire        pwm1,
    output wire        pwm2,
    output wire        pwm3,

    // GPIO 0 (8-bit)
    input  wire [7:0]  gpio0_in,
    output wire [7:0]  gpio0_out,
    output wire [7:0]  gpio0_oe,

    // GPIO 1 (4-bit only)
    input  wire [3:0]  gpio1_in,
    output wire [3:0]  gpio1_out,
    output wire [3:0]  gpio1_oe,

    // Universal Serial (UART/SPI switchable)
    input  wire        userial0_rx_miso,
    output wire        userial0_tx_mosi,
    output wire        userial0_sck,
    output wire        userial0_cs_n,

    // Universal Serial 1 (UART/SPI switchable)
    input  wire        userial1_rx_miso,
    output wire        userial1_tx_mosi,
    output wire        userial1_sck,
    output wire        userial1_cs_n,

    // I2C0
    input  wire        i2c0_sda_in,
    output wire        i2c0_sda_out,
    output wire        i2c0_sda_oe,
    input  wire        i2c0_scl_in,
    output wire        i2c0_scl_out,
    output wire        i2c0_scl_oe
);

    // I/O Ports
    localparam [7:0] PORT_ROM_BANK = 8'hF0;
    localparam [7:0] PORT_RAM_BANK = 8'hF1;

    // Address decode
    // Memory map (16KB/16KB Game Boy style banking):
    //   0x0000-0x3EFF: Common RAM (16KB - 256B, always bank 0)
    //   0x3F00-0x3FFF: Peripheral registers (256B, in common)
    //   0x4000-0x7FFF: Banked RAM window (16KB, 7 banks)
    //   0x8000-0xFFFF: Banked ROM window (32KB, 256 banks)

    // Forward declarations (needed for iverilog compatibility)
    reg [15:0] fetch_addr;
    wire periph_rd_strobe, periph_wr_strobe;

    // Read path uses fetch_addr (instruction fetch)
    wire        addr_is_periph = (fetch_addr[15:8] == 8'h3F);  // 0x3F00-0x3FFF
    wire        addr_is_rom    = fetch_addr[15];                // 0x8000-0xFFFF
    wire [3:0]  periph_slot    = fetch_addr[7:4];

    wire sel_timer0   = addr_is_periph && (periph_slot == 4'h0);
    wire sel_gpio0    = addr_is_periph && (periph_slot == 4'h1);
    wire sel_userial0 = addr_is_periph && (periph_slot == 4'h2);
    wire sel_userial1 = addr_is_periph && (periph_slot == 4'h3);
    wire sel_gpio1    = addr_is_periph && (periph_slot == 4'h4);
    wire sel_i2c0     = addr_is_periph && (periph_slot == 4'h5);
    wire sel_imath    = addr_is_periph && (periph_slot == 4'h6);

    // Write path uses cpu_mem_addr (memory operation address from CPU)
    // Forward declare cpu_mem_addr for write decode
    wire [15:0] cpu_mem_addr;
    wire        mem_addr_is_periph = (cpu_mem_addr[15:8] == 8'h3F);
    wire [3:0]  mem_periph_slot    = cpu_mem_addr[7:4];

    wire sel_timer0_wr   = mem_addr_is_periph && (mem_periph_slot == 4'h0);
    wire sel_gpio0_wr    = mem_addr_is_periph && (mem_periph_slot == 4'h1);
    wire sel_userial0_wr = mem_addr_is_periph && (mem_periph_slot == 4'h2);
    wire sel_userial1_wr = mem_addr_is_periph && (mem_periph_slot == 4'h3);
    wire sel_gpio1_wr    = mem_addr_is_periph && (mem_periph_slot == 4'h4);
    wire sel_i2c0_wr     = mem_addr_is_periph && (mem_periph_slot == 4'h5);
    wire sel_imath_wr    = mem_addr_is_periph && (mem_periph_slot == 4'h6);

    // SPRAM Banks with Game Boy style banking
    // Physical layout (128KB total):
    //   SPRAM 0: Common (16KB) + Bank 0 (16KB)
    //   SPRAM 1: Bank 1 (16KB) + Bank 2 (16KB)
    //   SPRAM 2: Bank 3 (16KB) + Bank 4 (16KB)
    //   SPRAM 3: Bank 5 (16KB) + Bank 6 (16KB)
    //
    // Physical address calculation:
    //   Common (0x0000-0x3FFF): physical = addr
    //   Banked (0x4000-0x7FFF): physical = (bank+1) << 14 | (addr & 0x3FFF)

    reg  [15:0] ram_wdata;
    reg  [3:0]  ram_we;
    wire [15:0] ram_rdata;
    reg  [2:0]  ram_bank_reg;   // 3 bits for 7 banks (0-6)

    // Single banker unit computes physical address from logical fetch_addr
    // Memory layout (128KB, 4x 32KB SPRAMs):
    //   SPRAM 0: Common (16KB) + Bank 1 (16KB)
    //   SPRAM 1: Bank 2 (16KB) + Bank 3 (16KB)
    //   SPRAM 2: Bank 4 (16KB) + Bank 5 (16KB)
    //   SPRAM 3: Bank 6 (16KB) + Bank 7 (16KB)
    // Common region (addr[14]=0): physical_bank = 0
    // Banked region (addr[14]=1): physical_bank = bank_reg + 1 (1-7)
    wire [2:0] active_ram_bank = ram_bank_reg + 3'd1;
    wire [2:0] physical_bank = {3{fetch_addr[14]}} & active_ram_bank;
    wire [1:0] ram_spram_sel = physical_bank[2:1];
    wire [13:0] ram_addr = {physical_bank[0], fetch_addr[13:1]};

    wire [3:0]  ram_cs = (4'b0001 << ram_spram_sel);

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

    assign ram_rdata = ram_rdata_0 & {16{ram_spram_latch == 2'd0}} |
                       ram_rdata_1 & {16{ram_spram_latch == 2'd1}} |
                       ram_rdata_2 & {16{ram_spram_latch == 2'd2}} |
                       ram_rdata_3 & {16{ram_spram_latch == 2'd3}};

    // Bank registers
    reg [7:0] rom_bank_reg;

    // Forward declaration for elaboration order
    reg        int_ack_pulse;

    // SPI Flash Cache
    reg        rom_rd_strobe;
    wire [7:0] cache_rom_data;
    wire       cache_rom_ready;

    spi_flash_cache flash_cache (
        .clk(clk), .reset_n(reset_n),
        .rom_addr(fetch_addr[14:0]), .rom_rd(rom_rd_strobe),
        .rom_data(cache_rom_data), .rom_ready(cache_rom_ready),
        .bank_sel(rom_bank_reg),
        .spi_sck(spi_sck), .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi), .spi_miso(spi_miso)
    );

    // Peripheral bus - address muxed between read path (fetch_addr) and write path (cpu_mem_addr)
    wire [3:0] periph_reg_addr = periph_wr_strobe ? cpu_mem_addr[3:0] : fetch_addr[3:0];
    // periph_wdata is combinational - connects directly to CPU write data
    // (must be valid when periph_wr_strobe fires, which is combinational)
    wire [7:0] periph_wdata;
    // periph_rd_strobe and periph_wr_strobe defined below after fsm_state

    // Read strobes use fetch_addr path (for memory read operations)
    wire timer0_rd   = periph_rd_strobe & sel_timer0;
    wire gpio0_rd    = periph_rd_strobe & sel_gpio0;
    wire gpio1_rd    = periph_rd_strobe & sel_gpio1;
    wire userial0_rd = periph_rd_strobe & sel_userial0;
    wire userial1_rd = periph_rd_strobe & sel_userial1;
    wire i2c0_rd     = periph_rd_strobe & sel_i2c0;
    wire imath_rd    = periph_rd_strobe & sel_imath;

    // Write strobes use cpu_mem_addr path (for memory write operations)
    wire timer0_wr   = periph_wr_strobe & sel_timer0_wr;
    wire gpio0_wr    = periph_wr_strobe & sel_gpio0_wr;
    wire gpio1_wr    = periph_wr_strobe & sel_gpio1_wr;
    wire userial0_wr = periph_wr_strobe & sel_userial0_wr;
    wire userial1_wr = periph_wr_strobe & sel_userial1_wr;
    wire i2c0_wr     = periph_wr_strobe & sel_i2c0_wr;
    wire imath_wr    = periph_wr_strobe & sel_imath_wr;

    wire [7:0] timer0_rdata, gpio0_rdata, gpio1_rdata, userial0_rdata, userial1_rdata, i2c0_rdata, imath_rdata;
    wire       timer0_irq_w, gpio0_irq, gpio1_irq, userial0_irq, userial1_irq, i2c0_irq;

    assign timer0_irq = timer0_irq_w;

    // Peripherals
    timer16_wrapper timer0 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_reg_addr), .data_in(periph_wdata), .data_out(timer0_rdata),
        .rd(timer0_rd), .wr(timer0_wr),
        .tick(1'b1), .irq(timer0_irq_w),
        .pwm0(pwm0), .pwm1(pwm1), .pwm2(pwm2), .pwm3(pwm3)
    );

    gpio8_wrapper gpio0 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_reg_addr), .data_in(periph_wdata), .data_out(gpio0_rdata),
        .rd(gpio0_rd), .wr(gpio0_wr),
        .pins_in(gpio0_in), .pins_out(gpio0_out), .pins_oe(gpio0_oe),
        .irq(gpio0_irq)
    );

`ifdef HAS_GPIO1
    // GPIO1 is only 4-bit - use dedicated gpio4_wrapper
    gpio4_wrapper gpio1 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_reg_addr), .data_in(periph_wdata), .data_out(gpio1_rdata),
        .rd(gpio1_rd), .wr(gpio1_wr),
        .pins_in(gpio1_in), .pins_out(gpio1_out), .pins_oe(gpio1_oe),
        .irq(gpio1_irq)
    );
`else
    assign gpio1_out = 4'b0;
    assign gpio1_oe = 4'b0;
    assign gpio1_rdata = 8'hFF;
    assign gpio1_irq = 1'b0;
`endif

    userial_wrapper userial0 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_reg_addr), .data_in(periph_wdata), .data_out(userial0_rdata),
        .rd(userial0_rd), .wr(userial0_wr),
        .rx_miso(userial0_rx_miso), .tx_mosi(userial0_tx_mosi),
        .sck(userial0_sck), .cs_n(userial0_cs_n),
        .irq(userial0_irq)
    );

`ifdef HAS_USERIAL1
    userial_wrapper userial1 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_reg_addr), .data_in(periph_wdata), .data_out(userial1_rdata),
        .rd(userial1_rd), .wr(userial1_wr),
        .rx_miso(userial1_rx_miso), .tx_mosi(userial1_tx_mosi),
        .sck(userial1_sck), .cs_n(userial1_cs_n),
        .irq(userial1_irq)
    );
`elsif HAS_SPI1
    // SPI-only variant saves ~270 LCs vs full userial
    spi_wrapper spi1 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_reg_addr), .data_in(periph_wdata), .data_out(userial1_rdata),
        .rd(userial1_rd), .wr(userial1_wr),
        .miso(userial1_rx_miso), .mosi(userial1_tx_mosi),
        .sck(userial1_sck), .cs_n(userial1_cs_n),
        .irq(userial1_irq)
    );
`else
    // Stub outputs when serial1 disabled
    assign userial1_tx_mosi = 1'b1;
    assign userial1_sck = 1'b0;
    assign userial1_cs_n = 1'b1;
    assign userial1_rdata = 8'hFF;
    assign userial1_irq = 1'b0;
`endif

    i2c_wrapper i2c0 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_reg_addr), .data_in(periph_wdata), .data_out(i2c0_rdata),
        .rd(i2c0_rd), .wr(i2c0_wr),
        .sda_in(i2c0_sda_in), .sda_out(i2c0_sda_out), .sda_oe(i2c0_sda_oe),
        .scl_in(i2c0_scl_in), .scl_out(i2c0_scl_out), .scl_oe(i2c0_scl_oe),
        .irq(i2c0_irq)
    );

    imath_lite_wrapper imath0 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_reg_addr), .data_in(periph_wdata), .data_out(imath_rdata),
        .rd(imath_rd), .wr(imath_wr)
    );

    // Interrupt controller
    reg rst75_prev, trap_prev;
    reg rst75_pending, trap_pending;
    reg intr_pending;

    wire [2:0] int_priority = timer0_irq_w  ? 3'd1 :
                              gpio0_irq     ? 3'd2 :
                              userial0_irq  ? 3'd3 :
                              userial1_irq     ? 3'd4 :
                              gpio1_irq     ? 3'd5 :
                              i2c0_irq      ? 3'd6 : 3'd0;
    wire [15:0] periph_int_vector = {10'b0, int_priority, 3'b000};

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
            if (rst75 && !rst75_prev) rst75_pending <= 1'b1;
            if ((trap && !trap_prev) || trap) trap_pending <= 1'b1;
            intr_pending <= timer0_irq_w | gpio0_irq | gpio1_irq | userial0_irq | userial1_irq | i2c0_irq;
            if (int_ack_pulse) begin
                if (trap_pending) trap_pending <= 1'b0;
                else if (rst75_pending) rst75_pending <= 1'b0;
            end
        end
    end

    // int_ack_pulse declared earlier for elaboration order

    // CPU interface (cpu_mem_addr declared earlier for write path decode)
    wire [7:0]  cpu_mem_data_out;
    assign periph_wdata = cpu_mem_data_out;  // Combinational for write timing
    wire        cpu_mem_wr;
    wire [15:0] cpu_stack_wr_addr;
    wire [7:0]  cpu_stack_wr_lo, cpu_stack_wr_hi;
    wire        cpu_stack_wr;
    wire [7:0]  cpu_io_port;
    wire [7:0]  cpu_io_data_out;
    wire        cpu_io_rd, cpu_io_wr;
    wire [15:0] cpu_pc, cpu_sp;
    wire [7:0]  cpu_reg_b, cpu_reg_c, cpu_reg_d, cpu_reg_e, cpu_reg_h, cpu_reg_l;
    wire [15:0] cpu_hl = {cpu_reg_h, cpu_reg_l};
    wire [15:0] cpu_bc = {cpu_reg_b, cpu_reg_c};
    wire [15:0] cpu_de = {cpu_reg_d, cpu_reg_e};
    wire        cpu_halted_wire;
    wire        cpu_inte;
    wire        cpu_sod;
    wire        cpu_mask_55, cpu_mask_65, cpu_mask_75;

    assign sod = cpu_sod;

    // FSM
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
    // fetch_addr declared earlier for elaboration order

    // Combinational peripheral strobes - FSM doesn't need to know about peripherals
    // Wait states are: 1,3,5,7,9,11 (odd, except 13 which is S_WRITE_STK)
    wire in_wait_state = fsm_state[0] && (fsm_state != S_WRITE_STK);
    assign periph_rd_strobe = in_wait_state && addr_is_periph;
    assign periph_wr_strobe = (fsm_state == S_EXECUTE) && cpu_mem_wr && mem_addr_is_periph;

    reg [7:0]  fetched_op;
    reg [7:0]  fetched_imm1;
    reg [7:0]  fetched_imm2;
    reg        execute_pulse;
    reg [7:0]  mem_rd_buf;
    reg [7:0]  stk_lo_buf, stk_hi_buf;
    reg [7:0]  io_rd_buf;

    // Data mux
    wire [7:0] ram_word_byte = fetch_addr[0] ? ram_rdata[15:8] : ram_rdata[7:0];

    wire [7:0] periph_rdata = ({8{sel_timer0}}   & timer0_rdata)   |
                              ({8{sel_gpio0}}    & gpio0_rdata)    |
                              ({8{sel_gpio1}}    & gpio1_rdata)    |
                              ({8{sel_userial0}} & userial0_rdata) |
                              ({8{sel_userial1}}    & userial1_rdata)    |
                              ({8{sel_i2c0}}     & i2c0_rdata)     |
                              ({8{sel_imath}}    & imath_rdata);

    wire [7:0] mem_byte = addr_is_rom    ? cache_rom_data :
                          addr_is_periph ? periph_rdata   :
                          ram_word_byte;

    wire mem_ready = addr_is_rom ? cache_rom_ready : 1'b1;
    wire [15:0] direct_addr = {fetched_imm2, fetched_imm1};

    // Instruction decode - use shared decode module
    // In S_WAIT_OP, decode incoming mem_byte (opcode not yet latched)
    // In all other states, decode fetched_op (latched opcode)
    wire [7:0] decode_opcode = (fsm_state == S_WAIT_OP) ? mem_byte : fetched_op;

    wire [1:0] dec_inst_len;
    wire       dec_needs_hl_read;
    wire       dec_needs_bc_read;
    wire       dec_needs_de_read;
    wire       dec_needs_direct_read;
    wire       dec_needs_stack_read;
    wire       dec_needs_io_read;

    i8085_decode decoder (
        .opcode(decode_opcode),
        .inst_len(dec_inst_len),
        .needs_hl_read(dec_needs_hl_read),
        .needs_bc_read(dec_needs_bc_read),
        .needs_de_read(dec_needs_de_read),
        .needs_direct_read(dec_needs_direct_read),
        .needs_stack_read(dec_needs_stack_read),
        .needs_io_read(dec_needs_io_read)
    );

    // FSM logic
    // Flag to ensure we wait one cycle after execute for cpu_pc to update
    reg pc_wait_done;

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
            ram_wdata <= 16'd0;
            ram_we <= 4'b0000;
            rom_bank_reg <= 8'h00;
            ram_bank_reg <= 3'b000;
            rom_rd_strobe <= 1'b0;
            int_ack_pulse <= 1'b0;
            pc_wait_done <= 1'b1;  // Start with wait done (first fetch is special)
        end else begin
            execute_pulse <= 1'b0;
            ram_we <= 4'b0000;
            rom_rd_strobe <= 1'b0;
            int_ack_pulse <= 1'b0;

            case (fsm_state)
                S_FETCH_OP: begin
                    // First entry after execute: wait one cycle for cpu_pc to update
                    // Second entry: now cpu_pc is valid, proceed with fetch
                    if (!pc_wait_done) begin
                        pc_wait_done <= 1'b1;
                        // Just wait, don't read cpu_pc yet
                    end else if (cpu_halted_wire) begin
                        fsm_state <= S_HALTED;
                    end else begin
                        fetch_addr <= cpu_pc;
                        rom_rd_strobe <= cpu_pc[15];
                        fsm_state <= S_WAIT_OP;
                    end
                end

                S_WAIT_OP: begin
                    if (mem_ready) begin
                        fetched_op <= mem_byte;
                        if (dec_inst_len >= 2'd2) begin
                            fetch_addr <= cpu_pc + 16'd1;
                            rom_rd_strobe <= cpu_pc[15];
                            fsm_state <= S_FETCH_IMM1;
                        end else if (dec_needs_hl_read) begin
                            fetch_addr <= cpu_hl;
                            rom_rd_strobe <= cpu_hl[15];
                            fsm_state <= S_READ_MEM;
                        end else if (dec_needs_bc_read) begin
                            fetch_addr <= cpu_bc;
                            rom_rd_strobe <= cpu_bc[15];
                            fsm_state <= S_READ_MEM;
                        end else if (dec_needs_de_read) begin
                            fetch_addr <= cpu_de;
                            rom_rd_strobe <= cpu_de[15];
                            fsm_state <= S_READ_MEM;
                        end
                        else if (dec_needs_stack_read) begin
                            fetch_addr <= cpu_sp;
                            fsm_state <= S_READ_STK_LO;
                        end else
                            fsm_state <= S_EXECUTE;
                    end
                end

                S_FETCH_IMM1: fsm_state <= S_WAIT_IMM1;

                S_WAIT_IMM1: begin
                    if (mem_ready) begin
                        fetched_imm1 <= mem_byte;
                        if (dec_inst_len >= 2'd3) begin
                            fetch_addr <= cpu_pc + 16'd2;
                            rom_rd_strobe <= cpu_pc[15];
                            fsm_state <= S_FETCH_IMM2;
                        end else if (dec_needs_io_read) begin
                            io_rd_buf <= 8'hFF;
                            fsm_state <= S_EXECUTE;
                        end else if (dec_needs_hl_read) begin
                            fetch_addr <= cpu_hl;
                            rom_rd_strobe <= cpu_hl[15];
                            fsm_state <= S_READ_MEM;
                        end else if (dec_needs_bc_read) begin
                            fetch_addr <= cpu_bc;
                            rom_rd_strobe <= cpu_bc[15];
                            fsm_state <= S_READ_MEM;
                        end else if (dec_needs_de_read) begin
                            fetch_addr <= cpu_de;
                            rom_rd_strobe <= cpu_de[15];
                            fsm_state <= S_READ_MEM;
                        end else if (dec_needs_stack_read) begin
                            fetch_addr <= cpu_sp;
                            fsm_state <= S_READ_STK_LO;
                        end else
                            fsm_state <= S_EXECUTE;
                    end
                end

                S_FETCH_IMM2: fsm_state <= S_WAIT_IMM2;

                S_WAIT_IMM2: begin
                    if (mem_ready) begin
                        fetched_imm2 <= mem_byte;
                        if (dec_needs_direct_read) begin
                            fetch_addr <= {mem_byte, fetched_imm1};
                            rom_rd_strobe <= mem_byte[7];
                            fsm_state <= S_READ_MEM;
                        end else if (dec_needs_stack_read) begin
                            fetch_addr <= cpu_sp;
                            fsm_state <= S_READ_STK_LO;
                        end else
                            fsm_state <= S_EXECUTE;
                    end
                end

                S_READ_MEM: fsm_state <= S_WAIT_MEM;

                S_WAIT_MEM: begin
                    if (mem_ready) begin
                        mem_rd_buf <= mem_byte;
                        if (fetched_op == 8'h2A) begin
                            fetch_addr <= direct_addr + 16'd1;
                            fsm_state <= S_READ_STK_LO;
                        end else if (dec_needs_stack_read) begin
                            fetch_addr <= cpu_sp;
                            fsm_state <= S_READ_STK_LO;
                        end else
                            fsm_state <= S_EXECUTE;
                    end
                end

                S_READ_STK_LO: fsm_state <= S_WAIT_STK_LO;

                S_WAIT_STK_LO: begin
                    if (mem_ready) begin
                        stk_lo_buf <= mem_byte;
                        fetch_addr <= fetch_addr + 16'd1;
                        fsm_state <= S_READ_STK_HI;
                    end
                end

                S_READ_STK_HI: fsm_state <= S_WAIT_STK_HI;

                S_WAIT_STK_HI: begin
                    if (mem_ready) begin
                        stk_hi_buf <= mem_byte;
                        fsm_state <= S_EXECUTE;
                    end
                end

                S_EXECUTE: begin
                    execute_pulse <= 1'b1;
                    pc_wait_done <= 1'b0;  // Need to wait for cpu_pc update
                    if (cpu_stack_wr) begin
                        fetch_addr <= cpu_stack_wr_addr;
                        ram_wdata <= {cpu_stack_wr_hi, cpu_stack_wr_lo};
                        ram_we <= cpu_stack_wr_addr[0] ? 4'b1100 : 4'b0011;
                        fsm_state <= S_WRITE_STK;
                    end else if (cpu_mem_wr) begin
                        fetch_addr <= cpu_mem_addr;
                        // RAM write: address < 0x8000 and not peripheral space
                        if (!cpu_mem_addr[15] && (cpu_mem_addr[15:8] != 8'h3F)) begin
                            ram_wdata <= {cpu_mem_data_out, cpu_mem_data_out};
                            ram_we <= cpu_mem_addr[0] ? 4'b1100 : 4'b0011;
                        end
                        // Peripheral write handled by combinational periph_wr_strobe
                        fsm_state <= S_FETCH_OP;
                    end else if (cpu_io_wr) begin
                        if (cpu_io_port == PORT_ROM_BANK)
                            rom_bank_reg <= cpu_io_data_out;
                        else if (cpu_io_port == PORT_RAM_BANK)
                            ram_bank_reg <= cpu_io_data_out[2:0];
                        fsm_state <= S_FETCH_OP;
                    end else
                        fsm_state <= S_FETCH_OP;
                end

                S_WRITE_STK: begin
                    if (cpu_stack_wr_addr[0] == 1'b0) begin
                        // Unaligned: second write at address + 2
                        fetch_addr <= cpu_stack_wr_addr + 16'd2;
                        ram_wdata <= {cpu_stack_wr_hi, cpu_stack_wr_hi};
                        ram_we <= 4'b0011;
                    end
                    fsm_state <= S_FETCH_OP;
                    // pc_wait_done already cleared in S_EXECUTE
                end

                S_HALTED: begin
                    if (trap_pending || (cpu_inte && (rst75_pending || rst65 || rst55 || intr_pending)))
                        fsm_state <= S_FETCH_OP;
                end

                default: fsm_state <= S_FETCH_OP;
            endcase
        end
    end

    // CPU Core
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
                    intr_pending ? periph_int_vector : 16'h0000),
        .int_is_trap(trap_pending),
        .sid(sid),
        .rst55_level(rst55),
        .rst65_level(rst65),
        .pc(cpu_pc),
        .sp(cpu_sp),
        .reg_a(), .reg_b(cpu_reg_b), .reg_c(cpu_reg_c), .reg_d(cpu_reg_d), .reg_e(cpu_reg_e), .reg_h(cpu_reg_h), .reg_l(cpu_reg_l),
        .halted(cpu_halted_wire),
        .inte(cpu_inte),
        .flag_z(), .flag_c(),
        .mask_55(cpu_mask_55),
        .mask_65(cpu_mask_65),
        .mask_75(cpu_mask_75),
        .rst75_pending(),
        .sod(cpu_sod)
    );

endmodule
