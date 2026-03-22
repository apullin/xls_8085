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

The original core, generated from [Google XLS](https://google.github.io/xls/) DSLX and then hand-optimized for parity-based flag computation to save ~450 LUTs. Uses a 16-state FSM architecture: a large combinational execute unit computes all next-state signals in one cycle, with a sequential wrapper handling fetch, decode, and memory sequencing.

- All 244 documented 8085 opcodes
- 10 undocumented instructions (DSUB, ARHL, RDEL, LDHI, LDSI, RSTV, SHLX, LHLX, JNX5, JX5)
- V (overflow) and X5 (undocumented) flags with correct PSW packing
- Full interrupt system (TRAP, RST7.5, RST6.5, RST5.5, INTR)
- RIM/SIM instructions with interrupt masks
- Serial I/O (SID/SOD)
- ROM/RAM bank registers via I/O ports
- **60 tests passing**

| File | Description |
|------|-------------|
| `i8085/i8085_core_parity_opt.v` | Combinational execute unit (~700 lines, hand-optimized from XLS) |
| `i8085/i8085_cpu.v` | 16-state FSM: fetch, decode, execute, memory sequencing (~630 lines) |
| `i8085/i8085_decode.v` | Instruction length and memory access classifier |

### j8085 -- Pipelined Core (`j8085/`)

A 3-stage pipelined reimplementation for improved throughput. ~1.2x faster than the FSM core on typical workloads, at the cost of ~23% more LUTs.

```
 IF Stage          ID Stage              EX Stage
 ┌───────────┐     ┌──────────────┐     ┌─────────────────┐
 │ PC manage │     │ Opcode decode│     │ ALU operation    │
 │ 4-byte    │────>│ Register read│────>│ Register write   │
 │ prefetch  │     │ Forwarding   │     │ Memory/IO access │
 │ buffer    │     │ Branch eval  │     │ Flag update      │
 └───────────┘     └──────────────┘     └─────────────────┘
```

- Same instruction set as i8085 (including all undocumented instructions)
- 4-byte prefetch buffer with variable-length instruction assembly
- Data forwarding (EX &rarr; ID) to reduce stalls
- Branch condition evaluation in ID stage (single-cycle branch resolution)
- Multi-cycle memory ops for SHLX (2-phase write), LHLX (3-phase read)
- **64 tests passing**

| File | Description |
|------|-------------|
| `j8085/j8085_cpu.v` | 3-stage pipelined CPU (~1200 lines) |
| `j8085/j8085_alu.v` | 8-bit ALU with overflow detection (~200 lines) |
| `j8085/j8085_decode.v` | Combinational decoder: 10 undoc + all standard ops (~500 lines) |

### Undocumented 8085 Instructions

Both cores implement the [10 undocumented 8085 instructions](http://www.righto.com/2013/02/looking-at-silicon-to-understanding.html), verified against the original silicon analysis:

| Opcode | Mnemonic | Operation |
|--------|----------|-----------|
| `08` | DSUB | HL = HL - BC (16-bit subtract, all flags) |
| `10` | ARHL | Arithmetic shift right HL (sign-extended) |
| `18` | RDEL | Rotate DE left through carry |
| `28` | LDHI _d8_ | DE = HL + immediate byte |
| `38` | LDSI _d8_ | DE = SP + immediate byte |
| `CB` | RSTV | If V flag set: RST 8 (CALL 0040h) |
| `D9` | SHLX | Store HL to address in DE |
| `DD` | JNX5 _a16_ | Jump if X5 flag = 0 |
| `ED` | LHLX | Load HL from address in DE |
| `FD` | JX5 _a16_ | Jump if X5 flag = 1 |

**PSW byte format:** `{S, Z, X5, AC, 0, P, V, CY}` -- V is bit 1 (overflow), X5 is bit 5 (set by INX overflow / DCX underflow).

### Shared Infrastructure (`shared/`)

Memory subsystem used by the MCU configurations. The SPI flash cache provides transparent read access to external SPI NOR flash, with bank switching for up to 8 MB of ROM.

| File | Description |
|------|-------------|
| `shared/memory_controller.v` | Unified memory routing (SPRAM, SPI flash, peripherals) |
| `shared/spi_flash_cache.v` | SPI flash controller with 2KB direct-mapped cache |
| `shared/spi_engine.v` | Low-level SPI protocol handler (JEDEC 0x03 read, Mode 0) |
| `shared/cache_logic.v` | Cache hit/miss logic (generated from XLS) |

**SPI flash cache performance:**

| Scenario | Cycles |
|----------|--------|
| Cache hit | 2 |
| Cache miss (critical word first) | ~80 |
| Cache miss (full 64-byte line fill) | ~1100 |

**Bank registers** (directly supported by the CPU via I/O ports):

| Port | Bits | Function |
|------|------|----------|
| `0xF0` | 8 | ROM bank select (256 banks x 32KB = 8MB flash) |
| `0xF1` | 2 | RAM bank select (4 banks x 32KB = 128KB SPRAM) |

## MCU System Integration (`mcu/`)

Two MCU configurations wrap the i8085 core with memory, peripherals, and I/O for the iCE40 UP5K SG48. These may move to a separate repo in the future.

```
┌─────────────────────────────────────────────────────────────┐
│  i8085sg / i8085sv  MCU                                     │
│                                                             │
│  ┌──────────┐  ┌─────────────┐  ┌────────────────────────┐ │
│  │ i8085_cpu│  │  memory_    │  │  Peripherals           │ │
│  │  (FSM)   │──│  controller │──│  GPIO, UART/SPI, I2C   │ │
│  │          │  │             │  │  Timers/PWM, imath     │ │
│  └──────────┘  │  4x SPRAM   │  │  vmath (SV only)       │ │
│                │  SPI flash  │  └────────────────────────┘ │
│                │  cache      │                              │
│                └─────────────┘                              │
└─────────────────────────────────────────────────────────────┘
```

| Config | Description | Peripherals |
|--------|-------------|-------------|
| **i8085sg** | System General | 2x UART/SPI, 12 GPIO, 4 PWM, I2C, imath (2 DSP) |
| **i8085sv** | System Vector | 1x UART/SPI, 8 GPIO, timer, vmath DMA (4 DSP, for ML inference) |

**Memory map** (both configs):

```
0x0000-0x7EFF   Internal SPRAM (32KB per bank, 4 banks via port 0xF1)
0x7F00-0x7FFF   Peripheral registers (memory-mapped)
0x8000-0xFFFF   SPI flash cache (32KB per bank, 256 banks via port 0xF0)
```

**Resource usage** (iCE40 UP5K, 5280 LCs total):

| Config | LCs | DSP | SPRAM | EBR | Fmax |
|--------|-----|-----|-------|-----|------|
| i8085sg | ~5300 (100%) | 2 | 4 | 4 | ~26 MHz |
| i8085sv | ~5500 (104%) | 4 | 4 | 4 | ~22 MHz |

_Note: Both configs currently exceed the UP5K LC budget after the undocumented instruction additions. SG is 39 LCs over; SV needs further optimization or a move to Lattice Radiant for better packing._

### Building

Requires [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) (Yosys + nextpnr).

```bash
cd mcu
make -f Makefile.synth sg             # Synthesize System General
make -f Makefile.synth sv             # Synthesize System Vector
make -f Makefile.synth summary        # Show timing comparison
make -f Makefile.synth sg-seedsearch  # Search for better PnR seed
```

See `doc/README_MCU.md` for the full peripheral register map.

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
