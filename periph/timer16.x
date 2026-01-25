// 16-bit Timer with 4 Compare Channels
// Memory-mapped peripheral for 8085 MCU configuration

// =============================================================================
// Constants
// =============================================================================

// Control register bits
const CTRL_ENABLE: u8 = 0x01;
const CTRL_AUTO_RELOAD: u8 = 0x02;
const CTRL_COUNT_DOWN: u8 = 0x04;

// Status/IRQ enable bits
const FLAG_CMP0: u8 = 0x01;
const FLAG_CMP1: u8 = 0x02;
const FLAG_CMP2: u8 = 0x04;
const FLAG_CMP3: u8 = 0x08;
const FLAG_OVF: u8 = 0x10;

// Register addresses
const REG_CNT_LO: u4 = 0x0;
const REG_CNT_HI: u4 = 0x1;
const REG_RELOAD_LO: u4 = 0x2;
const REG_RELOAD_HI: u4 = 0x3;
const REG_PRESCALE: u4 = 0x4;
const REG_CTRL: u4 = 0x5;
const REG_IRQ_EN: u4 = 0x6;
const REG_STATUS: u4 = 0x7;
const REG_CMP0_LO: u4 = 0x8;
const REG_CMP0_HI: u4 = 0x9;
const REG_CMP1_LO: u4 = 0xA;
const REG_CMP1_HI: u4 = 0xB;
const REG_CMP2_LO: u4 = 0xC;
const REG_CMP2_HI: u4 = 0xD;
const REG_CMP3_LO: u4 = 0xE;
const REG_CMP3_HI: u4 = 0xF;

// =============================================================================
// State
// =============================================================================

pub struct TimerState {
    // Counter and reload
    counter: u16,
    reload: u16,

    // Prescaler
    prescale: u8,
    prescale_cnt: u8,

    // Control and status
    ctrl: u8,
    irq_en: u8,
    status: u8,

    // Compare registers
    cmp0: u16,
    cmp1: u16,
    cmp2: u16,
    cmp3: u16,

    // Latch for atomic counter reads
    cnt_hi_latch: u8,
}

// =============================================================================
// Bus Interface
// =============================================================================

pub struct TimerInput {
    // Register interface
    addr: u4,
    data_in: u8,
    rd: bool,
    wr: bool,

    // Clock tick (active each cycle timer should potentially count)
    tick: bool,
}

pub struct TimerOutput {
    data_out: u8,
    irq: bool,
}

// =============================================================================
// Helper Functions
// =============================================================================

pub fn initial_state() -> TimerState {
    TimerState {
        counter: u16:0,
        reload: u16:0,
        prescale: u8:0,
        prescale_cnt: u8:0,
        ctrl: u8:0,
        irq_en: u8:0,
        status: u8:0,
        cmp0: u16:0,
        cmp1: u16:0,
        cmp2: u16:0,
        cmp3: u16:0,
        cnt_hi_latch: u8:0,
    }
}

fn get_low(val: u16) -> u8 {
    val[0:8] as u8
}

fn get_high(val: u16) -> u8 {
    val[8:16] as u8
}

fn set_low(val: u16, lo: u8) -> u16 {
    (val & u16:0xFF00) | (lo as u16)
}

fn set_high(val: u16, hi: u8) -> u16 {
    (val & u16:0x00FF) | ((hi as u16) << 8)
}

// =============================================================================
// Register Read Logic
// =============================================================================

fn do_read(state: TimerState, addr: u4) -> (TimerState, u8) {
    match addr {
        REG_CNT_LO => {
            // Latch high byte for atomic read
            let new_state = TimerState { cnt_hi_latch: get_high(state.counter), ..state };
            (new_state, get_low(state.counter))
        },
        REG_CNT_HI => (state, state.cnt_hi_latch),
        REG_RELOAD_LO => (state, get_low(state.reload)),
        REG_RELOAD_HI => (state, get_high(state.reload)),
        REG_PRESCALE => (state, state.prescale),
        REG_CTRL => (state, state.ctrl),
        REG_IRQ_EN => (state, state.irq_en),
        REG_STATUS => (state, state.status),
        REG_CMP0_LO => (state, get_low(state.cmp0)),
        REG_CMP0_HI => (state, get_high(state.cmp0)),
        REG_CMP1_LO => (state, get_low(state.cmp1)),
        REG_CMP1_HI => (state, get_high(state.cmp1)),
        REG_CMP2_LO => (state, get_low(state.cmp2)),
        REG_CMP2_HI => (state, get_high(state.cmp2)),
        REG_CMP3_LO => (state, get_low(state.cmp3)),
        REG_CMP3_HI => (state, get_high(state.cmp3)),
        _ => (state, u8:0xFF),
    }
}

// =============================================================================
// Register Write Logic
// =============================================================================

fn do_write(state: TimerState, addr: u4, data: u8) -> TimerState {
    match addr {
        REG_CNT_LO => TimerState { counter: set_low(state.counter, data), ..state },
        REG_CNT_HI => TimerState { counter: set_high(state.counter, data), ..state },
        REG_RELOAD_LO => TimerState { reload: set_low(state.reload, data), ..state },
        REG_RELOAD_HI => TimerState { reload: set_high(state.reload, data), ..state },
        REG_PRESCALE => TimerState { prescale: data, ..state },
        REG_CTRL => TimerState { ctrl: data, ..state },
        REG_IRQ_EN => TimerState { irq_en: data, ..state },
        // STATUS: write 1 to clear
        REG_STATUS => TimerState { status: state.status & !data, ..state },
        REG_CMP0_LO => TimerState { cmp0: set_low(state.cmp0, data), ..state },
        REG_CMP0_HI => TimerState { cmp0: set_high(state.cmp0, data), ..state },
        REG_CMP1_LO => TimerState { cmp1: set_low(state.cmp1, data), ..state },
        REG_CMP1_HI => TimerState { cmp1: set_high(state.cmp1, data), ..state },
        REG_CMP2_LO => TimerState { cmp2: set_low(state.cmp2, data), ..state },
        REG_CMP2_HI => TimerState { cmp2: set_high(state.cmp2, data), ..state },
        REG_CMP3_LO => TimerState { cmp3: set_low(state.cmp3, data), ..state },
        REG_CMP3_HI => TimerState { cmp3: set_high(state.cmp3, data), ..state },
        _ => state,
    }
}

// =============================================================================
// Counter Logic
// =============================================================================

fn do_count(state: TimerState) -> TimerState {
    let enabled = (state.ctrl & CTRL_ENABLE) != u8:0;
    let count_down = (state.ctrl & CTRL_COUNT_DOWN) != u8:0;
    let auto_reload = (state.ctrl & CTRL_AUTO_RELOAD) != u8:0;

    if !enabled {
        state
    } else {
        // Prescaler check
        let prescale_match = state.prescale_cnt >= state.prescale;
        let new_prescale_cnt = if prescale_match { u8:0 } else { state.prescale_cnt + u8:1 };

        if !prescale_match {
            // Just update prescaler, no count
            TimerState { prescale_cnt: new_prescale_cnt, ..state }
        } else {
            // Prescaler matched - do the count
            let (new_counter, overflow) = if count_down {
                // Count down
                if state.counter == u16:0 {
                    let reload_val = if auto_reload { state.reload } else { u16:0 };
                    (reload_val, true)
                } else {
                    (state.counter - u16:1, false)
                }
            } else {
                // Count up
                if state.counter == u16:0xFFFF {
                    let reload_val = if auto_reload { state.reload } else { u16:0 };
                    (reload_val, true)
                } else {
                    (state.counter + u16:1, false)
                }
            };

            // Update status flags
            let status_with_ovf = if overflow { state.status | FLAG_OVF } else { state.status };

            // Compare matches (check new counter value)
            let status_with_cmp0 = if new_counter == state.cmp0 { status_with_ovf | FLAG_CMP0 } else { status_with_ovf };
            let status_with_cmp1 = if new_counter == state.cmp1 { status_with_cmp0 | FLAG_CMP1 } else { status_with_cmp0 };
            let status_with_cmp2 = if new_counter == state.cmp2 { status_with_cmp1 | FLAG_CMP2 } else { status_with_cmp1 };
            let new_status = if new_counter == state.cmp3 { status_with_cmp2 | FLAG_CMP3 } else { status_with_cmp2 };

            // One-shot: disable on overflow
            let new_ctrl = if overflow && !auto_reload { state.ctrl & !CTRL_ENABLE } else { state.ctrl };

            TimerState {
                counter: new_counter,
                prescale_cnt: new_prescale_cnt,
                status: new_status,
                ctrl: new_ctrl,
                ..state
            }
        }
    }
}

// =============================================================================
// Main Timer Function
// =============================================================================

pub fn timer_tick(state: TimerState, bus_in: TimerInput) -> (TimerState, TimerOutput) {
    // Process read (may latch high byte)
    let (state_after_read, data_out) = if bus_in.rd {
        do_read(state, bus_in.addr)
    } else {
        (state, u8:0xFF)
    };

    // Process write
    let state_after_write = if bus_in.wr {
        do_write(state_after_read, bus_in.addr, bus_in.data_in)
    } else {
        state_after_read
    };

    // Process count
    let state_after_count = if bus_in.tick {
        do_count(state_after_write)
    } else {
        state_after_write
    };

    // Generate IRQ
    let irq = (state_after_count.status & state_after_count.irq_en) != u8:0;

    (state_after_count, TimerOutput { data_out, irq })
}

// =============================================================================
// Tests
// =============================================================================

#[test]
fn test_initial_state() {
    let state = initial_state();
    assert_eq(state.counter, u16:0);
    assert_eq(state.ctrl, u8:0);
}

#[test]
fn test_write_reload() {
    let state = initial_state();
    let input = TimerInput {
        addr: REG_RELOAD_LO,
        data_in: u8:0x34,
        rd: false,
        wr: true,
        tick: false,
    };
    let (state2, _) = timer_tick(state, input);
    assert_eq(get_low(state2.reload), u8:0x34);

    let input2 = TimerInput {
        addr: REG_RELOAD_HI,
        data_in: u8:0x12,
        rd: false,
        wr: true,
        tick: false,
    };
    let (state3, _) = timer_tick(state2, input2);
    assert_eq(state3.reload, u16:0x1234);
}

#[test]
fn test_count_up() {
    let state = TimerState { ctrl: CTRL_ENABLE, prescale: u8:0, ..initial_state() };

    let tick_input = TimerInput {
        addr: u4:0,
        data_in: u8:0,
        rd: false,
        wr: false,
        tick: true,
    };

    // Tick a few times
    let (state2, _) = timer_tick(state, tick_input);
    assert_eq(state2.counter, u16:1);

    let (state3, _) = timer_tick(state2, tick_input);
    assert_eq(state3.counter, u16:2);

    let (state4, _) = timer_tick(state3, tick_input);
    assert_eq(state4.counter, u16:3);
}

#[test]
fn test_prescaler() {
    let state = TimerState { ctrl: CTRL_ENABLE, prescale: u8:2, ..initial_state() };

    let tick_input = TimerInput {
        addr: u4:0,
        data_in: u8:0,
        rd: false,
        wr: false,
        tick: true,
    };

    // First two ticks: prescaler counts but counter doesn't increment
    let (state2, _) = timer_tick(state, tick_input);
    assert_eq(state2.counter, u16:0);
    assert_eq(state2.prescale_cnt, u8:1);

    let (state3, _) = timer_tick(state2, tick_input);
    assert_eq(state3.counter, u16:0);
    assert_eq(state3.prescale_cnt, u8:2);

    // Third tick: prescaler matches, counter increments, prescaler resets
    let (state4, _) = timer_tick(state3, tick_input);
    assert_eq(state4.counter, u16:1);
    assert_eq(state4.prescale_cnt, u8:0);
}

#[test]
fn test_compare_match() {
    let state = TimerState {
        ctrl: CTRL_ENABLE,
        prescale: u8:0,
        cmp0: u16:2,
        irq_en: FLAG_CMP0,
        ..initial_state()
    };

    let tick_input = TimerInput {
        addr: u4:0,
        data_in: u8:0,
        rd: false,
        wr: false,
        tick: true,
    };

    let (state2, out2) = timer_tick(state, tick_input);  // counter = 1
    assert_eq(state2.status & FLAG_CMP0, u8:0);
    assert_eq(out2.irq, false);

    let (state3, out3) = timer_tick(state2, tick_input);  // counter = 2, match!
    assert_eq(state3.status & FLAG_CMP0, FLAG_CMP0);
    assert_eq(out3.irq, true);
}

#[test]
fn test_overflow_auto_reload() {
    let state = TimerState {
        ctrl: CTRL_ENABLE | CTRL_AUTO_RELOAD,
        prescale: u8:0,
        counter: u16:0xFFFE,
        reload: u16:0x1000,
        ..initial_state()
    };

    let tick_input = TimerInput {
        addr: u4:0,
        data_in: u8:0,
        rd: false,
        wr: false,
        tick: true,
    };

    let (state2, _) = timer_tick(state, tick_input);  // counter = 0xFFFF
    assert_eq(state2.counter, u16:0xFFFF);
    assert_eq(state2.status & FLAG_OVF, u8:0);

    let (state3, _) = timer_tick(state2, tick_input);  // overflow, reload
    assert_eq(state3.counter, u16:0x1000);
    assert_eq(state3.status & FLAG_OVF, FLAG_OVF);
    // Still enabled (auto-reload)
    assert_eq(state3.ctrl & CTRL_ENABLE, CTRL_ENABLE);
}

#[test]
fn test_one_shot() {
    let state = TimerState {
        ctrl: CTRL_ENABLE,  // No auto-reload = one-shot
        prescale: u8:0,
        counter: u16:0xFFFF,
        ..initial_state()
    };

    let tick_input = TimerInput {
        addr: u4:0,
        data_in: u8:0,
        rd: false,
        wr: false,
        tick: true,
    };

    let (state2, _) = timer_tick(state, tick_input);  // overflow
    assert_eq(state2.counter, u16:0);
    assert_eq(state2.status & FLAG_OVF, FLAG_OVF);
    // Disabled after one-shot
    assert_eq(state2.ctrl & CTRL_ENABLE, u8:0);
}

#[test]
fn test_status_clear() {
    let state = TimerState { status: FLAG_CMP0 | FLAG_OVF, ..initial_state() };

    // Write 1 to CMP0 to clear it
    let input = TimerInput {
        addr: REG_STATUS,
        data_in: FLAG_CMP0,
        rd: false,
        wr: true,
        tick: false,
    };

    let (state2, _) = timer_tick(state, input);
    assert_eq(state2.status, FLAG_OVF);  // CMP0 cleared, OVF remains
}

#[test]
fn test_atomic_read() {
    let state = TimerState { counter: u16:0xABCD, ..initial_state() };

    // Read low byte - should latch high byte
    let input_lo = TimerInput {
        addr: REG_CNT_LO,
        data_in: u8:0,
        rd: true,
        wr: false,
        tick: false,
    };

    let (state2, out_lo) = timer_tick(state, input_lo);
    assert_eq(out_lo.data_out, u8:0xCD);
    assert_eq(state2.cnt_hi_latch, u8:0xAB);

    // Read high byte - should return latched value
    let input_hi = TimerInput {
        addr: REG_CNT_HI,
        data_in: u8:0,
        rd: true,
        wr: false,
        tick: false,
    };

    let (_, out_hi) = timer_tick(state2, input_hi);
    assert_eq(out_hi.data_out, u8:0xAB);
}
