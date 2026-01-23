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

| Config | Internal RAM | Internal ROM | External A/D Bus | Target | Use Case |
|--------|-------------|--------------|------------------|--------|----------|
| `i8085_test` | 128KB | 8MB SPI | No | UP5K | Validation, benchmarking |
| `i8085_40dip` | None | None | Full | HX8K | True drop-in replacement |
| `i8085_40dip_plus` | ~124KB | 8MB SPI | Configurable window | UP5K | Enhanced drop-in |
| `i8085_mcu` | TBD | TBD | No | - | **FUTURE** - Modern MCU |

### i8085_test - Validation Target

Self-contained system for CPU validation and benchmarking.

- **Internal**: 128KB SPRAM (4 banks), 8MB SPI flash ROM (256 banks)
- **External**: Minimal pins (debug LED only)
- **Purpose**: CPU verification, timing analysis, test programs
- **Synthesis**: Unconstrained for maximum Fmax measurement
- **Target**: iCE40 UP5K SG48

### i8085_40dip - True Drop-in Replacement

Exact 40-DIP pinout compatible with original Intel 8085.

- **Internal**: None - all memory external
- **External**: Full 8085 bus interface (AD[7:0], A[15:8], ALE, RD, WR, etc.)
- **Purpose**: Replace physical 8085 in existing systems
- **Target**: iCE40 HX8K CT256 (more IOs, faster fabric)

### i8085_40dip_plus - Enhanced Drop-in

Drop-in replacement with internal resources + configurable external window.

- **Internal**: ~124KB SPRAM (banked), 8MB SPI flash ROM
- **External**: Configurable address window (1/2/4KB) for peripherals
- **Build Parameters**:
  - `EXT_WINDOW_BASE`: Window start address (default: `0x7C00`)
  - `EXT_WINDOW_SIZE`: 10=1KB, 11=2KB, 12=4KB (default: 10)
  - `ACTIVE_AD_BUS`: 0=quiet pins, 1=active bus (default: 1)
- **Purpose**: Drop into existing 8085 socket with onboard resources
- **Target**: iCE40 UP5K SG48

**Default Memory Map:**
```
0x0000-0x7BFF: Internal SPRAM (31KB per bank, 4 banks = 124KB)
0x7C00-0x7FFF: EXTERNAL (1KB window for peripherals)
0x8000-0xFFFF: Internal SPI flash cache (32KB, banked 256× = 8MB)
```

## Quick Start

```bash
# 1. Setup XLS tools (one-time, auto-detects platform)
make setup

# 2. Run DSLX tests
make test

# 3. Synthesize a configuration
make test-synth        # i8085_test (unconstrained)
make 40dip-synth       # i8085_40dip (HX8K)
make 40dip-plus-synth  # i8085_40dip_plus (UP5K)
```

## Files

| File | Description |
|------|-------------|
| `i8085_core.x` | DSLX source - all CPU logic |
| `i8085_core.v` | Generated Verilog (combinational) |
| `i8085_wrapper.v` | Verilog wrapper with state registers |
| `i8085_test.v` | Test/validation configuration |
| `i8085_40dip.v` | True 40-DIP drop-in replacement |
| `i8085_40dip_plus.v` | Enhanced drop-in with configurable window |
| `cache_logic.x` | DSLX source - cache hit/miss logic |
| `spi_flash_cache.v` | SPI flash controller with 2KB cache |
| `spi_engine.v` | Low-level SPI protocol handler |
| `ice40hx8k_40dip.pcf` | Pin constraints for 40-DIP on HX8K |
| `ice40up5k_40dip_plus.pcf` | Pin constraints for 40dip_plus on UP5K |

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
| `make 40dip-synth` | Synthesize i8085_40dip for HX8K |
| `make 40dip-plus-synth` | Synthesize i8085_40dip_plus for UP5K |
| `make clean` | Remove generated files |

## Resource Usage

| Target | LCs | EBR | SPRAM | Fmax |
|--------|-----|-----|-------|------|
| i8085_test (UP5K) | ~4,100 (78%) | 4 | 4 | ~14 MHz |
| i8085_40dip (HX8K) | ~3,100 (40%) | - | - | ~25-30 MHz |
| i8085_40dip_plus (UP5K) | ~4,200 (80%) | 4 | 4 | ~12-14 MHz |

## 40-DIP Bus Interface

The `i8085_40dip` provides the classic 8085 bus interface:

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

Both `i8085_test` and `i8085_40dip_plus` support memory banking via I/O ports:

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
│ i8085_40dip - True Drop-in (HX8K)                           │
│                                                             │
│   External A/D bus, ALE, RD, WR, IO/M, interrupts           │
│     └── i8085_wrapper.v  - State registers                  │
│           └── i8085_core.v   - XLS combinational logic      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ i8085_test / i8085_40dip_plus (UP5K)                        │
│                                                             │
│   4× SB_SPRAM256KA (128KB) + SPI flash cache (8MB)          │
│     └── spi_flash_cache.v → spi_engine.v                    │
│     └── i8085_wrapper.v  - State registers                  │
│           └── i8085_core.v   - XLS combinational logic      │
│                                                             │
│   (40dip_plus adds: external window with A/D bus)           │
└─────────────────────────────────────────────────────────────┘
```

## Future: i8085_mcu

Planned modern microcontroller configuration:

- No external A/D bus
- Internal SPRAM + SPI flash
- iCE40 hard IP: SB_SPI, SB_I2C
- Soft cores: UART (16550-ish), GPIO with IRQ
- Possibly PWM, timers

## License

MIT
