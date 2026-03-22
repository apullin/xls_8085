# Intel 8085 CPU Cores

Two complete [Intel 8085A](https://en.wikipedia.org/wiki/Intel_8085) CPU implementations in Verilog, targeting the [iCE40 UP5K](https://www.latticesemi.com/Products/FPGAandCPLD/iCE40UltraPlus) FPGA.

## Project Vision

This started as a project to evaluate [Google XLS](https://google.github.io/xls/), especially in combination with AI coding tools. The target was chosen because of the [TRS-80 Model 100](https://en.wikipedia.org/wiki/TRS-80_Model_100) and [small-C](https://github.com/apullin/small-c).

The goal was to build a working 8085 core that fits in a cheap/easy-to-use FPGA and could eventually be deployed on a DIP40 package adapter PCB, nominally making a drop-in replacement for the original chip. Or at least a quirky, anachronistic breadboard computer.

The iCE40 UP5K is the primary target because it is well supported by the [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build). In the small-package version, it has _just_ enough pins to implement a 40-pin CPU, and enough LUTs and SPRAM for a full "SoC."

(silly stretch goal - an 8085duino)

## Why the 8085?

The 8085 occupies an interesting place in computing history, as it's still early, as integrated CPUs were being rapidly iterated, but there's still a clear lineage from the true original commercial microprocessor:
4004 (1971) &rarr; 8008 (1972) &rarr; 8080 (1974, of Altair 8800 fame) &rarr; 8085 (1976) &rarr; 8086 (1978)

The 4004 was the true progenitor -- the first commercial microprocessor. Revs to the 8008, 8080, and then 8085 were all improvements towards usability. And it's the last waypoint before the [Intel 8086](https://en.wikipedia.org/wiki/Intel_8086), which established the Intel x86 kingdom.

Fun fact: The 8085 was also [cloned by the Soviets](https://en.wikipedia.org/wiki/KR580VM80A) (as the KR1821VM85), a testament to its importance during the Cold War tech race.

## CPU Cores

### i8085 -- FSM Core (`i8085/`)

The original core, generated from [Google XLS](https://google.github.io/xls/) DSLX and then hand-optimized. Uses a 16-state FSM architecture with a combinational execute unit.

- All 244 documented 8085 opcodes
- 10 undocumented instructions (DSUB, ARHL, RDEL, LDHI, LDSI, RSTV, SHLX, LHLX, JNX5, JX5)
- V (overflow) and X5 (undocumented) flags with correct PSW packing
- Full interrupt system (TRAP, RST7.5, RST6.5, RST5.5, INTR)
- RIM/SIM instructions with interrupt masks
- Serial I/O (SID/SOD)
- **60 tests passing**

| File | Description |
|------|-------------|
| `i8085/i8085_core_parity_opt.v` | Combinational execute unit (hand-optimized from XLS) |
| `i8085/i8085_cpu.v` | FSM wrapper with fetch, decode, registers |
| `i8085/i8085_decode.v` | Instruction length and memory access classifier |

### j8085 -- Pipelined Core (`j8085/`)

A 3-stage pipelined reimplementation for improved throughput. ~1.2x faster than the FSM core on typical workloads, at the cost of ~23% more LUTs.

```
IF (Fetch) --> ID (Decode/Read) --> EX (Execute/Writeback)
```

- Same instruction set as i8085 (including all undocumented instructions)
- 4-byte prefetch buffer with variable-length instruction assembly
- Data forwarding (EX &rarr; ID) to reduce stalls
- Branch resolution in ID stage
- Multi-cycle memory ops for SHLX/LHLX
- **64 tests passing**

| File | Description |
|------|-------------|
| `j8085/j8085_cpu.v` | 3-stage pipelined CPU |
| `j8085/j8085_alu.v` | 8-bit ALU |
| `j8085/j8085_decode.v` | Combinational instruction decoder |

### Shared Infrastructure (`shared/`)

| File | Description |
|------|-------------|
| `shared/memory_controller.v` | Unified memory routing (SPRAM, SPI flash, peripherals) |
| `shared/spi_flash_cache.v` | SPI flash controller with 2KB direct-mapped cache |
| `shared/spi_engine.v` | Low-level SPI protocol handler |
| `shared/cache_logic.v` | Cache hit/miss logic (generated from XLS) |

## MCU System Integration (`mcu/`)

Two MCU configurations wrap the i8085 core with memory, peripherals, and I/O for the iCE40 UP5K. These may move to a separate repo in the future.

| Config | Description | Peripherals |
|--------|-------------|-------------|
| **i8085sg** | System General | 2x UART/SPI, 12 GPIO, 4 PWM, I2C, imath |
| **i8085sv** | System Vector | 1x UART/SPI, 8 GPIO, vmath DMA (for ML inference) |

### Building

Requires [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) (Yosys + nextpnr).

```bash
cd mcu
make -f Makefile.synth sg          # Synthesize System General
make -f Makefile.synth sv          # Synthesize System Vector
make -f Makefile.synth summary     # Show timing comparison
make -f Makefile.synth sg-seedsearch  # Search for better PnR seed
```

See `doc/README_MCU.md` for the full peripheral register map and memory map.

## Running Tests

```bash
# j8085 pipelined core (64 tests)
cd j8085
iverilog -o j8085_test j8085_cpu.v j8085_decode.v j8085_alu.v j8085_mem_sim.v j8085_tb.v
vvp j8085_test

# i8085 FSM core (60 tests, uses j8085 memory sim)
iverilog -o i8085_test i8085/i8085_cpu.v i8085/i8085_core_parity_opt.v \
    i8085/i8085_decode.v j8085/j8085_mem_sim.v j8085/i8085_compare_tb.v
vvp i8085_test
```

## Repository Structure

```
i8085/          FSM-based CPU core (active)
j8085/          Pipelined CPU core + testbenches (active)
shared/         Memory subsystem (SPI cache, memory controller)
mcu/            MCU system integration (i8085sg, i8085sv, peripherals)
test/           System-level testbenches (blinky, timing)
legacy/         Original XLS sources, old wrapper, old FPGA targets
doc/            Reference documentation
```

## Legacy / XLS Origins

The `legacy/` directory preserves the original XLS DSLX sources, the auto-generated wrapper, and FPGA target configurations for iCE40 UP5K (DIP40, DIP40+), HX8K, and ECP5. These are no longer the active development path but document the project's history as an XLS evaluation.

## License

MIT
