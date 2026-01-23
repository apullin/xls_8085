# Intel 8085 CPU Core

A complete Intel 8085A microprocessor implementation in Google XLS DSLX, with Verilog wrappers for FPGA deployment.

## Features

- All 244 documented 8085 opcodes
- Full interrupt system (TRAP, RST7.5, RST6.5, RST5.5, INTR)
- RIM/SIM instructions with interrupt masks
- Serial I/O (SID/SOD)
- Two deployment options:
  - **40-DIP compatible** external bus interface
  - **iCE40 SoC** with integrated SPRAM and SPI flash ROM
- SPI flash ROM with 2KB line cache (DSLX cache logic)
- Full memory banking: 128KB RAM (4 banks) + 8MB ROM (256 banks)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Option A: 40-DIP External Bus                               │
│                                                             │
│   i8085_40dip.v     - Bus FSM, interrupts, ALE/RD/WR timing │
│     └── i8085_wrapper.v  - State registers, bit packing     │
│           └── i8085_core.v   - XLS combinational logic      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Option B: iCE40 SoC (self-contained)                        │
│                                                             │
│   i8085_soc.v       - Memory FSM + SB_SPRAM256KA (32/64KB)  │
│     └── i8085_wrapper.v  - State registers, bit packing     │
│           └── i8085_core.v   - XLS combinational logic      │
└─────────────────────────────────────────────────────────────┘
```

## Files

| File | Description |
|------|-------------|
| `i8085_core.x` | DSLX source - all CPU logic |
| `i8085_core.v` | Generated Verilog (combinational) |
| `i8085_wrapper.v` | Verilog wrapper with state registers |
| `i8085_40dip.v` | 40-DIP compatible external bus interface |
| `i8085_soc.v` | iCE40 SoC with integrated SPRAM |
| `cache_logic.x` | DSLX source - cache hit/miss logic |
| `spi_flash_cache.v` | SPI flash controller with 2KB line cache |
| `spi_engine.v` | Low-level SPI protocol handler |
| `ice40up5k.pcf` | Pin constraints for iCE40 UP5K |

## Quick Start

```bash
# 1. Setup XLS tools (one-time, auto-detects platform)
make setup

# 2. Run tests and build everything
make test      # Run DSLX tests
make all       # Generate Verilog + synthesize for iCE40 UP5K
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

### Makefile Targets

| Target | Description |
|--------|-------------|
| `make setup` | Install XLS tools (auto-detects platform) |
| `make test` | Run all DSLX tests |
| `make verilog` | Generate Verilog from DSLX |
| `make synth` | Synthesize for iCE40 UP5K |
| `make all` | Verilog + synthesis |
| `make clean` | Remove generated files |

### Manual Build Steps

<details>
<summary>Generate Verilog from DSLX (without Makefile)</summary>

```bash
# CPU core
./tools/xls interpreter_main i8085_core.x
./tools/xls ir_converter_main i8085_core.x --top=execute > i8085_core.ir
./tools/xls opt_main i8085_core.ir > i8085_core.opt.ir
./tools/xls codegen_main i8085_core.opt.ir \
  --generator=combinational \
  --output_verilog_path=i8085_core.v

# Cache logic
./tools/xls interpreter_main cache_logic.x
./tools/xls ir_converter_main cache_logic.x --top=cache_lookup > cache_logic.ir
./tools/xls opt_main cache_logic.ir > cache_logic.opt.ir
./tools/xls codegen_main cache_logic.opt.ir \
  --generator=combinational \
  --output_verilog_path=cache_logic.v
```

</details>

<details>
<summary>Synthesize for iCE40 (without Makefile)</summary>

**iCE40 UP5K SoC:**
```bash
yosys -p "read_verilog -sv i8085_core.v cache_logic.v; \
  read_verilog i8085_wrapper.v spi_engine.v spi_flash_cache.v i8085_soc.v; \
  synth_ice40 -top i8085_soc -json i8085_soc.json"
nextpnr-ice40 --up5k --package sg48 --json i8085_soc.json --pcf ice40up5k.pcf --asc i8085_soc.asc
```

**40-DIP wrapper (external memory):**
```bash
yosys -p "read_verilog -sv i8085_core.v; \
  read_verilog i8085_wrapper.v i8085_40dip.v; \
  synth_ice40 -top i8085_40dip -json i8085_40dip.json"
nextpnr-ice40 --hx8k --package ct256 --json i8085_40dip.json --asc i8085_40dip.asc
```

</details>

## Resource Usage

| Target | LCs | EBR | SPRAM | Fmax |
|--------|-----|-----|-------|------|
| i8085_40dip (HX8K) | ~3,100 (40%) | - | - | ~38 MHz |
| i8085_soc (UP5K) | ~3,200 (65%) | 4 | 4 | ~25 MHz |

## 40-DIP Bus Interface

Active during T1 (ALE high):

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

## iCE40 SoC

The `i8085_soc.v` provides a self-contained system for iCE40 UP5K:

- **RAM**: 128KB via all 4 × SB_SPRAM256KA, banked as 4 × 32KB
- **ROM**: 8MB via SPI flash with 2KB cache, banked as 256 × 32KB
- **I/O**: Simple 8-bit parallel port + bank registers
- **Interrupts**: Directly tied off (no external IRQ)

### Memory Map

```
CPU Address Space (64KB)
├── 0x0000-0x7FFF: RAM (32KB window)
│   └── Port 0xF1 selects bank 0-3 → 128KB total (4 × SB_SPRAM256KA)
└── 0x8000-0xFFFF: ROM (32KB window)
    └── Port 0xF0 selects bank 0-255 → 8MB SPI flash
```

### Bank Registers

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

### SPI Flash ROM

The SoC includes an integrated SPI flash controller with cache:

- **SPI Interface**: Standard JEDEC read command (0x03), Mode 0
- **Cache**: 2KB direct-mapped, 32 lines × 64 bytes
- **Banking**: 256 banks × 32KB = 8MB addressable ROM
- **Cache Logic**: Implemented in DSLX (`cache_logic.x`)

The cache tag includes the bank number, so switching banks doesn't require cache invalidation. Lines from multiple banks can be cached simultaneously.

**Performance:**
| Scenario | Cycles |
|----------|--------|
| Cache hit | 2 |
| Cache miss (critical word) | ~80 |
| Cache miss (full line fill) | ~1100 |

**SPI Pins:**
| Signal | Description |
|--------|-------------|
| `spi_sck` | SPI clock |
| `spi_cs_n` | Chip select (active low) |
| `spi_mosi` | Master out, slave in |
| `spi_miso` | Master in, slave out |

To add interrupt support, connect the wrapper's `int_ack`, `int_vector`, and interrupt input signals.

## XLS Tools on macOS

The Google XLS toolchain only provides pre-built binaries for x64 Linux. Building from source on macOS is [not officially supported](https://github.com/google/xls) and fails due to `toolchains_llvm` compatibility issues with Apple Silicon.

**Workaround: Docker via [OrbStack](https://orbstack.dev/)**

OrbStack provides fast, lightweight Docker on macOS with excellent Apple Silicon support via Rosetta emulation.

### Setup

```bash
# Install OrbStack (or Docker Desktop)
brew install orbstack

# Build the XLS tools image
cd tools
docker build -t xls -f Dockerfile.xls .
```

### Usage

The `tools/xls` wrapper runs XLS tools via Docker:

```bash
# From the cpu8085 directory:
./tools/xls interpreter_main i8085_core.x          # Run DSLX tests
./tools/xls ir_converter_main i8085_core.x --top=execute > i8085_core.ir
./tools/xls opt_main i8085_core.ir > i8085_core.opt.ir
./tools/xls codegen_main i8085_core.opt.ir --generator=combinational --output_verilog_path=i8085_core.v
```

The wrapper mounts the current directory into the container, so input/output files work seamlessly.

## License

MIT
