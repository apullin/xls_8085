// UART with FIFOs and Fractional Baud Rate
// Memory-mapped peripheral for 8085 MCU
//
// Features:
//   - 7 or 8 bit word length
//   - Optional parity (odd/even)
//   - 1 or 2 stop bits
//   - 4-entry TX and RX FIFOs
//   - 16-bit integer + 6-bit fractional baud divisor
//   - 16x oversampling on RX
//   - Configurable FIFO thresholds for IRQ
//   - RX timeout interrupt
//   - Loopback mode for testing
//
// Register Map (16 bytes):
//   0x00: CTRL     - [7]EN [6]TXEN [5]RXEN [4]FEN [3]LBE [2]WLEN [1]STP2 [0]PEN
//   0x01: PARITY   - [0]EPS (0=odd, 1=even)
//   0x02: STAT     - [7]BUSY [6]TXFE [5]TXFF [4]RXFE [3]RXFF [2]OE [1]FE [0]PE (RO)
//   0x03: FIFOLVL  - [7:4]RX_CNT [3:0]TX_CNT (RO)
//   0x04: TXDATA   - Write to push TX FIFO
//   0x05: RXDATA   - Read to pop RX FIFO
//   0x06: BRD_L    - Baud divisor low byte
//   0x07: BRD_H    - Baud divisor high byte
//   0x08: BRD_F    - [5:0] Fractional divisor
//   0x09: IRQ_EN   - [4]RXTO [3]TXLVL [2]RXLVL [1]OE [0]FE
//   0x0A: IRQ_STAT - Same bits (W1C)
//   0x0B: IFLS     - [5:4]RXTHR [1:0]TXTHR
//   0x0C: RXTO_CFG - RX timeout in bit periods
//
// Baud rate: baud = clk / ((BRD_H:BRD_L + BRD_F/64) * 16)

// =============================================================================
// Constants - Register Addresses
// =============================================================================

const REG_CTRL: u4     = 0x0;
const REG_PARITY: u4   = 0x1;
const REG_STAT: u4     = 0x2;
const REG_FIFOLVL: u4  = 0x3;
const REG_TXDATA: u4   = 0x4;
const REG_RXDATA: u4   = 0x5;
const REG_BRD_L: u4    = 0x6;
const REG_BRD_H: u4    = 0x7;
const REG_BRD_F: u4    = 0x8;
const REG_IRQ_EN: u4   = 0x9;
const REG_IRQ_STAT: u4 = 0xA;
const REG_IFLS: u4     = 0xB;
const REG_RXTO_CFG: u4 = 0xC;

// CTRL register bits
const CTRL_EN: u8    = u8:0x80;
const CTRL_TXEN: u8  = u8:0x40;
const CTRL_RXEN: u8  = u8:0x20;
const CTRL_FEN: u8   = u8:0x10;
const CTRL_LBE: u8   = u8:0x08;
const CTRL_WLEN: u8  = u8:0x04;  // 0=7bit, 1=8bit
const CTRL_STP2: u8  = u8:0x02;
const CTRL_PEN: u8   = u8:0x01;

// STAT register bits
const STAT_BUSY: u8  = u8:0x80;
const STAT_TXFE: u8  = u8:0x40;
const STAT_TXFF: u8  = u8:0x20;
const STAT_RXFE: u8  = u8:0x10;
const STAT_RXFF: u8  = u8:0x08;
const STAT_OE: u8    = u8:0x04;
const STAT_FE: u8    = u8:0x02;
const STAT_PE: u8    = u8:0x01;

// IRQ bits
const IRQ_RXTO: u8   = u8:0x10;
const IRQ_TXLVL: u8  = u8:0x08;
const IRQ_RXLVL: u8  = u8:0x04;
const IRQ_OE: u8     = u8:0x02;
const IRQ_FE: u8     = u8:0x01;

// FIFO depth
const FIFO_DEPTH: u3 = u3:4;

// =============================================================================
// State
// =============================================================================

pub struct UartState {
    // Configuration registers
    ctrl: u8,
    parity_cfg: u8,
    brd_int: u16,
    brd_frac: u6,
    irq_en: u8,
    irq_stat: u8,
    ifls: u8,
    rxto_cfg: u8,

    // Baud rate generator
    baud_counter: u16,
    frac_accum: u6,
    baud_tick: bool,        // Pulses at baud rate (16x bit rate)

    // TX state machine
    tx_state: u2,           // 0=idle, 1=start, 2=data, 3=stop
    tx_shift: u8,           // Shift register
    tx_bit_idx: u4,         // Current bit (0-7 for data, 8+ for stop)
    tx_sample_cnt: u4,      // 16x counter within bit
    tx_parity: bool,        // Running parity

    // TX FIFO (4 entries)
    tx_fifo: u8[4],
    tx_fifo_head: u2,       // Write pointer
    tx_fifo_tail: u2,       // Read pointer
    tx_fifo_count: u3,      // 0-4

    // RX state machine
    rx_state: u2,           // 0=idle, 1=start, 2=data, 3=stop
    rx_shift: u8,           // Shift register
    rx_bit_idx: u4,         // Current bit
    rx_sample_cnt: u4,      // 16x counter
    rx_parity: bool,        // Running parity
    rx_frame_err: bool,     // Framing error on current byte
    rx_parity_err: bool,    // Parity error on current byte

    // RX FIFO (4 entries)
    rx_fifo: u8[4],
    rx_fifo_head: u2,       // Write pointer
    rx_fifo_tail: u2,       // Read pointer
    rx_fifo_count: u3,      // 0-4

    // RX timeout
    rxto_counter: u8,       // Counts idle bit periods

    // Error flags (sticky until cleared)
    overrun_err: bool,
    frame_err: bool,
    parity_err: bool,

    // Previous RX pin for edge detection
    rx_prev: bool,
}

// =============================================================================
// Bus Interface
// =============================================================================

pub struct UartInput {
    addr: u4,
    data_in: u8,
    rd: bool,
    wr: bool,
    rx_pin: bool,           // Serial input
}

pub struct UartOutput {
    data_out: u8,
    irq: bool,
    tx_pin: bool,           // Serial output
}

// =============================================================================
// Helper Functions
// =============================================================================

pub fn initial_state() -> UartState {
    UartState {
        ctrl: u8:0,
        parity_cfg: u8:0,
        brd_int: u16:1,     // Avoid div by zero
        brd_frac: u6:0,
        irq_en: u8:0,
        irq_stat: u8:0,
        ifls: u8:0,
        rxto_cfg: u8:0,

        baud_counter: u16:0,
        frac_accum: u6:0,
        baud_tick: false,

        tx_state: u2:0,
        tx_shift: u8:0,
        tx_bit_idx: u4:0,
        tx_sample_cnt: u4:0,
        tx_parity: false,

        tx_fifo: u8[4]:[u8:0, ...],
        tx_fifo_head: u2:0,
        tx_fifo_tail: u2:0,
        tx_fifo_count: u3:0,

        rx_state: u2:0,
        rx_shift: u8:0,
        rx_bit_idx: u4:0,
        rx_sample_cnt: u4:0,
        rx_parity: false,
        rx_frame_err: false,
        rx_parity_err: false,

        rx_fifo: u8[4]:[u8:0, ...],
        rx_fifo_head: u2:0,
        rx_fifo_tail: u2:0,
        rx_fifo_count: u3:0,

        rxto_counter: u8:0,

        overrun_err: false,
        frame_err: false,
        parity_err: false,

        rx_prev: true,      // Idle high
    }
}

// Calculate parity (XOR of all bits)
fn calc_parity(val: u8) -> bool {
    let p = val ^ (val >> u8:4);
    let p = p ^ (p >> u8:2);
    let p = p ^ (p >> u8:1);
    (p & u8:1) == u8:1
}

// Get threshold value from IFLS field (0=1, 1=2, 2=3, 3=4)
fn get_threshold(thr: u2) -> u3 {
    (thr as u3) + u3:1
}

// =============================================================================
// Baud Rate Generator
// =============================================================================

fn baud_tick_gen(state: UartState) -> (u16, u6, bool) {
    // Fractional baud rate: effective_div = brd_int + brd_frac/64
    // We count down from effective divisor, using fractional accumulator
    // to decide whether to use brd_int or brd_int+1 each cycle

    if state.baud_counter == u16:0 {
        // Time for next baud tick
        // Add fractional part to accumulator
        let new_accum = (state.frac_accum as u7) + (state.brd_frac as u7);
        let overflow = new_accum >= u7:64;
        let frac_out = if overflow { (new_accum - u7:64) as u6 } else { new_accum as u6 };

        // Use brd_int+1 if fractional overflow, else brd_int
        let divisor = if overflow { state.brd_int + u16:1 } else { state.brd_int };
        let new_counter = if divisor == u16:0 { u16:0 } else { divisor - u16:1 };

        (new_counter, frac_out, true)
    } else {
        (state.baud_counter - u16:1, state.frac_accum, false)
    }
}

// =============================================================================
// TX State Machine
// =============================================================================

const TX_IDLE: u2  = u2:0;
const TX_START: u2 = u2:1;
const TX_DATA: u2  = u2:2;
const TX_STOP: u2  = u2:3;

fn tx_get_output(state: UartState) -> bool {
    // Determine TX output based on current state
    if state.tx_state == TX_IDLE {
        true  // Idle high
    } else if state.tx_state == TX_START {
        false  // Start bit low
    } else if state.tx_state == TX_DATA {
        if state.tx_bit_idx == u4:15 {
            // Parity bit
            let even_parity = (state.parity_cfg & u8:1) != u8:0;
            if even_parity { state.tx_parity } else { !state.tx_parity }
        } else {
            let bit_val = (state.tx_shift >> (state.tx_bit_idx as u8)) & u8:1;
            bit_val == u8:1
        }
    } else {
        true  // Stop bit high
    }
}

fn tx_tick(state: UartState, baud_tick: bool) -> (UartState, bool) {
    let enabled = (state.ctrl & CTRL_EN) != u8:0 && (state.ctrl & CTRL_TXEN) != u8:0;
    let word_len = if (state.ctrl & CTRL_WLEN) != u8:0 { u4:8 } else { u4:7 };
    let use_parity = (state.ctrl & CTRL_PEN) != u8:0;
    let two_stop = (state.ctrl & CTRL_STP2) != u8:0;

    if !enabled {
        // Disabled - reset TX state
        let new_state = UartState {
            tx_state: TX_IDLE,
            tx_shift: u8:0,
            tx_bit_idx: u4:0,
            tx_sample_cnt: u4:0,
            tx_parity: false,
            ..state
        };
        (new_state, true)  // Idle high
    } else if !baud_tick {
        // No baud tick - maintain current state and output
        (state, tx_get_output(state))
    } else {
        // Process on baud tick (16x bit rate)
        let sample_done = state.tx_sample_cnt == u4:15;

        if state.tx_state == TX_IDLE {
            // Check if data available in FIFO
            if state.tx_fifo_count > u3:0 {
                // Load byte from FIFO
                let tx_byte = state.tx_fifo[state.tx_fifo_tail];
                let new_state = UartState {
                    tx_state: TX_START,
                    tx_shift: tx_byte,
                    tx_bit_idx: u4:0,
                    tx_sample_cnt: u4:0,
                    tx_parity: false,
                    tx_fifo_tail: state.tx_fifo_tail + u2:1,
                    tx_fifo_count: state.tx_fifo_count - u3:1,
                    ..state
                };
                (new_state, false)  // Start bit (low)
            } else {
                (state, true)  // Idle high
            }
        } else if state.tx_state == TX_START {
            let new_state = if sample_done {
                UartState { tx_state: TX_DATA, tx_sample_cnt: u4:0, ..state }
            } else {
                UartState { tx_sample_cnt: state.tx_sample_cnt + u4:1, ..state }
            };
            (new_state, false)  // Start bit
        } else if state.tx_state == TX_DATA {
            // Handle parity phase (tx_bit_idx == 15)
            if state.tx_bit_idx == u4:15 {
                let even_parity = (state.parity_cfg & u8:1) != u8:0;
                let parity_out = if even_parity { state.tx_parity } else { !state.tx_parity };
                let new_state = if sample_done {
                    UartState { tx_state: TX_STOP, tx_bit_idx: u4:0, tx_sample_cnt: u4:0, ..state }
                } else {
                    UartState { tx_sample_cnt: state.tx_sample_cnt + u4:1, ..state }
                };
                (new_state, parity_out)
            } else {
                // Data bit
                let bit_val = (state.tx_shift >> (state.tx_bit_idx as u8)) & u8:1;
                let tx_out = bit_val == u8:1;

                let new_state = if sample_done {
                    let new_parity = state.tx_parity ^ (bit_val == u8:1);
                    let next_bit = state.tx_bit_idx + u4:1;
                    let data_done = next_bit >= word_len;

                    if data_done && use_parity {
                        UartState { tx_bit_idx: u4:15, tx_sample_cnt: u4:0, tx_parity: new_parity, ..state }
                    } else if data_done {
                        UartState { tx_state: TX_STOP, tx_bit_idx: u4:0, tx_sample_cnt: u4:0, tx_parity: new_parity, ..state }
                    } else {
                        UartState { tx_bit_idx: next_bit, tx_sample_cnt: u4:0, tx_parity: new_parity, ..state }
                    }
                } else {
                    UartState { tx_sample_cnt: state.tx_sample_cnt + u4:1, ..state }
                };
                (new_state, tx_out)
            }
        } else {
            // TX_STOP
            let new_state = if sample_done {
                let stop_bits_needed = if two_stop { u4:2 } else { u4:1 };
                let next_stop = state.tx_bit_idx + u4:1;
                if next_stop >= stop_bits_needed {
                    UartState { tx_state: TX_IDLE, tx_bit_idx: u4:0, tx_sample_cnt: u4:0, ..state }
                } else {
                    UartState { tx_bit_idx: next_stop, tx_sample_cnt: u4:0, ..state }
                }
            } else {
                UartState { tx_sample_cnt: state.tx_sample_cnt + u4:1, ..state }
            };
            (new_state, true)  // Stop bit high
        }
    }
}

// =============================================================================
// RX State Machine
// =============================================================================

const RX_IDLE: u2  = u2:0;
const RX_START: u2 = u2:1;
const RX_DATA: u2  = u2:2;
const RX_STOP: u2  = u2:3;

fn rx_tick(state: UartState, baud_tick: bool, rx_in: bool) -> UartState {
    let enabled = (state.ctrl & CTRL_EN) != u8:0 && (state.ctrl & CTRL_RXEN) != u8:0;
    let word_len = if (state.ctrl & CTRL_WLEN) != u8:0 { u4:8 } else { u4:7 };
    let use_parity = (state.ctrl & CTRL_PEN) != u8:0;

    if !enabled {
        UartState {
            rx_state: RX_IDLE,
            rx_shift: u8:0,
            rx_bit_idx: u4:0,
            rx_sample_cnt: u4:0,
            rx_parity: false,
            rx_frame_err: false,
            rx_parity_err: false,
            rx_prev: rx_in,
            ..state
        }
    } else if !baud_tick {
        UartState { rx_prev: rx_in, ..state }
    } else if state.rx_state == RX_IDLE {
        // Look for falling edge (start bit)
        if state.rx_prev && !rx_in {
            UartState {
                rx_state: RX_START,
                rx_sample_cnt: u4:0,
                rx_shift: u8:0,
                rx_bit_idx: u4:0,
                rx_parity: false,
                rx_frame_err: false,
                rx_parity_err: false,
                rx_prev: rx_in,
                ..state
            }
        } else {
            UartState { rx_prev: rx_in, ..state }
        }
    } else if state.rx_state == RX_START {
        let new_cnt = state.rx_sample_cnt + u4:1;
        if new_cnt == u4:8 && rx_in {
            // False start - go back to idle
            UartState { rx_state: RX_IDLE, rx_sample_cnt: u4:0, rx_prev: rx_in, ..state }
        } else if new_cnt == u4:15 {
            // End of start bit period
            UartState { rx_state: RX_DATA, rx_sample_cnt: u4:0, rx_prev: rx_in, ..state }
        } else {
            UartState { rx_sample_cnt: new_cnt, rx_prev: rx_in, ..state }
        }
    } else if state.rx_state == RX_DATA {
        let new_cnt = state.rx_sample_cnt + u4:1;

        if new_cnt == u4:8 {
            // Sample in middle of bit
            if state.rx_bit_idx == u4:15 {
                // Parity bit
                let even_parity = (state.parity_cfg & u8:1) != u8:0;
                let expected = if even_parity { state.rx_parity } else { !state.rx_parity };
                UartState { rx_sample_cnt: new_cnt, rx_parity_err: rx_in != expected, rx_prev: rx_in, ..state }
            } else {
                // Data bit - shift in (LSB first)
                let bit_val = if rx_in { u8:1 } else { u8:0 };
                let new_shift = state.rx_shift | (bit_val << (state.rx_bit_idx as u8));
                UartState { rx_shift: new_shift, rx_sample_cnt: new_cnt, rx_parity: state.rx_parity ^ rx_in, rx_prev: rx_in, ..state }
            }
        } else if new_cnt == u4:15 {
            // End of bit period
            let next_bit = state.rx_bit_idx + u4:1;
            let data_done = next_bit >= word_len;

            if state.rx_bit_idx == u4:15 {
                // Parity done - move to stop
                UartState { rx_state: RX_STOP, rx_sample_cnt: u4:0, rx_prev: rx_in, ..state }
            } else if data_done && use_parity {
                UartState { rx_bit_idx: u4:15, rx_sample_cnt: u4:0, rx_prev: rx_in, ..state }
            } else if data_done {
                UartState { rx_state: RX_STOP, rx_sample_cnt: u4:0, rx_prev: rx_in, ..state }
            } else {
                UartState { rx_bit_idx: next_bit, rx_sample_cnt: u4:0, rx_prev: rx_in, ..state }
            }
        } else {
            UartState { rx_sample_cnt: new_cnt, rx_prev: rx_in, ..state }
        }
    } else {
        // RX_STOP
        let new_cnt = state.rx_sample_cnt + u4:1;

        if new_cnt == u4:8 {
            // Check stop bit (should be high)
            UartState { rx_sample_cnt: new_cnt, rx_frame_err: !rx_in, rx_prev: rx_in, ..state }
        } else if new_cnt == u4:15 {
            // End of stop bit - store received byte
            let word_mask = if (state.ctrl & CTRL_WLEN) != u8:0 { u8:0xFF } else { u8:0x7F };
            let rx_byte = state.rx_shift & word_mask;
            let fifo_en = (state.ctrl & CTRL_FEN) != u8:0;
            let max_count = if fifo_en { u3:4 } else { u3:1 };
            let overrun = state.rx_fifo_count >= max_count;

            if overrun {
                UartState {
                    rx_state: RX_IDLE, rx_sample_cnt: u4:0,
                    overrun_err: true,
                    frame_err: state.frame_err | state.rx_frame_err,
                    parity_err: state.parity_err | state.rx_parity_err,
                    rx_prev: rx_in, ..state
                }
            } else {
                UartState {
                    rx_state: RX_IDLE, rx_sample_cnt: u4:0,
                    rx_fifo: update(state.rx_fifo, state.rx_fifo_head, rx_byte),
                    rx_fifo_head: state.rx_fifo_head + u2:1,
                    rx_fifo_count: state.rx_fifo_count + u3:1,
                    frame_err: state.frame_err | state.rx_frame_err,
                    parity_err: state.parity_err | state.rx_parity_err,
                    rxto_counter: u8:0, rx_prev: rx_in, ..state
                }
            }
        } else {
            UartState { rx_sample_cnt: new_cnt, rx_prev: rx_in, ..state }
        }
    }
}

// =============================================================================
// Register Read
// =============================================================================

fn do_read(state: UartState) -> u8 {
    // Build status register
    let tx_empty = state.tx_fifo_count == u3:0;
    let tx_full = state.tx_fifo_count == u3:4;
    let rx_empty = state.rx_fifo_count == u3:0;
    let rx_full = state.rx_fifo_count == u3:4;
    let busy = state.tx_state != TX_IDLE;

    (if busy { STAT_BUSY } else { u8:0 }) |
    (if tx_empty { STAT_TXFE } else { u8:0 }) |
    (if tx_full { STAT_TXFF } else { u8:0 }) |
    (if rx_empty { STAT_RXFE } else { u8:0 }) |
    (if rx_full { STAT_RXFF } else { u8:0 }) |
    (if state.overrun_err { STAT_OE } else { u8:0 }) |
    (if state.frame_err { STAT_FE } else { u8:0 }) |
    (if state.parity_err { STAT_PE } else { u8:0 })
}

// =============================================================================
// Register Write / FIFO Operations
// =============================================================================

fn do_reg_write(state: UartState, addr: u4, data: u8) -> UartState {
    if addr == REG_CTRL {
        UartState { ctrl: data, ..state }
    } else if addr == REG_PARITY {
        UartState { parity_cfg: data, ..state }
    } else if addr == REG_BRD_L {
        let new_brd = (state.brd_int & u16:0xFF00) | (data as u16);
        UartState { brd_int: new_brd, ..state }
    } else if addr == REG_BRD_H {
        let new_brd = (state.brd_int & u16:0x00FF) | ((data as u16) << u16:8);
        UartState { brd_int: new_brd, ..state }
    } else if addr == REG_BRD_F {
        UartState { brd_frac: (data & u8:0x3F) as u6, ..state }
    } else if addr == REG_IRQ_EN {
        UartState { irq_en: data, ..state }
    } else if addr == REG_IRQ_STAT {
        // Write 1 to clear
        UartState { irq_stat: state.irq_stat & !data, ..state }
    } else if addr == REG_IFLS {
        UartState { ifls: data, ..state }
    } else if addr == REG_RXTO_CFG {
        UartState { rxto_cfg: data, ..state }
    } else if addr == REG_TXDATA {
        // Push to TX FIFO if not full
        let fifo_en = (state.ctrl & CTRL_FEN) != u8:0;
        let max_count = if fifo_en { u3:4 } else { u3:1 };
        if state.tx_fifo_count < max_count {
            UartState {
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

fn do_rx_read(state: UartState) -> (u8, UartState) {
    // Pop from RX FIFO
    if state.rx_fifo_count > u3:0 {
        let rx_byte = state.rx_fifo[state.rx_fifo_tail];
        // Clear error flags on read
        (rx_byte, UartState {
            rx_fifo_tail: state.rx_fifo_tail + u2:1,
            rx_fifo_count: state.rx_fifo_count - u3:1,
            overrun_err: false,
            frame_err: false,
            parity_err: false,
            ..state
        })
    } else {
        (u8:0, state)
    }
}

// =============================================================================
// IRQ Generation
// =============================================================================

fn update_irq(state: UartState) -> UartState {
    let tx_thr = get_threshold((state.ifls & u8:0x03) as u2);
    let rx_thr = get_threshold(((state.ifls >> u8:4) & u8:0x03) as u2);

    // TX level: IRQ when count <= threshold (FIFO draining)
    let tx_lvl_irq = state.tx_fifo_count <= tx_thr;
    // RX level: IRQ when count >= threshold (FIFO filling)
    let rx_lvl_irq = state.rx_fifo_count >= rx_thr;

    let new_stat = (if state.rxto_counter >= state.rxto_cfg && state.rxto_cfg != u8:0 && state.rx_fifo_count > u3:0 { IRQ_RXTO } else { u8:0 }) |
                   (if tx_lvl_irq { IRQ_TXLVL } else { u8:0 }) |
                   (if rx_lvl_irq { IRQ_RXLVL } else { u8:0 }) |
                   (if state.overrun_err { IRQ_OE } else { u8:0 }) |
                   (if state.frame_err { IRQ_FE } else { u8:0 });

    // Set bits in irq_stat (they're sticky until cleared)
    UartState { irq_stat: state.irq_stat | new_stat, ..state }
}

// =============================================================================
// RX Timeout Counter
// =============================================================================

fn update_rxto(state: UartState, baud_tick: bool) -> UartState {
    // Count bit periods when RX is idle with data in FIFO
    if baud_tick && state.rx_state == RX_IDLE && state.rx_fifo_count > u3:0 {
        // Count 16 baud ticks = 1 bit period
        if state.rx_sample_cnt == u4:15 {
            let new_rxto = if state.rxto_counter < u8:255 {
                state.rxto_counter + u8:1
            } else {
                state.rxto_counter
            };
            UartState { rxto_counter: new_rxto, rx_sample_cnt: u4:0, ..state }
        } else {
            UartState { rx_sample_cnt: state.rx_sample_cnt + u4:1, ..state }
        }
    } else if state.rx_state != RX_IDLE {
        // Reset when receiving
        UartState { rxto_counter: u8:0, ..state }
    } else {
        state
    }
}

// =============================================================================
// Main UART Function
// =============================================================================

pub fn uart_tick(state: UartState, bus_in: UartInput) -> (UartState, UartOutput) {
    // Baud rate generator
    let (new_baud_cnt, new_frac_accum, baud_tick) = baud_tick_gen(state);
    let state1 = UartState {
        baud_counter: new_baud_cnt,
        frac_accum: new_frac_accum,
        baud_tick: baud_tick,
        ..state
    };

    // Loopback: feed TX back to RX
    let loopback = (state1.ctrl & CTRL_LBE) != u8:0;

    // TX state machine
    let (state2, tx_out) = tx_tick(state1, baud_tick);

    // RX input (use loopback or external)
    let rx_in = if loopback { tx_out } else { bus_in.rx_pin };

    // RX state machine
    let state3 = rx_tick(state2, baud_tick, rx_in);

    // RX timeout
    let state4 = update_rxto(state3, baud_tick);

    // Register access
    let state5 = if bus_in.wr {
        do_reg_write(state4, bus_in.addr, bus_in.data_in)
    } else {
        state4
    };

    // Read data
    let read_stat = do_read(state5);
    let (rx_byte, state6) = if bus_in.rd && bus_in.addr == REG_RXDATA {
        do_rx_read(state5)
    } else {
        (u8:0, state5)
    };

    // Update IRQ status
    let state7 = update_irq(state6);

    // Build read data output (counts now fit in 3 bits each)
    let fifolvl = ((state7.rx_fifo_count as u8) << u8:4) | (state7.tx_fifo_count as u8);

    let data_out = if bus_in.rd {
        if bus_in.addr == REG_CTRL { state7.ctrl }
        else if bus_in.addr == REG_PARITY { state7.parity_cfg }
        else if bus_in.addr == REG_STAT { read_stat }
        else if bus_in.addr == REG_FIFOLVL { fifolvl }
        else if bus_in.addr == REG_RXDATA { rx_byte }
        else if bus_in.addr == REG_BRD_L { (state7.brd_int & u16:0xFF) as u8 }
        else if bus_in.addr == REG_BRD_H { ((state7.brd_int >> u16:8) & u16:0xFF) as u8 }
        else if bus_in.addr == REG_BRD_F { state7.brd_frac as u8 }
        else if bus_in.addr == REG_IRQ_EN { state7.irq_en }
        else if bus_in.addr == REG_IRQ_STAT { state7.irq_stat }
        else if bus_in.addr == REG_IFLS { state7.ifls }
        else if bus_in.addr == REG_RXTO_CFG { state7.rxto_cfg }
        else { u8:0xFF }
    } else {
        u8:0xFF
    };

    // IRQ output
    let irq = (state7.irq_stat & state7.irq_en) != u8:0;

    let output = UartOutput {
        data_out: data_out,
        irq: irq,
        tx_pin: tx_out,
    };

    (state7, output)
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
}

#[test]
fn test_fifo_array_ops() {
    let fifo = u8[4]:[u8:0, ...];
    let fifo = update(fifo, u2:0, u8:0xAA);
    let fifo = update(fifo, u2:1, u8:0xBB);
    let fifo = update(fifo, u2:3, u8:0xFF);

    assert_eq(fifo[u2:0], u8:0xAA);
    assert_eq(fifo[u2:1], u8:0xBB);
    assert_eq(fifo[u2:3], u8:0xFF);
}

#[test]
fn test_parity_calc() {
    assert_eq(calc_parity(u8:0x00), false);  // 0 ones = even
    assert_eq(calc_parity(u8:0x01), true);   // 1 one = odd
    assert_eq(calc_parity(u8:0x03), false);  // 2 ones = even
    assert_eq(calc_parity(u8:0xFF), false);  // 8 ones = even
    assert_eq(calc_parity(u8:0x55), false);  // 4 ones = even
}

#[test]
fn test_tx_fifo_push() {
    let state = initial_state();
    let state = UartState { ctrl: CTRL_EN | CTRL_FEN, ..state };

    // Push a byte to TX FIFO
    let input = UartInput {
        addr: REG_TXDATA,
        data_in: u8:0x55,
        rd: false,
        wr: true,
        rx_pin: true,
    };

    let (state2, _) = uart_tick(state, input);
    assert_eq(state2.tx_fifo_count, u3:1);
}

#[test]
fn test_baud_divisor_write() {
    let state = initial_state();

    // Write low byte
    let input1 = UartInput {
        addr: REG_BRD_L,
        data_in: u8:0x34,
        rd: false,
        wr: true,
        rx_pin: true,
    };
    let (state2, _) = uart_tick(state, input1);

    // Write high byte
    let input2 = UartInput {
        addr: REG_BRD_H,
        data_in: u8:0x12,
        rd: false,
        wr: true,
        rx_pin: true,
    };
    let (state3, _) = uart_tick(state2, input2);

    assert_eq(state3.brd_int, u16:0x1234);
}

#[test]
fn test_loopback_idle() {
    // In loopback, TX feeds RX. When idle, both should be high.
    let state = initial_state();
    let state = UartState {
        ctrl: CTRL_EN | CTRL_TXEN | CTRL_RXEN | CTRL_LBE,
        brd_int: u16:10,
        ..state
    };

    let input = UartInput {
        addr: u4:0,
        data_in: u8:0,
        rd: false,
        wr: false,
        rx_pin: true,
    };

    let (_, output) = uart_tick(state, input);
    assert_eq(output.tx_pin, true);  // Idle high
}

#[test]
fn test_fifo_depth_limit() {
    let state = initial_state();
    let state = UartState { ctrl: CTRL_EN | CTRL_FEN, ..state };

    let input = UartInput {
        addr: REG_TXDATA,
        data_in: u8:0x00,
        rd: false,
        wr: true,
        rx_pin: true,
    };

    // Push 4 bytes (should all succeed)
    let (state, _) = uart_tick(state, input);
    let (state, _) = uart_tick(state, input);
    let (state, _) = uart_tick(state, input);
    let (state, _) = uart_tick(state, input);
    assert_eq(state.tx_fifo_count, u3:4);

    // Push 5th byte (should be rejected - FIFO full)
    let (state, _) = uart_tick(state, input);
    assert_eq(state.tx_fifo_count, u3:4);  // Still 4
}
