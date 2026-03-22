// Intel 8085 CPU Implementation in DSLX
// Functionally-accurate (instruction-level), not cycle-accurate
//
// Reference: Intel 8085AH Datasheet

// ============================================================================
// Type Definitions
// ============================================================================

// Status flags
struct Flags {
    sign: u1,       // S - bit 7: set if result is negative
    zero: u1,       // Z - bit 6: set if result is zero
    aux_carry: u1,  // AC - bit 4: carry from bit 3 to bit 4 (BCD)
    parity: u1,     // P - bit 2: set if even parity
    carry: u1,      // CY - bit 0: carry/borrow from bit 7
}

// CPU state
struct Cpu8085State {
    regs: u8[8],    // B=0, C=1, D=2, E=3, H=4, L=5, (unused)=6, A=7
    sp: u16,        // Stack pointer
    pc: u16,        // Program counter
    flags: Flags,   // Status flags
    halted: bool,   // HLT instruction sets this
    inte: bool,     // Interrupt enable flag
}

// Memory size - small for synthesis testing
// For real hardware, memory would be external via bus interface
const MEM_SIZE = u32:256;

// ============================================================================
// Register Constants
// ============================================================================

// 8-bit register indices (matches 8085 encoding in DDD/SSS fields)
const REG_B = u3:0;
const REG_C = u3:1;
const REG_D = u3:2;
const REG_E = u3:3;
const REG_H = u3:4;
const REG_L = u3:5;
const REG_M = u3:6;  // Memory reference via HL (special handling)
const REG_A = u3:7;

// Register pair indices (matches 8085 encoding in RP field)
const RP_BC = u2:0;
const RP_DE = u2:1;
const RP_HL = u2:2;
const RP_SP = u2:3;  // Or PSW for PUSH/POP

// I/O is memory-mapped at high addresses for simplicity
const IO_BASE = u16:0xFF00;

// ============================================================================
// Flag Computation Functions
// ============================================================================

// Compute even parity (returns 1 if even number of 1 bits)
fn compute_parity(val: u8) -> u1 {
    let b0 = val[0:1];
    let b1 = val[1:2];
    let b2 = val[2:3];
    let b3 = val[3:4];
    let b4 = val[4:5];
    let b5 = val[5:6];
    let b6 = val[6:7];
    let b7 = val[7:8];
    // XOR all bits - result is 0 if even parity, 1 if odd
    let parity_odd = b0 ^ b1 ^ b2 ^ b3 ^ b4 ^ b5 ^ b6 ^ b7;
    // Return 1 for even parity
    !parity_odd
}

#[test]
fn test_parity() {
    assert_eq(compute_parity(u8:0x00), u1:1);  // 0 ones = even
    assert_eq(compute_parity(u8:0x01), u1:0);  // 1 one = odd
    assert_eq(compute_parity(u8:0x03), u1:1);  // 2 ones = even
    assert_eq(compute_parity(u8:0xFF), u1:1);  // 8 ones = even
    assert_eq(compute_parity(u8:0x7F), u1:0);  // 7 ones = odd
}

// Compute flags for a result (used by logic operations)
fn compute_szp_flags(result: u8, old_flags: Flags) -> Flags {
    Flags {
        sign: result[7:8],
        zero: if result == u8:0 { u1:1 } else { u1:0 },
        aux_carry: old_flags.aux_carry,  // Preserved or set by caller
        parity: compute_parity(result),
        carry: old_flags.carry,  // Preserved or set by caller
    }
}

// Add with flags (used by ADD, ADC, INR)
fn add_with_flags(a: u8, b: u8, cin: u1, old_flags: Flags) -> (u8, Flags) {
    // 9-bit addition to capture carry
    let sum9 = (a as u9) + (b as u9) + (cin as u9);
    let result = sum9[0:8] as u8;

    // Auxiliary carry: carry from bit 3 to bit 4
    let low_a = a[0:4];
    let low_b = b[0:4];
    let low_sum = (low_a as u5) + (low_b as u5) + (cin as u5);
    let ac = low_sum[4:5];

    let flags = Flags {
        sign: result[7:8],
        zero: if result == u8:0 { u1:1 } else { u1:0 },
        aux_carry: ac,
        parity: compute_parity(result),
        carry: sum9[8:9],
    };
    (result, flags)
}

#[test]
fn test_add_with_flags() {
    let zero_flags = Flags { sign: u1:0, zero: u1:0, aux_carry: u1:0, parity: u1:0, carry: u1:0 };

    // Simple add
    let (result, flags) = add_with_flags(u8:0x10, u8:0x20, u1:0, zero_flags);
    assert_eq(result, u8:0x30);
    assert_eq(flags.carry, u1:0);
    assert_eq(flags.zero, u1:0);

    // Add with carry out
    let (result, flags) = add_with_flags(u8:0xFF, u8:0x01, u1:0, zero_flags);
    assert_eq(result, u8:0x00);
    assert_eq(flags.carry, u1:1);
    assert_eq(flags.zero, u1:1);

    // Add with carry in
    let (result, flags) = add_with_flags(u8:0x10, u8:0x20, u1:1, zero_flags);
    assert_eq(result, u8:0x31);

    // Auxiliary carry
    let (result, flags) = add_with_flags(u8:0x0F, u8:0x01, u1:0, zero_flags);
    assert_eq(result, u8:0x10);
    assert_eq(flags.aux_carry, u1:1);
}

// Subtract with flags (used by SUB, SBB, DCR, CMP)
fn sub_with_flags(a: u8, b: u8, borrow: u1, old_flags: Flags) -> (u8, Flags) {
    // Subtraction: a - b - borrow = a + (~b) + 1 - borrow = a + (~b) + !borrow
    let not_b = !b;
    let cin = if borrow == u1:0 { u1:1 } else { u1:0 };

    let diff9 = (a as u9) + (not_b as u9) + (cin as u9);
    let result = diff9[0:8] as u8;

    // Auxiliary carry for subtraction (borrow from bit 4)
    let low_a = a[0:4];
    let low_not_b = not_b[0:4];
    let low_diff = (low_a as u5) + (low_not_b as u5) + (cin as u5);
    let ac = low_diff[4:5];

    // Carry is inverted for subtraction (represents borrow)
    let carry = !diff9[8:9];

    let flags = Flags {
        sign: result[7:8],
        zero: if result == u8:0 { u1:1 } else { u1:0 },
        aux_carry: ac,
        parity: compute_parity(result),
        carry: carry,
    };
    (result, flags)
}

#[test]
fn test_sub_with_flags() {
    let zero_flags = Flags { sign: u1:0, zero: u1:0, aux_carry: u1:0, parity: u1:0, carry: u1:0 };

    // Simple subtract
    let (result, flags) = sub_with_flags(u8:0x30, u8:0x10, u1:0, zero_flags);
    assert_eq(result, u8:0x20);
    assert_eq(flags.carry, u1:0);

    // Subtract with borrow (underflow)
    let (result, flags) = sub_with_flags(u8:0x00, u8:0x01, u1:0, zero_flags);
    assert_eq(result, u8:0xFF);
    assert_eq(flags.carry, u1:1);  // Borrow occurred
    assert_eq(flags.sign, u1:1);   // Negative result

    // Subtract equal values
    let (result, flags) = sub_with_flags(u8:0x42, u8:0x42, u1:0, zero_flags);
    assert_eq(result, u8:0x00);
    assert_eq(flags.zero, u1:1);
    assert_eq(flags.carry, u1:0);
}

// Convert Flags struct to byte (for PUSH PSW)
// Flag byte format: S Z 0 AC 0 P 1 CY (bits 7-0)
fn flags_to_byte(flags: Flags) -> u8 {
    ((flags.sign as u8) << 7) |
    ((flags.zero as u8) << 6) |
    // bit 5 is always 0
    ((flags.aux_carry as u8) << 4) |
    // bit 3 is always 0
    ((flags.parity as u8) << 2) |
    u8:0b00000010 |  // bit 1 is always 1
    (flags.carry as u8)
}

// Convert byte to Flags struct (for POP PSW)
fn byte_to_flags(b: u8) -> Flags {
    Flags {
        sign: b[7:8],
        zero: b[6:7],
        aux_carry: b[4:5],
        parity: b[2:3],
        carry: b[0:1],
    }
}

#[test]
fn test_flags_conversion() {
    let flags = Flags { sign: u1:1, zero: u1:0, aux_carry: u1:1, parity: u1:1, carry: u1:1 };
    let byte = flags_to_byte(flags);
    let flags2 = byte_to_flags(byte);
    assert_eq(flags.sign, flags2.sign);
    assert_eq(flags.zero, flags2.zero);
    assert_eq(flags.aux_carry, flags2.aux_carry);
    assert_eq(flags.parity, flags2.parity);
    assert_eq(flags.carry, flags2.carry);
}

// ============================================================================
// Register Pair Helpers
// ============================================================================

// Get 16-bit value from register pair
fn get_register_pair(state: Cpu8085State, rp: u2) -> u16 {
    match rp {
        RP_BC => ((state.regs[REG_B] as u16) << 8) | (state.regs[REG_C] as u16),
        RP_DE => ((state.regs[REG_D] as u16) << 8) | (state.regs[REG_E] as u16),
        RP_HL => ((state.regs[REG_H] as u16) << 8) | (state.regs[REG_L] as u16),
        RP_SP => state.sp,
        _ => u16:0,
    }
}

// Set 16-bit value to register pair, returns updated state
fn set_register_pair(state: Cpu8085State, rp: u2, val: u16) -> Cpu8085State {
    let high = (val >> 8) as u8;
    let low = val as u8;

    match rp {
        RP_BC => {
            let new_regs = update(state.regs, REG_B as u32, high);
            let new_regs = update(new_regs, REG_C as u32, low);
            Cpu8085State { regs: new_regs, ..state }
        },
        RP_DE => {
            let new_regs = update(state.regs, REG_D as u32, high);
            let new_regs = update(new_regs, REG_E as u32, low);
            Cpu8085State { regs: new_regs, ..state }
        },
        RP_HL => {
            let new_regs = update(state.regs, REG_H as u32, high);
            let new_regs = update(new_regs, REG_L as u32, low);
            Cpu8085State { regs: new_regs, ..state }
        },
        RP_SP => Cpu8085State { sp: val, ..state },
        _ => state,
    }
}

// Get high/low bytes of a register pair (for PUSH)
fn get_register_pair_bytes(state: Cpu8085State, rp: u2) -> (u8, u8) {
    match rp {
        RP_BC => (state.regs[REG_B], state.regs[REG_C]),
        RP_DE => (state.regs[REG_D], state.regs[REG_E]),
        RP_HL => (state.regs[REG_H], state.regs[REG_L]),
        _ => (u8:0, u8:0),
    }
}

// ============================================================================
// Initial State
// ============================================================================

fn zero_flags() -> Flags {
    Flags { sign: u1:0, zero: u1:0, aux_carry: u1:0, parity: u1:0, carry: u1:0 }
}

fn initial_state() -> Cpu8085State {
    Cpu8085State {
        regs: u8[8]:[0, 0, 0, 0, 0, 0, 0, 0],
        sp: u16:0xFFFF,
        pc: u16:0x0000,
        flags: zero_flags(),
        halted: false,
        inte: false,
    }
}

// ============================================================================
// Register Access Helpers
// ============================================================================

// Get value from register (handles M = memory at HL)
fn get_reg_value(state: Cpu8085State, mem: u8[MEM_SIZE], reg: u3) -> u8 {
    if reg == REG_M {
        let hl = get_register_pair(state, RP_HL);
        mem[hl]
    } else {
        state.regs[reg]
    }
}

// Set register value (returns new state and memory)
// If reg is M, writes to memory at HL
fn set_reg_value(state: Cpu8085State, mem: u8[MEM_SIZE], reg: u3, val: u8) -> (Cpu8085State, u8[MEM_SIZE]) {
    if reg == REG_M {
        let hl = get_register_pair(state, RP_HL);
        let new_mem = update(mem, hl as u32, val);
        (state, new_mem)
    } else {
        let new_regs = update(state.regs, reg as u32, val);
        (Cpu8085State { regs: new_regs, ..state }, mem)
    }
}

// ============================================================================
// Condition Code Checking
// ============================================================================

// Check condition code (CCC field in conditional instructions)
fn check_condition(flags: Flags, cond: u3) -> bool {
    match cond {
        u3:0b000 => flags.zero == u1:0,      // NZ - not zero
        u3:0b001 => flags.zero == u1:1,      // Z  - zero
        u3:0b010 => flags.carry == u1:0,     // NC - no carry
        u3:0b011 => flags.carry == u1:1,     // C  - carry
        u3:0b100 => flags.parity == u1:0,    // PO - parity odd
        u3:0b101 => flags.parity == u1:1,    // PE - parity even
        u3:0b110 => flags.sign == u1:0,      // P  - positive (plus)
        u3:0b111 => flags.sign == u1:1,      // M  - minus (negative)
        _ => false,
    }
}

#[test]
fn test_check_condition() {
    let flags_z = Flags { sign: u1:0, zero: u1:1, aux_carry: u1:0, parity: u1:0, carry: u1:0 };
    assert_eq(check_condition(flags_z, u3:0b000), false);  // NZ - should be false
    assert_eq(check_condition(flags_z, u3:0b001), true);   // Z - should be true

    let flags_c = Flags { sign: u1:0, zero: u1:0, aux_carry: u1:0, parity: u1:0, carry: u1:1 };
    assert_eq(check_condition(flags_c, u3:0b010), false);  // NC - should be false
    assert_eq(check_condition(flags_c, u3:0b011), true);   // C - should be true
}

// ============================================================================
// Instruction Decoding
// ============================================================================

// Get instruction length from opcode
fn instruction_length(opcode: u8) -> u8 {
    // 3-byte instructions
    let is_3byte =
        // LXI rp, d16 (00 RP0 001)
        ((opcode & u8:0b11001111) == u8:0b00000001) ||
        // SHLD addr (00 100 010)
        (opcode == u8:0x22) ||
        // LHLD addr (00 101 010)
        (opcode == u8:0x2A) ||
        // STA addr (00 110 010)
        (opcode == u8:0x32) ||
        // LDA addr (00 111 010)
        (opcode == u8:0x3A) ||
        // JMP addr (11 000 011)
        (opcode == u8:0xC3) ||
        // Jcond addr (11 CCC 010)
        ((opcode & u8:0b11000111) == u8:0b11000010) ||
        // CALL addr (11 001 101)
        (opcode == u8:0xCD) ||
        // Ccond addr (11 CCC 100)
        ((opcode & u8:0b11000111) == u8:0b11000100);

    // 2-byte instructions
    let is_2byte =
        // MVI r, d8 (00 DDD 110)
        ((opcode & u8:0b11000111) == u8:0b00000110) ||
        // ADI, ACI, SUI, SBI, ANI, XRI, ORI, CPI (11 XXX 110)
        ((opcode & u8:0b11000111) == u8:0b11000110) ||
        // IN port (11 011 011)
        (opcode == u8:0xDB) ||
        // OUT port (11 010 011)
        (opcode == u8:0xD3);

    if is_3byte { u8:3 }
    else if is_2byte { u8:2 }
    else { u8:1 }
}

#[test]
fn test_instruction_length() {
    // 1-byte
    assert_eq(instruction_length(u8:0x00), u8:1);  // NOP
    assert_eq(instruction_length(u8:0x76), u8:1);  // HLT
    assert_eq(instruction_length(u8:0x40), u8:1);  // MOV B,B
    assert_eq(instruction_length(u8:0x80), u8:1);  // ADD B

    // 2-byte
    assert_eq(instruction_length(u8:0x06), u8:2);  // MVI B, d8
    assert_eq(instruction_length(u8:0xC6), u8:2);  // ADI d8
    assert_eq(instruction_length(u8:0xDB), u8:2);  // IN port
    assert_eq(instruction_length(u8:0xD3), u8:2);  // OUT port

    // 3-byte
    assert_eq(instruction_length(u8:0x01), u8:3);  // LXI B, d16
    assert_eq(instruction_length(u8:0xC3), u8:3);  // JMP addr
    assert_eq(instruction_length(u8:0xCD), u8:3);  // CALL addr
    assert_eq(instruction_length(u8:0xCA), u8:3);  // JZ addr
    assert_eq(instruction_length(u8:0x3A), u8:3);  // LDA addr
}

// ============================================================================
// Data Transfer Instructions
// ============================================================================

fn run_data_transfer(state: Cpu8085State, mem: u8[MEM_SIZE], opcode: u8, byte2: u8, byte3: u8)
    -> (Cpu8085State, u8[MEM_SIZE]) {

    let immediate16 = ((byte3 as u16) << 8) | (byte2 as u16);
    let ddd = (opcode >> 3) & u8:0b111;
    let sss = opcode & u8:0b111;
    let rp = ((opcode >> 4) & u8:0b11) as u2;

    // MOV r1, r2 (01 DDD SSS) - excludes HLT (01 110 110)
    if (opcode & u8:0b11000000) == u8:0b01000000 && opcode != u8:0x76 {
        let src_val = get_reg_value(state, mem, sss as u3);
        let (new_state, new_mem) = set_reg_value(state, mem, ddd as u3, src_val);
        (Cpu8085State { pc: new_state.pc + u16:1, ..new_state }, new_mem)
    }
    // MVI r, d8 (00 DDD 110)
    else if (opcode & u8:0b11000111) == u8:0b00000110 {
        let (new_state, new_mem) = set_reg_value(state, mem, ddd as u3, byte2);
        (Cpu8085State { pc: new_state.pc + u16:2, ..new_state }, new_mem)
    }
    // LXI rp, d16 (00 RP0 001)
    else if (opcode & u8:0b11001111) == u8:0b00000001 {
        let new_state = set_register_pair(state, rp, immediate16);
        (Cpu8085State { pc: new_state.pc + u16:3, ..new_state }, mem)
    }
    // LDA addr (00 111 010)
    else if opcode == u8:0x3A {
        let val = mem[immediate16];
        let new_regs = update(state.regs, REG_A as u32, val);
        (Cpu8085State { regs: new_regs, pc: state.pc + u16:3, ..state }, mem)
    }
    // STA addr (00 110 010)
    else if opcode == u8:0x32 {
        let new_mem = update(mem, immediate16 as u32, state.regs[REG_A]);
        (Cpu8085State { pc: state.pc + u16:3, ..state }, new_mem)
    }
    // LDAX B (00 001 010)
    else if opcode == u8:0x0A {
        let bc = get_register_pair(state, RP_BC);
        let val = mem[bc];
        let new_regs = update(state.regs, REG_A as u32, val);
        (Cpu8085State { regs: new_regs, pc: state.pc + u16:1, ..state }, mem)
    }
    // LDAX D (00 011 010)
    else if opcode == u8:0x1A {
        let de = get_register_pair(state, RP_DE);
        let val = mem[de];
        let new_regs = update(state.regs, REG_A as u32, val);
        (Cpu8085State { regs: new_regs, pc: state.pc + u16:1, ..state }, mem)
    }
    // STAX B (00 000 010)
    else if opcode == u8:0x02 {
        let bc = get_register_pair(state, RP_BC);
        let new_mem = update(mem, bc as u32, state.regs[REG_A]);
        (Cpu8085State { pc: state.pc + u16:1, ..state }, new_mem)
    }
    // STAX D (00 010 010)
    else if opcode == u8:0x12 {
        let de = get_register_pair(state, RP_DE);
        let new_mem = update(mem, de as u32, state.regs[REG_A]);
        (Cpu8085State { pc: state.pc + u16:1, ..state }, new_mem)
    }
    // LHLD addr (00 101 010)
    else if opcode == u8:0x2A {
        let low = mem[immediate16];
        let high = mem[immediate16 + u16:1];
        let new_regs = update(state.regs, REG_L as u32, low);
        let new_regs = update(new_regs, REG_H as u32, high);
        (Cpu8085State { regs: new_regs, pc: state.pc + u16:3, ..state }, mem)
    }
    // SHLD addr (00 100 010)
    else if opcode == u8:0x22 {
        let new_mem = update(mem, immediate16 as u32, state.regs[REG_L]);
        let new_mem = update(new_mem, (immediate16 + u16:1) as u32, state.regs[REG_H]);
        (Cpu8085State { pc: state.pc + u16:3, ..state }, new_mem)
    }
    // XCHG (11 101 011)
    else if opcode == u8:0xEB {
        let d = state.regs[REG_D];
        let e = state.regs[REG_E];
        let h = state.regs[REG_H];
        let l = state.regs[REG_L];
        let new_regs = update(state.regs, REG_D as u32, h);
        let new_regs = update(new_regs, REG_E as u32, l);
        let new_regs = update(new_regs, REG_H as u32, d);
        let new_regs = update(new_regs, REG_L as u32, e);
        (Cpu8085State { regs: new_regs, pc: state.pc + u16:1, ..state }, mem)
    }
    else {
        // Unknown - just advance PC
        (Cpu8085State { pc: state.pc + u16:1, ..state }, mem)
    }
}

// ============================================================================
// Arithmetic Instructions
// ============================================================================

fn run_arithmetic(state: Cpu8085State, mem: u8[MEM_SIZE], opcode: u8, byte2: u8)
    -> (Cpu8085State, u8[MEM_SIZE]) {

    let sss = opcode & u8:0b111;
    let ddd = (opcode >> 3) & u8:0b111;
    let rp = ((opcode >> 4) & u8:0b11) as u2;
    let a = state.regs[REG_A];

    // ADD r (10 000 SSS)
    if (opcode & u8:0b11111000) == u8:0b10000000 {
        let operand = get_reg_value(state, mem, sss as u3);
        let (result, flags) = add_with_flags(a, operand, u1:0, state.flags);
        let new_regs = update(state.regs, REG_A as u32, result);
        (Cpu8085State { regs: new_regs, flags: flags, pc: state.pc + u16:1, ..state }, mem)
    }
    // ADC r (10 001 SSS)
    else if (opcode & u8:0b11111000) == u8:0b10001000 {
        let operand = get_reg_value(state, mem, sss as u3);
        let (result, flags) = add_with_flags(a, operand, state.flags.carry, state.flags);
        let new_regs = update(state.regs, REG_A as u32, result);
        (Cpu8085State { regs: new_regs, flags: flags, pc: state.pc + u16:1, ..state }, mem)
    }
    // SUB r (10 010 SSS)
    else if (opcode & u8:0b11111000) == u8:0b10010000 {
        let operand = get_reg_value(state, mem, sss as u3);
        let (result, flags) = sub_with_flags(a, operand, u1:0, state.flags);
        let new_regs = update(state.regs, REG_A as u32, result);
        (Cpu8085State { regs: new_regs, flags: flags, pc: state.pc + u16:1, ..state }, mem)
    }
    // SBB r (10 011 SSS)
    else if (opcode & u8:0b11111000) == u8:0b10011000 {
        let operand = get_reg_value(state, mem, sss as u3);
        let (result, flags) = sub_with_flags(a, operand, state.flags.carry, state.flags);
        let new_regs = update(state.regs, REG_A as u32, result);
        (Cpu8085State { regs: new_regs, flags: flags, pc: state.pc + u16:1, ..state }, mem)
    }
    // ADI d8 (11 000 110)
    else if opcode == u8:0xC6 {
        let (result, flags) = add_with_flags(a, byte2, u1:0, state.flags);
        let new_regs = update(state.regs, REG_A as u32, result);
        (Cpu8085State { regs: new_regs, flags: flags, pc: state.pc + u16:2, ..state }, mem)
    }
    // ACI d8 (11 001 110)
    else if opcode == u8:0xCE {
        let (result, flags) = add_with_flags(a, byte2, state.flags.carry, state.flags);
        let new_regs = update(state.regs, REG_A as u32, result);
        (Cpu8085State { regs: new_regs, flags: flags, pc: state.pc + u16:2, ..state }, mem)
    }
    // SUI d8 (11 010 110)
    else if opcode == u8:0xD6 {
        let (result, flags) = sub_with_flags(a, byte2, u1:0, state.flags);
        let new_regs = update(state.regs, REG_A as u32, result);
        (Cpu8085State { regs: new_regs, flags: flags, pc: state.pc + u16:2, ..state }, mem)
    }
    // SBI d8 (11 011 110)
    else if opcode == u8:0xDE {
        let (result, flags) = sub_with_flags(a, byte2, state.flags.carry, state.flags);
        let new_regs = update(state.regs, REG_A as u32, result);
        (Cpu8085State { regs: new_regs, flags: flags, pc: state.pc + u16:2, ..state }, mem)
    }
    // INR r (00 DDD 100)
    else if (opcode & u8:0b11000111) == u8:0b00000100 {
        let val = get_reg_value(state, mem, ddd as u3);
        let (result, flags) = add_with_flags(val, u8:1, u1:0, state.flags);
        // INR doesn't affect carry
        let flags = Flags { carry: state.flags.carry, ..flags };
        let (new_state, new_mem) = set_reg_value(state, mem, ddd as u3, result);
        (Cpu8085State { flags: flags, pc: new_state.pc + u16:1, ..new_state }, new_mem)
    }
    // DCR r (00 DDD 101)
    else if (opcode & u8:0b11000111) == u8:0b00000101 {
        let val = get_reg_value(state, mem, ddd as u3);
        let (result, flags) = sub_with_flags(val, u8:1, u1:0, state.flags);
        // DCR doesn't affect carry
        let flags = Flags { carry: state.flags.carry, ..flags };
        let (new_state, new_mem) = set_reg_value(state, mem, ddd as u3, result);
        (Cpu8085State { flags: flags, pc: new_state.pc + u16:1, ..new_state }, new_mem)
    }
    // INX rp (00 RP0 011)
    else if (opcode & u8:0b11001111) == u8:0b00000011 {
        let val = get_register_pair(state, rp);
        let new_state = set_register_pair(state, rp, val + u16:1);
        (Cpu8085State { pc: new_state.pc + u16:1, ..new_state }, mem)
    }
    // DCX rp (00 RP1 011)
    else if (opcode & u8:0b11001111) == u8:0b00001011 {
        let val = get_register_pair(state, rp);
        let new_state = set_register_pair(state, rp, val - u16:1);
        (Cpu8085State { pc: new_state.pc + u16:1, ..new_state }, mem)
    }
    // DAD rp (00 RP1 001)
    else if (opcode & u8:0b11001111) == u8:0b00001001 {
        let hl = get_register_pair(state, RP_HL);
        let rp_val = get_register_pair(state, rp);
        let sum = (hl as u17) + (rp_val as u17);
        let result = sum as u16;
        let new_state = set_register_pair(state, RP_HL, result);
        // DAD only affects carry
        let flags = Flags { carry: sum[16:17], ..state.flags };
        (Cpu8085State { flags: flags, pc: new_state.pc + u16:1, ..new_state }, mem)
    }
    else {
        (Cpu8085State { pc: state.pc + u16:1, ..state }, mem)
    }
}

// ============================================================================
// Logical Instructions
// ============================================================================

fn run_logical(state: Cpu8085State, mem: u8[MEM_SIZE], opcode: u8, byte2: u8)
    -> (Cpu8085State, u8[MEM_SIZE]) {

    let sss = opcode & u8:0b111;
    let a = state.regs[REG_A];

    // ANA r (10 100 SSS)
    if (opcode & u8:0b11111000) == u8:0b10100000 {
        let operand = get_reg_value(state, mem, sss as u3);
        let result = a & operand;
        let flags = Flags {
            sign: result[7:8],
            zero: if result == u8:0 { u1:1 } else { u1:0 },
            aux_carry: u1:1,  // ANA sets AC
            parity: compute_parity(result),
            carry: u1:0,      // ANA clears CY
        };
        let new_regs = update(state.regs, REG_A as u32, result);
        (Cpu8085State { regs: new_regs, flags: flags, pc: state.pc + u16:1, ..state }, mem)
    }
    // XRA r (10 101 SSS)
    else if (opcode & u8:0b11111000) == u8:0b10101000 {
        let operand = get_reg_value(state, mem, sss as u3);
        let result = a ^ operand;
        let flags = Flags {
            sign: result[7:8],
            zero: if result == u8:0 { u1:1 } else { u1:0 },
            aux_carry: u1:0,  // XRA clears AC
            parity: compute_parity(result),
            carry: u1:0,      // XRA clears CY
        };
        let new_regs = update(state.regs, REG_A as u32, result);
        (Cpu8085State { regs: new_regs, flags: flags, pc: state.pc + u16:1, ..state }, mem)
    }
    // ORA r (10 110 SSS)
    else if (opcode & u8:0b11111000) == u8:0b10110000 {
        let operand = get_reg_value(state, mem, sss as u3);
        let result = a | operand;
        let flags = Flags {
            sign: result[7:8],
            zero: if result == u8:0 { u1:1 } else { u1:0 },
            aux_carry: u1:0,  // ORA clears AC
            parity: compute_parity(result),
            carry: u1:0,      // ORA clears CY
        };
        let new_regs = update(state.regs, REG_A as u32, result);
        (Cpu8085State { regs: new_regs, flags: flags, pc: state.pc + u16:1, ..state }, mem)
    }
    // CMP r (10 111 SSS)
    else if (opcode & u8:0b11111000) == u8:0b10111000 {
        let operand = get_reg_value(state, mem, sss as u3);
        let (_, flags) = sub_with_flags(a, operand, u1:0, state.flags);
        // CMP doesn't store result, just sets flags
        (Cpu8085State { flags: flags, pc: state.pc + u16:1, ..state }, mem)
    }
    // ANI d8 (11 100 110)
    else if opcode == u8:0xE6 {
        let result = a & byte2;
        let flags = Flags {
            sign: result[7:8],
            zero: if result == u8:0 { u1:1 } else { u1:0 },
            aux_carry: u1:1,
            parity: compute_parity(result),
            carry: u1:0,
        };
        let new_regs = update(state.regs, REG_A as u32, result);
        (Cpu8085State { regs: new_regs, flags: flags, pc: state.pc + u16:2, ..state }, mem)
    }
    // XRI d8 (11 101 110)
    else if opcode == u8:0xEE {
        let result = a ^ byte2;
        let flags = Flags {
            sign: result[7:8],
            zero: if result == u8:0 { u1:1 } else { u1:0 },
            aux_carry: u1:0,
            parity: compute_parity(result),
            carry: u1:0,
        };
        let new_regs = update(state.regs, REG_A as u32, result);
        (Cpu8085State { regs: new_regs, flags: flags, pc: state.pc + u16:2, ..state }, mem)
    }
    // ORI d8 (11 110 110)
    else if opcode == u8:0xF6 {
        let result = a | byte2;
        let flags = Flags {
            sign: result[7:8],
            zero: if result == u8:0 { u1:1 } else { u1:0 },
            aux_carry: u1:0,
            parity: compute_parity(result),
            carry: u1:0,
        };
        let new_regs = update(state.regs, REG_A as u32, result);
        (Cpu8085State { regs: new_regs, flags: flags, pc: state.pc + u16:2, ..state }, mem)
    }
    // CPI d8 (11 111 110)
    else if opcode == u8:0xFE {
        let (_, flags) = sub_with_flags(a, byte2, u1:0, state.flags);
        (Cpu8085State { flags: flags, pc: state.pc + u16:2, ..state }, mem)
    }
    // CMA (00 101 111)
    else if opcode == u8:0x2F {
        let new_regs = update(state.regs, REG_A as u32, !a);
        (Cpu8085State { regs: new_regs, pc: state.pc + u16:1, ..state }, mem)
    }
    // CMC (00 111 111)
    else if opcode == u8:0x3F {
        let flags = Flags { carry: !state.flags.carry, ..state.flags };
        (Cpu8085State { flags: flags, pc: state.pc + u16:1, ..state }, mem)
    }
    // STC (00 110 111)
    else if opcode == u8:0x37 {
        let flags = Flags { carry: u1:1, ..state.flags };
        (Cpu8085State { flags: flags, pc: state.pc + u16:1, ..state }, mem)
    }
    else {
        (Cpu8085State { pc: state.pc + u16:1, ..state }, mem)
    }
}

// ============================================================================
// Branch Instructions
// ============================================================================

fn run_branch(state: Cpu8085State, mem: u8[MEM_SIZE], opcode: u8, byte2: u8, byte3: u8)
    -> (Cpu8085State, u8[MEM_SIZE]) {

    let immediate16 = ((byte3 as u16) << 8) | (byte2 as u16);
    let ccc = ((opcode >> 3) & u8:0b111) as u3;
    let nnn = ((opcode >> 3) & u8:0b111) as u3;

    // JMP addr (11 000 011)
    if opcode == u8:0xC3 {
        (Cpu8085State { pc: immediate16, ..state }, mem)
    }
    // Jcond addr (11 CCC 010)
    else if (opcode & u8:0b11000111) == u8:0b11000010 {
        if check_condition(state.flags, ccc) {
            (Cpu8085State { pc: immediate16, ..state }, mem)
        } else {
            (Cpu8085State { pc: state.pc + u16:3, ..state }, mem)
        }
    }
    // CALL addr (11 001 101)
    else if opcode == u8:0xCD {
        let return_addr = state.pc + u16:3;
        let new_sp = state.sp - u16:2;
        let new_mem = update(mem, new_sp as u32, return_addr as u8);
        let new_mem = update(new_mem, (new_sp + u16:1) as u32, (return_addr >> 8) as u8);
        (Cpu8085State { pc: immediate16, sp: new_sp, ..state }, new_mem)
    }
    // Ccond addr (11 CCC 100)
    else if (opcode & u8:0b11000111) == u8:0b11000100 {
        if check_condition(state.flags, ccc) {
            let return_addr = state.pc + u16:3;
            let new_sp = state.sp - u16:2;
            let new_mem = update(mem, new_sp as u32, return_addr as u8);
            let new_mem = update(new_mem, (new_sp + u16:1) as u32, (return_addr >> 8) as u8);
            (Cpu8085State { pc: immediate16, sp: new_sp, ..state }, new_mem)
        } else {
            (Cpu8085State { pc: state.pc + u16:3, ..state }, mem)
        }
    }
    // RET (11 001 001)
    else if opcode == u8:0xC9 {
        let pcl = mem[state.sp] as u16;
        let pch = (mem[state.sp + u16:1] as u16) << 8;
        let return_addr = pch | pcl;
        (Cpu8085State { pc: return_addr, sp: state.sp + u16:2, ..state }, mem)
    }
    // Rcond (11 CCC 000)
    else if (opcode & u8:0b11000111) == u8:0b11000000 {
        if check_condition(state.flags, ccc) {
            let pcl = mem[state.sp] as u16;
            let pch = (mem[state.sp + u16:1] as u16) << 8;
            let return_addr = pch | pcl;
            (Cpu8085State { pc: return_addr, sp: state.sp + u16:2, ..state }, mem)
        } else {
            (Cpu8085State { pc: state.pc + u16:1, ..state }, mem)
        }
    }
    // RST n (11 NNN 111)
    else if (opcode & u8:0b11000111) == u8:0b11000111 {
        let return_addr = state.pc + u16:1;
        let new_sp = state.sp - u16:2;
        let new_mem = update(mem, new_sp as u32, return_addr as u8);
        let new_mem = update(new_mem, (new_sp + u16:1) as u32, (return_addr >> 8) as u8);
        let target = (nnn as u16) << 3;  // n * 8
        (Cpu8085State { pc: target, sp: new_sp, ..state }, new_mem)
    }
    // PCHL (11 101 001)
    else if opcode == u8:0xE9 {
        let hl = get_register_pair(state, RP_HL);
        (Cpu8085State { pc: hl, ..state }, mem)
    }
    else {
        (Cpu8085State { pc: state.pc + u16:1, ..state }, mem)
    }
}

// ============================================================================
// Stack Instructions
// ============================================================================

fn run_stack(state: Cpu8085State, mem: u8[MEM_SIZE], opcode: u8)
    -> (Cpu8085State, u8[MEM_SIZE]) {

    let rp = ((opcode >> 4) & u8:0b11) as u2;

    // PUSH rp (11 RP0 101)
    if (opcode & u8:0b11001111) == u8:0b11000101 {
        let new_sp = state.sp - u16:2;
        let (high, low) = if rp == u2:3 {
            // PUSH PSW: push A and flags
            (state.regs[REG_A], flags_to_byte(state.flags))
        } else {
            get_register_pair_bytes(state, rp)
        };
        let new_mem = update(mem, new_sp as u32, low);
        let new_mem = update(new_mem, (new_sp + u16:1) as u32, high);
        (Cpu8085State { sp: new_sp, pc: state.pc + u16:1, ..state }, new_mem)
    }
    // POP rp (11 RP0 001)
    else if (opcode & u8:0b11001111) == u8:0b11000001 {
        let low = mem[state.sp];
        let high = mem[state.sp + u16:1];
        let new_sp = state.sp + u16:2;

        if rp == u2:3 {
            // POP PSW: pop flags and A
            let new_flags = byte_to_flags(low);
            let new_regs = update(state.regs, REG_A as u32, high);
            (Cpu8085State { regs: new_regs, flags: new_flags, sp: new_sp, pc: state.pc + u16:1, ..state }, mem)
        } else {
            let val = ((high as u16) << 8) | (low as u16);
            let new_state = set_register_pair(state, rp, val);
            (Cpu8085State { sp: new_sp, pc: new_state.pc + u16:1, ..new_state }, mem)
        }
    }
    // XTHL (11 100 011)
    else if opcode == u8:0xE3 {
        let l = state.regs[REG_L];
        let h = state.regs[REG_H];
        let stack_l = mem[state.sp];
        let stack_h = mem[state.sp + u16:1];
        let new_regs = update(state.regs, REG_L as u32, stack_l);
        let new_regs = update(new_regs, REG_H as u32, stack_h);
        let new_mem = update(mem, state.sp as u32, l);
        let new_mem = update(new_mem, (state.sp + u16:1) as u32, h);
        (Cpu8085State { regs: new_regs, pc: state.pc + u16:1, ..state }, new_mem)
    }
    // SPHL (11 111 001)
    else if opcode == u8:0xF9 {
        let hl = get_register_pair(state, RP_HL);
        (Cpu8085State { sp: hl, pc: state.pc + u16:1, ..state }, mem)
    }
    else {
        (Cpu8085State { pc: state.pc + u16:1, ..state }, mem)
    }
}

// ============================================================================
// Rotate Instructions
// ============================================================================

fn run_rotate(state: Cpu8085State, opcode: u8) -> Cpu8085State {
    let a = state.regs[REG_A];

    let (result, new_carry) =
        // RLC (00 000 111) - rotate A left, bit 7 -> CY and bit 0
        if opcode == u8:0x07 {
            let bit7 = a[7:8];
            let result = (a << 1) | (bit7 as u8);
            (result, bit7)
        }
        // RRC (00 001 111) - rotate A right, bit 0 -> CY and bit 7
        else if opcode == u8:0x0F {
            let bit0 = a[0:1];
            let result = (a >> 1) | ((bit0 as u8) << 7);
            (result, bit0)
        }
        // RAL (00 010 111) - rotate A left through carry
        else if opcode == u8:0x17 {
            let bit7 = a[7:8];
            let result = (a << 1) | (state.flags.carry as u8);
            (result, bit7)
        }
        // RAR (00 011 111) - rotate A right through carry
        else if opcode == u8:0x1F {
            let bit0 = a[0:1];
            let result = (a >> 1) | ((state.flags.carry as u8) << 7);
            (result, bit0)
        }
        else {
            (a, state.flags.carry)
        };

    let new_regs = update(state.regs, REG_A as u32, result);
    let new_flags = Flags { carry: new_carry, ..state.flags };
    Cpu8085State { regs: new_regs, flags: new_flags, pc: state.pc + u16:1, ..state }
}

// ============================================================================
// I/O Instructions
// ============================================================================

fn run_io(state: Cpu8085State, mem: u8[MEM_SIZE], opcode: u8, byte2: u8)
    -> (Cpu8085State, u8[MEM_SIZE]) {

    // IN port (11 011 011)
    if opcode == u8:0xDB {
        let port = byte2 as u16;
        let val = mem[IO_BASE + port];
        let new_regs = update(state.regs, REG_A as u32, val);
        (Cpu8085State { regs: new_regs, pc: state.pc + u16:2, ..state }, mem)
    }
    // OUT port (11 010 011)
    else if opcode == u8:0xD3 {
        let port = byte2 as u16;
        let new_mem = update(mem, (IO_BASE + port) as u32, state.regs[REG_A]);
        (Cpu8085State { pc: state.pc + u16:2, ..state }, new_mem)
    }
    else {
        (Cpu8085State { pc: state.pc + u16:2, ..state }, mem)
    }
}

// ============================================================================
// Control Instructions
// ============================================================================

fn run_control(state: Cpu8085State, opcode: u8) -> Cpu8085State {
    // NOP (00 000 000)
    if opcode == u8:0x00 {
        Cpu8085State { pc: state.pc + u16:1, ..state }
    }
    // HLT (01 110 110)
    else if opcode == u8:0x76 {
        Cpu8085State { halted: true, pc: state.pc + u16:1, ..state }
    }
    // EI (11 111 011)
    else if opcode == u8:0xFB {
        Cpu8085State { inte: true, pc: state.pc + u16:1, ..state }
    }
    // DI (11 110 011)
    else if opcode == u8:0xF3 {
        Cpu8085State { inte: false, pc: state.pc + u16:1, ..state }
    }
    // RIM (00 100 000) - simplified: just return 0 in A
    else if opcode == u8:0x20 {
        let new_regs = update(state.regs, REG_A as u32, u8:0);
        Cpu8085State { regs: new_regs, pc: state.pc + u16:1, ..state }
    }
    // SIM (00 110 000) - simplified: just advance PC
    else if opcode == u8:0x30 {
        Cpu8085State { pc: state.pc + u16:1, ..state }
    }
    else {
        Cpu8085State { pc: state.pc + u16:1, ..state }
    }
}

// ============================================================================
// Main Instruction Dispatcher
// ============================================================================

fn run_instruction(state: Cpu8085State, mem: u8[MEM_SIZE]) -> (Cpu8085State, u8[MEM_SIZE]) {
    // Don't execute if halted
    if state.halted {
        (state, mem)
    } else {
        let opcode = mem[state.pc];
        let byte2 = mem[state.pc + u16:1];
        let byte3 = mem[state.pc + u16:2];

        // Dispatch based on opcode patterns

        // Control: NOP, HLT, EI, DI, RIM, SIM
        if opcode == u8:0x00 || opcode == u8:0x76 || opcode == u8:0xFB ||
           opcode == u8:0xF3 || opcode == u8:0x20 || opcode == u8:0x30 {
            (run_control(state, opcode), mem)
        }
        // Rotate: RLC, RRC, RAL, RAR
        else if opcode == u8:0x07 || opcode == u8:0x0F ||
                opcode == u8:0x17 || opcode == u8:0x1F {
            (run_rotate(state, opcode), mem)
        }
        // I/O: IN, OUT
        else if opcode == u8:0xDB || opcode == u8:0xD3 {
            run_io(state, mem, opcode, byte2)
        }
        // Stack: PUSH, POP, XTHL, SPHL
        else if (opcode & u8:0b11001111) == u8:0b11000101 ||  // PUSH
                (opcode & u8:0b11001111) == u8:0b11000001 ||  // POP
                opcode == u8:0xE3 || opcode == u8:0xF9 {
            run_stack(state, mem, opcode)
        }
        // Branch: JMP, Jcond, CALL, Ccond, RET, Rcond, RST, PCHL
        else if opcode == u8:0xC3 ||  // JMP
                (opcode & u8:0b11000111) == u8:0b11000010 ||  // Jcond
                opcode == u8:0xCD ||  // CALL
                (opcode & u8:0b11000111) == u8:0b11000100 ||  // Ccond
                opcode == u8:0xC9 ||  // RET
                (opcode & u8:0b11000111) == u8:0b11000000 ||  // Rcond
                (opcode & u8:0b11000111) == u8:0b11000111 ||  // RST
                opcode == u8:0xE9 {  // PCHL
            run_branch(state, mem, opcode, byte2, byte3)
        }
        // Logical: ANA, XRA, ORA, CMP (register), ANI, XRI, ORI, CPI (immediate), CMA, CMC, STC
        else if (opcode & u8:0b11100000) == u8:0b10100000 ||  // ANA, XRA, ORA, CMP
                opcode == u8:0xE6 || opcode == u8:0xEE ||     // ANI, XRI
                opcode == u8:0xF6 || opcode == u8:0xFE ||     // ORI, CPI
                opcode == u8:0x2F || opcode == u8:0x3F || opcode == u8:0x37 {  // CMA, CMC, STC
            run_logical(state, mem, opcode, byte2)
        }
        // Arithmetic: ADD, ADC, SUB, SBB, INR, DCR, INX, DCX, DAD, ADI, ACI, SUI, SBI
        else if (opcode & u8:0b11100000) == u8:0b10000000 ||  // ADD, ADC, SUB, SBB
                (opcode & u8:0b11000111) == u8:0b00000100 ||  // INR
                (opcode & u8:0b11000111) == u8:0b00000101 ||  // DCR
                (opcode & u8:0b11001111) == u8:0b00000011 ||  // INX
                (opcode & u8:0b11001111) == u8:0b00001011 ||  // DCX
                (opcode & u8:0b11001111) == u8:0b00001001 ||  // DAD
                opcode == u8:0xC6 || opcode == u8:0xCE ||     // ADI, ACI
                opcode == u8:0xD6 || opcode == u8:0xDE {      // SUI, SBI
            run_arithmetic(state, mem, opcode, byte2)
        }
        // Data transfer: everything else (MOV, MVI, LXI, LDA, STA, etc.)
        else {
            run_data_transfer(state, mem, opcode, byte2, byte3)
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

#[test]
fn test_mov_b_c() {
    let state = initial_state();
    let new_regs = update(state.regs, REG_C as u32, u8:0x42);
    let state = Cpu8085State { regs: new_regs, ..state };

    // MOV B, C (opcode 0x41)
    let mem = u8[MEM_SIZE]:[u8:0x41, ...];
    let (new_state, _) = run_instruction(state, mem);

    assert_eq(new_state.regs[REG_B], u8:0x42);
    assert_eq(new_state.pc, u16:1);
}

#[test]
fn test_mvi_a() {
    let state = initial_state();

    // MVI A, 0x55 (opcode 0x3E, data 0x55)
    let mem = u8[MEM_SIZE]:[u8:0x3E, u8:0x55, ...];
    let (new_state, _) = run_instruction(state, mem);

    assert_eq(new_state.regs[REG_A], u8:0x55);
    assert_eq(new_state.pc, u16:2);
}

#[test]
fn test_lxi_bc() {
    let state = initial_state();

    // LXI B, 0x1234 (opcode 0x01, data 0x34 0x12)
    let mem = u8[MEM_SIZE]:[u8:0x01, u8:0x34, u8:0x12, ...];
    let (new_state, _) = run_instruction(state, mem);

    assert_eq(new_state.regs[REG_B], u8:0x12);
    assert_eq(new_state.regs[REG_C], u8:0x34);
    assert_eq(new_state.pc, u16:3);
}

#[test]
fn test_add_b() {
    let state = initial_state();
    let new_regs = update(state.regs, REG_A as u32, u8:0x10);
    let new_regs = update(new_regs, REG_B as u32, u8:0x20);
    let state = Cpu8085State { regs: new_regs, ..state };

    // ADD B (opcode 0x80)
    let mem = u8[MEM_SIZE]:[u8:0x80, ...];
    let (new_state, _) = run_instruction(state, mem);

    assert_eq(new_state.regs[REG_A], u8:0x30);
    assert_eq(new_state.pc, u16:1);
}

#[test]
fn test_jmp() {
    let state = initial_state();

    // JMP 0x1234 (opcode 0xC3, addr 0x34 0x12)
    let mem = u8[MEM_SIZE]:[u8:0xC3, u8:0x34, u8:0x12, ...];
    let (new_state, _) = run_instruction(state, mem);

    assert_eq(new_state.pc, u16:0x1234);
}

#[test]
fn test_call_ret() {
    let state = Cpu8085State { sp: u16:0x100, ..initial_state() };

    // CALL 0x0010 (opcode 0xCD, addr 0x10 0x00)
    let mem = u8[MEM_SIZE]:[u8:0xCD, u8:0x10, u8:0x00, ...];
    let (new_state, new_mem) = run_instruction(state, mem);

    assert_eq(new_state.pc, u16:0x0010);
    assert_eq(new_state.sp, u16:0x00FE);
    // Return address 0x0003 should be on stack
    assert_eq(new_mem[u32:0x00FE], u8:0x03);  // Low byte
    assert_eq(new_mem[u32:0x00FF], u8:0x00);  // High byte

    // Now RET
    let mem2 = update(new_mem, u32:0x0010, u8:0xC9);  // RET at 0x0010
    let (final_state, _) = run_instruction(new_state, mem2);

    assert_eq(final_state.pc, u16:0x0003);
    assert_eq(final_state.sp, u16:0x0100);
}

#[test]
fn test_push_pop() {
    let state0 = Cpu8085State { sp: u16:0x100, ..initial_state() };
    let new_regs = update(state0.regs, REG_B as u32, u8:0x12);
    let new_regs = update(new_regs, REG_C as u32, u8:0x34);
    let state = Cpu8085State { regs: new_regs, ..state0 };

    // PUSH B (opcode 0xC5)
    let mem = u8[MEM_SIZE]:[u8:0xC5, ...];
    let (new_state, new_mem) = run_instruction(state, mem);

    assert_eq(new_state.sp, u16:0x00FE);
    assert_eq(new_mem[u32:0x00FE], u8:0x34);  // C (low)
    assert_eq(new_mem[u32:0x00FF], u8:0x12);  // B (high)

    // Clear BC and POP
    let new_regs = update(new_state.regs, REG_B as u32, u8:0);
    let new_regs = update(new_regs, REG_C as u32, u8:0);
    let state2 = Cpu8085State { regs: new_regs, pc: u16:0, ..new_state };
    let mem2 = update(new_mem, u32:0, u8:0xC1);  // POP B

    let (final_state, _) = run_instruction(state2, mem2);

    assert_eq(final_state.regs[REG_B], u8:0x12);
    assert_eq(final_state.regs[REG_C], u8:0x34);
    assert_eq(final_state.sp, u16:0x0100);
}

#[test]
fn test_inr_dcr() {
    let state = initial_state();
    let new_regs = update(state.regs, REG_B as u32, u8:0x05);
    let state = Cpu8085State { regs: new_regs, ..state };

    // INR B (opcode 0x04)
    let mem = u8[MEM_SIZE]:[u8:0x04, ...];
    let (new_state, _) = run_instruction(state, mem);
    assert_eq(new_state.regs[REG_B], u8:0x06);

    // DCR B (opcode 0x05)
    let mem2 = u8[MEM_SIZE]:[u8:0x05, ...];
    let state2 = Cpu8085State { pc: u16:0, ..new_state };
    let (final_state, _) = run_instruction(state2, mem2);
    assert_eq(final_state.regs[REG_B], u8:0x05);
}

#[test]
fn test_ana_xra_ora() {
    let state = initial_state();
    let new_regs = update(state.regs, REG_A as u32, u8:0xFF);
    let new_regs = update(new_regs, REG_B as u32, u8:0x0F);
    let state = Cpu8085State { regs: new_regs, ..state };

    // ANA B (opcode 0xA0)
    let mem = u8[MEM_SIZE]:[u8:0xA0, ...];
    let (new_state, _) = run_instruction(state, mem);
    assert_eq(new_state.regs[REG_A], u8:0x0F);

    // XRA A (opcode 0xAF) - A XOR A = 0
    let mem2 = u8[MEM_SIZE]:[u8:0xAF, ...];
    let state2 = Cpu8085State { pc: u16:0, ..new_state };
    let (state3, _) = run_instruction(state2, mem2);
    assert_eq(state3.regs[REG_A], u8:0x00);
    assert_eq(state3.flags.zero, u1:1);
}

#[test]
fn test_cmp() {
    let state = initial_state();
    let new_regs = update(state.regs, REG_A as u32, u8:0x10);
    let new_regs = update(new_regs, REG_B as u32, u8:0x10);
    let state = Cpu8085State { regs: new_regs, ..state };

    // CMP B (opcode 0xB8) - compare equal
    let mem = u8[MEM_SIZE]:[u8:0xB8, ...];
    let (new_state, _) = run_instruction(state, mem);
    assert_eq(new_state.regs[REG_A], u8:0x10);  // A unchanged
    assert_eq(new_state.flags.zero, u1:1);       // Z set (equal)
    assert_eq(new_state.flags.carry, u1:0);      // CY clear (no borrow)
}

#[test]
fn test_rotate() {
    let state = initial_state();
    let new_regs = update(state.regs, REG_A as u32, u8:0x81);  // 10000001
    let state = Cpu8085State { regs: new_regs, ..state };

    // RLC (opcode 0x07) - rotate left
    let mem = u8[MEM_SIZE]:[u8:0x07, ...];
    let (new_state, _) = run_instruction(state, mem);
    assert_eq(new_state.regs[REG_A], u8:0x03);  // 00000011
    assert_eq(new_state.flags.carry, u1:1);     // Bit 7 went to carry

    // RRC (opcode 0x0F) - rotate right
    let state2 = Cpu8085State { pc: u16:0, ..new_state };
    let mem2 = u8[MEM_SIZE]:[u8:0x0F, ...];
    let (state3, _) = run_instruction(state2, mem2);
    assert_eq(state3.regs[REG_A], u8:0x81);  // Back to original
    assert_eq(state3.flags.carry, u1:1);     // Bit 0 went to carry
}
