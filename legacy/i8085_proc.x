// Intel 8085 CPU as a DSLX Proc
// Proper stateful architecture with clean bus interface

// ============================================================================
// Types
// ============================================================================

struct Flags {
    sign: u1,
    zero: u1,
    aux_carry: u1,
    parity: u1,
    carry: u1,
}

// CPU registers - internal state, not exposed
struct Registers {
    a: u8,
    b: u8,
    c: u8,
    d: u8,
    e: u8,
    h: u8,
    l: u8,
    sp: u16,
    pc: u16,
    flags: Flags,
    inte: bool,
}

// FSM phases
enum Phase : u3 {
    FETCH = 0,
    FETCH_WAIT = 1,
    DECODE = 2,
    READ_MEM = 3,
    READ_STACK = 4,
    EXECUTE = 5,
    WRITE_MEM = 6,
    HALTED = 7,
}

// Memory bus request (output from CPU)
struct MemRequest {
    addr: u16,
    write_data: u8,
    read: bool,
    write: bool,
}

// Full CPU state
struct CpuState {
    regs: Registers,
    phase: Phase,
    halted: bool,
    // Instruction buffer
    opcode: u8,
    imm1: u8,
    imm2: u8,
    // Memory read buffer
    mem_data: u8,
    stack_lo: u8,
    stack_hi: u8,
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

// ============================================================================
// Helper Functions (pure, reusable)
// ============================================================================

fn zero_flags() -> Flags {
    Flags { sign: u1:0, zero: u1:0, aux_carry: u1:0, parity: u1:0, carry: u1:0 }
}

fn initial_registers() -> Registers {
    Registers {
        a: u8:0, b: u8:0, c: u8:0, d: u8:0, e: u8:0, h: u8:0, l: u8:0,
        sp: u16:0xFFFF, pc: u16:0x0000,
        flags: zero_flags(),
        inte: false,
    }
}

fn initial_state() -> CpuState {
    CpuState {
        regs: initial_registers(),
        phase: Phase::FETCH,
        halted: false,
        opcode: u8:0,
        imm1: u8:0,
        imm2: u8:0,
        mem_data: u8:0,
        stack_lo: u8:0,
        stack_hi: u8:0,
    }
}

fn get_hl(regs: Registers) -> u16 {
    ((regs.h as u16) << 8) | (regs.l as u16)
}

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

fn get_reg(regs: Registers, r: u3) -> u8 {
    match r {
        REG_B => regs.b,
        REG_C => regs.c,
        REG_D => regs.d,
        REG_E => regs.e,
        REG_H => regs.h,
        REG_L => regs.l,
        REG_A => regs.a,
        _ => u8:0,
    }
}

fn set_reg(regs: Registers, r: u3, val: u8) -> Registers {
    match r {
        REG_B => Registers { b: val, ..regs },
        REG_C => Registers { c: val, ..regs },
        REG_D => Registers { d: val, ..regs },
        REG_E => Registers { e: val, ..regs },
        REG_H => Registers { h: val, ..regs },
        REG_L => Registers { l: val, ..regs },
        REG_A => Registers { a: val, ..regs },
        _ => regs,
    }
}

// Instruction length from opcode
fn inst_length(op: u8) -> u8 {
    if (op & u8:0xCF) == u8:0x01 { u8:3 }        // LXI
    else if op == u8:0xC3 { u8:3 }               // JMP
    else if (op & u8:0xC7) == u8:0xC2 { u8:3 }   // Jcond
    else if op == u8:0xCD { u8:3 }               // CALL
    else if (op & u8:0xC7) == u8:0xC4 { u8:3 }   // Ccond
    else if op == u8:0x32 { u8:3 }               // STA
    else if op == u8:0x3A { u8:3 }               // LDA
    else if op == u8:0x22 { u8:3 }               // SHLD
    else if op == u8:0x2A { u8:3 }               // LHLD
    else if (op & u8:0xC7) == u8:0x06 { u8:2 }   // MVI
    else if (op & u8:0xC7) == u8:0xC6 { u8:2 }   // immediate ALU
    else if op == u8:0xDB { u8:2 }               // IN
    else if op == u8:0xD3 { u8:2 }               // OUT
    else { u8:1 }
}

// Does opcode need memory read at (HL)?
fn needs_mem_read(op: u8) -> bool {
    let sss = op & u8:0x07;
    if (op & u8:0xC7) == u8:0x46 { true }           // MOV r,M
    else if (op & u8:0xF8) == u8:0x80 && sss == u8:0x06 { true }  // ADD M
    else if (op & u8:0xF8) == u8:0x88 && sss == u8:0x06 { true }  // ADC M
    else if (op & u8:0xF8) == u8:0x90 && sss == u8:0x06 { true }  // SUB M
    else if (op & u8:0xF8) == u8:0x98 && sss == u8:0x06 { true }  // SBB M
    else if (op & u8:0xF8) == u8:0xA0 && sss == u8:0x06 { true }  // ANA M
    else if (op & u8:0xF8) == u8:0xA8 && sss == u8:0x06 { true }  // XRA M
    else if (op & u8:0xF8) == u8:0xB0 && sss == u8:0x06 { true }  // ORA M
    else if (op & u8:0xF8) == u8:0xB8 && sss == u8:0x06 { true }  // CMP M
    else if op == u8:0x34 { true }                  // INR M
    else if op == u8:0x35 { true }                  // DCR M
    else { false }
}

// Does opcode need stack read?
fn needs_stack_read(op: u8) -> bool {
    if op == u8:0xC9 { true }                       // RET
    else if (op & u8:0xC7) == u8:0xC0 { true }      // Rcond
    else if (op & u8:0xCF) == u8:0xC1 { true }      // POP
    else { false }
}

// ============================================================================
// The CPU Proc
// ============================================================================

proc i8085 {
    // Memory bus channels
    mem_req: chan<MemRequest> out;
    mem_resp: chan<u8> in;

    // Debug output (optional)
    debug_pc: chan<u16> out;

    init { initial_state() }

    config(mem_req: chan<MemRequest> out,
           mem_resp: chan<u8> in,
           debug_pc: chan<u16> out) {
        (mem_req, mem_resp, debug_pc)
    }

    next(state: CpuState) {
        let regs = state.regs;
        let hl = get_hl(regs);

        // Send debug PC
        let tok = send(join(), debug_pc, regs.pc);

        // Default: no memory request
        let no_req = MemRequest { addr: u16:0, write_data: u8:0, read: false, write: false };

        match state.phase {
            Phase::FETCH => {
                // Request opcode fetch from PC
                let req = MemRequest { addr: regs.pc, write_data: u8:0, read: true, write: false };
                let tok = send(tok, mem_req, req);
                CpuState { phase: Phase::FETCH_WAIT, ..state }
            },

            Phase::FETCH_WAIT => {
                // Receive opcode
                let (tok, opcode) = recv(tok, mem_resp);
                let need_mem = needs_mem_read(opcode);
                let need_stk = needs_stack_read(opcode);

                let next_phase = if need_mem { Phase::READ_MEM }
                                 else if need_stk { Phase::READ_STACK }
                                 else { Phase::EXECUTE };

                CpuState {
                    phase: next_phase,
                    opcode: opcode,
                    ..state
                }
            },

            Phase::READ_MEM => {
                // Read from (HL)
                let req = MemRequest { addr: hl, write_data: u8:0, read: true, write: false };
                let tok = send(tok, mem_req, req);
                let (tok, data) = recv(tok, mem_resp);

                let next_phase = if needs_stack_read(state.opcode) { Phase::READ_STACK }
                                 else { Phase::EXECUTE };

                CpuState { phase: next_phase, mem_data: data, ..state }
            },

            Phase::READ_STACK => {
                // Read stack (simplified - reads 2 bytes)
                let req_lo = MemRequest { addr: regs.sp, write_data: u8:0, read: true, write: false };
                let tok = send(tok, mem_req, req_lo);
                let (tok, lo) = recv(tok, mem_resp);

                let req_hi = MemRequest { addr: regs.sp + u16:1, write_data: u8:0, read: true, write: false };
                let tok = send(tok, mem_req, req_hi);
                let (tok, hi) = recv(tok, mem_resp);

                CpuState { phase: Phase::EXECUTE, stack_lo: lo, stack_hi: hi, ..state }
            },

            Phase::EXECUTE => {
                // Execute the instruction and update registers
                let op = state.opcode;
                let sss = (op & u8:0x07) as u3;
                let src_val = if sss == REG_M { state.mem_data }
                              else { get_reg(regs, sss) };

                // Simplified: handle a few key instructions
                let (new_regs, do_write, write_addr, write_data, halted) =
                    if op == u8:0x00 {
                        // NOP
                        (Registers { pc: regs.pc + u16:1, ..regs }, false, u16:0, u8:0, false)
                    } else if op == u8:0x76 {
                        // HLT
                        (Registers { pc: regs.pc + u16:1, ..regs }, false, u16:0, u8:0, true)
                    } else if (op & u8:0xF8) == u8:0x80 {
                        // ADD r/M
                        let (result, flags) = add_with_flags(regs.a, src_val, u1:0);
                        (Registers { a: result, flags: flags, pc: regs.pc + u16:1, ..regs },
                         false, u16:0, u8:0, false)
                    } else if (op & u8:0xC0) == u8:0x40 && op != u8:0x76 {
                        // MOV (excluding HLT)
                        let dst = ((op >> 3) & u8:0x07) as u3;
                        let new_regs = if dst == REG_M {
                            Registers { pc: regs.pc + u16:1, ..regs }
                        } else {
                            let r = set_reg(regs, dst, src_val);
                            Registers { pc: r.pc + u16:1, ..r }
                        };
                        let do_wr = dst == REG_M;
                        (new_regs, do_wr, hl, src_val, false)
                    } else if op == u8:0xC3 {
                        // JMP
                        let addr = ((state.imm2 as u16) << 8) | (state.imm1 as u16);
                        (Registers { pc: addr, ..regs }, false, u16:0, u8:0, false)
                    } else if op == u8:0xC9 {
                        // RET
                        let ret_addr = ((state.stack_hi as u16) << 8) | (state.stack_lo as u16);
                        (Registers { pc: ret_addr, sp: regs.sp + u16:2, ..regs },
                         false, u16:0, u8:0, false)
                    } else {
                        // Default: just advance PC
                        (Registers { pc: regs.pc + u16:1, ..regs }, false, u16:0, u8:0, false)
                    };

                let next_phase = if halted { Phase::HALTED }
                                 else if do_write { Phase::WRITE_MEM }
                                 else { Phase::FETCH };

                CpuState {
                    regs: new_regs,
                    phase: next_phase,
                    halted: halted,
                    // Store write info for WRITE_MEM phase (would need extra state fields)
                    ..state
                }
            },

            Phase::WRITE_MEM => {
                // Would issue write request here
                let tok = send(tok, mem_req, no_req);
                CpuState { phase: Phase::FETCH, ..state }
            },

            Phase::HALTED => {
                // Stay halted
                let tok = send(tok, mem_req, no_req);
                state
            },

            _ => state,
        }
    }
}
