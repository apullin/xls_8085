// SPI Flash Cache Controller
// Combines DSLX cache logic with EBR storage and SPI engine
//
// Organization:
//   32 lines × 64 bytes = 2KB data cache
//   Direct-mapped with 12-bit tags
//   Critical word first: returns data as soon as target byte arrives

module spi_flash_cache (
    input  wire        clk,
    input  wire        reset_n,

    // CPU Interface (from i8085_soc)
    input  wire [14:0] rom_addr,      // 15-bit address within 32KB window
    input  wire        rom_rd,        // Read request
    output wire [7:0]  rom_data,      // Data output
    output wire        rom_ready,     // Data valid

    // Bank Register
    input  wire [7:0]  bank_sel,      // Bank selection (256 × 32KB = 8MB)

    // SPI Flash Interface
    output wire        spi_sck,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso
);

    // =========================================================================
    // FSM States
    // =========================================================================

    localparam S_IDLE       = 3'd0;   // Waiting for request
    localparam S_TAG_READ   = 3'd1;   // Reading tag RAM (1 cycle)
    localparam S_TAG_CHECK  = 3'd2;   // Check hit/miss via DSLX logic
    localparam S_HIT        = 3'd3;   // Cache hit - read data RAM
    localparam S_MISS_START = 3'd4;   // Start SPI read
    localparam S_MISS_FILL  = 3'd5;   // Filling cache line from SPI
    localparam S_MISS_DONE  = 3'd6;   // Write new tag, done

    reg [2:0] state;

    // =========================================================================
    // Latched Request
    // =========================================================================

    reg [14:0] addr_latch;
    reg [7:0]  bank_latch;
    reg [5:0]  target_offset;     // Byte we need to return
    reg        target_valid;      // Target byte has been captured

    // =========================================================================
    // Tag RAM (32 entries × 13 bits: 1 valid + 12 tag)
    // Using distributed RAM (inferred) for simplicity
    // =========================================================================

    reg [12:0] tag_ram [0:31];    // {valid, tag[11:0]}
    reg [12:0] tag_read_data;
    wire       tag_valid = tag_read_data[12];
    wire [11:0] tag_stored = tag_read_data[11:0];

    // Tag RAM read
    always @(posedge clk) begin
        tag_read_data <= tag_ram[addr_latch[10:6]];
    end

    // =========================================================================
    // Data RAM (2KB = 32 lines × 64 bytes)
    // Organized as 256 × 64-bit words (8 bytes per word)
    // Address = {line_index[4:0], word_index[2:0]} = 8 bits
    // =========================================================================

    reg [63:0] data_ram [0:255];  // 256 × 8 bytes = 2KB
    reg [63:0] data_read_word;
    reg [7:0]  data_ram_addr;
    reg [63:0] data_write_word;
    reg        data_we;

    // Data RAM read/write
    always @(posedge clk) begin
        if (data_we) begin
            data_ram[data_ram_addr] <= data_write_word;
        end
        data_read_word <= data_ram[data_ram_addr];
    end

    // =========================================================================
    // DSLX Cache Logic Instance
    // =========================================================================

    wire        lookup_hit;
    wire [11:0] lookup_tag;
    wire [4:0]  lookup_index;
    wire [5:0]  lookup_offset;
    wire [22:0] lookup_line_addr;  // 23 bits for 8MB address space

    // XLS-generated module from cache_logic.x
    // Function: cache_lookup(addr, bank, stored_valid, stored_tag)
    __cache_logic__cache_lookup cache_logic_inst (
        .addr(addr_latch),
        .bank(bank_latch),
        .stored_valid(tag_valid),
        .stored_tag(tag_stored),
        .out({lookup_hit, lookup_tag, lookup_index, lookup_offset, lookup_line_addr})
    );

    // =========================================================================
    // SPI Engine Instance
    // =========================================================================

    reg        spi_start;
    reg [23:0] spi_addr;
    wire       spi_busy;
    wire [7:0] spi_data_out;
    wire       spi_data_valid;
    wire [5:0] spi_data_index;

    spi_engine spi_inst (
        .clk(clk),
        .reset_n(reset_n),
        .cmd_start(spi_start),
        .cmd_addr(spi_addr),
        .cmd_len(7'd64),          // Always fetch full 64-byte line
        .cmd_busy(spi_busy),
        .data_out(spi_data_out),
        .data_valid(spi_data_valid),
        .data_index(spi_data_index),
        .spi_sck(spi_sck),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso)
    );

    // =========================================================================
    // Output Data Selection
    // =========================================================================

    // Select byte from 64-bit word based on offset[2:0]
    reg [7:0] selected_byte;
    always @(*) begin
        case (target_offset[2:0])
            3'd0: selected_byte = data_read_word[7:0];
            3'd1: selected_byte = data_read_word[15:8];
            3'd2: selected_byte = data_read_word[23:16];
            3'd3: selected_byte = data_read_word[31:24];
            3'd4: selected_byte = data_read_word[39:32];
            3'd5: selected_byte = data_read_word[47:40];
            3'd6: selected_byte = data_read_word[55:48];
            3'd7: selected_byte = data_read_word[63:56];
        endcase
    end

    // Output mux: hit data from RAM or captured SPI data
    reg [7:0] captured_byte;
    reg       use_captured;

    assign rom_data = use_captured ? captured_byte : selected_byte;
    assign rom_ready = (state == S_HIT) || target_valid;

    // =========================================================================
    // Fill Buffer for Assembling 64-bit Words
    // =========================================================================

    reg [63:0] fill_buffer;
    reg [2:0]  fill_byte_idx;     // Which byte within 8-byte word
    reg [2:0]  fill_word_idx;     // Which 8-byte word (0-7)

    // =========================================================================
    // Main FSM
    // =========================================================================

    integer i;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_IDLE;
            addr_latch <= 15'd0;
            bank_latch <= 8'd0;
            target_offset <= 6'd0;
            target_valid <= 1'b0;
            use_captured <= 1'b0;
            captured_byte <= 8'd0;
            spi_start <= 1'b0;
            spi_addr <= 24'd0;
            data_ram_addr <= 8'd0;
            data_write_word <= 64'd0;
            data_we <= 1'b0;
            fill_buffer <= 64'd0;
            fill_byte_idx <= 3'd0;
            fill_word_idx <= 3'd0;

            // Initialize tag RAM to invalid
            for (i = 0; i < 32; i = i + 1) begin
                tag_ram[i] <= 13'd0;
            end
        end else begin
            // Defaults
            spi_start <= 1'b0;
            data_we <= 1'b0;

            case (state)
                S_IDLE: begin
                    target_valid <= 1'b0;
                    use_captured <= 1'b0;

                    if (rom_rd) begin
                        // Latch request
                        addr_latch <= rom_addr;
                        bank_latch <= bank_sel;
                        target_offset <= rom_addr[5:0];
                        state <= S_TAG_READ;
                    end
                end

                S_TAG_READ: begin
                    // Tag RAM read happens this cycle (registered)
                    // Set up data RAM address for potential hit
                    data_ram_addr <= {addr_latch[10:6], addr_latch[5:3]};
                    state <= S_TAG_CHECK;
                end

                S_TAG_CHECK: begin
                    // DSLX logic provides hit/miss result
                    if (lookup_hit) begin
                        // Cache hit - data RAM read already in progress
                        state <= S_HIT;
                    end else begin
                        // Cache miss - start SPI read
                        spi_addr <= {1'b0, lookup_line_addr};  // Pad 23-bit to 24 bits
                        spi_start <= 1'b1;
                        fill_byte_idx <= 3'd0;
                        fill_word_idx <= 3'd0;
                        fill_buffer <= 64'd0;
                        state <= S_MISS_START;
                    end
                end

                S_HIT: begin
                    // Data is ready from RAM (selected_byte valid)
                    // rom_ready asserted via state check
                    state <= S_IDLE;
                end

                S_MISS_START: begin
                    // Wait for SPI to start
                    if (spi_busy) begin
                        state <= S_MISS_FILL;
                    end
                end

                S_MISS_FILL: begin
                    if (spi_data_valid) begin
                        // Accumulate byte into fill buffer
                        case (fill_byte_idx)
                            3'd0: fill_buffer[7:0]   <= spi_data_out;
                            3'd1: fill_buffer[15:8]  <= spi_data_out;
                            3'd2: fill_buffer[23:16] <= spi_data_out;
                            3'd3: fill_buffer[31:24] <= spi_data_out;
                            3'd4: fill_buffer[39:32] <= spi_data_out;
                            3'd5: fill_buffer[47:40] <= spi_data_out;
                            3'd6: fill_buffer[55:48] <= spi_data_out;
                            3'd7: fill_buffer[63:56] <= spi_data_out;
                        endcase

                        // Check if this is the byte we need (critical word first)
                        if (spi_data_index == target_offset && !target_valid) begin
                            captured_byte <= spi_data_out;
                            target_valid <= 1'b1;
                            use_captured <= 1'b1;
                        end

                        fill_byte_idx <= fill_byte_idx + 3'd1;

                        // Write complete 8-byte word to data RAM
                        if (fill_byte_idx == 3'd7) begin
                            data_ram_addr <= {lookup_index, fill_word_idx};
                            // Need to include the current byte in the write
                            data_write_word <= {spi_data_out, fill_buffer[55:0]};
                            data_we <= 1'b1;

                            // Check if this is the last word (word 7)
                            if (fill_word_idx == 3'd7) begin
                                state <= S_MISS_DONE;
                            end else begin
                                fill_word_idx <= fill_word_idx + 3'd1;
                            end
                            fill_buffer <= 64'd0;
                        end
                    end
                end

                S_MISS_DONE: begin
                    // Update tag RAM with new tag
                    tag_ram[lookup_index] <= {1'b1, lookup_tag};
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
