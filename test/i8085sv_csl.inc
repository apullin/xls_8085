; ============================================
; i8085 Chip Support Library
; ============================================
; Memory-mapped peripheral definitions for i8085sg / i8085sv MCUs
; Include this file in your assembly programs
;
; Memory Map:
;   0x0000-0x3EFF  Common RAM (always bank 0, 16KB - 256B)
;   0x3F00-0x3FFF  Peripherals (memory-mapped, in common page)
;   0x4000-0x7FFF  Banked RAM (7 banks x 16KB)
;   0x8000-0xFFFF  Banked ROM (256 banks x 32KB, SPI flash)
;
; I/O Ports:
;   0xF0  ROM bank select (8-bit, 256 banks)
;   0xF1  RAM bank select (3-bit, banks 1-7)

; ============================================
; Memory Map Constants
; ============================================
RAM_BASE        EQU     0x0000
COMMON_SIZE     EQU     0x3F00  ; Common RAM size (before peripherals)
PERIPH_BASE     EQU     0x3F00
BANKED_RAM      EQU     0x4000  ; Banked RAM starts here
ROM_BASE        EQU     0x8000

; I/O Ports
PORT_ROM_BANK   EQU     0xF0
PORT_RAM_BANK   EQU     0xF1

; ============================================
; Peripheral Slot Map (16 bytes per slot)
; ============================================
;   Slot 0  0x3F00  Timer0      (SG + SV)
;   Slot 1  0x3F10  GPIO0       (SG + SV)  8-bit
;   Slot 2  0x3F20  Userial0    (SG + SV)
;   Slot 3  0x3F30  Userial1    (SG only)  or SPI1
;   Slot 4  0x3F40  GPIO1       (SG only)  4-bit
;   Slot 5  0x3F50  I2C0        (SG + SV)
;   Slot 6  0x3F60  imath       (SG + SV)
;   Slot 7  0x3F70  vmath       (SV only)

; ============================================
; Timer0 (0x3F00-0x3F0F) - Slot 0
; ============================================
TIMER0_BASE     EQU     0x3F00
TIMER0_CNT_LO   EQU     TIMER0_BASE + 0x0
TIMER0_CNT_HI   EQU     TIMER0_BASE + 0x1
TIMER0_RELOAD_LO EQU    TIMER0_BASE + 0x2
TIMER0_RELOAD_HI EQU    TIMER0_BASE + 0x3
TIMER0_PRESCALE EQU     TIMER0_BASE + 0x4
TIMER0_CTRL     EQU     TIMER0_BASE + 0x5
TIMER0_IRQ_EN   EQU     TIMER0_BASE + 0x6
TIMER0_STATUS   EQU     TIMER0_BASE + 0x7
TIMER0_CMP0_LO  EQU     TIMER0_BASE + 0x8
TIMER0_CMP0_HI  EQU     TIMER0_BASE + 0x9
TIMER0_CMP1_LO  EQU     TIMER0_BASE + 0xA
TIMER0_CMP1_HI  EQU     TIMER0_BASE + 0xB
TIMER0_CMP2_LO  EQU     TIMER0_BASE + 0xC
TIMER0_CMP2_HI  EQU     TIMER0_BASE + 0xD
TIMER0_CMP3_LO  EQU     TIMER0_BASE + 0xE
TIMER0_CMP3_HI  EQU     TIMER0_BASE + 0xF

; Timer CTRL bits
TIMER_CTRL_EN   EQU     0x01    ; Enable
TIMER_CTRL_AR   EQU     0x02    ; Auto-reload
TIMER_CTRL_DN   EQU     0x04    ; Count down

; Timer STATUS/IRQ bits
TIMER_FLAG_CMP0 EQU     0x01    ; Compare 0 match
TIMER_FLAG_CMP1 EQU     0x02    ; Compare 1 match
TIMER_FLAG_CMP2 EQU     0x04    ; Compare 2 match
TIMER_FLAG_CMP3 EQU     0x08    ; Compare 3 match
TIMER_FLAG_OVF  EQU     0x10    ; Overflow

; ============================================
; GPIO0 (0x3F10-0x3F1F) - Slot 1
; ============================================
GPIO0_BASE      EQU     0x3F10
GPIO0_DATA_OUT  EQU     GPIO0_BASE + 0x0
GPIO0_DATA_IN   EQU     GPIO0_BASE + 0x1
GPIO0_DIR       EQU     GPIO0_BASE + 0x2
GPIO0_IRQ_EN    EQU     GPIO0_BASE + 0x3
GPIO0_IRQ_RISE  EQU     GPIO0_BASE + 0x4
GPIO0_IRQ_FALL  EQU     GPIO0_BASE + 0x5
GPIO0_IRQ_STAT  EQU     GPIO0_BASE + 0x6
GPIO0_OUT_MODE  EQU     GPIO0_BASE + 0x7

; GPIO direction: 0=input, 1=output
; GPIO out_mode: 0=push-pull, 1=open-drain

; ============================================
; Userial0 (0x3F20-0x3F2F) - Slot 2
; ============================================
USERIAL0_BASE   EQU     0x3F20
USERIAL0_CTRL   EQU     USERIAL0_BASE + 0x0
USERIAL0_MODE   EQU     USERIAL0_BASE + 0x1
USERIAL0_STAT   EQU     USERIAL0_BASE + 0x2
USERIAL0_FIFOLVL EQU    USERIAL0_BASE + 0x3
USERIAL0_TXDATA EQU     USERIAL0_BASE + 0x4
USERIAL0_RXDATA EQU     USERIAL0_BASE + 0x5
USERIAL0_CLK_L  EQU     USERIAL0_BASE + 0x6
USERIAL0_CLK_H  EQU     USERIAL0_BASE + 0x7
USERIAL0_CLK_F  EQU     USERIAL0_BASE + 0x8
USERIAL0_IRQ_EN EQU     USERIAL0_BASE + 0x9
USERIAL0_IRQ_ST EQU     USERIAL0_BASE + 0xA
USERIAL0_IFLS   EQU     USERIAL0_BASE + 0xB
USERIAL0_SPI_CS EQU     USERIAL0_BASE + 0xC

; Userial CTRL bits
USERIAL_CTRL_EN   EQU   0x80    ; Enable
USERIAL_CTRL_TXEN EQU   0x40    ; TX enable
USERIAL_CTRL_RXEN EQU   0x20    ; RX enable
USERIAL_CTRL_FEN  EQU   0x10    ; FIFO enable
USERIAL_CTRL_MODE EQU   0x08    ; 0=UART, 1=SPI
USERIAL_CTRL_LBE  EQU   0x04    ; Loopback (UART)
USERIAL_CTRL_WLEN EQU   0x02    ; Word len: 0=7bit, 1=8bit
USERIAL_CTRL_LSBF EQU   0x01    ; LSB first (SPI)

; Userial MODE bits (UART mode)
USERIAL_MODE_EVEN EQU   0x04    ; Even parity
USERIAL_MODE_STP2 EQU   0x02    ; 2 stop bits
USERIAL_MODE_PEN  EQU   0x01    ; Parity enable

; Userial MODE bits (SPI mode)
USERIAL_MODE_CPOL EQU   0x02    ; Clock polarity
USERIAL_MODE_CPHA EQU   0x01    ; Clock phase

; ============================================
; Userial1 (0x3F30-0x3F3F) - Slot 3 (SG only)
; ============================================
USERIAL1_BASE   EQU     0x3F30
USERIAL1_CTRL   EQU     USERIAL1_BASE + 0x0
USERIAL1_MODE   EQU     USERIAL1_BASE + 0x1
USERIAL1_STAT   EQU     USERIAL1_BASE + 0x2
USERIAL1_FIFOLVL EQU    USERIAL1_BASE + 0x3
USERIAL1_TXDATA EQU     USERIAL1_BASE + 0x4
USERIAL1_RXDATA EQU     USERIAL1_BASE + 0x5
USERIAL1_CLK_L  EQU     USERIAL1_BASE + 0x6
USERIAL1_CLK_H  EQU     USERIAL1_BASE + 0x7
USERIAL1_CLK_F  EQU     USERIAL1_BASE + 0x8
USERIAL1_IRQ_EN EQU     USERIAL1_BASE + 0x9
USERIAL1_IRQ_ST EQU     USERIAL1_BASE + 0xA
USERIAL1_IFLS   EQU     USERIAL1_BASE + 0xB
USERIAL1_SPI_CS EQU     USERIAL1_BASE + 0xC

; ============================================
; GPIO1 (0x3F40-0x3F4F) - Slot 4 (SG only, 4-bit)
; ============================================
GPIO1_BASE      EQU     0x3F40
GPIO1_DATA_OUT  EQU     GPIO1_BASE + 0x0
GPIO1_DATA_IN   EQU     GPIO1_BASE + 0x1
GPIO1_DIR       EQU     GPIO1_BASE + 0x2
GPIO1_IRQ_EN    EQU     GPIO1_BASE + 0x3
GPIO1_IRQ_RISE  EQU     GPIO1_BASE + 0x4
GPIO1_IRQ_FALL  EQU     GPIO1_BASE + 0x5
GPIO1_IRQ_STAT  EQU     GPIO1_BASE + 0x6

; ============================================
; I2C0 (0x3F50-0x3F5F) - Slot 5
; ============================================
I2C0_BASE       EQU     0x3F50
; (Register definitions TBD based on i2c_wrapper)

; ============================================
; imath (0x3F60-0x3F6F) - Slot 6, Integer Math
; ============================================
IMATH_BASE      EQU     0x3F60
IMATH_A_LO      EQU     IMATH_BASE + 0x0
IMATH_A_HI      EQU     IMATH_BASE + 0x1
IMATH_B_LO      EQU     IMATH_BASE + 0x2
IMATH_B_HI      EQU     IMATH_BASE + 0x3
IMATH_RESULT_0  EQU     IMATH_BASE + 0x4
IMATH_RESULT_1  EQU     IMATH_BASE + 0x5
IMATH_RESULT_2  EQU     IMATH_BASE + 0x6
IMATH_RESULT_3  EQU     IMATH_BASE + 0x7
IMATH_CTRL      EQU     IMATH_BASE + 0x8

; imath CTRL bits
IMATH_CTRL_START EQU    0x01    ; Start multiply
IMATH_CTRL_SIGN  EQU    0x02    ; Signed multiply
IMATH_CTRL_BUSY  EQU    0x80    ; Busy flag (read-only)

; ============================================
; vmath (0x3F70-0x3F7F) - Slot 7, Vector Math (SV only)
; ============================================
VMATH_BASE      EQU     0x3F70
VMATH_A_PTR_LO  EQU     VMATH_BASE + 0x0
VMATH_A_PTR_MI  EQU     VMATH_BASE + 0x1
VMATH_A_PTR_HI  EQU     VMATH_BASE + 0x2
VMATH_B_PTR_LO  EQU     VMATH_BASE + 0x3
VMATH_B_PTR_MI  EQU     VMATH_BASE + 0x4
VMATH_B_PTR_HI  EQU     VMATH_BASE + 0x5
VMATH_LEN_LO    EQU     VMATH_BASE + 0x6
VMATH_LEN_HI    EQU     VMATH_BASE + 0x7
VMATH_ACC_0     EQU     VMATH_BASE + 0x8
VMATH_ACC_1     EQU     VMATH_BASE + 0x9
VMATH_ACC_2     EQU     VMATH_BASE + 0xA
VMATH_ACC_3     EQU     VMATH_BASE + 0xB
VMATH_BIAS_0    EQU     VMATH_BASE + 0xC
VMATH_BIAS_1    EQU     VMATH_BASE + 0xD
VMATH_BIAS_2    EQU     VMATH_BASE + 0xE
VMATH_CTRL      EQU     VMATH_BASE + 0xF

; vmath CTRL bits
VMATH_CTRL_START EQU    0x01    ; Start operation
VMATH_CTRL_DONE  EQU    0x40    ; Done flag (read-only)
VMATH_CTRL_BUSY  EQU    0x80    ; Busy flag (read-only)

; ============================================
; Interrupt Vectors (8085 RST instructions)
; ============================================
; Timer0 IRQ -> RST 1 (0x0008)
; GPIO0 IRQ  -> RST 2 (0x0010)
; Userial0   -> RST 3 (0x0018)
; Userial1   -> RST 4 (0x0020) (SG only)
; I2C0 IRQ   -> RST 5 (0x0028)
; GPIO1 IRQ  -> RST 6 (0x0030) (SG only)

INT_VEC_TIMER0   EQU    0x0008
INT_VEC_GPIO0    EQU    0x0010
INT_VEC_USERIAL0 EQU    0x0018
INT_VEC_USERIAL1 EQU    0x0020
INT_VEC_I2C0     EQU    0x0028
INT_VEC_GPIO1    EQU    0x0030

; Hardware interrupts
INT_VEC_TRAP    EQU     0x0024
INT_VEC_RST55   EQU     0x002C
INT_VEC_RST65   EQU     0x0034
INT_VEC_RST75   EQU     0x003C

; ============================================
; Common RAM locations (suggestion)
; ============================================
; 0x0080-0x00FF: Scratch variables
; 0x0100-0x01FF: Stack (grows down)
STACK_TOP       EQU     0x0100
