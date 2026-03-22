// Behavioral SB_I2C stub for simulation
// This is a minimal stub that does not implement actual I2C functionality.
// It just provides the interface so the rest of the MCU can be simulated.

module SB_I2C #(
    parameter I2C_SLAVE_INIT_ADDR = "0b0000000",
    parameter BUS_ADDR74 = "0b0001"
) (
    // System bus interface (active high directly from Lattice docs)
    input  SBCLKI,
    input  SBRWI,
    input  SBSTBI,
    input  SBADRI7, SBADRI6, SBADRI5, SBADRI4,
    input  SBADRI3, SBADRI2, SBADRI1, SBADRI0,
    input  SBDATI7, SBDATI6, SBDATI5, SBDATI4,
    input  SBDATI3, SBDATI2, SBDATI1, SBDATI0,
    output SBDATO7, SBDATO6, SBDATO5, SBDATO4,
    output SBDATO3, SBDATO2, SBDATO1, SBDATO0,
    output SBACKO,

    // I2C signals
    input  SCLI,
    output SCLO,
    output SCLOE,
    input  SDAI,
    output SDAO,
    output SDAOE,

    // Interrupts
    output I2CIRQ,
    output I2CWKUP
);

    // Stub - no actual I2C functionality
    // Just provide default outputs so simulation can proceed

    // Status register returns 0x00 (no activity)
    assign {SBDATO7, SBDATO6, SBDATO5, SBDATO4,
            SBDATO3, SBDATO2, SBDATO1, SBDATO0} = 8'h00;

    assign SBACKO = 1'b1;   // Always acknowledge

    // I2C lines tri-stated (high impedance)
    assign SCLO = 1'b1;
    assign SCLOE = 1'b0;    // Not driving SCL
    assign SDAO = 1'b1;
    assign SDAOE = 1'b0;    // Not driving SDA

    // No interrupts
    assign I2CIRQ = 1'b0;
    assign I2CWKUP = 1'b0;

endmodule
