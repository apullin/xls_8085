; Blinky 1: Simple busywait GPIO toggle
; For i8085sv MCU
;
; Toggles GPIO bit 0 with a delay loop

        INCLUDE "i8085sv_csl.inc"

DELAY_COUNT     EQU     0x80    ; Delay iterations

        ORG     ROM_BASE

START:
        ; Set GPIO bit 0 as output
        LXI     H, GPIO0_DIR
        MVI     M, 0x01

        MVI     B, 0x00         ; B = LED state

MAIN_LOOP:
        ; Toggle LED state
        MOV     A, B
        XRI     0x01
        MOV     B, A

        ; Write to GPIO
        LXI     H, GPIO0_DATA_OUT
        MOV     M, A

        ; Delay loop
        CALL    DELAY
        JMP     MAIN_LOOP

; Nested delay loop
DELAY:
        MVI     D, DELAY_COUNT
DELAY_OUTER:
        MVI     E, 0xFF
DELAY_INNER:
        DCR     E
        JNZ     DELAY_INNER
        DCR     D
        JNZ     DELAY_OUTER
        RET

        END
