# i8085_mcu Technical Reference

## Overview

The i8085_mcu is a self-contained microcontroller built around an Intel 8085 CPU core. Unlike the DIP40 configurations which expose the address/data bus, the MCU configuration integrates memory and peripherals internally, exposing only dedicated I/O pins.

**Target:** iCE40 UP5K (tight fit) or ECP5 (comfortable)

## Memory Map

| Address Range | Size | Description |
|---------------|------|-------------|
| 0x0000-0x7EFF | 32KB - 256B | Internal SPRAM (banked via port 0xF1) |
| 0x7F00-0x7FFF | 256B | Peripheral registers |
| 0x8000-0xFFFF | 32KB | SPI flash cache (banked via port 0xF0) |

### RAM Banking
- 4 banks x 32KB = 128KB total
- Bank select via I/O port 0xF1 (2-bit)
- Bank 0 is default after reset

### ROM Banking
- 256 banks x 32KB = 8MB addressable
- Bank select via I/O port 0xF0 (8-bit)
- Cached via 4KB SPI flash cache

## Peripheral Map

| Address | Peripheral | Description |
|---------|------------|-------------|
| 0x7F00-0x7F0F | Timer0 | 16-bit timer, 4 compare channels |
| 0x7F10-0x7F1F | GPIO0 | 8-pin GPIO with IRQ |
| 0x7F20-0x7F2F | UART0 | Debug/console UART |
| 0x7F30-0x7F3F | UART1 | System UART |
| 0x7F40-0x7F4F | SPI1 | General-purpose SPI master |
| 0x7F50-0x7F5F | I2C0 | Hard silicon I2C (master+slave) |
| 0x7F60-0x7F6F | imath | Integer math coprocessor (2 DSP) |
| 0x7F70-0x7F7F | vmath | Vector math unit (6 DSP) - RESERVED |
| 0x7F80-0x7FFF | - | Reserved |

## Vectored Interrupts

Each peripheral has a dedicated interrupt vector (no scanning required):

| Vector | RST | Source | Notes |
|--------|-----|--------|-------|
| 0x0024 | - | TRAP | Non-maskable |
| 0x003C | 7.5 | RST7.5 pin | Edge-triggered |
| 0x0034 | 6.5 | RST6.5 pin | Level-triggered |
| 0x002C | 5.5 | RST5.5 pin | Level-triggered |
| 0x0008 | 1 | Timer0 | Check timer status for channel |
| 0x0010 | 2 | GPIO0 | Check GPIO status for pin |
| 0x0018 | 3 | UART0 | Check UART status for TX/RX |
| 0x0020 | 4 | UART1 | Check UART status for TX/RX |
| 0x0028 | 5 | SPI1 | Check SPI status |
| 0x0030 | 6 | I2C0 | Check I2C status |
| 0x0038 | 7 | - | Software syscall (RST 7 instruction) |

---

# imath - Integer Math Coprocessor

## Overview

The 8085 has no hardware multiply or divide instructions. The imath coprocessor provides fast integer multiplication (signed and unsigned) using 2x iCE40 SB_MAC16 DSP blocks.

**Base Address:** 0x7F60
**Size:** 16 bytes (0x7F60-0x7F6F)
**DSP Usage:** 2x SB_MAC16
**Interrupt:** None (polling only)

## Hardware Architecture

The imath unit contains two 16×16 hardware multipliers (SB_MAC16), one configured for signed operations and one for unsigned:

- **mac_s (signed):** `A_SIGNED=1, B_SIGNED=1` - handles signed 8×8 and 16×16
- **mac_u (unsigned):** `A_SIGNED=0, B_SIGNED=0` - handles unsigned 8×8 and 16×16, plus all 32×32

**Operation timing:**

- **8×8 mode:** 1 cycle (uses mac_s or mac_u based on SIGNED bit)
- **16×16 mode:** 1 cycle (uses mac_s or mac_u based on SIGNED bit)
- **32×32 mode:** 4 cycles using unsigned DSP on absolute values:
  - Phase 0: Compute lo×lo
  - Phase 1: Compute hi×hi
  - Phase 2: Compute lo×hi
  - Phase 3: Compute hi×lo, combine all partial products
  - For signed: takes absolute values, then negates result if signs differ

## Register Map

**Absolute addresses shown. All registers are 8-bit.**

| Address | Name | R/W | Reset | Description |
|---------|------|-----|-------|-------------|
| 0x7F60 | A_0 | R/W | 0x00 | Operand A, bits [7:0] (LSB) |
| 0x7F61 | A_1 | R/W | 0x00 | Operand A, bits [15:8] |
| 0x7F62 | A_2 | R/W | 0x00 | Operand A, bits [23:16] |
| 0x7F63 | A_3 | R/W | 0x00 | Operand A, bits [31:24] (MSB) |
| 0x7F64 | B_0 | R/W | 0x00 | Operand B, bits [7:0] (LSB) |
| 0x7F65 | B_1 | R/W | 0x00 | Operand B, bits [15:8] |
| 0x7F66 | B_2 | R/W | 0x00 | Operand B, bits [23:16] |
| 0x7F67 | B_3 | R/W | 0x00 | Operand B, bits [31:24] (MSB) |
| 0x7F68 | R_0 | R | 0x00 | Result, bits [7:0] (LSB) |
| 0x7F69 | R_1 | R | 0x00 | Result, bits [15:8] |
| 0x7F6A | R_2 | R | 0x00 | Result, bits [23:16] |
| 0x7F6B | R_3 | R | 0x00 | Result, bits [31:24] |
| 0x7F6C | R_4 | R | 0x00 | Result, bits [39:32] |
| 0x7F6D | R_5 | R | 0x00 | Result, bits [47:40] |
| 0x7F6E | R_6 | R | 0x00 | Result, bits [55:48] |
| 0x7F6F | CTRL | R/W | 0x00 | Control/Status register |

### CTRL Register (0x7F6F)

| Bit | Name | R/W | Description |
|-----|------|-----|-------------|
| 0 | MODE[0] | R/W | Mode select bit 0 |
| 1 | MODE[1] | R/W | Mode select bit 1 |
| 2 | SIGNED | R/W | Signed mode (0=unsigned, 1=signed) |
| 3-6 | - | - | Reserved, read as 0 |
| 7 | BUSY | R | Operation in progress (1=busy, 0=ready) |

**MODE field values:**

| MODE | Operation | Operand Size | Result Size | Cycles |
|------|-----------|--------------|-------------|--------|
| 0b00 | 8×8 | A_0, B_0 | R_0, R_1 | 1 |
| 0b01 | 16×16 | A_0:A_1, B_0:B_1 | R_0:R_3 | 1 |
| 0b10 | 32×32 | A_0:A_3, B_0:B_3 | R_0:R_7 | 4 |
| 0b11 | Reserved | - | - | - |

## Programming Guide

### 8×8 Unsigned Multiply (Mode 0, SIGNED=0)

Multiplies two 8-bit unsigned values, producing a 16-bit result.

```asm
; Compute: result = 25 * 10 = 250
    MVI     A, 25
    STA     7F60h       ; A_0 = 25
    MVI     A, 10
    STA     7F64h       ; B_0 = 10
    MVI     A, 00h      ; MODE=0 (8x8)
    STA     7F6Fh       ; Start operation
    ; Result available immediately
    LDA     7F68h       ; R_0 = 250 (0xFA)
    LDA     7F69h       ; R_1 = 0
```

### 16×16 Unsigned Multiply (Mode 1, SIGNED=0)

Multiplies two 16-bit unsigned values, producing a 32-bit result.

```asm
; Compute: result = 1000 * 2000 = 2,000,000
; 1000 = 0x03E8, 2000 = 0x07D0
    MVI     A, 0E8h
    STA     7F60h       ; A_0
    MVI     A, 03h
    STA     7F61h       ; A_1 (A = 0x03E8 = 1000)
    MVI     A, 0D0h
    STA     7F64h       ; B_0
    MVI     A, 07h
    STA     7F65h       ; B_1 (B = 0x07D0 = 2000)
    MVI     A, 01h      ; MODE=1 (16x16), SIGNED=0
    STA     7F6Fh       ; Start operation
    ; Result available immediately
    LDA     7F68h       ; R_0 = 0x80
    LDA     7F69h       ; R_1 = 0x84
    LDA     7F6Ah       ; R_2 = 0x1E
    LDA     7F6Bh       ; R_3 = 0x00
    ; Result = 0x001E8480 = 2,000,000
```

### 16×16 Signed Multiply (Mode 1, SIGNED=1)

Multiplies two 16-bit signed values, producing a 32-bit signed result.

```asm
; Compute: result = -1000 * 2000 = -2,000,000
; -1000 = 0xFC18, 2000 = 0x07D0
    MVI     A, 18h
    STA     7F60h       ; A_0
    MVI     A, 0FCh
    STA     7F61h       ; A_1 (A = 0xFC18 = -1000)
    MVI     A, 0D0h
    STA     7F64h       ; B_0
    MVI     A, 07h
    STA     7F65h       ; B_1 (B = 0x07D0 = 2000)
    MVI     A, 05h      ; MODE=1 (16x16), SIGNED=1 (bit 2 set)
    STA     7F6Fh       ; Start operation
    ; Result available immediately
    LDA     7F68h       ; R_0 = 0x80
    LDA     7F69h       ; R_1 = 0x7B
    LDA     7F6Ah       ; R_2 = 0xE1
    LDA     7F6Bh       ; R_3 = 0xFF
    ; Result = 0xFFE17B80 = -2,000,000
```

### 32×32 Multiply (Mode 2)

Multiplies two 32-bit unsigned values, producing a 64-bit result. **Requires polling.**

```asm
; Compute: result = 0x12345678 * 0x9ABCDEF0
    ; Load operand A (little-endian)
    MVI     A, 78h
    STA     7F60h       ; A_0
    MVI     A, 56h
    STA     7F61h       ; A_1
    MVI     A, 34h
    STA     7F62h       ; A_2
    MVI     A, 12h
    STA     7F63h       ; A_3

    ; Load operand B (little-endian)
    MVI     A, 0F0h
    STA     7F64h       ; B_0
    MVI     A, 0DEh
    STA     7F65h       ; B_1
    MVI     A, 0BCh
    STA     7F66h       ; B_2
    MVI     A, 9Ah
    STA     7F67h       ; B_3

    ; Start 32x32 multiply
    MVI     A, 02h      ; MODE=2 (32x32)
    STA     7F6Fh

    ; Poll BUSY flag (required for mode 2)
poll:
    LDA     7F6Fh
    ANI     80h         ; Test bit 7 (BUSY)
    JNZ     poll

    ; Read 64-bit result from R_0 through R_7
    LDA     7F68h       ; R_0 (bits 7:0)
    ; ... continue reading R_1 through R_7 ...
```

## Compiler Intrinsic Support

The imath unit is designed to accelerate these common compiler runtime functions:

| Intrinsic | Description | imath Mode | SIGNED |
|-----------|-------------|------------|--------|
| `__mulqi3` | signed 8-bit multiply | Mode 0 | 1 |
| `__umulqi3` | unsigned 8-bit multiply | Mode 0 | 0 |
| `__mulhi3` | signed 16-bit multiply | Mode 1 | 1 |
| `__umulhi3` | unsigned 16-bit multiply | Mode 1 | 0 |
| `__mulsi3` | signed 32-bit multiply (low 32 bits) | Mode 2 | 1 |
| `__umulsi3` | unsigned 32-bit multiply (low 32 bits) | Mode 2 | 0 |
| `__mulsi3_highpart` | signed 32-bit multiply (high 32 bits) | Mode 2 | 1 |
| `__umulsi3_highpart` | unsigned 32-bit multiply (high 32 bits) | Mode 2 | 0 |

### Result Conventions

For C multiplication `a * b`:
- **8-bit:** Full 16-bit result available (no overflow possible in result)
- **16-bit:** Full 32-bit result available
- **32-bit:** Standard C returns low 32 bits; high 32 bits available for `mulh` operations

| Use Case | Read These Registers |
|----------|---------------------|
| 8×8 full result | R_0, R_1 |
| 16×16 full result | R_0, R_1, R_2, R_3 |
| 32×32 low result (standard C) | R_0, R_1, R_2, R_3 |
| 32×32 high result | R_4, R_5, R_6, R_7 |
| 32×32 full 64-bit | R_0 through R_7 |

## Limitations

1. **No interrupt:** Must poll BUSY flag for 32×32 operations. Single-cycle
   operations (8×8, 16×16) don't need polling.

2. **Little-endian:** All multi-byte values are little-endian (LSB at lowest address).

3. **32×32 takes 4 cycles:** Due to using one partial product per cycle with a single
   unsigned DSP for the schoolbook multiplication algorithm.

> **Note:** The iCE40 SB_MAC16 DSP block only performs multiply and multiply-accumulate.
> It has no hardware support for division or shifting. The imath unit accelerates
> multiplication only. Division and shift operations remain software-only on this platform.

---

## Example: 32x32 Multiply in 8085 Assembly

This implements `uint32_t __mulsi3(uint32_t a, uint32_t b)`:

```asm
; __mulsi3 - 32x32 unsigned multiply
; Input:  DE:HL = pointer to 32-bit operand A (little-endian)
;         BC = pointer to 32-bit operand B (little-endian)
; Output: Result written to memory at address in stack arg
;         Returns low 32 bits (standard C convention)
;
; imath base address
IMATH_A0    EQU 7F60h
IMATH_B0    EQU 7F64h
IMATH_R0    EQU 7F68h
IMATH_CTRL  EQU 7F6Fh

; Calling convention: args pushed right-to-left
; SP+2: pointer to result (4 bytes)
; SP+4: pointer to B (4 bytes)
; SP+6: pointer to A (4 bytes)

__mulsi3:
    PUSH    PSW
    PUSH    H
    PUSH    D
    PUSH    B

    ; Get pointer to A from stack
    LXI     H, 12           ; offset to first arg (after pushes + ret addr)
    DAD     SP
    MOV     E, M
    INX     H
    MOV     D, M            ; DE = pointer to A

    ; Load A into imath (4 bytes)
    XCHG                    ; HL = pointer to A
    MOV     A, M
    STA     IMATH_A0
    INX     H
    MOV     A, M
    STA     IMATH_A0+1
    INX     H
    MOV     A, M
    STA     IMATH_A0+2
    INX     H
    MOV     A, M
    STA     IMATH_A0+3

    ; Get pointer to B from stack
    LXI     H, 10
    DAD     SP
    MOV     E, M
    INX     H
    MOV     D, M            ; DE = pointer to B

    ; Load B into imath (4 bytes)
    XCHG                    ; HL = pointer to B
    MOV     A, M
    STA     IMATH_B0
    INX     H
    MOV     A, M
    STA     IMATH_B0+1
    INX     H
    MOV     A, M
    STA     IMATH_B0+2
    INX     H
    MOV     A, M
    STA     IMATH_B0+3

    ; Start 32x32 multiply (mode 2)
    MVI     A, 02h
    STA     IMATH_CTRL

    ; Poll BUSY flag
wait_busy:
    LDA     IMATH_CTRL
    ANI     80h             ; test BUSY bit
    JNZ     wait_busy

    ; Get pointer to result from stack
    LXI     H, 8
    DAD     SP
    MOV     E, M
    INX     H
    MOV     D, M            ; DE = pointer to result

    ; Copy low 32 bits of result (C convention: return low bits)
    XCHG                    ; HL = pointer to result
    LDA     IMATH_R0
    MOV     M, A
    INX     H
    LDA     IMATH_R0+1
    MOV     M, A
    INX     H
    LDA     IMATH_R0+2
    MOV     M, A
    INX     H
    LDA     IMATH_R0+3
    MOV     M, A

    POP     B
    POP     D
    POP     H
    POP     PSW
    RET
```

### Full 64-bit Result

If you need the full 64-bit result (e.g., for fixed-point or `muldi3`):

```asm
    ; Copy all 8 bytes of result
    LDA     IMATH_R0
    MOV     M, A
    ; ... (R0 through R7)
    LDA     IMATH_R0+7
    MOV     M, A
```

---

# vmath - Vector Math Accelerator

## Overview

The vmath unit is a streaming dot product accelerator designed to offload
neural network inference and matrix multiplication from the 8085 core.
It uses 4× SB_MAC16 DSP blocks with internal 32-bit accumulators.

**Base Address:** 0x7F70
**Size:** 16 bytes (0x7F70-0x7F7F)
**DSP Usage:** 4× SB_MAC16 (16×16 mode with accumulator)
**Interrupt:** None (polling via BUSY flag)

## Design Decisions

### Overall Architecture

vmath implements a **4-wide int8 streaming MAC** with 32-bit accumulation:

```
For each 4-element chunk:
    DSP0: acc0 += a[0] × b[0]
    DSP1: acc1 += a[1] × b[1]
    DSP2: acc2 += a[2] × b[2]
    DSP3: acc3 += a[3] × b[3]

At end: result = acc0 + acc1 + acc2 + acc3 + bias
```

Each DSP uses its internal accumulator, eliminating per-cycle adder trees.
The 4-way sum and bias add happen only once at the end of the dot product.

### Why Streaming?

The 8085's 8-bit bus is the bottleneck. CPU-driven register loads would take
~10 cycles per byte, making parallel MACs pointless. Instead:

1. CPU sets up pointers (A_PTR, B_PTR) and length (LEN)
2. CPU triggers START
3. vmath **takes over the SPRAM bus**, CPU stalls
4. vmath streams through memory autonomously
5. vmath writes result, releases bus
6. CPU resumes

This achieves **1.5 cycles per MAC** (6 cycles per 4 MACs) vs ~100+ cycles
for software multiply-accumulate.

### Memory Access Strategy

vmath performs 2× 16-bit sequential reads per 32-bit load (4 bytes):
- SPRAM is 16-bit wide, single-port
- No memory reorganization required
- Existing 4× 32KB bank structure preserved
- vmath addresses include bank bits for cross-bank operation

This is an "end run" around the 8-bit core—vmath has a dedicated 16-bit
path to SPRAM that only activates when the core is stalled. The 8085
address/data bus is not modified.

### DSP Accumulator Mode

Each SB_MAC16 is configured in 16×16 multiply-accumulate mode:
- 8-bit inputs are sign-extended to 16-bit
- Product is 32-bit
- Internal accumulator adds product each cycle
- Accumulator cleared on START via ORST signals

This moves the accumulation into hardware, saving ~100 LUTs vs external
adder tree.

## Capabilities

| Parameter | Value |
|-----------|-------|
| MAC width | 4× int8 parallel |
| Accumulator | 32-bit signed per DSP |
| Max products before overflow | ~131K per DSP, ~500K total |
| Max vector length (LEN register) | 65,535 elements |
| Cycles per 4 MACs | 6 (1.5 cycles/MAC) |
| Memory bandwidth | 16 bits/cycle (2 bytes) |

**Practical limits:**
- 2048-element dot product: safe, uses <1% of accumulator range
- Memory: vectors must fit in 128KB SPRAM (or stream from flash via cache)

## Register Map

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x0 | A_PTR[7:0] | R/W | Source A pointer (weights), byte 0 |
| 0x1 | A_PTR[15:8] | R/W | Source A pointer, byte 1 |
| 0x2 | A_PTR[23:16] | R/W | Source A pointer, byte 2 (bank in [16:15]) |
| 0x3 | B_PTR[7:0] | R/W | Source B pointer (activations), byte 0 |
| 0x4 | B_PTR[15:8] | R/W | Source B pointer, byte 1 |
| 0x5 | B_PTR[23:16] | R/W | Source B pointer, byte 2 (bank in [16:15]) |
| 0x6 | LEN[7:0] | R/W | Element count, low byte (must be multiple of 4) |
| 0x7 | LEN[15:8] | R/W | Element count, high byte |
| 0x8 | ACC[7:0] | R | Result accumulator, byte 0 |
| 0x9 | ACC[15:8] | R | Result accumulator, byte 1 |
| 0xA | ACC[23:16] | R | Result accumulator, byte 2 |
| 0xB | ACC[31:24] | R | Result accumulator, byte 3 |
| 0xC | BIAS[7:0] | R/W | Bias value, byte 0 |
| 0xD | BIAS[15:8] | R/W | Bias value, byte 1 |
| 0xE | BIAS[23:16] | R/W | Bias value, byte 2 |
| 0xF | CTRL | R/W | Control/status register |

### CTRL Register (0x7F7F)

| Bit | Name | R/W | Description |
|-----|------|-----|-------------|
| 0 | START | W | Write 1 to start operation (clears accumulators) |
| 1 | - | - | Reserved |
| 2-5 | - | - | Reserved |
| 6 | DONE | R | Operation complete (cleared on START) |
| 7 | BUSY | R | Operation in progress |

### Pointer Format

```
A_PTR / B_PTR: 24-bit pointer
  [14:0]  - Byte address within 32KB bank
  [16:15] - Bank select (0-3)
  [23:17] - Reserved (should be 0)
```

## Theory of Operation

### Setup Phase (CPU)

```
1. Ensure vectors are in SPRAM (weights at A_PTR, activations at B_PTR)
2. Vectors must be 4-byte aligned, length multiple of 4
3. Zero-pad vectors if needed
```

### Execution

```
CPU:
    Write A_PTR (3 bytes)
    Write B_PTR (3 bytes)
    Write LEN (2 bytes)
    Write BIAS (3 bytes, or 0 if no bias)
    Write CTRL = 0x01 (START)

    Poll CTRL until BUSY=0

    Read ACC (4 bytes) - result
```

### Memory Access Pattern

```
For N elements (N/4 iterations):
  Cycle 1: Read A_PTR[15:0]
  Cycle 2: Read A_PTR[31:16], setup B read
  Cycle 3: Read B_PTR[15:0]
  Cycle 4: Read B_PTR[31:16]
  Cycle 5: DSP accumulate (all 4 MACs)
  Cycle 6: Increment pointers, check LEN

After loop:
  Cycle 7: Sum 4 DSP accumulators
  Cycle 8: Add bias
  Cycle 9: Write result[15:0]
  Cycle 10: Write result[31:16]
```

## Programming Example

### Single Dot Product (Assembly)

```asm
; Compute: result = dot(weights[0:255], activations[0:255]) + bias
; Weights at 0x1000 (bank 0), activations at 0x2000 (bank 0)
; Result written to 0x2000 (overwrites activations)

VMATH_BASE  EQU 7F70h
VMATH_CTRL  EQU 7F7Fh

    ; Set A_PTR = 0x001000 (weights)
    MVI     A, 00h
    STA     VMATH_BASE+0    ; A_PTR[7:0]
    MVI     A, 10h
    STA     VMATH_BASE+1    ; A_PTR[15:8]
    MVI     A, 00h
    STA     VMATH_BASE+2    ; A_PTR[23:16] (bank 0)

    ; Set B_PTR = 0x002000 (activations)
    MVI     A, 00h
    STA     VMATH_BASE+3    ; B_PTR[7:0]
    MVI     A, 20h
    STA     VMATH_BASE+4    ; B_PTR[15:8]
    MVI     A, 00h
    STA     VMATH_BASE+5    ; B_PTR[23:16] (bank 0)

    ; Set LEN = 256
    MVI     A, 00h
    STA     VMATH_BASE+6    ; LEN[7:0]
    MVI     A, 01h
    STA     VMATH_BASE+7    ; LEN[15:8]

    ; Set BIAS = 0 (or desired value)
    XRA     A
    STA     VMATH_BASE+0Ch
    STA     VMATH_BASE+0Dh
    STA     VMATH_BASE+0Eh

    ; START
    MVI     A, 01h
    STA     VMATH_CTRL

    ; Poll BUSY
wait_vmath:
    LDA     VMATH_CTRL
    ANI     80h             ; Test BUSY bit
    JNZ     wait_vmath

    ; Read result from ACC
    LDA     VMATH_BASE+8    ; ACC[7:0]
    ; ... store result as needed
```

### C Pseudocode

```c
void vmath_dot(uint8_t* weights, uint8_t* activations,
               uint16_t len, int32_t bias, int32_t* result) {
    // Set pointers (includes bank bits)
    VMATH_A_PTR = (uint32_t)weights;
    VMATH_B_PTR = (uint32_t)activations;
    VMATH_LEN = len;
    VMATH_BIAS = bias;

    // Start and wait
    VMATH_CTRL = 0x01;
    while (VMATH_CTRL & 0x80);

    // Read result
    *result = VMATH_ACC;
}
```

## Limitations

1. **LEN must be multiple of 4** - pad vectors with zeros if needed
2. **Pointers should be aligned** - unaligned access may give wrong results
3. **No interrupt** - must poll BUSY flag
4. **CPU stalled during operation** - plan accordingly for real-time constraints
5. **Single operation at a time** - no queuing

---

# Resource Usage

## iCE40 UP5K

| Resource | Used | Available | % |
|----------|------|-----------|---|
| LUT4 | 6688 | 5280 | 127% (over!) |
| DFF | ~2500 | 5280 | 47% |
| SPRAM | 4 | 4 | 100% |
| EBR | 4 | 30 | 13% |
| MAC16 | 6 | 8 | 75% |
| I2C | 1 | 2 | 50% |

### DSP Allocation

| Unit | DSPs | Mode | Purpose |
|------|------|------|---------|
| imath | 2 | 16×16 / 8×8 | Scalar signed/unsigned multiply |
| vmath | 4 | 16×16 accumulate | 4-wide int8 dot product |
| Free | 2 | - | Future expansion |

**Note:** Full MCU exceeds UP5K LUT capacity. Options:
- Target ECP5 for full configuration (recommended)
- Create "lite" variant without vmath (~6000 LUTs)
- Accept that nextpnr may still fit (estimates are conservative)

## ECP5 (Target: OrangeCrab 25F)

Comfortable fit with headroom for additional features. ECP5-25F has:
- 24K LUTs (vs 5.3K on UP5K)
- 56 EBR blocks
- 28 DSP blocks (MULT18X18D)
- DDR3 memory controller possible
