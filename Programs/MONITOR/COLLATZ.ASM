; ====================================================
; COLLATZ.ASM - Collatz Conjecture Explorer
; Author: kayto
; Version date: 28/02/2026
; Licensed under the MIT License. See LICENSE file in the project root for full license text.
; ====================================================
; Assembler syntax: asmx -C 8080 -e -w -o COLLATZ.hex COLLATZ.ASM
;
; Monitor program for the Altaid 8800.
; Load via ':' command, run with 'G 8000'.
;
; The Collatz conjecture (the 3N+1 problem):
;   Given any positive integer N,
;     if N is even  ->  N / 2
;     if N is odd   ->  3N + 1
;   Repeat.  The conjecture states that no matter what N you
;   start with, the sequence always reaches 1.  No counter-
;   example has ever been found, yet it remains unproven.
;
; This program tests consecutive integers starting from 2.
; Each step of the journey is displayed on the front panel:
;
;   Address LEDs (A0-A15) : current value in binary
;   Data LEDs (D0-D7)     : step count (wraps at 256)
;   Status LEDs           :
;       S3+S1 lit = odd step  (3N+1 -- value grows)
;       S2+S0 lit = even step (N/2  -- value shrinks)
;       all four  = goal reached (N = 1)
;
; Arithmetic is 24-bit internally so intermediate values
; that exceed 65535 during the 3N+1 multiply are handled.
;
; When a number reaches 1 the LEDs flash in celebration,
; then the next starting number is loaded automatically.
;
; Press any key to exit back to the monitor.
; B=90 (step loop) — number of refresh cycles per step, controls speed
; D=120 — inner pause per refresh, controls brightness (keep ≥60)
; C=3 — celebration flash count
; B=50/50 — flash on/off duration
; B=100 — final state hold before advancing
;
; ====================================================

        ORG     8000H

; --- ROM entry points ---
PRINTI  EQU     0BAFH
GETCHAR EQU     0BDEH
PUT_CHAR EQU    0BF6H
MAINMNU EQU     015BH

; --- UART RX buffer pointers ---
RXBHEAD EQU     0FF2EH
RXBTAIL EQU     0FF30H

; --- Timer ---
TMRVAL  EQU     0FF45H

; =============================================================
START:
        XRA     A
        OUT     46H             ; stop hardware timer

        CALL    PRINTI
        DB      0DH, 0AH
        DB      'COLLATZ - Conjecture Explorer'
        DB      0DH, 0AH
        DB      'ESC=exit'
        DB      0DH, 0AH, 0

        LXI     H, 2            ; first number to test
        SHLD    STARTNO

; -------------------------------------------------------------
; Begin testing a new starting number
; -------------------------------------------------------------
NEWNUM:
        LHLD    STARTNO
        SHLD    CURVAL
        XRA     A
        STA     CURVAL+2        ; 24-bit high byte = 0
        STA     STEPCNT
        STA     STEPCNT+1       ; 16-bit step counter
        STA     SFLAGS          ; neutral status

        ; Serial: "N=<number>: "
        CALL    PRINTI
        DB      'N=', 0
        LHLD    STARTNO
        CALL    PRDEC
        CALL    PRINTI
        DB      ': ', 0

; -------------------------------------------------------------
; Main iteration loop
; -------------------------------------------------------------
STEP:
        CALL    KEYCHK
        JZ      NOKEY1
        CALL    GETCHAR
        CPI     1BH
        JZ      EXIT
NOKEY1:

        CALL    SHOWLED

        ; --- Is current value = 1? ---
        LDA     CURVAL+2
        ORA     A
        JNZ     NOTONE          ; high byte > 0, not 1
        LHLD    CURVAL
        MOV     A, H
        ORA     A
        JNZ     NOTONE          ; mid byte > 0, not 1
        MOV     A, L
        CPI     1
        JZ      GOAL

NOTONE:
        ; Odd or even? (test bit 0)
        LDA     CURVAL
        RAR
        JC      DOODD

; --- EVEN: value = value / 2 (24-bit shift right) ---
DOEVEN:
        LDA     CURVAL+2
        ORA     A               ; clear carry
        RAR
        STA     CURVAL+2
        LDA     CURVAL+1
        RAR                     ; carry chains through
        STA     CURVAL+1
        LDA     CURVAL
        RAR
        STA     CURVAL

        MVI     A, 05H          ; status: even (S2+S0)
        JMP     STEPDN

; --- ODD: value = 3 * value + 1 ---
DOODD:
        ; Save original value
        LHLD    CURVAL
        SHLD    SAVVAL
        LDA     CURVAL+2
        STA     SAVVAL+2

        ; Multiply by 2 (24-bit shift left)
        LHLD    CURVAL
        DAD     H               ; HL *= 2, carry out
        SHLD    CURVAL
        LDA     CURVAL+2
        RAL                     ; rotate carry in
        STA     CURVAL+2

        ; Add original to get 3x
        LHLD    CURVAL          ; 2x (low 16)
        XCHG                    ; DE = 2x
        LHLD    SAVVAL          ; HL = original (low 16)
        DAD     D               ; HL = 3x low 16, carry
        SHLD    CURVAL
        LDA     CURVAL+2        ; 2x high byte
        MOV     B, A
        LDA     SAVVAL+2        ; original high byte
        ADC     B               ; 3x high = 2x_hi + orig_hi + carry
        STA     CURVAL+2

        ; Plus 1 to complete 3N+1
        LHLD    CURVAL
        INX     H
        SHLD    CURVAL
        MOV     A, H
        ORA     L               ; zero only if FFFF wrapped to 0000
        JNZ     NOINC
        LDA     CURVAL+2
        INR     A
        STA     CURVAL+2
NOINC:
        MVI     A, 0AH          ; status: odd (S3+S1)

; --- Common tail for both branches ---
STEPDN:
        STA     SFLAGS

        LDA     STEPCNT
        INR     A
        STA     STEPCNT
        JNZ     NOINC2
        LDA     STEPCNT+1
        INR     A
        STA     STEPCNT+1
NOINC2:

        ; Active refresh loop -- keeps LEDs bright
        ; TIMING: B*D sets step duration. Increase B to slow
        ; down, decrease to speed up. D controls brightness --
        ; keep above ~60 to avoid visible flicker.
        MVI     B, 90           ; refresh iterations  (speed)
        MVI     D, 120          ; inner pause per refresh (brightness)
REFRSH:
        CALL    SHOWLED
        PUSH    D               ; restore D each pass
RPAUSE:
        DCR     D
        JNZ     RPAUSE
        POP     D
        DCR     B
        JNZ     REFRSH

        JMP     STEP

; -------------------------------------------------------------
; Goal reached -- value = 1
; -------------------------------------------------------------
GOAL:
        MVI     A, 0FH
        STA     SFLAGS
        CALL    SHOWLED

        ; Serial: "<steps>\r\n"
        LHLD    STEPCNT
        CALL    PRDEC
        CALL    PRINTI
        DB      0DH, 0AH, 0

        ; Celebration flash (active refresh)
        ; TIMING: C = flash count, B = on/off duration
        MVI     C, 3            ; number of flashes
GFLASH:
        MVI     B, 100           ; on duration
GFON:
        CALL    ALLON
        MVI     D, 80
GFONP:
        DCR     D
        JNZ     GFONP
        DCR     B
        JNZ     GFON
        MVI     B, 100           ; off duration
GFOFF:
        CALL    ALLOFF
        MVI     D, 80
GFOFP:
        DCR     D
        JNZ     GFOFP
        DCR     B
        JNZ     GFOFF
        DCR     C
        JNZ     GFLASH

        ; Show final state briefly (active refresh)
        ; TIMING: B = hold duration before advancing
        MVI     B, 200          ; hold duration
GFHOLD:
        CALL    SHOWLED
        MVI     D, 80
GFHLP:
        DCR     D
        JNZ     GFHLP
        DCR     B
        JNZ     GFHOLD

        ; Advance to next starting number
        LHLD    STARTNO
        INX     H
        SHLD    STARTNO
        JMP     NEWNUM

; -------------------------------------------------------------
; Exit to monitor
; -------------------------------------------------------------
EXIT:
        LDA     TMRVAL
        OUT     46H             ; restore timer ISR
        CALL    PRINTI
        DB      0DH, 0AH
        DB      'Done.'
        DB      0DH, 0AH, 0
        JMP     MAINMNU

; =============================================================
; SHOWLED - Write current state to all 7 LED columns
; =============================================================
SHOWLED:
        ; Col 2 (A0-A3): value bits 3:0
        LDA     CURVAL
        ANI     0FH
        ORI     0A0H
        OUT     0C0H

        ; Col 3 (A4-A7): value bits 7:4
        LDA     CURVAL
        RRC
        RRC
        RRC
        RRC
        ANI     0FH
        ORI     0B0H
        OUT     0C0H

        ; Col 0 (A8-A11): value bits 11:8
        LDA     CURVAL+1
        ANI     0FH
        ORI     80H
        OUT     0C0H

        ; Col 1 (A12-A15): value bits 15:12
        LDA     CURVAL+1
        RRC
        RRC
        RRC
        RRC
        ANI     0FH
        ORI     90H
        OUT     0C0H

        ; Col 4 (D0-D3): step count bits 3:0
        LDA     STEPCNT
        ANI     0FH
        ORI     0C0H
        OUT     0C0H

        ; Col 5 (D4-D7): step count bits 7:4
        LDA     STEPCNT
        RRC
        RRC
        RRC
        RRC
        ANI     0FH
        ORI     0D0H
        OUT     0C0H

        ; Col 6 (Status): operation indicator
        LDA     SFLAGS
        ANI     0FH
        ORI     0E0H
        OUT     0C0H

        RET

; =============================================================
; ALLON - All 28 LEDs on
; =============================================================
ALLON:
        MVI     A, 8FH
        OUT     0C0H
        MVI     A, 9FH
        OUT     0C0H
        MVI     A, 0AFH
        OUT     0C0H
        MVI     A, 0BFH
        OUT     0C0H
        MVI     A, 0CFH
        OUT     0C0H
        MVI     A, 0DFH
        OUT     0C0H
        MVI     A, 0EFH
        OUT     0C0H
        RET

; =============================================================
; ALLOFF - All 28 LEDs off
; =============================================================
ALLOFF:
        MVI     A, 80H
        OUT     0C0H
        MVI     A, 90H
        OUT     0C0H
        MVI     A, 0A0H
        OUT     0C0H
        MVI     A, 0B0H
        OUT     0C0H
        MVI     A, 0C0H
        OUT     0C0H
        MVI     A, 0D0H
        OUT     0C0H
        MVI     A, 0E0H
        OUT     0C0H
        RET

; =============================================================\n; KEYCHK - Test for keypress (Z = none, NZ = key waiting)\n; =============================================================
KEYCHK:
        PUSH    H
        LHLD    RXBHEAD
        XCHG
        LHLD    RXBTAIL
        MOV     A, H
        CMP     D
        JNZ     GOTKEY
        MOV     A, L
        CMP     E
GOTKEY:
        POP     H
        RET

; =============================================================
; PRDEC - Print HL as unsigned decimal, suppress leading zeros
; =============================================================
PRDEC:
        PUSH    B
        PUSH    D
        MVI     B, 0            ; leading zero suppression
        LXI     D, 10000
        CALL    PDIGIT
        LXI     D, 1000
        CALL    PDIGIT
        LXI     D, 100
        CALL    PDIGIT
        LXI     D, 10
        CALL    PDIGIT
        MOV     A, L            ; last digit (ones)
        ADI     '0'
        CALL    PUT_CHAR
        POP     D
        POP     B
        RET

; PDIGIT - Divide HL by DE, print quotient digit
PDIGIT:
        MVI     C, '0'
PDLOOP:
        MOV     A, L
        SUB     E
        MOV     L, A
        MOV     A, H
        SBB     D
        MOV     H, A
        JC      PDFIX
        INR     C
        JMP     PDLOOP
PDFIX:
        DAD     D               ; undo last subtract
        MOV     A, C
        CPI     '0'
        JNZ     PDPRNT          ; non-zero digit
        MOV     A, B
        ORA     A
        RZ                      ; suppress leading zero
PDPRNT:
        MVI     B, 1            ; disable suppression
        MOV     A, C
        PUSH    H
        CALL    PUT_CHAR
        POP     H
        RET

; =============================================================
; Variables
; =============================================================
CURVAL: DS      3               ; current value (24-bit, LE)
SAVVAL: DS      3               ; temp for 3N+1 multiply
STARTNO: DS     2               ; number under test
STEPCNT: DS     2               ; iteration counter (16-bit)
SFLAGS: DS      1               ; status LED pattern

        END     START
