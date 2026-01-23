// Intel 8085 CPU Core - Complete Implementation
// All opcodes, I/O support, stack operations
// Uses separate register fields (not array) for Yosys compatibility

// ============================================================================
// Type Definitions
// ============================================================================

struct Flags {
    sign: u1,
    zero: u1,
    aux_carry: u1,
    parity: u1,
    carry: u1,
}

struct Cpu8085State {
    reg_b: u8,
    reg_c: u8,
    reg_d: u8,
    reg_e: u8,
    reg_h: u8,
    reg_l: u8,
    reg_a: u8,
    sp: u16,
    pc: u16,
    flags: Flags,
    halted: bool,
    inte: bool,
    // Interrupt masks (1 = masked/disabled)
    mask_55: bool,
    mask_65: bool,
    mask_75: bool,
    // RST 7.5 pending latch (edge-triggered)
    rst75_pending: bool,
    // Serial output data latch
    sod_latch: bool,
}

// Extended bus output with stack write and I/O
struct MemBusOut {
    // Memory write
    addr: u16,
    write_data: u8,
    write_enable: bool,
    // Stack write (for CALL, PUSH, RST)
    stack_addr: u16,
    stack_data_lo: u8,
    stack_data_hi: u8,
    stack_write: bool,
    // I/O
    io_port: u8,
    io_data: u8,
    io_read: bool,
    io_write: bool,
}

// ============================================================================
// Constants
// ============================================================================

const REG_B = u3:0;
const REG_C = u3:1;
const REG_D = u3:2;
const REG_E = u3:3;
const REG_H = u3:4;
const REG_L = u3:5;
const REG_M = u3:6;
const REG_A = u3:7;

const RP_BC = u2:0;
const RP_DE = u2:1;
const RP_HL = u2:2;
const RP_SP = u2:3;

// ============================================================================
// Register Access Helpers
// ============================================================================

fn get_reg(state: Cpu8085State, r: u3) -> u8 {
    match r {
        REG_B => state.reg_b,
        REG_C => state.reg_c,
        REG_D => state.reg_d,
        REG_E => state.reg_e,
        REG_H => state.reg_h,
        REG_L => state.reg_l,
        REG_A => state.reg_a,
        _ => u8:0,
    }
}

fn set_reg(state: Cpu8085State, r: u3, val: u8) -> Cpu8085State {
    match r {
        REG_B => Cpu8085State { reg_b: val, ..state },
        REG_C => Cpu8085State { reg_c: val, ..state },
        REG_D => Cpu8085State { reg_d: val, ..state },
        REG_E => Cpu8085State { reg_e: val, ..state },
        REG_H => Cpu8085State { reg_h: val, ..state },
        REG_L => Cpu8085State { reg_l: val, ..state },
        REG_A => Cpu8085State { reg_a: val, ..state },
        _ => state,
    }
}

// ============================================================================
// Flag Functions
// ============================================================================

fn compute_parity(val: u8) -> u1 {
    let p = val[0:1] ^ val[1:2] ^ val[2:3] ^ val[3:4] ^
            val[4:5] ^ val[5:6] ^ val[6:7] ^ val[7:8];
    !p
}

fn add_with_flags(a: u8, b: u8, cin: u1) -> (u8, Flags) {
    let sum9 = (a as u9) + (b as u9) + (cin as u9);
    let result = sum9[0:8] as u8;
    let low_sum = (a[0:4] as u5) + (b[0:4] as u5) + (cin as u5);
    let flags = Flags {
        sign: result[7:8],
        zero: if result == u8:0 { u1:1 } else { u1:0 },
        aux_carry: low_sum[4:5],
        parity: compute_parity(result),
        carry: sum9[8:9],
    };
    (result, flags)
}

fn sub_with_flags(a: u8, b: u8, borrow: u1) -> (u8, Flags) {
    let not_b = !b;
    let cin = if borrow == u1:0 { u1:1 } else { u1:0 };
    let diff9 = (a as u9) + (not_b as u9) + (cin as u9);
    let result = diff9[0:8] as u8;
    let low_diff = (a[0:4] as u5) + (not_b[0:4] as u5) + (cin as u5);
    let flags = Flags {
        sign: result[7:8],
        zero: if result == u8:0 { u1:1 } else { u1:0 },
        aux_carry: low_diff[4:5],
        parity: compute_parity(result),
        carry: !diff9[8:9],
    };
    (result, flags)
}

fn flags_to_byte(flags: Flags) -> u8 {
    ((flags.sign as u8) << 7) |
    ((flags.zero as u8) << 6) |
    ((flags.aux_carry as u8) << 4) |
    ((flags.parity as u8) << 2) |
    u8:0b00000010 |
    (flags.carry as u8)
}

fn byte_to_flags(b: u8) -> Flags {
    Flags {
        sign: b[7:8],
        zero: b[6:7],
        aux_carry: b[4:5],
        parity: b[2:3],
        carry: b[0:1],
    }
}

// ============================================================================
// Register Pair Helpers
// ============================================================================

fn get_register_pair(state: Cpu8085State, rp: u2) -> u16 {
    match rp {
        RP_BC => ((state.reg_b as u16) << 8) | (state.reg_c as u16),
        RP_DE => ((state.reg_d as u16) << 8) | (state.reg_e as u16),
        RP_HL => ((state.reg_h as u16) << 8) | (state.reg_l as u16),
        RP_SP => state.sp,
        _ => u16:0,
    }
}

fn set_register_pair(state: Cpu8085State, rp: u2, val: u16) -> Cpu8085State {
    let high = (val >> 8) as u8;
    let low = val as u8;
    match rp {
        RP_BC => Cpu8085State { reg_b: high, reg_c: low, ..state },
        RP_DE => Cpu8085State { reg_d: high, reg_e: low, ..state },
        RP_HL => Cpu8085State { reg_h: high, reg_l: low, ..state },
        RP_SP => Cpu8085State { sp: val, ..state },
        _ => state,
    }
}

// Get register pair for PUSH/POP (BC, DE, HL, PSW)
fn get_push_pair(state: Cpu8085State, rp: u2) -> (u8, u8) {
    match rp {
        u2:0 => (state.reg_b, state.reg_c),
        u2:1 => (state.reg_d, state.reg_e),
        u2:2 => (state.reg_h, state.reg_l),
        u2:3 => (state.reg_a, flags_to_byte(state.flags)),
        _ => (u8:0, u8:0),
    }
}

fn set_pop_pair(state: Cpu8085State, rp: u2, hi: u8, lo: u8) -> Cpu8085State {
    match rp {
        u2:0 => Cpu8085State { reg_b: hi, reg_c: lo, ..state },
        u2:1 => Cpu8085State { reg_d: hi, reg_e: lo, ..state },
        u2:2 => Cpu8085State { reg_h: hi, reg_l: lo, ..state },
        u2:3 => Cpu8085State { reg_a: hi, flags: byte_to_flags(lo), ..state },
        _ => state,
    }
}

// ============================================================================
// Condition Checking
// ============================================================================

fn check_condition(flags: Flags, cond: u3) -> bool {
    match cond {
        u3:0b000 => flags.zero == u1:0,      // NZ
        u3:0b001 => flags.zero == u1:1,      // Z
        u3:0b010 => flags.carry == u1:0,     // NC
        u3:0b011 => flags.carry == u1:1,     // C
        u3:0b100 => flags.parity == u1:0,    // PO
        u3:0b101 => flags.parity == u1:1,    // PE
        u3:0b110 => flags.sign == u1:0,      // P
        u3:0b111 => flags.sign == u1:1,      // M
        _ => false,
    }
}

// ============================================================================
// Initial State and Bus Helpers
// ============================================================================

fn zero_flags() -> Flags {
    Flags { sign: u1:0, zero: u1:0, aux_carry: u1:0, parity: u1:0, carry: u1:0 }
}

fn initial_state() -> Cpu8085State {
    Cpu8085State {
        reg_b: u8:0, reg_c: u8:0, reg_d: u8:0, reg_e: u8:0,
        reg_h: u8:0, reg_l: u8:0, reg_a: u8:0,
        sp: u16:0xFFFF,
        pc: u16:0x0000,
        flags: zero_flags(),
        halted: false,
        inte: false,
        mask_55: true,   // Masked by default
        mask_65: true,
        mask_75: true,
        rst75_pending: false,
        sod_latch: false,
    }
}

fn no_bus_activity() -> MemBusOut {
    MemBusOut {
        addr: u16:0, write_data: u8:0, write_enable: false,
        stack_addr: u16:0, stack_data_lo: u8:0, stack_data_hi: u8:0, stack_write: false,
        io_port: u8:0, io_data: u8:0, io_read: false, io_write: false,
    }
}

fn mem_write(addr: u16, data: u8) -> MemBusOut {
    MemBusOut {
        addr: addr, write_data: data, write_enable: true,
        stack_addr: u16:0, stack_data_lo: u8:0, stack_data_hi: u8:0, stack_write: false,
        io_port: u8:0, io_data: u8:0, io_read: false, io_write: false,
    }
}

fn stack_push(addr: u16, hi: u8, lo: u8) -> MemBusOut {
    MemBusOut {
        addr: u16:0, write_data: u8:0, write_enable: false,
        stack_addr: addr, stack_data_lo: lo, stack_data_hi: hi, stack_write: true,
        io_port: u8:0, io_data: u8:0, io_read: false, io_write: false,
    }
}

fn io_out(port: u8, data: u8) -> MemBusOut {
    MemBusOut {
        addr: u16:0, write_data: u8:0, write_enable: false,
        stack_addr: u16:0, stack_data_lo: u8:0, stack_data_hi: u8:0, stack_write: false,
        io_port: port, io_data: data, io_read: false, io_write: true,
    }
}

fn io_in(port: u8) -> MemBusOut {
    MemBusOut {
        addr: u16:0, write_data: u8:0, write_enable: false,
        stack_addr: u16:0, stack_data_lo: u8:0, stack_data_hi: u8:0, stack_write: false,
        io_port: port, io_data: u8:0, io_read: true, io_write: false,
    }
}

// ============================================================================
// Core Execution Function
// ============================================================================

pub fn execute(
    state: Cpu8085State,
    opcode: u8,
    byte2: u8,
    byte3: u8,
    mem_read_data: u8,
    stack_read_lo: u8,
    stack_read_hi: u8,
    io_read_data: u8,
    // Interrupt/serial inputs for RIM
    sid: bool,            // Serial Input Data pin
    rst55_level: bool,    // RST 5.5 pin level (for pending status)
    rst65_level: bool     // RST 6.5 pin level (for pending status)
) -> (Cpu8085State, MemBusOut) {

    if state.halted {
        (state, no_bus_activity())
    } else {
        let immediate16 = ((byte3 as u16) << 8) | (byte2 as u16);
        let ddd = ((opcode >> 3) & u8:0b111) as u3;
        let sss = (opcode & u8:0b111) as u3;
        let rp = ((opcode >> 4) & u8:0b11) as u2;
        let ccc = ((opcode >> 3) & u8:0b111) as u3;
        let nnn = ((opcode >> 3) & u8:0b111) as u3;
        let a = state.reg_a;
        let hl = get_register_pair(state, RP_HL);
        let bc = get_register_pair(state, RP_BC);
        let de = get_register_pair(state, RP_DE);

        // Get source register value (using mem_read_data for M)
        let src_val = if sss == REG_M { mem_read_data } else { get_reg(state, sss) };

        // ====== NOP ======
        if opcode == u8:0x00 {
            (Cpu8085State { pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== HLT ======
        else if opcode == u8:0x76 {
            (Cpu8085State { halted: true, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== STAX BC (0x02) ======
        else if opcode == u8:0x02 {
            (Cpu8085State { pc: state.pc + u16:1, ..state }, mem_write(bc, a))
        }
        // ====== LDAX BC (0x0A) ======
        else if opcode == u8:0x0A {
            // mem_read_data should contain data from BC address
            (Cpu8085State { reg_a: mem_read_data, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== STAX DE (0x12) ======
        else if opcode == u8:0x12 {
            (Cpu8085State { pc: state.pc + u16:1, ..state }, mem_write(de, a))
        }
        // ====== LDAX DE (0x1A) ======
        else if opcode == u8:0x1A {
            (Cpu8085State { reg_a: mem_read_data, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== RIM (0x20) - Read Interrupt Mask ======
        else if opcode == u8:0x20 {
            // Build RIM result:
            // Bit 7: SID (Serial Input Data)
            // Bit 6: I7.5 (RST 7.5 pending)
            // Bit 5: I6.5 (RST 6.5 pending - level)
            // Bit 4: I5.5 (RST 5.5 pending - level)
            // Bit 3: IE (Interrupt Enable)
            // Bit 2: M7.5 (RST 7.5 mask)
            // Bit 1: M6.5 (RST 6.5 mask)
            // Bit 0: M5.5 (RST 5.5 mask)
            let rim_result = ((sid as u8) << 7) |
                             ((state.rst75_pending as u8) << 6) |
                             ((rst65_level as u8) << 5) |
                             ((rst55_level as u8) << 4) |
                             ((state.inte as u8) << 3) |
                             ((state.mask_75 as u8) << 2) |
                             ((state.mask_65 as u8) << 1) |
                             (state.mask_55 as u8);
            (Cpu8085State { reg_a: rim_result, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== SHLD addr (0x22) ======
        else if opcode == u8:0x22 {
            // Store L to addr, H to addr+1 - handled by SoC FSM
            // Signal memory write of L first
            (Cpu8085State { pc: state.pc + u16:3, ..state }, mem_write(immediate16, state.reg_l))
        }
        // ====== DAA (0x27) - Decimal Adjust Accumulator ======
        else if opcode == u8:0x27 {
            let lo_nibble = a[0:4];
            let ac = state.flags.aux_carry;
            let cy = state.flags.carry;

            // Add 6 to low nibble if > 9 or aux carry set
            let add_lo = (lo_nibble > u4:9) || (ac == u1:1);
            let (tmp1, _) = if add_lo { add_with_flags(a, u8:0x06, u1:0) } else { (a, state.flags) };
            let new_ac = if add_lo { u1:1 } else { u1:0 };

            // Add 6 to high nibble if > 9 or carry set
            let new_hi = tmp1[4:8];
            let add_hi = (new_hi > u4:9) || (cy == u1:1);
            let (result, _) = if add_hi { add_with_flags(tmp1, u8:0x60, u1:0) } else { (tmp1, state.flags) };
            let new_cy = if add_hi || (cy == u1:1) { u1:1 } else { u1:0 };

            let flags = Flags {
                sign: result[7:8],
                zero: if result == u8:0 { u1:1 } else { u1:0 },
                aux_carry: new_ac,
                parity: compute_parity(result),
                carry: new_cy,
            };
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== LHLD addr (0x2A) ======
        else if opcode == u8:0x2A {
            // mem_read_data = L, stack_read_lo = H (reusing for second byte)
            // Actually SoC needs to handle fetching two bytes
            (Cpu8085State { reg_l: mem_read_data, reg_h: stack_read_lo, pc: state.pc + u16:3, ..state }, no_bus_activity())
        }
        // ====== SIM (0x30) - Set Interrupt Mask ======
        else if opcode == u8:0x30 {
            // Interpret A register:
            // Bit 7: SOD (Serial Output Data)
            // Bit 6: SDE (Serial Data Enable) - if 1, latch SOD
            // Bit 5: R7.5 (Reset RST 7.5) - if 1, clear rst75_pending
            // Bit 4: MSE (Mask Set Enable) - if 1, load mask from bits 0-2
            // Bit 2: M7.5 mask
            // Bit 1: M6.5 mask
            // Bit 0: M5.5 mask
            let sde = (a >> 6) & u8:1 == u8:1;
            let r75 = (a >> 5) & u8:1 == u8:1;
            let mse = (a >> 4) & u8:1 == u8:1;

            // Update SOD if SDE is set
            let new_sod = if sde { (a >> 7) & u8:1 == u8:1 } else { state.sod_latch };

            // Clear RST 7.5 pending if R7.5 bit is set
            let new_rst75_pending = if r75 { false } else { state.rst75_pending };

            // Update masks if MSE is set
            let new_mask_55 = if mse { (a & u8:1) == u8:1 } else { state.mask_55 };
            let new_mask_65 = if mse { (a >> 1) & u8:1 == u8:1 } else { state.mask_65 };
            let new_mask_75 = if mse { (a >> 2) & u8:1 == u8:1 } else { state.mask_75 };

            (Cpu8085State {
                pc: state.pc + u16:1,
                sod_latch: new_sod,
                rst75_pending: new_rst75_pending,
                mask_55: new_mask_55,
                mask_65: new_mask_65,
                mask_75: new_mask_75,
                ..state
            }, no_bus_activity())
        }
        // ====== STA addr (0x32) ======
        else if opcode == u8:0x32 {
            (Cpu8085State { pc: state.pc + u16:3, ..state }, mem_write(immediate16, a))
        }
        // ====== LDA addr (0x3A) ======
        else if opcode == u8:0x3A {
            // mem_read_data should contain data from immediate16 address
            (Cpu8085State { reg_a: mem_read_data, pc: state.pc + u16:3, ..state }, no_bus_activity())
        }
        // ====== MOV r,r (01 DDD SSS) excluding HLT ======
        else if (opcode & u8:0b11000000) == u8:0b01000000 {
            if ddd == REG_M {
                let write_val = if sss == REG_M { mem_read_data } else { get_reg(state, sss) };
                (Cpu8085State { pc: state.pc + u16:1, ..state }, mem_write(hl, write_val))
            } else {
                let s = set_reg(state, ddd, src_val);
                (Cpu8085State { pc: s.pc + u16:1, ..s }, no_bus_activity())
            }
        }
        // ====== MVI r,d8 (00 DDD 110) ======
        else if (opcode & u8:0b11000111) == u8:0b00000110 {
            if ddd == REG_M {
                (Cpu8085State { pc: state.pc + u16:2, ..state }, mem_write(hl, byte2))
            } else {
                let s = set_reg(state, ddd, byte2);
                (Cpu8085State { pc: s.pc + u16:2, ..s }, no_bus_activity())
            }
        }
        // ====== LXI rp,d16 (00 RP0 001) ======
        else if (opcode & u8:0b11001111) == u8:0b00000001 {
            let s = set_register_pair(state, rp, immediate16);
            (Cpu8085State { pc: s.pc + u16:3, ..s }, no_bus_activity())
        }
        // ====== ADD r (10 000 SSS) ======
        else if (opcode & u8:0b11111000) == u8:0b10000000 {
            let (result, flags) = add_with_flags(a, src_val, u1:0);
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== ADC r (10 001 SSS) ======
        else if (opcode & u8:0b11111000) == u8:0b10001000 {
            let (result, flags) = add_with_flags(a, src_val, state.flags.carry);
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== SUB r (10 010 SSS) ======
        else if (opcode & u8:0b11111000) == u8:0b10010000 {
            let (result, flags) = sub_with_flags(a, src_val, u1:0);
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== SBB r (10 011 SSS) ======
        else if (opcode & u8:0b11111000) == u8:0b10011000 {
            let (result, flags) = sub_with_flags(a, src_val, state.flags.carry);
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== ANA r (10 100 SSS) ======
        else if (opcode & u8:0b11111000) == u8:0b10100000 {
            let result = a & src_val;
            let flags = Flags {
                sign: result[7:8],
                zero: if result == u8:0 { u1:1 } else { u1:0 },
                aux_carry: u1:1,
                parity: compute_parity(result),
                carry: u1:0,
            };
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== XRA r (10 101 SSS) ======
        else if (opcode & u8:0b11111000) == u8:0b10101000 {
            let result = a ^ src_val;
            let flags = Flags {
                sign: result[7:8],
                zero: if result == u8:0 { u1:1 } else { u1:0 },
                aux_carry: u1:0,
                parity: compute_parity(result),
                carry: u1:0,
            };
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== ORA r (10 110 SSS) ======
        else if (opcode & u8:0b11111000) == u8:0b10110000 {
            let result = a | src_val;
            let flags = Flags {
                sign: result[7:8],
                zero: if result == u8:0 { u1:1 } else { u1:0 },
                aux_carry: u1:0,
                parity: compute_parity(result),
                carry: u1:0,
            };
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== CMP r (10 111 SSS) ======
        else if (opcode & u8:0b11111000) == u8:0b10111000 {
            let (_, flags) = sub_with_flags(a, src_val, u1:0);
            (Cpu8085State { flags: flags, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== INR r (00 DDD 100) ======
        else if (opcode & u8:0b11000111) == u8:0b00000100 {
            let val = if ddd == REG_M { mem_read_data } else { get_reg(state, ddd) };
            let (result, flags) = add_with_flags(val, u8:1, u1:0);
            let flags = Flags { carry: state.flags.carry, ..flags };
            if ddd == REG_M {
                (Cpu8085State { flags: flags, pc: state.pc + u16:1, ..state }, mem_write(hl, result))
            } else {
                let s = set_reg(state, ddd, result);
                (Cpu8085State { flags: flags, pc: s.pc + u16:1, ..s }, no_bus_activity())
            }
        }
        // ====== DCR r (00 DDD 101) ======
        else if (opcode & u8:0b11000111) == u8:0b00000101 {
            let val = if ddd == REG_M { mem_read_data } else { get_reg(state, ddd) };
            let (result, flags) = sub_with_flags(val, u8:1, u1:0);
            let flags = Flags { carry: state.flags.carry, ..flags };
            if ddd == REG_M {
                (Cpu8085State { flags: flags, pc: state.pc + u16:1, ..state }, mem_write(hl, result))
            } else {
                let s = set_reg(state, ddd, result);
                (Cpu8085State { flags: flags, pc: s.pc + u16:1, ..s }, no_bus_activity())
            }
        }
        // ====== INX rp (00 RP0 011) ======
        else if (opcode & u8:0b11001111) == u8:0b00000011 {
            let val = get_register_pair(state, rp);
            let s = set_register_pair(state, rp, val + u16:1);
            (Cpu8085State { pc: s.pc + u16:1, ..s }, no_bus_activity())
        }
        // ====== DCX rp (00 RP1 011) ======
        else if (opcode & u8:0b11001111) == u8:0b00001011 {
            let val = get_register_pair(state, rp);
            let s = set_register_pair(state, rp, val - u16:1);
            (Cpu8085State { pc: s.pc + u16:1, ..s }, no_bus_activity())
        }
        // ====== DAD rp (00 RP1 001) ======
        else if (opcode & u8:0b11001111) == u8:0b00001001 {
            let rp_val = get_register_pair(state, rp);
            let sum = (hl as u17) + (rp_val as u17);
            let s = set_register_pair(state, RP_HL, sum as u16);
            let flags = Flags { carry: sum[16:17], ..state.flags };
            (Cpu8085State { flags: flags, pc: s.pc + u16:1, ..s }, no_bus_activity())
        }
        // ====== RLC (0x07) ======
        else if opcode == u8:0x07 {
            let bit7 = a[7:8];
            let result = (a << 1) | (bit7 as u8);
            let flags = Flags { carry: bit7, ..state.flags };
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== RRC (0x0F) ======
        else if opcode == u8:0x0F {
            let bit0 = a[0:1];
            let result = (a >> 1) | ((bit0 as u8) << 7);
            let flags = Flags { carry: bit0, ..state.flags };
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== RAL (0x17) ======
        else if opcode == u8:0x17 {
            let bit7 = a[7:8];
            let result = (a << 1) | (state.flags.carry as u8);
            let flags = Flags { carry: bit7, ..state.flags };
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== RAR (0x1F) ======
        else if opcode == u8:0x1F {
            let bit0 = a[0:1];
            let result = (a >> 1) | ((state.flags.carry as u8) << 7);
            let flags = Flags { carry: bit0, ..state.flags };
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== CMA (0x2F) ======
        else if opcode == u8:0x2F {
            (Cpu8085State { reg_a: !a, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== STC (0x37) ======
        else if opcode == u8:0x37 {
            let flags = Flags { carry: u1:1, ..state.flags };
            (Cpu8085State { flags: flags, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== CMC (0x3F) ======
        else if opcode == u8:0x3F {
            let flags = Flags { carry: !state.flags.carry, ..state.flags };
            (Cpu8085State { flags: flags, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== ADI d8 (0xC6) ======
        else if opcode == u8:0xC6 {
            let (result, flags) = add_with_flags(a, byte2, u1:0);
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:2, ..state }, no_bus_activity())
        }
        // ====== ACI d8 (0xCE) ======
        else if opcode == u8:0xCE {
            let (result, flags) = add_with_flags(a, byte2, state.flags.carry);
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:2, ..state }, no_bus_activity())
        }
        // ====== SUI d8 (0xD6) ======
        else if opcode == u8:0xD6 {
            let (result, flags) = sub_with_flags(a, byte2, u1:0);
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:2, ..state }, no_bus_activity())
        }
        // ====== SBI d8 (0xDE) ======
        else if opcode == u8:0xDE {
            let (result, flags) = sub_with_flags(a, byte2, state.flags.carry);
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:2, ..state }, no_bus_activity())
        }
        // ====== ANI d8 (0xE6) ======
        else if opcode == u8:0xE6 {
            let result = a & byte2;
            let flags = Flags {
                sign: result[7:8],
                zero: if result == u8:0 { u1:1 } else { u1:0 },
                aux_carry: u1:1,
                parity: compute_parity(result),
                carry: u1:0,
            };
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:2, ..state }, no_bus_activity())
        }
        // ====== XRI d8 (0xEE) ======
        else if opcode == u8:0xEE {
            let result = a ^ byte2;
            let flags = Flags {
                sign: result[7:8],
                zero: if result == u8:0 { u1:1 } else { u1:0 },
                aux_carry: u1:0,
                parity: compute_parity(result),
                carry: u1:0,
            };
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:2, ..state }, no_bus_activity())
        }
        // ====== ORI d8 (0xF6) ======
        else if opcode == u8:0xF6 {
            let result = a | byte2;
            let flags = Flags {
                sign: result[7:8],
                zero: if result == u8:0 { u1:1 } else { u1:0 },
                aux_carry: u1:0,
                parity: compute_parity(result),
                carry: u1:0,
            };
            (Cpu8085State { reg_a: result, flags: flags, pc: state.pc + u16:2, ..state }, no_bus_activity())
        }
        // ====== CPI d8 (0xFE) ======
        else if opcode == u8:0xFE {
            let (_, flags) = sub_with_flags(a, byte2, u1:0);
            (Cpu8085State { flags: flags, pc: state.pc + u16:2, ..state }, no_bus_activity())
        }
        // ====== JMP addr (0xC3) ======
        else if opcode == u8:0xC3 {
            (Cpu8085State { pc: immediate16, ..state }, no_bus_activity())
        }
        // ====== Jcond addr (11 CCC 010) ======
        else if (opcode & u8:0b11000111) == u8:0b11000010 {
            if check_condition(state.flags, ccc) {
                (Cpu8085State { pc: immediate16, ..state }, no_bus_activity())
            } else {
                (Cpu8085State { pc: state.pc + u16:3, ..state }, no_bus_activity())
            }
        }
        // ====== CALL addr (0xCD) ======
        else if opcode == u8:0xCD {
            let ret_addr = state.pc + u16:3;
            let new_sp = state.sp - u16:2;
            let bus = stack_push(new_sp, (ret_addr >> 8) as u8, ret_addr as u8);
            (Cpu8085State { pc: immediate16, sp: new_sp, ..state }, bus)
        }
        // ====== Ccond addr (11 CCC 100) ======
        else if (opcode & u8:0b11000111) == u8:0b11000100 {
            if check_condition(state.flags, ccc) {
                let ret_addr = state.pc + u16:3;
                let new_sp = state.sp - u16:2;
                let bus = stack_push(new_sp, (ret_addr >> 8) as u8, ret_addr as u8);
                (Cpu8085State { pc: immediate16, sp: new_sp, ..state }, bus)
            } else {
                (Cpu8085State { pc: state.pc + u16:3, ..state }, no_bus_activity())
            }
        }
        // ====== RET (0xC9) ======
        else if opcode == u8:0xC9 {
            let ret_addr = ((stack_read_hi as u16) << 8) | (stack_read_lo as u16);
            (Cpu8085State { pc: ret_addr, sp: state.sp + u16:2, ..state }, no_bus_activity())
        }
        // ====== Rcond (11 CCC 000) ======
        else if (opcode & u8:0b11000111) == u8:0b11000000 {
            if check_condition(state.flags, ccc) {
                let ret_addr = ((stack_read_hi as u16) << 8) | (stack_read_lo as u16);
                (Cpu8085State { pc: ret_addr, sp: state.sp + u16:2, ..state }, no_bus_activity())
            } else {
                (Cpu8085State { pc: state.pc + u16:1, ..state }, no_bus_activity())
            }
        }
        // ====== RST n (11 NNN 111) ======
        else if (opcode & u8:0b11000111) == u8:0b11000111 {
            let ret_addr = state.pc + u16:1;
            let new_sp = state.sp - u16:2;
            let rst_addr = ((nnn as u16) << 3);
            let bus = stack_push(new_sp, (ret_addr >> 8) as u8, ret_addr as u8);
            (Cpu8085State { pc: rst_addr, sp: new_sp, ..state }, bus)
        }
        // ====== PUSH rp (11 RP0 101) ======
        else if (opcode & u8:0b11001111) == u8:0b11000101 {
            let (hi, lo) = get_push_pair(state, rp);
            let new_sp = state.sp - u16:2;
            let bus = stack_push(new_sp, hi, lo);
            (Cpu8085State { sp: new_sp, pc: state.pc + u16:1, ..state }, bus)
        }
        // ====== POP rp (11 RP0 001) ======
        else if (opcode & u8:0b11001111) == u8:0b11000001 {
            let s = set_pop_pair(state, rp, stack_read_hi, stack_read_lo);
            (Cpu8085State { sp: s.sp + u16:2, pc: s.pc + u16:1, ..s }, no_bus_activity())
        }
        // ====== PCHL (0xE9) ======
        else if opcode == u8:0xE9 {
            (Cpu8085State { pc: hl, ..state }, no_bus_activity())
        }
        // ====== XTHL (0xE3) ======
        else if opcode == u8:0xE3 {
            // Exchange L with (SP), H with (SP+1)
            // stack_read_lo = (SP), stack_read_hi = (SP+1)
            let new_l = stack_read_lo;
            let new_h = stack_read_hi;
            // Write old L to (SP), old H to (SP+1)
            let bus = stack_push(state.sp, state.reg_h, state.reg_l);
            (Cpu8085State { reg_h: new_h, reg_l: new_l, pc: state.pc + u16:1, ..state }, bus)
        }
        // ====== XCHG (0xEB) ======
        else if opcode == u8:0xEB {
            (Cpu8085State {
                reg_d: state.reg_h, reg_e: state.reg_l,
                reg_h: state.reg_d, reg_l: state.reg_e,
                pc: state.pc + u16:1, ..state
            }, no_bus_activity())
        }
        // ====== SPHL (0xF9) ======
        else if opcode == u8:0xF9 {
            (Cpu8085State { sp: hl, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== IN port (0xDB) ======
        else if opcode == u8:0xDB {
            (Cpu8085State { reg_a: io_read_data, pc: state.pc + u16:2, ..state }, io_in(byte2))
        }
        // ====== OUT port (0xD3) ======
        else if opcode == u8:0xD3 {
            (Cpu8085State { pc: state.pc + u16:2, ..state }, io_out(byte2, a))
        }
        // ====== EI (0xFB) ======
        else if opcode == u8:0xFB {
            (Cpu8085State { inte: true, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== DI (0xF3) ======
        else if opcode == u8:0xF3 {
            (Cpu8085State { inte: false, pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
        // ====== Default: treat as NOP ======
        else {
            (Cpu8085State { pc: state.pc + u16:1, ..state }, no_bus_activity())
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

#[test]
fn test_add_b() {
    let state = Cpu8085State { reg_b: u8:0x20, reg_a: u8:0x10, ..initial_state() };
    let (new_state, bus) = execute(state, u8:0x80, u8:0, u8:0, u8:0, u8:0, u8:0, u8:0, false, false, false);
    assert_eq(new_state.reg_a, u8:0x30);
    assert_eq(new_state.pc, u16:1);
    assert_eq(bus.write_enable, false);
}

#[test]
fn test_mov_a_b() {
    let state = Cpu8085State { reg_b: u8:0x42, ..initial_state() };
    let (new_state, _) = execute(state, u8:0x78, u8:0, u8:0, u8:0, u8:0, u8:0, u8:0, false, false, false);
    assert_eq(new_state.reg_a, u8:0x42);
}

#[test]
fn test_mvi_a() {
    let state = initial_state();
    let (new_state, _) = execute(state, u8:0x3E, u8:0x55, u8:0, u8:0, u8:0, u8:0, u8:0, false, false, false);
    assert_eq(new_state.reg_a, u8:0x55);
    assert_eq(new_state.pc, u16:2);
}

#[test]
fn test_jmp() {
    let state = initial_state();
    let (new_state, _) = execute(state, u8:0xC3, u8:0x34, u8:0x12, u8:0, u8:0, u8:0, u8:0, false, false, false);
    assert_eq(new_state.pc, u16:0x1234);
}

#[test]
fn test_call() {
    let state = Cpu8085State { sp: u16:0x200, pc: u16:0x100, ..initial_state() };
    let (new_state, bus) = execute(state, u8:0xCD, u8:0x00, u8:0x05, u8:0, u8:0, u8:0, u8:0, false, false, false);
    assert_eq(new_state.pc, u16:0x0500);
    assert_eq(new_state.sp, u16:0x1FE);
    assert_eq(bus.stack_write, true);
    assert_eq(bus.stack_addr, u16:0x1FE);
    assert_eq(bus.stack_data_lo, u8:0x03);  // Low byte of 0x103
    assert_eq(bus.stack_data_hi, u8:0x01);  // High byte of 0x103
}

#[test]
fn test_ret() {
    let state = Cpu8085State { sp: u16:0x100, ..initial_state() };
    let (new_state, _) = execute(state, u8:0xC9, u8:0, u8:0, u8:0, u8:0x34, u8:0x12, u8:0, false, false, false);
    assert_eq(new_state.pc, u16:0x1234);
    assert_eq(new_state.sp, u16:0x102);
}

#[test]
fn test_push_bc() {
    let state = Cpu8085State { reg_b: u8:0x12, reg_c: u8:0x34, sp: u16:0x200, ..initial_state() };
    let (new_state, bus) = execute(state, u8:0xC5, u8:0, u8:0, u8:0, u8:0, u8:0, u8:0, false, false, false);
    assert_eq(new_state.sp, u16:0x1FE);
    assert_eq(bus.stack_write, true);
    assert_eq(bus.stack_data_hi, u8:0x12);
    assert_eq(bus.stack_data_lo, u8:0x34);
}

#[test]
fn test_pop_bc() {
    let state = Cpu8085State { sp: u16:0x100, ..initial_state() };
    let (new_state, _) = execute(state, u8:0xC1, u8:0, u8:0, u8:0, u8:0x34, u8:0x12, u8:0, false, false, false);
    assert_eq(new_state.reg_b, u8:0x12);
    assert_eq(new_state.reg_c, u8:0x34);
    assert_eq(new_state.sp, u16:0x102);
}

#[test]
fn test_inr() {
    let state = Cpu8085State { reg_b: u8:0x0F, ..initial_state() };
    let (new_state, _) = execute(state, u8:0x04, u8:0, u8:0, u8:0, u8:0, u8:0, u8:0, false, false, false);
    assert_eq(new_state.reg_b, u8:0x10);
    assert_eq(new_state.flags.aux_carry, u1:1);
}

#[test]
fn test_xra_a() {
    let state = Cpu8085State { reg_a: u8:0xFF, ..initial_state() };
    let (new_state, _) = execute(state, u8:0xAF, u8:0, u8:0, u8:0, u8:0, u8:0, u8:0, false, false, false);
    assert_eq(new_state.reg_a, u8:0x00);
    assert_eq(new_state.flags.zero, u1:1);
}

#[test]
fn test_out() {
    let state = Cpu8085State { reg_a: u8:0x42, ..initial_state() };
    let (new_state, bus) = execute(state, u8:0xD3, u8:0x10, u8:0, u8:0, u8:0, u8:0, u8:0, false, false, false);
    assert_eq(new_state.pc, u16:2);
    assert_eq(bus.io_write, true);
    assert_eq(bus.io_port, u8:0x10);
    assert_eq(bus.io_data, u8:0x42);
}

#[test]
fn test_in() {
    let state = initial_state();
    let (new_state, bus) = execute(state, u8:0xDB, u8:0x20, u8:0, u8:0, u8:0, u8:0, u8:0x55, false, false, false);
    assert_eq(new_state.reg_a, u8:0x55);
    assert_eq(new_state.pc, u16:2);
    assert_eq(bus.io_read, true);
    assert_eq(bus.io_port, u8:0x20);
}

#[test]
fn test_rst() {
    let state = Cpu8085State { sp: u16:0x200, pc: u16:0x100, ..initial_state() };
    let (new_state, bus) = execute(state, u8:0xDF, u8:0, u8:0, u8:0, u8:0, u8:0, u8:0, false, false, false);  // RST 3
    assert_eq(new_state.pc, u16:0x18);  // 3 * 8 = 24 = 0x18
    assert_eq(new_state.sp, u16:0x1FE);
    assert_eq(bus.stack_write, true);
}

#[test]
fn test_sta() {
    let state = Cpu8085State { reg_a: u8:0x42, ..initial_state() };
    let (new_state, bus) = execute(state, u8:0x32, u8:0x00, u8:0x20, u8:0, u8:0, u8:0, u8:0, false, false, false);
    assert_eq(new_state.pc, u16:3);
    assert_eq(bus.write_enable, true);
    assert_eq(bus.addr, u16:0x2000);
    assert_eq(bus.write_data, u8:0x42);
}

#[test]
fn test_lda() {
    let state = initial_state();
    let (new_state, _) = execute(state, u8:0x3A, u8:0x00, u8:0x20, u8:0x55, u8:0, u8:0, u8:0, false, false, false);
    assert_eq(new_state.reg_a, u8:0x55);
    assert_eq(new_state.pc, u16:3);
}
