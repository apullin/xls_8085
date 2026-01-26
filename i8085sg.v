// i8085sg.v - "System General" MCU variant
// 2x userial (UART/SPI), 12 GPIO, 4 PWM (center-aligned), imath_lite, I2C
// Uses: timer-v-pwm.v, gpio-v.v, gpio4-v.v, userial-v.v
// 5182 LCs (98%), 39 pins

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
    wire [15:0] decode_addr;
    wire        addr_is_periph = (decode_addr[15:8] == 8'h7F);
    wire        addr_is_rom    = decode_addr[15];
    wire        addr_is_ram    = !decode_addr[15] && !addr_is_periph;
    wire [3:0]  periph_slot    = decode_addr[7:4];

    wire sel_timer0   = addr_is_periph && (periph_slot == 4'h0);
    wire sel_gpio0    = addr_is_periph && (periph_slot == 4'h1);
    wire sel_userial0 = addr_is_periph && (periph_slot == 4'h2);
    wire sel_userial1 = addr_is_periph && (periph_slot == 4'h3);
    wire sel_gpio1    = addr_is_periph && (periph_slot == 4'h4);
    wire sel_i2c0     = addr_is_periph && (periph_slot == 4'h5);
    wire sel_imath    = addr_is_periph && (periph_slot == 4'h6);

    // SPRAM Banks
    reg  [13:0] ram_addr;
    reg  [15:0] ram_wdata;
    reg  [3:0]  ram_we;
    wire [15:0] ram_rdata;
    reg  [1:0]  ram_bank_reg;
    wire [3:0]  ram_cs = (4'b0001 << ram_bank_reg);

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

    reg [1:0] ram_bank_latch;
    always @(posedge clk) ram_bank_latch <= ram_bank_reg;

    assign ram_rdata = ram_rdata_0 & {16{ram_bank_latch == 2'd0}} |
                       ram_rdata_1 & {16{ram_bank_latch == 2'd1}} |
                       ram_rdata_2 & {16{ram_bank_latch == 2'd2}} |
                       ram_rdata_3 & {16{ram_bank_latch == 2'd3}};

    // Bank registers
    reg [7:0] rom_bank_reg;

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

    // Peripheral bus
    wire [3:0] periph_reg_addr = fetch_addr[3:0];
    reg  [7:0] periph_wdata;
    reg        periph_rd_strobe;
    reg        periph_wr_strobe;

    wire timer0_rd   = periph_rd_strobe & sel_timer0;
    wire timer0_wr   = periph_wr_strobe & sel_timer0;
    wire gpio0_rd    = periph_rd_strobe & sel_gpio0;
    wire gpio0_wr    = periph_wr_strobe & sel_gpio0;
    wire gpio1_rd    = periph_rd_strobe & sel_gpio1;
    wire gpio1_wr    = periph_wr_strobe & sel_gpio1;
    wire userial0_rd = periph_rd_strobe & sel_userial0;
    wire userial0_wr = periph_wr_strobe & sel_userial0;
    wire userial1_rd    = periph_rd_strobe & sel_userial1;
    wire userial1_wr    = periph_wr_strobe & sel_userial1;
    wire i2c0_rd     = periph_rd_strobe & sel_i2c0;
    wire i2c0_wr     = periph_wr_strobe & sel_i2c0;
    wire imath_rd    = periph_rd_strobe & sel_imath;
    wire imath_wr    = periph_wr_strobe & sel_imath;

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

    // GPIO1 is only 4-bit - use dedicated gpio4_wrapper
    gpio4_wrapper gpio1 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_reg_addr), .data_in(periph_wdata), .data_out(gpio1_rdata),
        .rd(gpio1_rd), .wr(gpio1_wr),
        .pins_in(gpio1_in), .pins_out(gpio1_out), .pins_oe(gpio1_oe),
        .irq(gpio1_irq)
    );

    userial_wrapper userial0 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_reg_addr), .data_in(periph_wdata), .data_out(userial0_rdata),
        .rd(userial0_rd), .wr(userial0_wr),
        .rx_miso(userial0_rx_miso), .tx_mosi(userial0_tx_mosi),
        .sck(userial0_sck), .cs_n(userial0_cs_n),
        .irq(userial0_irq)
    );

    userial_wrapper userial1 (
        .clk(clk), .reset_n(reset_n),
        .addr(periph_reg_addr), .data_in(periph_wdata), .data_out(userial1_rdata),
        .rd(userial1_rd), .wr(userial1_wr),
        .rx_miso(userial1_rx_miso), .tx_mosi(userial1_tx_mosi),
        .sck(userial1_sck), .cs_n(userial1_cs_n),
        .irq(userial1_irq)
    );

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

    reg int_ack_pulse;

    // CPU interface
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
    reg [15:0] fetch_addr;
    reg [7:0]  fetched_op;
    reg [7:0]  fetched_imm1;
    reg [7:0]  fetched_imm2;
    reg        execute_pulse;
    reg [7:0]  mem_rd_buf;
    reg [7:0]  stk_lo_buf, stk_hi_buf;
    reg [7:0]  io_rd_buf;

    assign decode_addr = fetch_addr;

    // Instruction decode
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

    // FSM logic
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
            rom_bank_reg <= 8'h00;
            ram_bank_reg <= 2'b00;
            periph_wdata <= 8'd0;
            periph_rd_strobe <= 1'b0;
            periph_wr_strobe <= 1'b0;
            rom_rd_strobe <= 1'b0;
            int_ack_pulse <= 1'b0;
        end else begin
            execute_pulse <= 1'b0;
            ram_we <= 4'b0000;
            rom_rd_strobe <= 1'b0;
            periph_rd_strobe <= 1'b0;
            periph_wr_strobe <= 1'b0;
            int_ack_pulse <= 1'b0;

            case (fsm_state)
                S_FETCH_OP: begin
                    if (cpu_halted_wire)
                        fsm_state <= S_HALTED;
                    else begin
                        fetch_addr <= cpu_pc;
                        ram_addr <= cpu_pc[14:1];
                        rom_rd_strobe <= cpu_pc[15];
                        fsm_state <= S_WAIT_OP;
                    end
                end

                S_WAIT_OP: begin
                    periph_rd_strobe <= addr_is_periph;
                    if (mem_ready) begin
                        fetched_op <= mem_byte;
                        if (inst_len(mem_byte) >= 2'd2) begin
                            fetch_addr <= cpu_pc + 16'd1;
                            ram_addr <= cpu_pc[14:1] + {13'd0, !cpu_pc[0]};
                            rom_rd_strobe <= cpu_pc[15];
                            fsm_state <= S_FETCH_IMM1;
                        end else if (needs_hl_read(mem_byte) || needs_bc_read(mem_byte) || needs_de_read(mem_byte))
                            fsm_state <= S_READ_MEM;
                        else if (needs_stack_read(mem_byte)) begin
                            fetch_addr <= cpu_sp;
                            ram_addr <= cpu_sp[14:1];
                            fsm_state <= S_READ_STK_LO;
                        end else
                            fsm_state <= S_EXECUTE;
                    end
                end

                S_FETCH_IMM1: fsm_state <= S_WAIT_IMM1;

                S_WAIT_IMM1: begin
                    periph_rd_strobe <= addr_is_periph;
                    if (mem_ready) begin
                        fetched_imm1 <= mem_byte;
                        if (inst_len(fetched_op) >= 2'd3) begin
                            fetch_addr <= cpu_pc + 16'd2;
                            ram_addr <= (cpu_pc + 16'd2) >> 1;
                            rom_rd_strobe <= cpu_pc[15];
                            fsm_state <= S_FETCH_IMM2;
                        end else if (needs_io_read(fetched_op)) begin
                            io_rd_buf <= 8'hFF;
                            fsm_state <= S_EXECUTE;
                        end else if (needs_hl_read(fetched_op) || needs_bc_read(fetched_op) || needs_de_read(fetched_op))
                            fsm_state <= S_READ_MEM;
                        else if (needs_stack_read(fetched_op)) begin
                            fetch_addr <= cpu_sp;
                            ram_addr <= cpu_sp[14:1];
                            fsm_state <= S_READ_STK_LO;
                        end else
                            fsm_state <= S_EXECUTE;
                    end
                end

                S_FETCH_IMM2: fsm_state <= S_WAIT_IMM2;

                S_WAIT_IMM2: begin
                    periph_rd_strobe <= addr_is_periph;
                    if (mem_ready) begin
                        fetched_imm2 <= mem_byte;
                        if (needs_direct_read(fetched_op)) begin
                            fetch_addr <= {mem_byte, fetched_imm1};
                            ram_addr <= {mem_byte, fetched_imm1[7:1]};
                            rom_rd_strobe <= mem_byte[7];
                            fsm_state <= S_READ_MEM;
                        end else if (needs_stack_read(fetched_op)) begin
                            fetch_addr <= cpu_sp;
                            ram_addr <= cpu_sp[14:1];
                            fsm_state <= S_READ_STK_LO;
                        end else
                            fsm_state <= S_EXECUTE;
                    end
                end

                S_READ_MEM: fsm_state <= S_WAIT_MEM;

                S_WAIT_MEM: begin
                    periph_rd_strobe <= addr_is_periph;
                    if (mem_ready) begin
                        mem_rd_buf <= mem_byte;
                        if (fetched_op == 8'h2A) begin
                            fetch_addr <= direct_addr + 16'd1;
                            ram_addr <= (direct_addr + 16'd1) >> 1;
                            fsm_state <= S_READ_STK_LO;
                        end else if (needs_stack_read(fetched_op)) begin
                            fetch_addr <= cpu_sp;
                            ram_addr <= cpu_sp[14:1];
                            fsm_state <= S_READ_STK_LO;
                        end else
                            fsm_state <= S_EXECUTE;
                    end
                end

                S_READ_STK_LO: fsm_state <= S_WAIT_STK_LO;

                S_WAIT_STK_LO: begin
                    periph_rd_strobe <= addr_is_periph;
                    if (mem_ready) begin
                        stk_lo_buf <= mem_byte;
                        fetch_addr <= fetch_addr + 16'd1;
                        ram_addr <= (fetch_addr + 16'd1) >> 1;
                        fsm_state <= S_READ_STK_HI;
                    end
                end

                S_READ_STK_HI: fsm_state <= S_WAIT_STK_HI;

                S_WAIT_STK_HI: begin
                    periph_rd_strobe <= addr_is_periph;
                    if (mem_ready) begin
                        stk_hi_buf <= mem_byte;
                        fsm_state <= S_EXECUTE;
                    end
                end

                S_EXECUTE: begin
                    execute_pulse <= 1'b1;
                    if (cpu_stack_wr) begin
                        fetch_addr <= cpu_stack_wr_addr;
                        ram_addr <= cpu_stack_wr_addr[14:1];
                        ram_wdata <= {cpu_stack_wr_hi, cpu_stack_wr_lo};
                        ram_we <= cpu_stack_wr_addr[0] ? 4'b1100 : 4'b0011;
                        fsm_state <= S_WRITE_STK;
                    end else if (cpu_mem_wr) begin
                        fetch_addr <= cpu_mem_addr;
                        ram_addr <= cpu_mem_addr[14:1];
                        periph_wdata <= cpu_mem_data_out;
                        if (cpu_mem_addr[15:8] == 8'h7F) begin
                            periph_wr_strobe <= 1'b1;
                            fsm_state <= S_FETCH_OP;
                        end else if (!cpu_mem_addr[15]) begin
                            ram_wdata <= {cpu_mem_data_out, cpu_mem_data_out};
                            ram_we <= cpu_mem_addr[0] ? 4'b1100 : 4'b0011;
                            fsm_state <= S_FETCH_OP;
                        end else
                            fsm_state <= S_FETCH_OP;
                    end else if (cpu_io_wr) begin
                        if (cpu_io_port == PORT_ROM_BANK)
                            rom_bank_reg <= cpu_io_data_out;
                        else if (cpu_io_port == PORT_RAM_BANK)
                            ram_bank_reg <= cpu_io_data_out[1:0];
                        fsm_state <= S_FETCH_OP;
                    end else
                        fsm_state <= S_FETCH_OP;
                end

                S_WRITE_STK: begin
                    if (cpu_stack_wr_addr[0] == 1'b0) begin
                        ram_addr <= (cpu_stack_wr_addr + 16'd2) >> 1;
                        ram_wdata <= {cpu_stack_wr_hi, cpu_stack_wr_hi};
                        ram_we <= 4'b0011;
                    end
                    fsm_state <= S_FETCH_OP;
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
        .reg_a(), .reg_b(), .reg_c(), .reg_d(), .reg_e(), .reg_h(), .reg_l(),
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
