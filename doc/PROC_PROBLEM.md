# XLS Proc Codegen Issue

## Date
2025-01-22

## Summary
Attempted to implement 8085 CPU as a DSLX `proc` for cleaner bus interfaces, but hit codegen errors.

## The Goal
Use XLS procs to get:
- Internal state (registers) hidden inside the module
- Clean channel-based bus interface (addr, data, rd, wr)
- XLS generates the registers and state machine

## What We Tried

### Proc Structure
```dslx
proc i8085 {
    mem_req: chan<MemRequest> out;
    mem_resp: chan<u8> in;
    debug_pc: chan<u16> out;

    init { initial_state() }

    config(mem_req: chan<MemRequest> out,
           mem_resp: chan<u8> in,
           debug_pc: chan<u16> out) {
        (mem_req, mem_resp, debug_pc)
    }

    next(state: CpuState) {
        // State machine with send/recv on channels
        match state.phase {
            Phase::FETCH => {
                let req = MemRequest { addr: regs.pc, ... };
                let tok = send(tok, mem_req, req);
                CpuState { phase: Phase::FETCH_WAIT, ..state }
            },
            // ... etc
        }
    }
}
```

### IR Conversion - WORKED
```bash
/opt/xls/ir_converter_main cpu8085/i8085_proc.x --top=i8085
```

Generated IR with clean channel declarations:
```
chan i8085_proc__mem_req((bits[16], bits[8], bits[1], bits[1]), ...)
chan i8085_proc__mem_resp(bits[8], ...)
chan i8085_proc__debug_pc(bits[16], ...)
```

### Codegen - FAILED

#### Attempt 1: Combinational
```bash
codegen_main cpu8085/i8085_proc.ir --generator=combinational
```
Error:
```
Register ____state has a reset value but corresponding register write
operation register_write.1328 has no reset operand
```

#### Attempt 2: Pipeline
```bash
codegen_main cpu8085/i8085_proc.ir --generator=pipeline \
    --pipeline_stages=1 --delay_model=unit
```
Error:
```
Impossible to schedule proc as specified; cannot achieve the specified
pipeline length or full throughput. Try --pipeline_stages=3 --worst_case_throughput=3
```

#### Attempt 3: Pipeline with suggested options
```bash
codegen_main cpu8085/i8085_proc.ir --generator=pipeline \
    --pipeline_stages=3 --worst_case_throughput=3 --delay_model=unit
```
Error:
```
Register ____state has a reset value but corresponding register write
operation register_write.3675 has no reset operand
```

## Root Cause (Hypothesis)
The proc has state with an `init` block that sets initial values, but something about how the state machine is structured causes the codegen to not properly wire up the reset logic.

Possibly related to:
- Multiple state variables in CpuState struct
- Complex match expression in next()
- send/recv blocking semantics creating scheduling constraints

## Files
- `cpu8085/i8085_proc.x` - The proc implementation (may be overwritten)
- `cpu8085/i8085_proc.ir` - Generated IR (if saved)

## Workaround
Use pure function approach:
- `i8085_core.x` - Combinational function: `(state, inputs) -> (new_state, outputs)`
- Hand-written Verilog wrapper holds state registers
- Generate wrapper from XLS signature file to hide bit-packing

## Future Investigation
1. Try simpler proc example to isolate the issue
2. Check XLS GitHub issues for similar problems
3. May need different proc structure (separate state variables vs struct?)
4. Consider filing bug report with minimal repro
