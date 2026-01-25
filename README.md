# Intel 8085 CPU Core

A complete [Intel 8085A](https://en.wikipedia.org/wiki/Intel_8085) microprocessor implementation in Google XLS DSLX.

## Project Vision

This started as a project to evaluate XLS, see how the ecosystem works. Especially in combination with new AI coding tools.
The target was chosen a little arbitrarily, but because I've been looking at the [TRS-80 Model 100](https://en.wikipedia.org/wiki/TRS-80_Model_100) and [small-C](https://github.com/apullin/small-c) recently.

The goal was to build a working 8085 core that fits in a cheap/easy-to-use FPGA and could eventually be deployed on a DIP40 package adapter PCB, nominally making a drop-in replacement for the original chip. Or at least a quirky, anachronistic breadboard computer.

The [iCE40 UP5K](https://www.latticesemi.com/Products/FPGAandCPLD/iCE40UltraPlus) is the primary target because it is well supported by Yosys and the [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build). And in the small-package version, it has _just_ enough pins to implement a 40-pin CPU!
It turned out to have enough LUTs for the core, and as it also has SRAM, we can also ship an "8085 SoC": a resource-rich variant using SRAM, banking, SPI-flash for ROM (with a cache implemented in XLS!).

**TODO:** Design a DIP40 adapter PCB that makes this a true drop-in replacement for vintage systems.

(silly stretch goal - an 8085duino 😏)

## Why the 8085?

The 8085 occupies an interesting place in computing history, as it's still early, as integrated CPUs were being rapidly iterated, but there's still a clear lineage from the true original commercial microprocessor:
4004 (1971) → 8008 (1972) → 8080 (1974, of Altair 8800 fame) → 8085 (1976) → 8086 (1978)

The 4004 was the true progenitor—the first commercial microprocessor. Revs to the 8008, 8080, and then 8085 were all improvements towards usability. And it's the last waypoint before the [Intel 8086](https://en.wikipedia.org/wiki/Intel_8086), which established the Intel x86 kingdom.

Fun fact: The 8085 was also [cloned by the Soviets](https://en.wikipedia.org/wiki/KR580VM80A) (as the KR1821VM85), a testament to its importance during the Cold War tech race.

But it's still an "uncommon" processor. It was used in the [TRS-80 Model 100](https://en.wikipedia.org/wiki/TRS-80_Model_100), one of the original portable computers, especially counting for mass-market adoption.† The design certainly has some real verve (The original "cyberdeck"?), and put the 8085 on my radar.


† Any computer historians, please chime in on this. Public data suggests sales of 6 million units, which seems like a massive deal for the era. Also super interested to hear from anyone who owned & used one of these machines!
(At least one retired journo told me how he'd take one to Kuwait, where he'd write stories and dial them back to New York using an acoustic coupler from his hotel room!)

## Status

As is detailed below, the core and all the wrapper systems seemed to come together very well. Claude was able to do quite a lot with XLS, quite quickly. The idea to rig a "SoC" out of the ice40 resources was certainly a fun design experiment, interactive with Claude, and was something of a test to myself of "do I know how to design a useful embedded system?"

The code and targets look complete, and there is some testbench coverage.
Has not been tried in hardware yet.

**TODO**: Get a real "blinky" working in-silicon on a dev board (modify PCF as needed)

## Features

- All 244 documented 8085 opcodes
- Full interrupt system (TRAP, RST7.5, RST6.5, RST5.5, INTR)
- RIM/SIM instructions with interrupt masks
- Serial I/O (SID/SOD)
- Multiple deployment configurations (bare CPU to full "SoC")

## Configurations

### Primary Target: iCE40 UP5K

All primary configurations target the **iCE40 UP5K SG48** for consistent comparison.

| Config | Description | Internal RAM | Internal ROM | External Bus |
|--------|-------------|--------------|--------------|--------------|
| `i8085_dip40` | True drop-in replacement | None | None | Full 8085 bus |
| `i8085_dip40_plus` | "SoC" with external window | 128KB SPRAM | 8MB SPI flash | 1KB window |
| `i8085_test` | Validation/benchmarking | 128KB SPRAM | 8MB SPI flash | None |

#### Timing-Compatible Variants

The base configurations run at FPGA speed, which violates 8085 AC timing specs. For compatibility with original 8085 peripherals, use the `_compat` variants:

| Config | Description |
|--------|-------------|
| `i8085_dip40_compat` | Timing-stretched signals for original peripherals |
| `i8085_dip40_plus_compat` | "SoC" variant with timing compatibility |

The timing wrapper stretches ALE (≥140ns), RD (≥400ns), and WR (≥400ns) to meet 8085 specifications while letting the CPU run internally at full speed.

### Configuration Details

#### i8085_dip40 — True Drop-in Replacement

Full 8085 bus interface for replacing a physical 8085 in existing systems.

- **Internal**: None—all memory is external
- **External**: Full 8085 bus (AD[7:0], A[15:8], ALE, RD, WR, IO/M, S0, S1, etc.)
- **Pins**: 38 of 39 used (1 spare)

#### i8085_dip40_plus — The "SoC" Variant

Same 8085 interface, but with internal SPRAM, SPI flash ROM, and a configurable external peripheral window. This is effectively an "8085 SoC"—the classic instruction set backed by modern resources.

- **Internal**: 128KB SPRAM (4 banks), 8MB SPI flash ROM (256 banks)
- **External**: 1KB window at 0x7C00-0x7FFF for peripherals
- **Extra pins**: 4 SPI pins for on-board flash ROM
- **Pins**: 35 of 39 used (4 spare)

**Default Memory Map:**
```
0x0000-0x7BFF: Internal SPRAM (31KB per bank, 4 banks via port 0xF1)
0x7C00-0x7FFF: EXTERNAL (1KB window for peripherals)
0x8000-0xFFFF: Internal SPI flash cache (32KB, 256 banks via port 0xF0)
```

**Why A15-A11 are omitted:** The UP5K SG48 has 39 IOs. The full 8085 interface needs 38, leaving only 1 spare—not enough for 4 SPI pins. However, A15-A11 are constant within the external window (0x7C00-0x7FFF = 0,1,1,1,1), so external devices only need A10-A0. Omitting A15-A11 saves 5 pins.

#### i8085_test — Validation Target

Self-contained system for CPU validation and benchmarking.

- **Internal**: 128KB SPRAM, 8MB SPI flash ROM
- **External**: Minimal pins (debug LED only)
- **Purpose**: CPU verification, timing analysis, test programs

### Future: i8085_mcu — Microcontroller Variant

A planned modern microcontroller configuration:

- No external address/data bus
- Internal SPRAM + SPI flash only
- iCE40 hard IP: SB_SPI, SB_I2C
- Soft peripherals: GPIO, UART, timers, PWM, IRQ controller

## Resource Usage (iCE40 UP5K)

| Configuration | LCs | EBR | SPRAM | Fmax |
|---------------|-----|-----|-------|------|
| i8085_dip40 | 3,079 (58%) | — | — | 15.5 MHz |
| i8085_dip40_plus | 4,300 (81%) | 4 | 4 | 14.2 MHz |
| i8085_test | 4,134 (78%) | 4 | 4 | 14.4 MHz |

## Other FPGA Implementations

Larger FPGAs can also be used. These are primarily synthesis tests demonstrating that more advanced process nodes yield substantial speed improvements:

| Target | Configuration | LCs | Fmax | Notes |
|--------|---------------|-----|------|-------|
| iCE40 HX8K | i8085_dip40_plus_hx8k | ~4,200 | ~18 MHz | Uses EBR instead of SPRAM |
| ECP5-25F | i8085_dip40_plus_ecp5 | ~3,800 | ~45 MHz | OrangeCrab target |

The ECP5's more advanced architecture nearly triples the clock speed compared to iCE40.

## Files

### Core CPU

| File | Description |
|------|-------------|
| `i8085_core.x` | DSLX source—all CPU logic (combinational) |
| `i8085_core.v` | Generated Verilog from DSLX |
| `i8085_wrapper.v` | Verilog wrapper adding state registers |

### iCE40 UP5K Configurations

| File | Description |
|------|-------------|
| `i8085_dip40.v` | True DIP40 drop-in replacement |
| `i8085_dip40_plus.v` | "SoC" with external window |
| `i8085_test.v` | Validation/benchmarking configuration |
| `i8085_dip40_compat.v` | Timing-compatible DIP40 wrapper |
| `i8085_dip40_plus_compat.v` | Timing-compatible "SoC" wrapper |
| `i8085_timing_compat.v` | Timing stretcher for 8085 AC specs |

### Other FPGA Targets

| File | Description |
|------|-------------|
| `i8085_dip40_plus_hx8k.v` | HX8K variant using EBR |
| `i8085_test_hx8k.v` | HX8K test configuration |
| `i8085_dip40_plus_ecp5.v` | ECP5 OrangeCrab variant |
| `i8085_test_ecp5.v` | ECP5 test configuration |

### Memory Subsystem

| File | Description |
|------|-------------|
| `spi_flash_cache.v` | SPI flash controller with 2KB cache |
| `spi_engine.v` | Low-level SPI protocol handler |
| `cache_logic.x` | DSLX source—cache hit/miss logic |
| `cache_logic.v` | Generated cache logic |

### Testbenches

| File | Description |
|------|-------------|
| `i8085_timing_tb.v` | Base CPU timing verification |
| `i8085_compat_tb.v` | Timing-compatible variant verification |

### Build Support

| File | Description |
|------|-------------|
| `ice40up5k_dip40.pcf` | Pin constraints for DIP40 on UP5K |
| `ice40up5k_dip40_plus.pcf` | Pin constraints for dip40_plus on UP5K |

## Quick Start

```bash
# 1. Setup XLS tools (one-time, auto-detects platform)
make setup

# 2. Run DSLX tests
make test

# 3. Synthesize a configuration
make dip40-synth       # i8085_dip40 for UP5K
make dip40-plus-synth  # i8085_dip40_plus for UP5K
make test-synth        # i8085_test (unconstrained)
```

## Building

### Prerequisites

- **XLS tools**: Installed via `make setup` (Docker on macOS, native on Linux x64)
- **FPGA tools**: [Yosys](https://github.com/YosysHQ/yosys) and [nextpnr](https://github.com/YosysHQ/nextpnr)

```bash
# macOS
brew install yosys nextpnr

# Linux
apt install yosys nextpnr
```

## DIP40 Bus Interface

The `i8085_dip40` provides the classic 8085 bus interface:

| Signal | Description |
|--------|-------------|
| AD[7:0] | Multiplexed address/data bus |
| A[15:8] | High address bits |
| ALE | Address Latch Enable |
| RD | Read strobe (active low) |
| WR | Write strobe (active low) |
| IO/M | High=I/O, Low=Memory |
| S0, S1 | Status outputs |
| READY | Wait state input |
| HOLD/HLDA | DMA support |
| TRAP, RST7.5, RST6.5, RST5.5, INTR | Interrupts |
| INTA | Interrupt acknowledge |
| SID/SOD | Serial I/O |

## Bank Registers

Configurations with internal memory support banking via I/O ports:

| Port | Bits | Function |
|------|------|----------|
| `0xF0` | 8 | ROM bank (256 banks × 32KB = 8MB) |
| `0xF1` | 2 | RAM bank (4 banks × 32KB = 128KB) |

```asm
; Switch to ROM bank 3
MVI A, 03h
OUT 0F0h

; Switch to RAM bank 2
MVI A, 02h
OUT 0F1h
```

## SPI Flash ROM

Configurations with internal ROM include an SPI flash controller:

- **Interface**: Standard JEDEC read command (0x03), Mode 0
- **Cache**: 2KB direct-mapped, 32 lines × 64 bytes
- **Banking**: 256 banks × 32KB = 8MB addressable ROM
- **Cache Logic**: Implemented in DSLX (`cache_logic.x`)

| Scenario | Cycles |
|----------|--------|
| Cache hit | 2 |
| Cache miss (critical word) | ~80 |
| Cache miss (full line fill) | ~1100 |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ i8085_dip40 — True Drop-in                                  │
│                                                             │
│   External A/D bus, ALE, RD, WR, IO/M, interrupts           │
│     └── i8085_wrapper.v  — State registers                  │
│           └── i8085_core.v   — XLS combinational logic      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ i8085_dip40_plus / i8085_test — "SoC" Configurations        │
│                                                             │
│   4× SB_SPRAM256KA (128KB) + SPI flash cache (8MB)          │
│     └── spi_flash_cache.v → spi_engine.v                    │
│     └── i8085_wrapper.v  — State registers                  │
│           └── i8085_core.v   — XLS combinational logic      │
│                                                             │
│   (dip40_plus adds: external window with A/D bus)           │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ i8085_*_compat — Timing-Compatible Variants                 │
│                                                             │
│   Wraps base configuration with timing stretcher            │
│     └── i8085_timing_compat.v — ALE/RD/WR stretching        │
│           └── [base configuration]                          │
└─────────────────────────────────────────────────────────────┘
```

## XLS Tools on macOS

The Google XLS toolchain only provides pre-built binaries for x64 Linux. For macOS (Apple Silicon), prebuilt native tools are available at:

```
/Users/andrewpullin/personal/xls/xls-src/bin/
```

Key tools:
- `dslx_interpreter_main` - Run DSLX tests
- `ir_converter_main` - Convert DSLX to XLS IR
- `opt_main` - Optimize XLS IR
- `codegen_main` - Generate Verilog from IR

Example usage:
```bash
XLS=/Users/andrewpullin/personal/xls/xls-src/bin

# Run tests
$XLS/dslx_interpreter_main myfile.x

# Generate Verilog (no SystemVerilog features for Yosys compatibility)
$XLS/ir_converter_main myfile.x --top=my_func > myfile.ir
$XLS/opt_main myfile.ir > myfile_opt.ir
$XLS/codegen_main myfile_opt.ir --output_verilog_path=myfile.v \
    --generator=combinational --delay_model=unit --use_system_verilog=false
```

## License

MIT
