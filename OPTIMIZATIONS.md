# i8085 MCU Optimizations for iCE40 UP5K

The iCE40 UP5K has only 5280 LUTs, making every optimization critical. This document captures the major techniques used to fit a full-featured 8085 MCU into this constrained FPGA.

## 1. Hand-Written Verilog vs XLS-Generated

XLS (Google's hardware synthesis language) generates correct but verbose Verilog. Replacing XLS-generated peripherals with hand-written Verilog yielded significant savings:

| Peripheral | XLS LUTs | Hand-Written | Savings |
|------------|----------|--------------|---------|
| SPI        | 493      | 234          | 259 (53%) |
| UART       | 684      | ~450         | ~230 |
| Timer      | 470      | 329-392      | ~100-140 |
| GPIO       | 192      | ~130         | ~60 |

XLS tends to generate explicit state for every possible condition, while hand-written code can share logic and use more implicit state.

## 2. LUT-RAM FIFOs

FIFOs declared as `reg [7:0] fifo [0:3]` infer LUT-RAM on iCE40, which is essentially free (uses existing LUT resources as memory). Register-based FIFOs cost ~8 LUTs per byte.

```verilog
// Good: infers LUT-RAM (4 bytes = ~0 extra LUTs)
reg [7:0] tx_fifo [0:3];

// Bad: explicit registers (4 bytes = ~32 LUTs)
reg [7:0] tx_fifo_0, tx_fifo_1, tx_fifo_2, tx_fifo_3;
```

This optimization was critical for UART and userial peripherals.

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
# Default seed may fail timing at 20MHz
nextpnr-ice40 --up5k --json design.json  # 18.5 MHz

# Seed 3 passes
nextpnr-ice40 --up5k --json design.json --seed 3  # 20.1 MHz
```

For production, iterate seeds until timing passes, or use the `--timing-strict` flag with multiple attempts.

## Summary: Final Resource Usage

**i8085sg** (System General): 5182/5280 LCs (98%)
- 2x userial (UART/SPI switchable)
- 12 GPIO (8+4)
- 4 PWM with center-aligned mode
- imath_lite (DSP multiply)
- I2C
- SPI flash cache
- 128KB SPRAM

**i8085sv** (System Vector): 5324/5280 LCs (needs ~44 LUT reduction)
- 1x userial
- 8 GPIO
- Timer
- imath_lite + vmath (vector DMA)
- I2C
- SPI flash cache
- 128KB SPRAM
