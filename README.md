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
- ROM banking for 256KB program space (8 banks × 32KB)

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

## Building

### Prerequisites

- [Google XLS](https://github.com/google/xls) toolchain

### Generate Verilog from DSLX

```bash
# Convert DSLX to IR
xls/dslx/interpreter_main i8085_core.x  # Run tests first
xls/tools/ir_converter_main i8085_core.x --top=execute > i8085_core.ir

# Optimize
xls/tools/opt_main i8085_core.ir > i8085_core.opt.ir

# Generate Verilog
xls/tools/codegen_main i8085_core.opt.ir \
  --generator=combinational \
  --output_verilog_path=i8085_core.v \
  --output_signature_path=i8085_core.sig.textproto
```

### Generate Cache Logic from DSLX

```bash
# Run cache logic tests
xls/dslx/interpreter_main cache_logic.x

# Convert to Verilog
xls/tools/ir_converter_main cache_logic.x --top=cache_lookup > cache_logic.ir
xls/tools/opt_main cache_logic.ir > cache_logic.opt.ir
xls/tools/codegen_main cache_logic.opt.ir \
  --generator=combinational \
  --output_verilog_path=cache_logic.v
```

### Synthesize for iCE40

**Option A: 40-DIP wrapper (external memory)**
```bash
yosys -p "read_verilog -sv i8085_core.v; read_verilog i8085_wrapper.v i8085_40dip.v; synth_ice40 -top i8085_40dip -json i8085_40dip.json"
nextpnr-ice40 --hx8k --package ct256 --json i8085_40dip.json --asc i8085_40dip.asc
```

**Option B: SoC with SPRAM (iCE40 UP5K)**
```bash
yosys -p "read_verilog -sv i8085_core.v cache_logic.v; read_verilog i8085_wrapper.v spi_engine.v spi_flash_cache.v i8085_soc.v; synth_ice40 -top i8085_soc -json i8085_soc.json"
nextpnr-ice40 --up5k --package sg48 --json i8085_soc.json --pcf ice40up5k.pcf --asc i8085_soc.asc
```

## Resource Usage

| Target | LCs | SPRAM | Fmax |
|--------|-----|-------|------|
| i8085_40dip (HX8K) | ~3,100 (40%) | - | ~38 MHz |
| i8085_soc RAM_KB=32 (UP5K) | ~2,500 | 1 block | ~25 MHz |
| i8085_soc RAM_KB=64 (UP5K) | ~2,500 | 2 blocks | ~25 MHz |

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

The `i8085_soc.v` provides a self-contained system:

- **Memory**: Configurable 32KB or 64KB via SB_SPRAM256KA (iCE40 UP5K)
- **I/O**: Simple 8-bit parallel port
- **Interrupts**: Directly tied off (no external IRQ)

### RAM Configuration

The `RAM_KB` parameter controls memory layout:

| RAM_KB | RAM | ROM | Address Map |
|--------|-----|-----|-------------|
| 32 (default) | 0x0000-0x7FFF | 0x8000-0xFFFF | RAM low, ROM high |
| 64 | 0x0000-0xFFFF | None | Full 64KB RAM |

### SPI Flash ROM (32KB mode)

When `RAM_KB=32`, the SoC includes an integrated SPI flash controller with cache:

- **SPI Interface**: Standard JEDEC read command (0x03), Mode 0
- **Cache**: 2KB direct-mapped, 32 lines × 64 bytes
- **Banking**: 8 banks × 32KB = 256KB addressable ROM
- **Cache Logic**: Implemented in DSLX (`cache_logic.x`)

**Performance:**
| Scenario | Cycles |
|----------|--------|
| Cache hit | 2 |
| Cache miss (critical word) | ~80 |
| Cache miss (full line fill) | ~1100 |

**Bank Register**: I/O port `0xF0`
```asm
; Switch to ROM bank 3
MVI A, 03h
OUT 0F0h
```

**SPI Pins:**
| Signal | Description |
|--------|-------------|
| `spi_sck` | SPI clock |
| `spi_cs_n` | Chip select (active low) |
| `spi_mosi` | Master out, slave in |
| `spi_miso` | Master in, slave out |

To add interrupt support, connect the wrapper's `int_ack`, `int_vector`, and interrupt input signals.

## License

MIT
