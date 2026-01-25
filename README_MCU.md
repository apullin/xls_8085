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

The 8085 has no hardware multiply or divide instructions. The imath coprocessor provides fast integer multiplication using iCE40 SB_MAC16 DSP blocks.

**Base Address:** 0x7F60
**Size:** 16 bytes (0x7F60-0x7F6F)
**Interrupt:** None (single-cycle operations)

## Variant Selection

Two imath variants are available, trading features for FPGA resources:

| Variant | File | DSPs | LUTs | 8×8 | 16×16 | 32×32 |
|---------|------|------|------|-----|-------|-------|
| **imath** | `imath_wrapper.v` | 4 | ~252 | unsigned | unsigned | unsigned (1 cycle) |
| **imath_lite** | `imath_lite_wrapper.v` | 2 | ~124 | signed+unsigned | signed+unsigned | software only |

### Design Evolution

The original imath used 2 DSPs with a 4-cycle state machine for 32×32 multiply, consuming **771 LUTs**. This was refactored to eliminate the FSM:

- **imath (4-DSP):** All 4 partial products computed in parallel. Single-cycle 32×32. Unsigned only (signed requires software abs/negate). **Saves 519 LUTs.**
- **imath_lite (2-DSP):** Drops 32×32 hardware entirely. Software does 4× 16×16 multiplies. Supports signed via dedicated DSP. **Saves 647 LUTs.**

### When to Use Each

**Use imath (default)** when:
- You need fast 32×32 multiply
- Unsigned operations are sufficient (or software handles sign)
- You have 4 DSPs available

**Use imath_lite** when:
- LUT budget is critical (saves 128 LUTs vs imath)
- You need signed 8×8/16×16 in hardware
- 32×32 multiply is rare (software is acceptable)

## Hardware Architecture (imath - 4 DSP)

Four unsigned 16×16 multipliers compute 32×32 in parallel:

```
    A = [a_hi : a_lo]    B = [b_hi : b_lo]

    dsp_ll: a_lo × b_lo  →  p_ll (bits 31:0)
    dsp_lh: a_lo × b_hi  →  p_lh (bits 47:16)
    dsp_hl: a_hi × b_lo  →  p_hl (bits 47:16)
    dsp_hh: a_hi × b_hi  →  p_hh (bits 63:32)

    result = (p_hh << 32) + ((p_lh + p_hl) << 16) + p_ll
```

**All operations are single-cycle.** No BUSY polling required.

## Hardware Architecture (imath_lite - 2 DSP)

Two 16×16 multipliers, one signed and one unsigned:

- **mac_s:** `A_SIGNED=1, B_SIGNED=1` - signed 8×8 and 16×16
- **mac_u:** `A_SIGNED=0, B_SIGNED=0` - unsigned 8×8 and 16×16

For 32×32 multiply, software combines four 16×16 operations:
```c
uint64_t mul32(uint32_t a, uint32_t b) {
    uint32_t p0 = mul16u(a & 0xFFFF, b & 0xFFFF);
    uint32_t p1 = mul16u(a >> 16, b >> 16);
    uint32_t p2 = mul16u(a & 0xFFFF, b >> 16);
    uint32_t p3 = mul16u(a >> 16, b & 0xFFFF);
    return ((uint64_t)p1 << 32) + ((uint64_t)(p2 + p3) << 16) + p0;
}
```

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

**imath (4-DSP, unsigned only):**

| Bit | Name | R/W | Description |
|-----|------|-----|-------------|
| 0-1 | MODE | R/W | Mode select (see below) |
| 2-6 | - | - | Reserved, read as 0 |
| 7 | - | R | Always 0 (no BUSY - single cycle) |

**imath_lite (2-DSP, signed support):**

| Bit | Name | R/W | Description |
|-----|------|-----|-------------|
| 0 | MODE | R/W | 0=8×8, 1=16×16 |
| 1 | - | - | Reserved |
| 2 | SIGNED | R/W | 0=unsigned, 1=signed |
| 3-6 | - | - | Reserved, read as 0 |
| 7 | - | R | Always 0 (single cycle) |

**MODE field values (imath):**

| MODE | Operation | Operand Size | Result Size | Cycles |
|------|-----------|--------------|-------------|--------|
| 0b00 | 8×8 unsigned | A_0, B_0 | R_0, R_1 | 1 |
| 0b01 | 16×16 unsigned | A_0:A_1, B_0:B_1 | R_0:R_3 | 1 |
| 0b10 | 32×32 unsigned | A_0:A_3, B_0:B_3 | R_0:R_7 | 1 |
| 0b11 | Reserved | - | - | - |

## Programming Guide

### 8×8 Unsigned Multiply (imath or imath_lite)

Multiplies two 8-bit unsigned values, producing a 16-bit result.

```asm
; Compute: result = 25 * 10 = 250
    MVI     A, 25
    STA     7F60h       ; A_0 = 25
    MVI     A, 10
    STA     7F64h       ; B_0 = 10
    MVI     A, 00h      ; MODE=0 (8x8)
    STA     7F6Fh       ; Trigger operation
    ; Result available immediately (single cycle)
    LDA     7F68h       ; R_0 = 250 (0xFA)
    LDA     7F69h       ; R_1 = 0
```

### 16×16 Unsigned Multiply (imath or imath_lite)

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
    MVI     A, 01h      ; MODE=1 (16x16)
    STA     7F6Fh       ; Trigger operation
    ; Result available immediately
    LDA     7F68h       ; R_0 = 0x80
    LDA     7F69h       ; R_1 = 0x84
    LDA     7F6Ah       ; R_2 = 0x1E
    LDA     7F6Bh       ; R_3 = 0x00
    ; Result = 0x001E8480 = 2,000,000
```

### 16×16 Signed Multiply (imath_lite only)

Multiplies two 16-bit signed values, producing a 32-bit signed result.
**Note:** Only available with imath_lite. For imath (unsigned), use software sign handling.

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
    STA     7F6Fh       ; Trigger operation
    ; Result available immediately
    LDA     7F68h       ; R_0 = 0x80
    LDA     7F69h       ; R_1 = 0x7B
    LDA     7F6Ah       ; R_2 = 0xE1
    LDA     7F6Bh       ; R_3 = 0xFF
    ; Result = 0xFFE17B80 = -2,000,000
```

### 32×32 Unsigned Multiply (imath only)

Multiplies two 32-bit unsigned values, producing a 64-bit result. **Single cycle - no polling!**

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

    ; Trigger 32x32 multiply
    MVI     A, 02h      ; MODE=2 (32x32)
    STA     7F6Fh

    ; Result available immediately (single cycle!)
    LDA     7F68h       ; R_0 (bits 7:0)
    ; ... continue reading R_1 through R_7 ...
```

### 32×32 Multiply with imath_lite (software)

With imath_lite, 32×32 requires four 16×16 multiplies:

```asm
; Software 32x32 using imath_lite 16x16 operations
; A = [A_hi:A_lo], B = [B_hi:B_lo]
; Result = (A_hi×B_hi)<<32 + (A_lo×B_hi + A_hi×B_lo)<<16 + A_lo×B_lo

; Step 1: p0 = A_lo × B_lo
    ; Load A_lo to 0x7F60-61, B_lo to 0x7F64-65
    MVI     A, 01h      ; MODE=1 (16x16), unsigned
    STA     7F6Fh
    ; Read p0 from R_0:R_3

; Step 2: p1 = A_hi × B_hi
    ; Load A_hi to 0x7F60-61, B_hi to 0x7F64-65
    MVI     A, 01h
    STA     7F6Fh
    ; Read p1 from R_0:R_3

; Step 3: p2 = A_lo × B_hi
    ; Load A_lo to 0x7F60-61, B_hi to 0x7F64-65
    MVI     A, 01h
    STA     7F6Fh
    ; Read p2 from R_0:R_3

; Step 4: p3 = A_hi × B_lo
    ; Load A_hi to 0x7F60-61, B_lo to 0x7F64-65
    MVI     A, 01h
    STA     7F6Fh
    ; Read p3 from R_0:R_3

; Step 5: Combine in software
    ; result = (p1 << 32) + ((p2 + p3) << 16) + p0
```

## Compiler Intrinsic Support

The imath unit accelerates common compiler runtime functions:

**imath (4-DSP, unsigned):**

| Intrinsic | Description | imath Mode |
|-----------|-------------|------------|
| `__umulqi3` | unsigned 8-bit multiply | Mode 0 |
| `__umulhi3` | unsigned 16-bit multiply | Mode 1 |
| `__umulsi3` | unsigned 32-bit multiply (low 32 bits) | Mode 2 |
| `__umulsi3_highpart` | unsigned 32-bit multiply (high 32 bits) | Mode 2 |
| `__mulqi3` | signed 8-bit (software sign handling) | Mode 0 + SW |
| `__mulhi3` | signed 16-bit (software sign handling) | Mode 1 + SW |
| `__mulsi3` | signed 32-bit (software sign handling) | Mode 2 + SW |

**imath_lite (2-DSP, signed support):**

| Intrinsic | Description | Mode | SIGNED |
|-----------|-------------|------|--------|
| `__mulqi3` | signed 8-bit multiply | Mode 0 | 1 |
| `__umulqi3` | unsigned 8-bit multiply | Mode 0 | 0 |
| `__mulhi3` | signed 16-bit multiply | Mode 1 | 1 |
| `__umulhi3` | unsigned 16-bit multiply | Mode 1 | 0 |
| `__mulsi3` | signed 32-bit (4× 16×16 + software) | SW | - |
| `__umulsi3` | unsigned 32-bit (4× 16×16 + software) | SW | - |

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

**imath (4-DSP):**
1. **Unsigned only:** All operations are unsigned. For signed multiply, software must handle sign (abs, multiply, conditionally negate).
2. **Little-endian:** All multi-byte values are little-endian (LSB at lowest address).

**imath_lite (2-DSP):**
1. **No 32×32 hardware:** Software must combine four 16×16 multiplies.
2. **Little-endian:** All multi-byte values are little-endian.

> **Note:** The iCE40 SB_MAC16 DSP block only performs multiply and multiply-accumulate.
> It has no hardware support for division or shifting. Division and shift operations
> remain software-only on this platform.

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

**Full MCU (all peripherals):**

| Resource | Used | Available | % |
|----------|------|-----------|---|
| LUT4 | 6147 | 5280 | 116% (over!) |
| DFF | ~2300 | 5280 | 44% |
| SPRAM | 4 | 4 | 100% |
| EBR | 4 | 30 | 13% |
| MAC16 | 8 | 8 | 100% |
| I2C | 1 | 2 | 50% |

**Lite MCU (no UART1, no SPI1):** 5131 LUTs - **FITS!**

### DSP Allocation

| Unit | DSPs | LUTs | Purpose |
|------|------|------|---------|
| imath | 4 | 252 | Single-cycle 32×32 unsigned multiply |
| vmath | 4 | 503 | 4-wide int8 streaming dot product |
| **Total** | **8** | - | All DSPs used |

**Alternative: imath_lite**

| Unit | DSPs | LUTs | Purpose |
|------|------|------|---------|
| imath_lite | 2 | 124 | Signed 8×8/16×16, software 32×32 |
| vmath | 4 | 503 | 4-wide int8 streaming dot product |
| Free | 2 | - | Future expansion |

### UP5K-Compatible Configurations

| Configuration | LUTs | DSPs | Peripherals |
|---------------|------|------|-------------|
| Full | 6147 | 8 | All - **exceeds UP5K** |
| No UART1 | 5445 | 8 | -UART1 - still over |
| **Lite (no UART1, no SPI1)** | **5131** | **8** | **Timer, GPIO, UART0, I2C, imath, vmath** |
| Lite + imath_lite | 4973 | 6 | Same + 2 DSPs free |

**Note:** For UP5K, use "Lite" configuration. Full MCU targets ECP5.

## ECP5 (Target: OrangeCrab 25F)

Comfortable fit with headroom for additional features. ECP5-25F has:
- 24K LUTs (vs 5.3K on UP5K)
- 56 EBR blocks
- 28 DSP blocks (MULT18X18D)
- DDR3 memory controller possible
