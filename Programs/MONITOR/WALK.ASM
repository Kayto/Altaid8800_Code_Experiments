; ====================================================
; WALK.ASM - Walking Bit on Data LEDs
; Author: kayto
; Version date: 28/02/2026
; Licensed under the MIT License. See LICENSE file in the project root for full license text.
; ====================================================
; Assembler syntax: asmx -C 8080 -e -w -o WALK.hex WALK.ASM
;
; A single lit LED walks right across the 8 data LEDs,
; wrapping from D0 back to D7 continuously.
; Press any key to stop and return to the monitor.
;
; Port C0H is multiplexed: bits 6:4 select column,
; bits 3:0 are the nibble, bit 7 = TX idle (always 1).
;   Column 4 (C0H prefix) = data low nibble  (D0-D3)
;   Column 5 (D0H prefix) = data high nibble (D4-D7)
;
; Timer ISR must be stopped to prevent C0H conflicts.
; UART RX buffer is checked directly for exit key.
;
;=====================================================

        ORG     8000H

;------------------------------------------------------
; ROM / hardware equates
;------------------------------------------------------
PRINTI      EQU 0BAFH       ; Print inline null-terminated string
MAIN_MENU   EQU 015BH       ; Monitor main menu entry
OUTPORT     EQU 0C0H        ; LED + TX output port
TIMER       EQU 046H        ; Timer control port
TIMERV      EQU 0FF45H      ; TIMER_RUN variable in RAM
RXBHEAD     EQU 0FF2EH      ; UART RX buffer head pointer
RXBTAIL     EQU 0FF30H      ; UART RX buffer tail pointer
GETCHAR     EQU 0BDEH       ; ROM blocking char read

SCAN_COUNT  EQU 60           ; POV scan cycles per step (speed)

; ====================================================
START:
        ; --- Print banner ---
        CALL    PRINTI
        DB      0DH,0AH,'WALK - ESC=exit',0DH,0AH,0

        ; --- Save and stop timer ---
        LDA     TIMERV
        STA     SAVTMR
        XRA     A
        STA     TIMERV
        OUT     TIMER

        ; --- Init: start at D0 (rightmost) ---
        MVI     A,01H
        STA     PATTERN

;------------------------------------------------------
; Main loop: multiplex data LEDs for persistence of vision
;------------------------------------------------------
MAINLP:
        MVI     B,SCAN_COUNT

SCAN:
        ; Column 4: low nibble (D0-D3)
        LDA     PATTERN
        ANI     0FH
        ORI     0C0H            ; col 4 + TX idle
        OUT     OUTPORT

        MVI     C,0             ; 256-iter delay
DLY1:   DCR     C
        JNZ     DLY1

        ; Column 5: high nibble (D4-D7)
        LDA     PATTERN
        RRC
        RRC
        RRC
        RRC
        ANI     0FH
        ORI     0D0H            ; col 5 + TX idle
        OUT     OUTPORT

        MVI     C,0             ; 256-iter delay
DLY2:   DCR     C
        JNZ     DLY2

        DCR     B
        JNZ     SCAN

        ; --- Walk the bit right ---
        LDA     PATTERN
        RRC
        STA     PATTERN

        ; --- Check UART buffer for keypress ---
        LDA     RXBHEAD
        LXI     H,RXBTAIL
        SUB     M
        JZ      MAINLP          ; no key, keep going

        ; Read key - only ESC exits
        CALL    GETCHAR
        CPI     1BH
        JNZ     MAINLP

;------------------------------------------------------
; Exit: restore timer, return to monitor
;------------------------------------------------------

        ; LEDs off
        MVI     A,80H
        OUT     OUTPORT

        ; Restore timer
        LDA     SAVTMR
        STA     TIMERV
        OUT     TIMER

        ; Exit message
        CALL    PRINTI
        DB      0DH,0AH,'Done.',0DH,0AH,0

        JMP     MAIN_MENU

;------------------------------------------------------
; Data
;------------------------------------------------------
PATTERN:    DB  01H
SAVTMR:     DB  00H

        END     START
