; ====================================================
; BUTTONS.ASM - Front Panel Button Test
; Author: kayto
; Version date: 28/02/2026
; Licensed under the MIT License. See LICENSE file in the project root for full license text.
; ====================================================
; Assembler syntax: asmx -C 8080 -e -w -o BUTTONS.hex BUTTONS.ASM
;
; Tests all 11 software-readable buttons:
;   D0-D7  = 8 Data Momentary Switches
;   RUN    = Run control switch
;   MODE   = Mode control switch
;   NEXT   = Next control switch
;   (RESET is hardwired, not software-readable)
;
; When buttons are pressed the corresponding LEDs
; light up and the state is printed on the serial
; terminal.  Data switches D0-D7 echo on Data LEDs.
; Control switches echo on Status LEDs:
;   RUN  -> S0 (rightmost)
;   MODE -> S1
;   NEXT -> S2
;
; The switch input port (40H) is multiplexed through
; the same column-select mechanism as the LED output.
; Write a column-select value to port C0H, then
; immediately read port 40H to sample that column's
; switches.  Active-low: bit=0 means pressed.
;
;   Column 4 (C0H) -> IN 40H bits 3:0 = D0-D3
;   Column 5 (D0H) -> IN 40H bits 3:0 = D4-D7
;   Column 6 (E0H) -> IN 40H bits 2:0 = RUN,MODE,NEXT
;
; Timer ISR must be stopped to prevent C0H conflicts.
;
; ====================================================

        ORG     8000H

;------------------------------------------------------
; ROM / hardware equates
;------------------------------------------------------
PRINTI      EQU 0BAFH       ; Print inline null-terminated string
MAIN_MENU   EQU 015BH       ; Monitor main menu entry
PUT_CHAR    EQU 0BF6H       ; Print char in A
GETCHAR     EQU 0BDEH       ; ROM blocking char read
OUTPORT     EQU 0C0H        ; LED + TX output port
INPORT      EQU 040H        ; Switch input port
TIMER       EQU 046H        ; Timer control port
TIMERV      EQU 0FF45H      ; TIMER_RUN variable in RAM
RXBHEAD     EQU 0FF2EH      ; UART RX buffer head pointer
RXBTAIL     EQU 0FF30H      ; UART RX buffer tail pointer

;======================================================
START:
        ; --- Print banner ---
        CALL    PRINTI
        DB      0DH,0AH
        DB      'BUTTONS - Switch Test',0DH,0AH
        DB      'Press buttons to test. ESC=exit',0DH,0AH,0

        ; --- Save and stop timer ---
        LDA     TIMERV
        STA     SAVTMR
        XRA     A
        STA     TIMERV
        OUT     TIMER

        ; --- Clear previous state ---
        XRA     A
        STA     PREV_DATA
        STA     PREV_CTL

;------------------------------------------------------
; Main loop: scan switches and display on LEDs
;------------------------------------------------------
MAINLP:
        ; === Read Data Switches D0-D3 ===
        MVI     A,0C0H          ; column 4 select + TX idle
        OUT     OUTPORT
        IN      INPORT          ; bits 3:0 = D0-D3 (active low)
        ANI     0FH
        CMA                     ; invert: 1=pressed
        ANI     0FH
        MOV     B,A             ; B = D0-D3

        ; === Read Data Switches D4-D7 ===
        MVI     A,0D0H          ; column 5 select + TX idle
        OUT     OUTPORT
        IN      INPORT          ; bits 3:0 = D4-D7 (active low)
        ANI     0FH
        CMA
        ANI     0FH
        ; Shift to upper nibble
        RLC
        RLC
        RLC
        RLC
        ORA     B               ; A = D7..D0 full byte (1=pressed)
        STA     CUR_DATA        ; save current data switches

        ; === Read Control Switches ===
        MVI     A,0E0H          ; column 6 select + TX idle
        OUT     OUTPORT
        IN      INPORT          ; bit0=RUN, bit1=MODE, bit2=NEXT (active low)
        ANI     07H
        CMA
        ANI     07H
        STA     CUR_CTL         ; save current control switches

        ; === Display on LEDs ===
        ; All 7 columns need refreshing for POV.
        ; Blank address LEDs (cols 0-3), show data + status.
        MVI     B,10            ; refresh cycles per scan

REFLP:
        ; Col 0: addr high low nibble - blank
        MVI     A,80H
        OUT     OUTPORT
        CALL    SMLDLY

        ; Col 1: addr high high nibble - blank
        MVI     A,90H
        OUT     OUTPORT
        CALL    SMLDLY

        ; Col 2: addr low low nibble - blank
        MVI     A,0A0H
        OUT     OUTPORT
        CALL    SMLDLY

        ; Col 3: addr low high nibble - blank
        MVI     A,0B0H
        OUT     OUTPORT
        CALL    SMLDLY

        ; Col 4: data low nibble (D0-D3)
        LDA     CUR_DATA
        ANI     0FH
        ORI     0C0H            ; col 4 + TX idle
        OUT     OUTPORT
        CALL    SMLDLY

        ; Col 5: data high nibble (D4-D7)
        LDA     CUR_DATA
        RRC
        RRC
        RRC
        RRC
        ANI     0FH
        ORI     0D0H            ; col 5 + TX idle
        OUT     OUTPORT
        CALL    SMLDLY

        ; Col 6: status (control switches)
        ; S0=RUN, S1=MODE, S2=NEXT
        LDA     CUR_CTL
        ANI     0FH
        ORI     0E0H            ; col 6 + TX idle
        OUT     OUTPORT
        CALL    SMLDLY

        DCR     B
        JNZ     REFLP

        ; === Check for state change -> print ===
        LDA     CUR_DATA
        MOV     B,A
        LDA     PREV_DATA
        CMP     B
        JNZ     CHANGED

        LDA     CUR_CTL
        MOV     B,A
        LDA     PREV_CTL
        CMP     B
        JNZ     CHANGED

        JMP     NOCHANGE

CHANGED:
        ; Update previous state
        LDA     CUR_DATA
        STA     PREV_DATA
        LDA     CUR_CTL
        STA     PREV_CTL

        ; Print current state
        ; Format: "D=XX CTL=XX  D7 D6 D5 D4 D3 D2 D1 D0  RUN MOD NXT"
        CALL    PRINTI
        DB      0DH,'D=',0

        LDA     CUR_DATA
        CALL    PRHEX

        CALL    PRINTI
        DB      ' Ctl=',0

        LDA     CUR_CTL
        CALL    PRHEX

        CALL    PRINTI
        DB      '  ',0

        ; Print individual data switch names
        MVI     C,8             ; 8 data switches
        MVI     D,80H           ; start from D7 (MSB)
PDSW:
        LDA     CUR_DATA
        ANA     D               ; test this bit
        JZ      PDOFF
        ; ON - print "D<n> "
        MVI     A,'D'
        CALL    PUT_CHAR
        ; Compute digit: D7 when mask=80, D0 when mask=01
        MOV     A,D
        CALL    BITNUM          ; A = bit number
        ADI     '0'
        CALL    PUT_CHAR
        MVI     A,' '
        CALL    PUT_CHAR
        JMP     PDNXT
PDOFF:
        ; OFF - print ".. "
        MVI     A,'.'
        CALL    PUT_CHAR
        MVI     A,'.'
        CALL    PUT_CHAR
        MVI     A,' '
        CALL    PUT_CHAR
PDNXT:
        MOV     A,D
        RRC                     ; shift mask right
        MOV     D,A
        DCR     C
        JNZ     PDSW

        ; Print control switches
        CALL    PRINTI
        DB      ' ',0

        ; RUN (bit 0)
        LDA     CUR_CTL
        ANI     01H
        JZ      NORUN
        CALL    PRINTI
        DB      'RUN ',0
        JMP     DOMOD
NORUN:
        CALL    PRINTI
        DB      '... ',0

DOMOD:
        ; MODE (bit 1)
        LDA     CUR_CTL
        ANI     02H
        JZ      NOMOD
        CALL    PRINTI
        DB      'MOD ',0
        JMP     DONXT
NOMOD:
        CALL    PRINTI
        DB      '... ',0

DONXT:
        ; NEXT (bit 2)
        LDA     CUR_CTL
        ANI     04H
        JZ      NONXT
        CALL    PRINTI
        DB      'NXT',0
        JMP     DONEP
NONXT:
        CALL    PRINTI
        DB      '...',0

DONEP:

NOCHANGE:
        ; === Check UART for ESC ===
        LDA     RXBHEAD
        LXI     H,RXBTAIL
        SUB     M
        JZ      MAINLP          ; no key, keep scanning

        ; Key available - read it
        CALL    GETCHAR
        CPI     1BH             ; ESC?
        JNZ     MAINLP          ; not ESC, keep going

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

        CALL    PRINTI
        DB      0DH,0AH,'Done.',0DH,0AH,0

        JMP     MAIN_MENU

;------------------------------------------------------
; PRHEX - Print A as two hex digits
;------------------------------------------------------
PRHEX:
        PUSH    PSW
        RRC
        RRC
        RRC
        RRC
        CALL    PRNIB
        POP     PSW
PRNIB:
        ANI     0FH
        ADI     '0'
        CPI     '9'+1
        JC      PRNIB1
        ADI     7               ; 'A'-'9'-1
PRNIB1:
        JMP     PUT_CHAR

;------------------------------------------------------
; BITNUM - Convert single-bit mask in A to bit number
; Input:  A = power of 2 (01,02,04,08,10,20,40,80)
; Output: A = bit number (0-7)
;------------------------------------------------------
BITNUM:
        PUSH    B
        MVI     B,0
BNLP:
        RRC
        JC      BNDONE
        INR     B
        JMP     BNLP
BNDONE:
        MOV     A,B
        POP     B
        RET

;------------------------------------------------------
; SMLDLY - Small delay for LED column persistence
;------------------------------------------------------
SMLDLY:
        PUSH    B
        MVI     B,80
SDLP:   DCR     B
        JNZ     SDLP
        POP     B
        RET

;------------------------------------------------------
; Data
;------------------------------------------------------
CUR_DATA:   DB  00H         ; current data switch state
CUR_CTL:    DB  00H         ; current control switch state
PREV_DATA:  DB  00H         ; previous data switch state
PREV_CTL:   DB  00H         ; previous control switch state
SAVTMR:     DB  00H         ; saved timer value

        END     START
