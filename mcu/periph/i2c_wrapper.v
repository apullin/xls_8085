// I2C Wrapper for iCE40 UP5K Hard I2C (SB_I2C)
// Provides memory-mapped register interface to the silicon I2C block
// Supports both master and slave modes

module i2c_wrapper (
    input  wire        clk,
    input  wire        reset_n,

    // Bus interface (directly maps to SB_I2C registers)
    input  wire [3:0]  addr,
    input  wire [7:0]  data_in,
    output wire [7:0]  data_out,
    input  wire        rd,
    input  wire        wr,

    // I2C pins (directly connect to SB_IO for open-drain)
    input  wire        sda_in,
    output wire        sda_out,
    output wire        sda_oe,
    input  wire        scl_in,
    output wire        scl_out,
    output wire        scl_oe,

    // Interrupt
    output wire        irq
);

    // SB_I2C register addresses (directly exposed through our interface)
    // 0x0: I2CCR0   - Control 0 (enable, clock select)
    // 0x1: I2CCR1   - Control 1 (wakeup enable)
    // 0x2: I2CCMDR  - Command register
    // 0x3: I2CBR    - Bus address register (7-bit addr + R/W)
    // 0x4: I2CSR    - Status register (read-only)
    // 0x5: I2CTXDR  - Transmit data register
    // 0x6: I2CRXDR  - Receive data register (read-only)
    // 0x7: I2CGCDR  - General call data register
    // 0x8: I2CSADDR - Slave address register
    // 0x9: I2CIRQEN - IRQ enable register
    // 0xA: I2CIRQST - IRQ status register

    // Active strobe generation
    wire strobe = rd | wr;

    // SB_I2C uses individual bit ports - create bus versions
    wire [7:0] sb_addr = {4'b0001, addr};  // BUS_ADDR74 prefix + register address

    // Directly instantiate hard I2C block
    // I2C_SLAVE_INIT_ADDR: 7-bit slave address (default 0x00)
    // BUS_ADDR74: Upper bits of the SB bus address for this instance
    SB_I2C #(
        .I2C_SLAVE_INIT_ADDR("0b0000000"),
        .BUS_ADDR74("0b0001")
    ) i2c_inst (
        // System interface
        .SBCLKI(clk),
        .SBRWI(rd),              // 1=read, 0=write
        .SBSTBI(strobe),
        .SBADRI7(sb_addr[7]),
        .SBADRI6(sb_addr[6]),
        .SBADRI5(sb_addr[5]),
        .SBADRI4(sb_addr[4]),
        .SBADRI3(sb_addr[3]),
        .SBADRI2(sb_addr[2]),
        .SBADRI1(sb_addr[1]),
        .SBADRI0(sb_addr[0]),
        .SBDATI7(data_in[7]),
        .SBDATI6(data_in[6]),
        .SBDATI5(data_in[5]),
        .SBDATI4(data_in[4]),
        .SBDATI3(data_in[3]),
        .SBDATI2(data_in[2]),
        .SBDATI1(data_in[1]),
        .SBDATI0(data_in[0]),
        .SBDATO7(data_out[7]),
        .SBDATO6(data_out[6]),
        .SBDATO5(data_out[5]),
        .SBDATO4(data_out[4]),
        .SBDATO3(data_out[3]),
        .SBDATO2(data_out[2]),
        .SBDATO1(data_out[1]),
        .SBDATO0(data_out[0]),
        .SBACKO(),               // Bus acknowledge - not used

        // I2C signals
        .SCLI(scl_in),
        .SCLO(scl_out),
        .SCLOE(scl_oe),
        .SDAI(sda_in),
        .SDAO(sda_out),
        .SDAOE(sda_oe),

        // Interrupt and wakeup
        .I2CIRQ(irq),
        .I2CWKUP()               // Wakeup - not used
    );

endmodule
