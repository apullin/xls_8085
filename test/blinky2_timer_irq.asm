; Blinky 2: Timer overflow IRQ -> GPIO toggle
; For i8085sv MCU
;
; Timer generates overflow interrupt, ISR toggles GPIO

        INCLUDE "i8085sv_csl.inc"

LED_STATE       EQU     0x0080  ; RAM variable for LED state

; ============================================
; Interrupt vectors
; ============================================
        ORG     0x8000
        JMP     START           ; Reset vector

        ORG     0x8008          ; RST 1 - Timer0 IRQ (priority 1 -> vector 0x08)
        JMP     TIMER_ISR

; ============================================
; Main code
; ============================================
        ORG     0x8040
START:
        ; Initialize stack
        LXI     SP, STACK_TOP

        ; Initialize LED state variable
        XRA     A
        STA     LED_STATE

        ; Configure GPIO bit 0 as output
        LXI     H, GPIO0_DIR
        MVI     M, 0x01

        ; Configure timer for periodic overflow
        ; Reload value: 0xFFFF for max period
        LXI     H, TIMER0_RELOAD_LO
        MVI     M, 0xFF
        INX     H
        MVI     M, 0xFF

        ; Prescaler: 255 for slowest tick
        LXI     H, TIMER0_PRESCALE
        MVI     M, 0xFF

        ; Enable overflow interrupt
        LXI     H, TIMER0_IRQ_EN
        MVI     M, TIMER_FLAG_OVF

        ; Start timer with auto-reload
        LXI     H, TIMER0_CTRL
        MVI     M, TIMER_CTRL_EN | TIMER_CTRL_AR

        ; Enable interrupts
        EI

        ; Main loop - just wait for interrupts
MAIN_LOOP:
        HLT                     ; Wait for interrupt
        JMP     MAIN_LOOP

; ============================================
; Timer overflow ISR
; ============================================
TIMER_ISR:
        PUSH    PSW
        PUSH    H

        ; Clear overflow flag (write 1 to clear)
        LXI     H, TIMER0_STATUS
        MVI     M, TIMER_FLAG_OVF

        ; Toggle LED state
        LDA     LED_STATE
        XRI     0x01
        STA     LED_STATE

        ; Write to GPIO
        LXI     H, GPIO0_DATA_OUT
        MOV     M, A

        POP     H
        POP     PSW
        EI                      ; Re-enable interrupts
        RET

        END
