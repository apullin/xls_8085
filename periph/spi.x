// SPI Master Peripheral
// Memory-mapped peripheral for 8085 MCU
//
// Features:
//   - Full-duplex SPI master
//   - 4-entry TX and RX FIFOs
//   - Configurable clock divider (8-bit, SCK = CLK / (2 * (DIV+1)))
//   - Configurable CPOL/CPHA (modes 0-3)
//   - Manual or auto CS control
//   - IRQ for TX empty, RX threshold, transfer complete
//
// Register Map (16 bytes):
//   0x00: CTRL     - [7]EN [6]CPHA [5]CPOL [4]AUTO_CS [3:0]reserved
//   0x01: STAT     - [7]BUSY [6]TXFE [5]TXFF [4]RXFE [3]RXFF [2:0]reserved (RO)
//   0x02: DIV      - Clock divider (SCK = CLK / (2 * (DIV+1)))
//   0x03: CS       - [0]CS_N output (manual mode only, directly controls CS pin)
//   0x04: TXDATA   - Write to push TX FIFO (starts transfer if AUTO)
//   0x05: RXDATA   - Read to pop RX FIFO
//   0x06: IRQ_EN   - [2]DONE [1]RXNE [0]TXE
//   0x07: IRQ_STAT - Same bits (W1C)
//   0x08: FIFOLVL  - [7:4]RX_CNT [3:0]TX_CNT (RO)
//
// SPI Modes:
//   Mode 0: CPOL=0, CPHA=0 - Clock idle low, sample on rising edge
//   Mode 1: CPOL=0, CPHA=1 - Clock idle low, sample on falling edge
//   Mode 2: CPOL=1, CPHA=0 - Clock idle high, sample on falling edge
//   Mode 3: CPOL=1, CPHA=1 - Clock idle high, sample on rising edge

// =============================================================================
// Constants
// =============================================================================

const REG_CTRL: u4     = 0x0;
const REG_STAT: u4     = 0x1;
const REG_DIV: u4      = 0x2;
const REG_CS: u4       = 0x3;
const REG_TXDATA: u4   = 0x4;
const REG_RXDATA: u4   = 0x5;
const REG_IRQ_EN: u4   = 0x6;
const REG_IRQ_STAT: u4 = 0x7;
const REG_FIFOLVL: u4  = 0x8;

// CTRL register bits
const CTRL_EN: u8      = u8:0x80;
const CTRL_CPHA: u8    = u8:0x40;
const CTRL_CPOL: u8    = u8:0x20;
const CTRL_AUTO_CS: u8 = u8:0x10;

// STAT register bits
const STAT_BUSY: u8    = u8:0x80;
const STAT_TXFE: u8    = u8:0x40;
const STAT_TXFF: u8    = u8:0x20;
const STAT_RXFE: u8    = u8:0x10;
const STAT_RXFF: u8    = u8:0x08;

// IRQ bits
const IRQ_DONE: u8     = u8:0x04;
const IRQ_RXNE: u8     = u8:0x02;
const IRQ_TXE: u8      = u8:0x01;

// =============================================================================
// State
// =============================================================================

pub struct SpiState {
    // Configuration
    ctrl: u8,
    div: u8,
    cs_reg: u8,         // Manual CS control
    irq_en: u8,
    irq_stat: u8,

    // Clock divider
    div_counter: u8,
    sck_phase: bool,    // Toggle for SCK generation

    // Transfer state
    state: u2,          // 0=idle, 1=transfer, 2=done
    tx_shift: u8,       // TX shift register
    rx_shift: u8,       // RX shift register
    bit_idx: u3,        // Current bit (0-7)

    // TX FIFO (4 entries)
    tx_fifo: u8[4],
    tx_fifo_head: u2,
    tx_fifo_tail: u2,
    tx_fifo_count: u3,

    // RX FIFO (4 entries)
    rx_fifo: u8[4],
    rx_fifo_head: u2,
    rx_fifo_tail: u2,
    rx_fifo_count: u3,

    // Output registers
    sck_out: bool,
    mosi_out: bool,
    cs_n_out: bool,
}

// =============================================================================
// Bus Interface
// =============================================================================

pub struct SpiInput {
    addr: u4,
    data_in: u8,
    rd: bool,
    wr: bool,
    miso: bool,         // SPI input from slave
}

pub struct SpiOutput {
    data_out: u8,
    irq: bool,
    sck: bool,          // SPI clock
    mosi: bool,         // SPI data out
    cs_n: bool,         // Chip select (directly from state)
}

// =============================================================================
// Helper Functions
// =============================================================================

pub fn initial_state() -> SpiState {
    SpiState {
        ctrl: u8:0,
        div: u8:0,
        cs_reg: u8:0x01,    // CS deasserted by default
        irq_en: u8:0,
        irq_stat: u8:0,

        div_counter: u8:0,
        sck_phase: false,

        state: u2:0,
        tx_shift: u8:0,
        rx_shift: u8:0,
        bit_idx: u3:0,

        tx_fifo: u8[4]:[u8:0, ...],
        tx_fifo_head: u2:0,
        tx_fifo_tail: u2:0,
        tx_fifo_count: u3:0,

        rx_fifo: u8[4]:[u8:0, ...],
        rx_fifo_head: u2:0,
        rx_fifo_tail: u2:0,
        rx_fifo_count: u3:0,

        sck_out: false,
        mosi_out: false,
        cs_n_out: true,
    }
}

// =============================================================================
// SPI Transfer State Machine
// =============================================================================

const ST_IDLE: u2     = u2:0;
const ST_TRANSFER: u2 = u2:1;
const ST_DONE: u2     = u2:2;

fn spi_tick(state: SpiState, miso: bool) -> SpiState {
    let enabled = (state.ctrl & CTRL_EN) != u8:0;
    let cpol = (state.ctrl & CTRL_CPOL) != u8:0;
    let cpha = (state.ctrl & CTRL_CPHA) != u8:0;
    let auto_cs = (state.ctrl & CTRL_AUTO_CS) != u8:0;

    // Idle SCK value depends on CPOL
    let sck_idle = cpol;

    if !enabled {
        // Disabled - reset to idle
        SpiState {
            state: ST_IDLE,
            sck_out: sck_idle,
            cs_n_out: if auto_cs { true } else { (state.cs_reg & u8:1) == u8:1 },
            div_counter: u8:0,
            sck_phase: false,
            bit_idx: u3:0,
            ..state
        }
    } else if state.state == ST_IDLE {
        // Check if we have data to send
        if state.tx_fifo_count > u3:0 {
            // Load TX byte and start transfer
            let tx_byte = state.tx_fifo[state.tx_fifo_tail];
            SpiState {
                state: ST_TRANSFER,
                tx_shift: tx_byte,
                rx_shift: u8:0,
                bit_idx: u3:0,
                div_counter: state.div,
                sck_phase: false,
                sck_out: sck_idle,
                mosi_out: if cpha { false } else { (tx_byte & u8:0x80) != u8:0 },
                cs_n_out: if auto_cs { false } else { (state.cs_reg & u8:1) == u8:1 },
                tx_fifo_tail: state.tx_fifo_tail + u2:1,
                tx_fifo_count: state.tx_fifo_count - u3:1,
                ..state
            }
        } else {
            // Stay idle
            SpiState {
                sck_out: sck_idle,
                cs_n_out: if auto_cs { true } else { (state.cs_reg & u8:1) == u8:1 },
                ..state
            }
        }
    } else if state.state == ST_TRANSFER {
        // Clock divider
        if state.div_counter > u8:0 {
            SpiState { div_counter: state.div_counter - u8:1, ..state }
        } else {
            // Time for clock edge
            let new_sck_phase = !state.sck_phase;
            let new_sck = if new_sck_phase { !sck_idle } else { sck_idle };

            // Determine sample and shift edges based on mode
            // CPHA=0: sample on first edge (rising if CPOL=0), shift on second
            // CPHA=1: shift on first edge, sample on second
            let is_sample_edge = if cpha { !new_sck_phase } else { new_sck_phase };
            let is_shift_edge = if cpha { new_sck_phase } else { !new_sck_phase };

            if is_sample_edge {
                // Sample MISO
                let new_rx = (state.rx_shift << u8:1) | (if miso { u8:1 } else { u8:0 });
                SpiState {
                    rx_shift: new_rx,
                    sck_out: new_sck,
                    sck_phase: new_sck_phase,
                    div_counter: state.div,
                    ..state
                }
            } else if is_shift_edge {
                // Shift out next bit
                let next_bit = state.bit_idx + u3:1;
                let byte_done = next_bit == u3:0;  // Wrapped from 7 to 0

                if byte_done {
                    // Byte complete - store RX byte
                    let rx_full = state.rx_fifo_count >= u3:4;
                    let new_rx_fifo = if rx_full {
                        state.rx_fifo
                    } else {
                        update(state.rx_fifo, state.rx_fifo_head, state.rx_shift)
                    };
                    let new_rx_head = if rx_full { state.rx_fifo_head } else { state.rx_fifo_head + u2:1 };
                    let new_rx_count = if rx_full { state.rx_fifo_count } else { state.rx_fifo_count + u3:1 };

                    // Check if more TX data
                    if state.tx_fifo_count > u3:0 {
                        // Load next byte
                        let next_tx = state.tx_fifo[state.tx_fifo_tail];
                        SpiState {
                            state: ST_TRANSFER,
                            tx_shift: next_tx,
                            rx_shift: u8:0,
                            bit_idx: u3:0,
                            sck_out: new_sck,
                            mosi_out: if cpha { false } else { (next_tx & u8:0x80) != u8:0 },
                            sck_phase: new_sck_phase,
                            div_counter: state.div,
                            tx_fifo_tail: state.tx_fifo_tail + u2:1,
                            tx_fifo_count: state.tx_fifo_count - u3:1,
                            rx_fifo: new_rx_fifo,
                            rx_fifo_head: new_rx_head,
                            rx_fifo_count: new_rx_count,
                            ..state
                        }
                    } else {
                        // Transfer complete
                        SpiState {
                            state: ST_DONE,
                            sck_out: new_sck,
                            sck_phase: new_sck_phase,
                            div_counter: state.div,
                            rx_fifo: new_rx_fifo,
                            rx_fifo_head: new_rx_head,
                            rx_fifo_count: new_rx_count,
                            irq_stat: state.irq_stat | IRQ_DONE,
                            ..state
                        }
                    }
                } else {
                    // Continue shifting
                    let new_tx = state.tx_shift << u8:1;
                    SpiState {
                        tx_shift: new_tx,
                        bit_idx: next_bit,
                        sck_out: new_sck,
                        mosi_out: (new_tx & u8:0x80) != u8:0,
                        sck_phase: new_sck_phase,
                        div_counter: state.div,
                        ..state
                    }
                }
            } else {
                SpiState {
                    sck_out: new_sck,
                    sck_phase: new_sck_phase,
                    div_counter: state.div,
                    ..state
                }
            }
        }
    } else {
        // ST_DONE - return to idle
        SpiState {
            state: ST_IDLE,
            sck_out: sck_idle,
            cs_n_out: if auto_cs { true } else { (state.cs_reg & u8:1) == u8:1 },
            ..state
        }
    }
}

// =============================================================================
// Register Access
// =============================================================================

fn do_read(state: SpiState) -> u8 {
    let busy = state.state != ST_IDLE;
    let tx_empty = state.tx_fifo_count == u3:0;
    let tx_full = state.tx_fifo_count >= u3:4;
    let rx_empty = state.rx_fifo_count == u3:0;
    let rx_full = state.rx_fifo_count >= u3:4;

    (if busy { STAT_BUSY } else { u8:0 }) |
    (if tx_empty { STAT_TXFE } else { u8:0 }) |
    (if tx_full { STAT_TXFF } else { u8:0 }) |
    (if rx_empty { STAT_RXFE } else { u8:0 }) |
    (if rx_full { STAT_RXFF } else { u8:0 })
}

fn do_write(state: SpiState, addr: u4, data: u8) -> SpiState {
    if addr == REG_CTRL {
        SpiState { ctrl: data, ..state }
    } else if addr == REG_DIV {
        SpiState { div: data, ..state }
    } else if addr == REG_CS {
        SpiState { cs_reg: data, ..state }
    } else if addr == REG_IRQ_EN {
        SpiState { irq_en: data, ..state }
    } else if addr == REG_IRQ_STAT {
        // Write 1 to clear
        SpiState { irq_stat: state.irq_stat & !data, ..state }
    } else if addr == REG_TXDATA {
        // Push to TX FIFO if not full
        if state.tx_fifo_count < u3:4 {
            SpiState {
                tx_fifo: update(state.tx_fifo, state.tx_fifo_head, data),
                tx_fifo_head: state.tx_fifo_head + u2:1,
                tx_fifo_count: state.tx_fifo_count + u3:1,
                ..state
            }
        } else {
            state
        }
    } else {
        state
    }
}

fn do_rx_read(state: SpiState) -> (u8, SpiState) {
    if state.rx_fifo_count > u3:0 {
        let rx_byte = state.rx_fifo[state.rx_fifo_tail];
        (rx_byte, SpiState {
            rx_fifo_tail: state.rx_fifo_tail + u2:1,
            rx_fifo_count: state.rx_fifo_count - u3:1,
            ..state
        })
    } else {
        (u8:0, state)
    }
}

fn update_irq(state: SpiState) -> SpiState {
    let tx_empty = state.tx_fifo_count == u3:0;
    let rx_not_empty = state.rx_fifo_count > u3:0;

    let new_stat = (if tx_empty { IRQ_TXE } else { u8:0 }) |
                   (if rx_not_empty { IRQ_RXNE } else { u8:0 });

    // Set bits (DONE is set during transfer completion)
    SpiState { irq_stat: state.irq_stat | new_stat, ..state }
}

// =============================================================================
// Main SPI Function
// =============================================================================

pub fn spi_tick_fn(state: SpiState, bus_in: SpiInput) -> (SpiState, SpiOutput) {
    // Register writes first (so state machine sees new data)
    let state1 = if bus_in.wr {
        do_write(state, bus_in.addr, bus_in.data_in)
    } else {
        state
    };

    // Run SPI state machine
    let state2 = spi_tick(state1, bus_in.miso);

    // Register reads
    let stat_reg = do_read(state2);
    let (rx_byte, state3) = if bus_in.rd && bus_in.addr == REG_RXDATA {
        do_rx_read(state2)
    } else {
        (u8:0, state2)
    };

    // Update IRQ
    let state4 = update_irq(state3);

    // Build FIFOLVL register
    let fifolvl = ((state4.rx_fifo_count as u8) << u8:4) | (state4.tx_fifo_count as u8);

    // Data out mux
    let data_out = if bus_in.rd {
        if bus_in.addr == REG_CTRL { state4.ctrl }
        else if bus_in.addr == REG_STAT { stat_reg }
        else if bus_in.addr == REG_DIV { state4.div }
        else if bus_in.addr == REG_CS { state4.cs_reg }
        else if bus_in.addr == REG_RXDATA { rx_byte }
        else if bus_in.addr == REG_IRQ_EN { state4.irq_en }
        else if bus_in.addr == REG_IRQ_STAT { state4.irq_stat }
        else if bus_in.addr == REG_FIFOLVL { fifolvl }
        else { u8:0xFF }
    } else {
        u8:0xFF
    };

    // IRQ output
    let irq = (state4.irq_stat & state4.irq_en) != u8:0;

    let output = SpiOutput {
        data_out: data_out,
        irq: irq,
        sck: state4.sck_out,
        mosi: state4.mosi_out,
        cs_n: state4.cs_n_out,
    };

    (state4, output)
}

// =============================================================================
// Tests
// =============================================================================

#[test]
fn test_initial_state() {
    let state = initial_state();
    assert_eq(state.ctrl, u8:0);
    assert_eq(state.tx_fifo_count, u3:0);
    assert_eq(state.rx_fifo_count, u3:0);
    assert_eq(state.cs_n_out, true);  // CS deasserted
}

#[test]
fn test_tx_fifo_push() {
    let state = initial_state();
    let state = SpiState { ctrl: CTRL_EN, ..state };

    let input = SpiInput {
        addr: REG_TXDATA,
        data_in: u8:0xA5,
        rd: false,
        wr: true,
        miso: false,
    };

    let (state2, _) = spi_tick_fn(state, input);
    // TX FIFO should have one byte, then state machine loads it
    // After spi_tick runs, it should start transfer
    assert_eq(state2.state, ST_TRANSFER);
}

#[test]
fn test_cs_manual_control() {
    let state = initial_state();
    let state = SpiState { ctrl: CTRL_EN, ..state };  // No AUTO_CS

    // CS should follow cs_reg
    let input = SpiInput {
        addr: REG_CS,
        data_in: u8:0x00,  // Assert CS (active low)
        rd: false,
        wr: true,
        miso: false,
    };

    let (state2, output) = spi_tick_fn(state, input);
    assert_eq(state2.cs_reg, u8:0x00);
    // CS output follows cs_reg when not AUTO
    assert_eq(output.cs_n, false);
}

#[test]
fn test_div_write() {
    let state = initial_state();

    let input = SpiInput {
        addr: REG_DIV,
        data_in: u8:0x0F,
        rd: false,
        wr: true,
        miso: false,
    };

    let (state2, _) = spi_tick_fn(state, input);
    assert_eq(state2.div, u8:0x0F);
}

#[test]
fn test_fifo_depth_limit() {
    let state = initial_state();
    let state = SpiState { ctrl: u8:0, ..state };  // Disabled so no transfer starts

    let input = SpiInput {
        addr: REG_TXDATA,
        data_in: u8:0x00,
        rd: false,
        wr: true,
        miso: false,
    };

    // Push 4 bytes (should all succeed)
    let (state, _) = spi_tick_fn(state, input);
    let (state, _) = spi_tick_fn(state, input);
    let (state, _) = spi_tick_fn(state, input);
    let (state, _) = spi_tick_fn(state, input);
    assert_eq(state.tx_fifo_count, u3:4);

    // Push 5th byte (should be rejected)
    let (state, _) = spi_tick_fn(state, input);
    assert_eq(state.tx_fifo_count, u3:4);
}

#[test]
fn test_sck_idle_cpol0() {
    let state = initial_state();
    let state = SpiState { ctrl: CTRL_EN, ..state };  // CPOL=0

    let input = SpiInput {
        addr: u4:0,
        data_in: u8:0,
        rd: false,
        wr: false,
        miso: false,
    };

    let (_, output) = spi_tick_fn(state, input);
    assert_eq(output.sck, false);  // CPOL=0 means idle low
}

#[test]
fn test_sck_idle_cpol1() {
    let state = initial_state();
    let state = SpiState { ctrl: CTRL_EN | CTRL_CPOL, ..state };  // CPOL=1

    let input = SpiInput {
        addr: u4:0,
        data_in: u8:0,
        rd: false,
        wr: false,
        miso: false,
    };

    let (_, output) = spi_tick_fn(state, input);
    assert_eq(output.sck, true);  // CPOL=1 means idle high
}
