# Intel 8085 CPU Core

A complete Intel 8085A microprocessor implementation in Google XLS DSLX, with multiple FPGA deployment configurations.

## Features

- All 244 documented 8085 opcodes
- Full interrupt system (TRAP, RST7.5, RST6.5, RST5.5, INTR)
- RIM/SIM instructions with interrupt masks
- Serial I/O (SID/SOD)
- SPI flash ROM with 2KB line cache (DSLX cache logic)
- Full memory banking: 128KB RAM (4 banks) + 8MB ROM (256 banks)

## Configurations

All configurations target **iCE40 UP5K SG48** for consistent silicon comparison.

| Config | Internal RAM | Internal ROM | External Bus | Use Case |
|--------|-------------|--------------|--------------|----------|
| `i8085_test` | 128KB | 8MB SPI | No | Validation, benchmarking |
| `i8085_dip40` | None | None | Full 8085 | True drop-in replacement |
| `i8085_dip40_plus` | 128KB | 8MB SPI | 1KB window | Enhanced drop-in |
| `i8085_mcu` | TBD | TBD | No | **FUTURE** - Modern MCU |

### i8085_test - Validation Target

Self-contained system for CPU validation and benchmarking.

- **Internal**: 128KB SPRAM (4 banks), 8MB SPI flash ROM (256 banks)
- **External**: Minimal pins (debug LED only)
- **Purpose**: CPU verification, timing analysis, test programs
- **Synthesis**: Unconstrained for maximum Fmax measurement

### i8085_dip40 - True Drop-in Replacement

Full 8085 bus interface for true drop-in replacement.

- **Internal**: None - all memory external
- **External**: Full 8085 bus (AD[7:0], A[15:8], ALE, RD, WR, IO/M, S0, S1, etc.)
- **Purpose**: Replace physical 8085 in existing systems
- **Pins**: 38 of 39 used (1 spare)

### i8085_dip40_plus - Enhanced Drop-in

Same 8085 interface as dip40, plus internal SPRAM and SPI flash ROM.

- **Internal**: 128KB SPRAM (4 banks), 8MB SPI flash ROM (256 banks)
- **External**: Same 8085 signals, but `a_hi[7:3]` (A15-A11) omitted
- **Extra pins**: 4 SPI pins for on-board flash ROM
- **Pins**: 35 of 39 used (4 spare)
- **Build Parameters**:
  - `EXT_WINDOW_BASE`: Window start address (default: `0x7C00`)
  - `EXT_WINDOW_SIZE`: 10=1KB, 11=2KB, 12=4KB (default: 10)

**Design choice - A15-A11 omitted:**

The UP5K SG48 has 39 IOs. The full 8085 interface needs 38 pins, leaving only 1
spare - not enough for 4 SPI pins. However, A15-A11 are unusable for external
access because those address regions are already mapped to internal resources:

- A15=1 (0x8000-0xFFFF): Internal SPI flash ROM
- A15=0, A14=0 (0x0000-0x3FFF): Internal SPRAM
- A15=0, A14=1, A13=0 (0x4000-0x5FFF): Internal SPRAM
- etc.

The only external window is at 0x7C00-0x7FFF, where A15-A11 are always constant
(0,1,1,1,1). External peripherals only need A10-A0 to distinguish addresses
within this window, provided via AD[7:0] + a_hi[2:0]. By not routing A15-A11
externally, we save 5 pins - enough for SPI (4 pins) with 1 spare.

The external bus signals (ALE, RD, WR, etc.) remain quiet when accessing internal
SPRAM or SPI flash ROM, only activating for accesses within the external window.

**Default Memory Map:**
```
0x0000-0x7BFF: Internal SPRAM (31KB per bank, 4 banks = 124KB)
0x7C00-0x7FFF: EXTERNAL (1KB window for peripherals)
0x8000-0xFFFF: Internal SPI flash cache (32KB, banked 256x = 8MB)
```

## Quick Start

```bash
# 1. Setup XLS tools (one-time, auto-detects platform)
make setup

# 2. Run DSLX tests
make test

# 3. Synthesize a configuration
make test-synth        # i8085_test (unconstrained)
make dip40-synth       # i8085_dip40 (HX8K)
make dip40-plus-synth  # i8085_dip40_plus (UP5K)
```

## Files

| File | Description |
|------|-------------|
| `i8085_core.x` | DSLX source - all CPU logic |
| `i8085_core.v` | Generated Verilog (combinational) |
| `i8085_wrapper.v` | Verilog wrapper with state registers |
| `i8085_test.v` | Test/validation configuration |
| `i8085_dip40.v` | True DIP40 drop-in replacement |
| `i8085_dip40_plus.v` | Enhanced drop-in with configurable window |
| `cache_logic.x` | DSLX source - cache hit/miss logic |
| `spi_flash_cache.v` | SPI flash controller with 2KB cache |
| `spi_engine.v` | Low-level SPI protocol handler |
| `ice40up5k_dip40.pcf` | Pin constraints for DIP40 on UP5K |
| `ice40up5k_dip40_plus.pcf` | Pin constraints for dip40_plus on UP5K |

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

### Makefile Targets

| Target | Description |
|--------|-------------|
| `make setup` | Install XLS tools (auto-detects platform) |
| `make test` | Run all DSLX tests |
| `make verilog` | Generate Verilog from DSLX |
| `make test-synth` | Synthesize i8085_test (unconstrained) |
| `make dip40-synth` | Synthesize i8085_dip40 for HX8K |
| `make dip40-plus-synth` | Synthesize i8085_dip40_plus for UP5K |
| `make clean` | Remove generated files |

## Resource Usage

All configurations target UP5K SG48 for consistent comparison.

| Target | LCs | EBR | SPRAM | Fmax |
|--------|-----|-----|-------|------|
| i8085_test | 4,134 (78%) | 4 | 4 | 14.4 MHz |
| i8085_dip40 | 3,079 (58%) | - | - | 15.5 MHz |
| i8085_dip40_plus | 4,300 (81%) | 4 | 4 | 14.2 MHz |

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

Both `i8085_test` and `i8085_dip40_plus` support memory banking via I/O ports:

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

Configurations with internal ROM include an SPI flash controller with cache:

- **SPI Interface**: Standard JEDEC read command (0x03), Mode 0
- **Cache**: 2KB direct-mapped, 32 lines × 64 bytes
- **Banking**: 256 banks × 32KB = 8MB addressable ROM
- **Cache Logic**: Implemented in DSLX (`cache_logic.x`)

The cache tag includes the bank number, so switching banks doesn't require cache invalidation.

**Performance:**
| Scenario | Cycles |
|----------|--------|
| Cache hit | 2 |
| Cache miss (critical word) | ~80 |
| Cache miss (full line fill) | ~1100 |

## XLS Tools on macOS

The Google XLS toolchain only provides pre-built binaries for x64 Linux. On macOS, use Docker via [OrbStack](https://orbstack.dev/):

```bash
# Install OrbStack (or Docker Desktop)
brew install orbstack

# Setup is automatic via make:
make setup
```

The `tools/xls` wrapper runs XLS tools via Docker, mounting the current directory so input/output files work seamlessly.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ i8085_dip40 - True Drop-in (HX8K)                           │
│                                                             │
│   External A/D bus, ALE, RD, WR, IO/M, interrupts           │
│     └── i8085_wrapper.v  - State registers                  │
│           └── i8085_core.v   - XLS combinational logic      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ i8085_test / i8085_dip40_plus (UP5K)                        │
│                                                             │
│   4× SB_SPRAM256KA (128KB) + SPI flash cache (8MB)          │
│     └── spi_flash_cache.v → spi_engine.v                    │
│     └── i8085_wrapper.v  - State registers                  │
│           └── i8085_core.v   - XLS combinational logic      │
│                                                             │
│   (dip40_plus adds: external window with A/D bus)           │
└─────────────────────────────────────────────────────────────┘
```

## Future: i8085_mcu

Planned modern microcontroller configuration:

- No external A/D bus
- Internal SPRAM + SPI flash
- iCE40 hard IP: SB_SPI, SB_I2C
- Soft cores: GPIO, UART, IRQ, PWM, timers, etc

## License

MIT
