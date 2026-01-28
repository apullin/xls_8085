# i8085 MCU Optimizations for iCE40 UP5K

The iCE40 UP5K has only 5280 LUTs, making every optimization critical. This document captures the major techniques used to fit a full-featured 8085 MCU into this constrained FPGA.

## Architecture Refactoring

The original MCU design grew organically around a single flat Verilog module (`i8085sg.v`, ~700 lines). The XLS-generated CPU core (`i8085_core_parity_opt.v`) is a pure combinational function — it takes the current state (registers, flags, opcode, immediate bytes, memory read results) and produces the next state in a single cycle. That means someone has to manage the fetch sequencing, and in the original design, that someone was the system wrapper.

This created several problems:

**The FSM lived in the wrong place.** The 15-state fetch FSM was in `i8085sg.v`, but the program counter it controlled was inside the core. Every fetch required the wrapper to extract `pc` from the core's output, present it on the address bus, wait for SPRAM, latch the result, and feed it back in. A `pc_wait_done` signal papered over the 1-cycle latency mismatch between "PC updated in core" and "address presented to SPRAM." It worked, but it was fragile.

**Instruction decode was duplicated.** The wrapper needed to know how many bytes to fetch (1, 2, or 3) and whether the instruction required a memory read or stack access — before execution. Functions like `inst_len()`, `needs_hl_read()`, `needs_direct_read()`, and `needs_stack_read()` appeared in `i8085sg.v`, `i8085_dip40_plus.v`, and anywhere else that wrapped the core. Each copy was ~30 lines of case logic that had to stay in sync.

**Read and write used different address paths.** The read path was FSM-controlled through `fetch_addr`. The write path was driven combinationally from `core_mem_addr` during the execute cycle. Two separate address decode paths meant two chances for bugs, and the asymmetric timing made the critical path hard to reason about.

**The wrapper did everything.** SPRAM instances, SPI flash cache, peripheral muxing, interrupt priority encoding, bank registers, and the fetch FSM were all in the same module. Changing the memory map meant touching the same file as changing the fetch sequence.

### The refactoring

The fix was separation of concerns into three layers:

```
i8085sg.v  (~200 lines, thin integration)
├── i8085_cpu.v  (self-contained CPU)
│   ├── PC, SP, registers, flags
│   ├── Fetch FSM (FETCH_OP → WAIT_OP → DECODE_OP → ... → EXECUTE)
│   ├── i8085_decode.v (shared instruction classifier)
│   └── i8085_core_parity_opt.v (XLS-generated ALU/execute)
│
├── memory_controller.v  (unified memory routing)
│   ├── Address decode: common RAM / peripherals / banked RAM / banked ROM
│   ├── 4× SB_SPRAM256KA instances
│   └── SPI flash cache
│
└── Peripherals  (unchanged, directly instantiated)
    ├── timer16_wrapper, gpio8_wrapper, gpio4_wrapper
    ├── userial_wrapper, spi_wrapper
    └── i2c_wrapper, imath_lite_wrapper
```

**The CPU owns the fetch.** `i8085_cpu.v` contains the PC, the fetch FSM, and the decode logic. It presents `bus_addr` / `bus_rd` / `bus_wr` as a bus master interface. The memory controller doesn't know or care that it's talking to an 8085 — it just sees address, read, write, and ready.

**Decode is shared.** `i8085_decode.v` is a pure combinational module that classifies an opcode into instruction length, memory access type, and stack access type. Instantiated once inside the CPU, referenced nowhere else.

**One address path.** The memory controller has a single `cpu_addr` input. Whether the CPU is fetching an opcode, reading an operand, or writing a result, it all goes through the same bus. The address decode (RAM vs. ROM vs. peripheral) happens in one place.

**The wrapper is just wiring.** `i8085sg.v` instantiates the CPU, memory controller, and peripherals, connects their ports, and handles the interrupt priority encoder. No FSM, no decode, no SPRAM.

This was done in four phases: extract shared decode (Phase 1), create self-contained CPU (Phase 2), create memory controller (Phase 3), simplify wrapper (Phase 4). Each phase was independently testable — the existing blinky testbenches caught regressions at every step.

### Results

The refactoring alone didn't dramatically change LUT count (the same logic exists, just reorganized). The real payoff was that with clean module boundaries, two targeted timing optimizations became obvious and easy to implement — see sections 11 and 12 below. Together:

| Metric | Before (flat) | After (refactored + optimized) |
|--------|---------------|-------------------------------|
| i8085sg.v | ~700 lines | ~200 lines |
| Duplicated decode | 3+ copies | 1 module |
| SG LUTs | 5192 | 4911 (−5%) |
| SG Fmax | ~18 MHz | 26.9 MHz (+49%) |
| SV Fmax | ~17 MHz | 24.2 MHz (+42%) |

---

## 1. Hand-Written Verilog vs XLS-Generated

XLS (Google's hardware synthesis language) generates correct but verbose Verilog. Replacing XLS-generated peripherals with hand-written Verilog yielded significant savings:

| Peripheral | XLS LUTs | Hand-Written | Savings |
|------------|----------|--------------|---------|
| SPI        | 493      | 234          | 259 (53%) |
| UART       | 684      | ~450         | ~230 |
| Timer      | 470      | 329-392      | ~100-140 |
| GPIO       | 192      | ~130         | ~60 |

XLS tends to generate explicit state for every possible condition, while hand-written code can share logic and use more implicit state.

## 2. Small Memory Arrays

**Note:** iCE40 does NOT have distributed RAM (LUT-RAM) like Xilinx FPGAs. Small memories are always implemented as registers.

For small FIFOs (4-8 entries), use array syntax for maintainability:

```verilog
reg [7:0] tx_fifo [0:3];  // 4-entry FIFO, becomes registers
```

Cost for a 4-byte FIFO: ~32 DFFs + ~16-24 LUTs (read mux + write decode).

For larger memories (>32 bytes), consider using BRAM (SB_RAM40_4K, minimum 512 bytes) if the size penalty is acceptable.

## 3. Edge-Detect for Compare Match IRQs

In the PWM timer, compare match interrupts were originally implemented with 16-bit equality comparisons:

```verilog
// Original: 4x 16-bit equality = ~64 LUTs
if (counter == cmp0) status[FLAG_CMP0] <= 1'b1;
if (counter == cmp1) status[FLAG_CMP1] <= 1'b1;
if (counter == cmp2) status[FLAG_CMP2] <= 1'b1;
if (counter == cmp3) status[FLAG_CMP3] <= 1'b1;
```

Since PWM outputs already use `counter < cmpN`, we can detect compare match as an edge on the PWM signal:

```verilog
// Optimized: reuse existing PWM comparison + 4 FFs + 4 XORs
assign pwm0 = (counter < cmp0);  // Already needed for PWM output
pwm0_prev <= pwm0;
if (pwm0 != pwm0_prev) status[FLAG_CMP0] <= 1'b1;  // Edge = compare match
```

**Savings: ~100+ LUTs** (eliminated 4x redundant 16-bit comparisons)

Note: This only works when PWM outputs exist. For timers without PWM, equality comparison is still needed.

## 4. Threshold Comparison Optimization

FIFO threshold comparisons like "trigger when count >= threshold + 1" waste an adder:

```verilog
// Original: requires 3-bit adder
wire [2:0] rx_threshold = {1'b0, rx_thr} + 3'd1;
wire irq_rxlvl = (rx_count >= rx_threshold);

// Optimized: mathematically equivalent, no adder
wire irq_rxlvl = (rx_count > {1'b0, rx_thr});
```

`count >= (thr + 1)` is identical to `count > thr`. Applied to both UART and userial.

## 5. Status Register Bit Insertion

Adding a read-only bit (like direction flag) to a status register:

```verilog
// Bad: OR insertion = ~60+ LUTs (creates wide mux)
REG_STATUS: data_out = status | {1'b0, count_dir, 6'b0};

// Good: concatenation = minimal LUTs
REG_STATUS: data_out = {1'b0, count_dir, status[5:0]};
```

## 6. Narrow Mux Before Padding

For peripherals with fewer than 8 bits of data (like 4-bit GPIO), mux at the narrow width then zero-pad:

```verilog
// Good: 4-bit mux, then pad
reg [3:0] data_out_4;
always @(*) begin
    case (addr)
        REG_DATA_OUT: data_out_4 = r_data_out;
        REG_DATA_IN:  data_out_4 = actual_pins;
        // ...
    endcase
    data_out = {4'h0, data_out_4};  // Pad after mux
end

// Bad: 8-bit mux with upper bits always zero
always @(*) begin
    case (addr)
        REG_DATA_OUT: data_out = {4'h0, r_data_out};
        REG_DATA_IN:  data_out = {4'h0, actual_pins};
        // ... (synthesizer may not optimize)
    endcase
end
```

## 7. SPRAM for Main Memory

UP5K has 4x 256Kbit SPRAM blocks (128KB total). Using these for main RAM instead of BRAM saves all 30 BRAM blocks for other uses (like instruction cache).

```verilog
SB_SPRAM256KA ram_bank0 (
    .ADDRESS(ram_addr), .DATAIN(ram_wdata), .MASKWREN(ram_we),
    .WREN(|ram_we & ram_cs[0]), .CHIPSELECT(ram_cs[0]), .CLOCK(clk),
    .STANDBY(1'b0), .SLEEP(1'b0), .POWEROFF(1'b1), .DATAOUT(ram_rdata_0)
);
```

## 8. DSP Blocks for Multiply

UP5K has 8 DSP blocks (SB_MAC16). Using these for integer multiply operations saves hundreds of LUTs:

```verilog
// imath_lite uses 2x SB_MAC16 for 16x16 signed/unsigned multiply
SB_MAC16 #(
    .A_SIGNED(1'b0), .B_SIGNED(1'b0), // ... config
) mac_unsigned ( ... );

SB_MAC16 #(
    .A_SIGNED(1'b1), .B_SIGNED(1'b1), // ... config
) mac_signed ( ... );
```

This provides single-cycle 8x8 or 16x16 multiply at zero LUT cost.

## 9. Placement Seed Iteration

nextpnr placement is non-deterministic. Running with different seeds can improve timing by 10-15%:

```bash
make -f Makefile.synth sg-seedsearch          # Search 20 seeds, 4-way parallel
make -f Makefile.synth sg SEED=17             # Build with specific seed
```

Best-known seeds are tracked in `Makefile.synth` and used by default. The seedsearch targets print a ranked top-10 and suggest the best seed found.

## 10. Parity-Optimized CPU Core

The XLS-generated CPU core (`i8085_core.v`) uses 1790 LUTs with 18 speculative parity calculations. The parity-optimized variant (`i8085_core_parity_opt.v`) computes parity only once after the result is known:

| Core | LUTs | Notes |
|------|------|-------|
| i8085_core.v | 1790 | XLS-generated, 18 speculative parity |
| i8085_core_parity_opt.v | 1423 | Single parity calculation |

**Savings: ~367 LUTs** - essential for fitting vmath-equipped builds.

Both use the same wrapper interface and are interchangeable in `i8085_cpu.v`.

## 11. Decode Pipeline Stage (S_DECODE_OP)

The refactored CPU (`i8085_cpu.v`) fetches opcodes from SPRAM. In the original 2-cycle fetch, the opcode arrives in S_WAIT_OP and the decode combinational logic (instruction length, memory read type, etc.) feeds directly into the FSM next-state mux — all in one cycle. On iCE40 this creates a long path from SPRAM output through the decode functions into the state register.

Inserting a dedicated S_DECODE_OP state breaks this into two stages:

1. **S_WAIT_OP** — latch `bus_data_in` into `fetched_op` (register)
2. **S_DECODE_OP** — the `i8085_decode` module reads the now-stable registered opcode; its combinational outputs (`inst_len`, `needs_hl_read`, etc.) drive the next-state decision

Cost: +1 cycle per instruction fetch (3 cycles instead of 2). The decode outputs are clean registered-input combinational logic, which nextpnr can place and route with less pressure.

## 12. Registered Write Address/Data

The XLS-generated core (`i8085_core_parity_opt.v`) is purely combinational — it produces `mem_addr`, `mem_data`, and `mem_wr` in the same cycle it receives its inputs. In the original design, `bus_addr` was driven directly from these core outputs during S_EXECUTE, creating a deep path:

```
XLS core internals → core_mem_addr → bus_addr → memory controller
address decode → SPRAM write-enable
```

The fix registers the write address and data during S_EXECUTE, then asserts the actual `bus_wr` one cycle later in S_WRITE_MEM:

```verilog
// S_EXECUTE: latch address and data
r_bus_addr       <= core_mem_addr;
r_pending_mem_wr <= 1'b1;
r_mem_data       <= core_mem_data;
fsm_state        <= S_WRITE_MEM;

// S_WRITE_MEM: bus_wr fires with registered address/data
assign bus_wr = (fsm_state == S_WRITE_MEM) && r_pending_mem_wr;
```

Cost: +1 cycle for memory-write instructions only. The bus address is always driven from `r_bus_addr` (a register), so the address decode in the memory controller starts from a flop — no combinational depth from the core.

**Combined result of optimizations 11 + 12:**

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| SG LUTs | 5192 | 4911 | −281 (−5.4%) |
| SG Fmax | ~18 MHz | 26.9 MHz | +49% |
| SV LUTs | 5164 | 5169 | ~same |
| SV Fmax | ~17 MHz | 24.2 MHz | +42% |

The LUT reduction comes from the registered write path eliminating the bus_addr mux that selected between fetch address and core write address. With the write path registered, bus_addr is always `r_bus_addr` — a single flop output with no mux.

To revert to the original combinational write path (for comparison), compile with `-DORIGINAL_EXECUTE_MEM_WR`.

## Summary: Final Resource Usage

Both variants fit on UP5K after the refactored CPU hierarchy and timing optimizations:

**i8085sg** (System General): 4911/5280 LCs (93%), 26.9 MHz
- 2x userial (UART/SPI switchable)
- 12 GPIO (8+4)
- 4 PWM with center-aligned mode
- imath_lite (DSP multiply)
- I2C
- SPI flash cache
- 128KB SPRAM
- Synthesis: `synth_ice40 -dsp -abc2`

**i8085sv** (System Vector): 5169/5280 LCs (97%), 24.2 MHz
- 1x userial
- 8 GPIO
- 4-channel timer
- imath_lite + vmath (vector DMA)
- I2C
- SPI flash cache
- 128KB SPRAM
- Synthesis: `synth_ice40 -dsp -noabc9 -retime`

The SG variant now has ~370 LUTs of headroom — enough for additional peripherals. The SV variant is tighter due to the vmath DMA engine but comfortably meets timing at 12 MHz system clock.

Build and test:
```bash
make -f Makefile.synth all     # Synthesize both variants
make -f Makefile.synth test    # Run all simulation testbenches
```
