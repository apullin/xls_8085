// 8-bit GPIO with IRQ and Bitbanding
// Memory-mapped peripheral for 8085 MCU configuration
//
// Features:
//   - 8 GPIO pins, individually configurable direction
//   - Per-pin output mode: push-pull or open-drain
//   - Per-pin IRQ with selectable edge (rising, falling, both)
//   - Bitband region for atomic bit operations on DATA
//
// Register Map (16 bytes):
//   Direct registers (0x00-0x07):
//     0x00: DATA_OUT   - output data register
//     0x01: DATA_IN    - input data (read-only, directly from pins)
//     0x02: DIR        - direction (0=input, 1=output)
//     0x03: IRQ_EN     - interrupt enable per pin
//     0x04: IRQ_RISE   - rising edge interrupt enable
//     0x05: IRQ_FALL   - falling edge interrupt enable
//     0x06: IRQ_STATUS - interrupt pending (write 1 to clear)
//     0x07: OUT_MODE   - output mode (0=push-pull, 1=open-drain)
//
//   Bitband region (0x08-0x0F):
//     0x08-0x0F: DATA bits 0-7
//                Read:  returns bit value (0 or 1)
//                Write: bit 0 of data becomes the new bit value
//
// Open-drain mode:
//   When OUT_MODE bit is 1, the pin only drives low. When DATA=1, pin is hi-Z.
//   Useful for I2C, wired-OR buses, etc.

// =============================================================================
// Constants
// =============================================================================

// Direct register addresses
const REG_DATA_OUT: u4   = 0x0;
const REG_DATA_IN: u4    = 0x1;
const REG_DIR: u4        = 0x2;
const REG_IRQ_EN: u4     = 0x3;
const REG_IRQ_RISE: u4   = 0x4;
const REG_IRQ_FALL: u4   = 0x5;
const REG_IRQ_STATUS: u4 = 0x6;
const REG_OUT_MODE: u4   = 0x7;  // 0=push-pull, 1=open-drain

// Bitband starts at 0x08
const BB_DATA_BASE: u4   = 0x8;

// =============================================================================
// State
// =============================================================================

pub struct GpioState {
    // Output and direction registers
    data_out: u8,
    dir: u8,           // 0=input, 1=output
    out_mode: u8,      // 0=push-pull, 1=open-drain

    // IRQ configuration
    irq_en: u8,        // Per-pin IRQ enable
    irq_rise: u8,      // Rising edge enable
    irq_fall: u8,      // Falling edge enable
    irq_status: u8,    // Pending flags

    // Previous pin state for edge detection
    pin_prev: u8,
}

// =============================================================================
// Bus Interface
// =============================================================================

pub struct GpioInput {
    addr: u4,          // 4-bit address for 16-byte region
    data_in: u8,
    rd: bool,
    wr: bool,

    // External pin inputs (directly from pads)
    pins_in: u8,
}

pub struct GpioOutput {
    data_out: u8,
    irq: bool,

    // Pin outputs and output enables
    pins_out: u8,      // Output values
    pins_oe: u8,       // Output enables (active high)
}

// =============================================================================
// Helper Functions
// =============================================================================

pub fn initial_state() -> GpioState {
    GpioState {
        data_out: u8:0,
        dir: u8:0,
        out_mode: u8:0,   // Default: push-pull
        irq_en: u8:0,
        irq_rise: u8:0,
        irq_fall: u8:0,
        irq_status: u8:0,
        pin_prev: u8:0,
    }
}

// Get single bit from byte
fn get_bit(val: u8, bit_idx: u3) -> u8 {
    (val >> (bit_idx as u8)) & u8:1
}

// Write single bit in byte (set or clear based on bit 0 of data)
fn write_bit(val: u8, bit_idx: u3, data: u8) -> u8 {
    let mask = u8:1 << (bit_idx as u8);
    if (data & u8:1) == u8:1 {
        val | mask      // Set
    } else {
        val & !mask     // Clear
    }
}

// =============================================================================
// Register Read Logic
// =============================================================================

fn do_read(state: GpioState, addr: u4, pins_in: u8) -> u8 {
    // Compose actual pin input: use data_out for outputs, pins_in for inputs
    let actual_pins = (state.data_out & state.dir) | (pins_in & !state.dir);

    if addr == REG_DATA_OUT {
        state.data_out
    } else if addr == REG_DATA_IN {
        actual_pins
    } else if addr == REG_DIR {
        state.dir
    } else if addr == REG_IRQ_EN {
        state.irq_en
    } else if addr == REG_IRQ_RISE {
        state.irq_rise
    } else if addr == REG_IRQ_FALL {
        state.irq_fall
    } else if addr == REG_IRQ_STATUS {
        state.irq_status
    } else if addr == REG_OUT_MODE {
        state.out_mode
    } else if addr >= BB_DATA_BASE {
        // Bitband DATA read - return bit value (0 or 1)
        let bit_idx = (addr - BB_DATA_BASE) as u3;
        get_bit(state.data_out, bit_idx)
    } else {
        u8:0xFF
    }
}

// =============================================================================
// Register Write Logic
// =============================================================================

fn do_write(state: GpioState, addr: u4, data: u8) -> GpioState {
    if addr == REG_DATA_OUT {
        GpioState { data_out: data, ..state }
    } else if addr == REG_DIR {
        GpioState { dir: data, ..state }
    } else if addr == REG_IRQ_EN {
        GpioState { irq_en: data, ..state }
    } else if addr == REG_IRQ_RISE {
        GpioState { irq_rise: data, ..state }
    } else if addr == REG_IRQ_FALL {
        GpioState { irq_fall: data, ..state }
    } else if addr == REG_IRQ_STATUS {
        // Write 1 to clear
        GpioState { irq_status: state.irq_status & !data, ..state }
    } else if addr == REG_OUT_MODE {
        GpioState { out_mode: data, ..state }
    } else if addr >= BB_DATA_BASE {
        // Bitband DATA write - bit 0 of data becomes the bit value
        let bit_idx = (addr - BB_DATA_BASE) as u3;
        GpioState { data_out: write_bit(state.data_out, bit_idx, data), ..state }
    } else {
        state
    }
}

// =============================================================================
// Edge Detection and IRQ Logic
// =============================================================================

fn do_edge_detect(state: GpioState, pins_in: u8) -> GpioState {
    // Get actual pin values (respecting direction)
    let actual_pins = (state.data_out & state.dir) | (pins_in & !state.dir);

    // Detect edges
    let rising = actual_pins & !state.pin_prev;   // Was 0, now 1
    let falling = !actual_pins & state.pin_prev;  // Was 1, now 0

    // Generate new IRQ status
    let rise_irqs = rising & state.irq_rise & state.irq_en;
    let fall_irqs = falling & state.irq_fall & state.irq_en;
    let new_status = state.irq_status | rise_irqs | fall_irqs;

    GpioState {
        irq_status: new_status,
        pin_prev: actual_pins,
        ..state
    }
}

// =============================================================================
// Main GPIO Function
// =============================================================================

pub fn gpio_tick(state: GpioState, bus_in: GpioInput) -> (GpioState, GpioOutput) {
    // Edge detection first (happens every cycle)
    let state_after_edge = do_edge_detect(state, bus_in.pins_in);

    // Process read
    let data_out = if bus_in.rd {
        do_read(state_after_edge, bus_in.addr, bus_in.pins_in)
    } else {
        u8:0xFF
    };

    // Process write
    let state_after_write = if bus_in.wr {
        do_write(state_after_edge, bus_in.addr, bus_in.data_in)
    } else {
        state_after_edge
    };

    // Generate IRQ (active if any enabled interrupt is pending)
    let irq = (state_after_write.irq_status & state_after_write.irq_en) != u8:0;

    // Output enable calculation:
    // Push-pull (out_mode=0): OE = DIR (always drive when output)
    // Open-drain (out_mode=1): OE = DIR & ~DATA (only drive low, hi-Z when data=1)
    // Combined: OE = DIR & (~out_mode | ~data_out)
    let pins_oe = state_after_write.dir &
                  (!state_after_write.out_mode | !state_after_write.data_out);

    // Output
    let output = GpioOutput {
        data_out: data_out,
        irq: irq,
        pins_out: state_after_write.data_out,
        pins_oe: pins_oe,
    };

    (state_after_write, output)
}

// =============================================================================
// Tests
// =============================================================================

#[test]
fn test_initial_state() {
    let state = initial_state();
    assert_eq(state.data_out, u8:0);
    assert_eq(state.dir, u8:0);
}

#[test]
fn test_write_data_out() {
    let state = initial_state();
    let input = GpioInput {
        addr: REG_DATA_OUT,
        data_in: u8:0xA5,
        rd: false,
        wr: true,
        pins_in: u8:0,
    };
    let (state2, _) = gpio_tick(state, input);
    assert_eq(state2.data_out, u8:0xA5);
}

#[test]
fn test_read_data_out() {
    let state = GpioState { data_out: u8:0x5A, ..initial_state() };
    let input = GpioInput {
        addr: REG_DATA_OUT,
        data_in: u8:0,
        rd: true,
        wr: false,
        pins_in: u8:0,
    };
    let (_, output) = gpio_tick(state, input);
    assert_eq(output.data_out, u8:0x5A);
}

#[test]
fn test_direction() {
    let state = GpioState { dir: u8:0x0F, data_out: u8:0xFF, ..initial_state() };
    let input = GpioInput {
        addr: REG_DATA_OUT,
        data_in: u8:0,
        rd: false,
        wr: false,
        pins_in: u8:0,
    };
    let (_, output) = gpio_tick(state, input);
    // Lower 4 bits are outputs (OE=1), upper 4 are inputs (OE=0)
    assert_eq(output.pins_oe, u8:0x0F);
    assert_eq(output.pins_out, u8:0xFF);
}

#[test]
fn test_bitband_set() {
    let state = GpioState { data_out: u8:0x00, ..initial_state() };
    let input = GpioInput {
        addr: BB_DATA_BASE + u4:3,  // Bit 3
        data_in: u8:0x01,           // Set (bit 0 = 1)
        rd: false,
        wr: true,
        pins_in: u8:0,
    };
    let (state2, _) = gpio_tick(state, input);
    assert_eq(state2.data_out, u8:0x08);  // Bit 3 set
}

#[test]
fn test_bitband_clear() {
    let state = GpioState { data_out: u8:0xFF, ..initial_state() };
    let input = GpioInput {
        addr: BB_DATA_BASE + u4:5,  // Bit 5
        data_in: u8:0x00,           // Clear (bit 0 = 0)
        rd: false,
        wr: true,
        pins_in: u8:0,
    };
    let (state2, _) = gpio_tick(state, input);
    assert_eq(state2.data_out, u8:0xDF);  // Bit 5 cleared
}

#[test]
fn test_bitband_read() {
    let state = GpioState { data_out: u8:0x08, ..initial_state() };  // Bit 3 set

    // Read bit 3 (should be 1)
    let input3 = GpioInput {
        addr: BB_DATA_BASE + u4:3,
        data_in: u8:0,
        rd: true,
        wr: false,
        pins_in: u8:0,
    };
    let (_, out3) = gpio_tick(state, input3);
    assert_eq(out3.data_out, u8:0x01);

    // Read bit 2 (should be 0)
    let input2 = GpioInput {
        addr: BB_DATA_BASE + u4:2,
        data_in: u8:0,
        rd: true,
        wr: false,
        pins_in: u8:0,
    };
    let (_, out2) = gpio_tick(state, input2);
    assert_eq(out2.data_out, u8:0x00);
}

#[test]
fn test_rising_edge_irq() {
    // Configure for rising edge IRQ on pin 0
    let state = GpioState {
        irq_en: u8:0x01,
        irq_rise: u8:0x01,
        irq_fall: u8:0x00,
        pin_prev: u8:0x00,  // Pin was low
        ..initial_state()
    };

    // Pin goes high
    let input = GpioInput {
        addr: u4:0,
        data_in: u8:0,
        rd: false,
        wr: false,
        pins_in: u8:0x01,  // Pin 0 now high
    };

    let (state2, output) = gpio_tick(state, input);
    assert_eq(state2.irq_status, u8:0x01);  // IRQ pending
    assert_eq(output.irq, true);
}

#[test]
fn test_falling_edge_irq() {
    // Configure for falling edge IRQ on pin 2
    let state = GpioState {
        irq_en: u8:0x04,
        irq_rise: u8:0x00,
        irq_fall: u8:0x04,
        pin_prev: u8:0x04,  // Pin was high
        ..initial_state()
    };

    // Pin goes low
    let input = GpioInput {
        addr: u4:0,
        data_in: u8:0,
        rd: false,
        wr: false,
        pins_in: u8:0x00,  // Pin 2 now low
    };

    let (state2, output) = gpio_tick(state, input);
    assert_eq(state2.irq_status, u8:0x04);  // IRQ pending
    assert_eq(output.irq, true);
}

#[test]
fn test_irq_status_clear() {
    let state = GpioState { irq_status: u8:0x05, irq_en: u8:0xFF, ..initial_state() };
    let input = GpioInput {
        addr: REG_IRQ_STATUS,
        data_in: u8:0x01,  // Clear bit 0 only
        rd: false,
        wr: true,
        pins_in: u8:0,
    };
    let (state2, _) = gpio_tick(state, input);
    assert_eq(state2.irq_status, u8:0x04);  // Bit 0 cleared, bit 2 remains
}

#[test]
fn test_both_edges() {
    // Configure for both edges on pin 0
    let state = GpioState {
        irq_en: u8:0x01,
        irq_rise: u8:0x01,
        irq_fall: u8:0x01,
        pin_prev: u8:0x01,  // Pin was high
        ..initial_state()
    };

    // Pin goes low - should trigger
    let input = GpioInput {
        addr: u4:0,
        data_in: u8:0,
        rd: false,
        wr: false,
        pins_in: u8:0x00,
    };

    let (state2, output) = gpio_tick(state, input);
    assert_eq(output.irq, true);
}

#[test]
fn test_push_pull_mode() {
    // Push-pull: OE always follows DIR
    let state = GpioState {
        dir: u8:0x0F,       // Lower 4 pins are outputs
        data_out: u8:0x05,  // Bits 0,2 = 1; bits 1,3 = 0
        out_mode: u8:0x00,  // Push-pull (default)
        ..initial_state()
    };
    let input = GpioInput {
        addr: u4:0,
        data_in: u8:0,
        rd: false,
        wr: false,
        pins_in: u8:0,
    };
    let (_, output) = gpio_tick(state, input);
    // In push-pull, OE = DIR regardless of data
    assert_eq(output.pins_oe, u8:0x0F);
    assert_eq(output.pins_out, u8:0x05);
}

#[test]
fn test_open_drain_mode() {
    // Open-drain: OE = DIR & ~data_out (only drive low)
    let state = GpioState {
        dir: u8:0x0F,       // Lower 4 pins are outputs
        data_out: u8:0x05,  // Bits 0,2 = 1 (hi-Z); bits 1,3 = 0 (drive low)
        out_mode: u8:0x0F,  // Open-drain on lower 4 pins
        ..initial_state()
    };
    let input = GpioInput {
        addr: u4:0,
        data_in: u8:0,
        rd: false,
        wr: false,
        pins_in: u8:0,
    };
    let (_, output) = gpio_tick(state, input);
    // In open-drain: OE = DIR & ~data_out = 0x0F & ~0x05 = 0x0F & 0xFA = 0x0A
    // So bits 1,3 have OE (driving low), bits 0,2 are hi-Z
    assert_eq(output.pins_oe, u8:0x0A);
    assert_eq(output.pins_out, u8:0x05);
}

#[test]
fn test_mixed_push_pull_open_drain() {
    // Mix of push-pull and open-drain on different pins
    let state = GpioState {
        dir: u8:0xFF,       // All outputs
        data_out: u8:0xAA,  // Alternating: 1,0,1,0,1,0,1,0
        out_mode: u8:0x0F,  // Lower 4 = open-drain, upper 4 = push-pull
        ..initial_state()
    };
    let input = GpioInput {
        addr: u4:0,
        data_in: u8:0,
        rd: false,
        wr: false,
        pins_in: u8:0,
    };
    let (_, output) = gpio_tick(state, input);
    // Upper 4 (push-pull): OE = 0xF0 (all enabled)
    // Lower 4 (open-drain): OE = 0x0F & ~0x0A = 0x0F & 0x05 = 0x05 (bits 0,2)
    // Wait, data_out lower nibble = 0xA = 1010, so ~0xA = 0101 = 0x5
    // OE lower = 0x0F & 0x05 = 0x05
    // Total OE = 0xF0 | 0x05 = 0xF5
    assert_eq(output.pins_oe, u8:0xF5);
}
