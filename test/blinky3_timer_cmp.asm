; Blinky 3: Timer compare match IRQ -> GPIO toggle
; For i8085sv MCU
;
; Uses CMP0 compare match for precise timing

        INCLUDE "i8085sv_csl.inc"

; Configuration
COMPARE_VAL     EQU     0x4000  ; Compare at 16384 counts
RELOAD_VAL      EQU     0x8000  ; Reload at 32768 (gives 50% duty)

LED_STATE       EQU     0x0080  ; RAM variable for LED state

; ============================================
; Interrupt vectors
; ============================================
        ORG     0x8000
        JMP     START           ; Reset vector

        ORG     0x8008          ; RST 1 - Timer0 IRQ
        JMP     TIMER_ISR

; ============================================
; Main code
; ============================================
        ORG     0x8040
START:
        ; Initialize stack
        LXI     SP, STACK_TOP

        ; Initialize LED state
        XRA     A
        STA     LED_STATE

        ; Configure GPIO bit 0 as output
        LXI     H, GPIO0_DIR
        MVI     M, 0x01

        ; Set compare value
        LXI     H, TIMER0_CMP0_LO
        MVI     M, (COMPARE_VAL AND 0xFF)
        INX     H
        MVI     M, (COMPARE_VAL SHR 8)

        ; Set reload value
        LXI     H, TIMER0_RELOAD_LO
        MVI     M, (RELOAD_VAL AND 0xFF)
        INX     H
        MVI     M, (RELOAD_VAL SHR 8)

        ; Prescaler: moderate division
        LXI     H, TIMER0_PRESCALE
        MVI     M, 0x10

        ; Enable CMP0 and OVF interrupts
        LXI     H, TIMER0_IRQ_EN
        MVI     M, TIMER_FLAG_CMP0 | TIMER_FLAG_OVF

        ; Start timer with auto-reload
        LXI     H, TIMER0_CTRL
        MVI     M, TIMER_CTRL_EN | TIMER_CTRL_AR

        ; Enable interrupts
        EI

        ; Main loop
MAIN_LOOP:
        HLT
        JMP     MAIN_LOOP

; ============================================
; Timer ISR - handles both CMP0 and OVF
; ============================================
TIMER_ISR:
        PUSH    PSW
        PUSH    H

        ; Read status to determine which interrupt
        LXI     H, TIMER0_STATUS
        MOV     A, M

        ; Check CMP0 flag
        ANI     TIMER_FLAG_CMP0
        JZ      CHECK_OVF

        ; CMP0 match - turn LED ON
        MVI     A, 0x01
        STA     LED_STATE
        LXI     H, GPIO0_DATA_OUT
        MOV     M, A

        ; Clear CMP0 flag
        LXI     H, TIMER0_STATUS
        MVI     M, TIMER_FLAG_CMP0
        JMP     ISR_DONE

CHECK_OVF:
        ; Read status again
        LXI     H, TIMER0_STATUS
        MOV     A, M
        ANI     TIMER_FLAG_OVF
        JZ      ISR_DONE

        ; Overflow - turn LED OFF
        XRA     A
        STA     LED_STATE
        LXI     H, GPIO0_DATA_OUT
        MOV     M, A

        ; Clear OVF flag
        LXI     H, TIMER0_STATUS
        MVI     M, TIMER_FLAG_OVF

ISR_DONE:
        POP     H
        POP     PSW
        EI
        RET

        END
