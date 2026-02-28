; ====================================================
; FPCLOCK28.ASM - 28-LED Tally Clock
; Author: kayto
; Version date: 28/02/2026
; Licensed under the MIT License. See LICENSE file in the project root for full license text.
; ====================================================
; Assembler syntax: asmx -C 8080 -e -w -o FPCLOCK28.hex FPCLOCK28.ASM
;
; Monitor program for the Altaid 8800.
; Load via ':' command, run with 'G 8000'.
;
; Uses all 28 front panel LEDs for a human-readable
; clock that alternates between two screens.
;
; HOUR SCREEN (24h format):
;   All 24 non-status LEDs show a tally bar.
;   Count the lit LEDs = current hour (0-23).
;   Fills right-to-left: A0->A15 then D0->D7.
;
;   Examples (* = lit, - = off):
;     Data      Status  Address
;     --------  ----    ----------------
;     --------  .H..    --------***----- =  3:xx
;     --------  .H..    ************---- = 12:xx
;     *******-  .H..    **************** = 23:xx
;
; MINUTE SCREEN:
;   Address high (A8-A15): each lit LED = 10 minutes
;   Address low  (A0-A7):  each lit LED =  5 minutes
;   Data         (D0-D7):  each lit LED =  1 minute
;
;   Read: (addr_high x 10) + (addr_low x 5)
;       + (data x 1) = minutes
;
;   Examples for 37 minutes:
;     Data      Status  Addr_high  Addr_low
;     **------  ..M.    ***-----   *-------
;     2 ones           3 tens     1 five
;     = 30 + 5 + 2 = 37
;
; STATUS LEDs (always visible, left to right):
;   S3: Second tick (blinks each second)
;   S2: PM indicator (lit = PM)
;   S1: Lit when showing Hours
;   S0: Lit when showing Minutes
;
; Screens alternate every ~3 sec with brief flash.
; Press ESC to exit.
; ====================================================

        ORG     8000H

;------------------------------------------------------
; System equates
;------------------------------------------------------
OUTPORT EQU     0C0H
TIMER   EQU     046H
TIMERV  EQU     0FF45H
RXBHEAD EQU     0FF2EH
RXBTAIL EQU     0FF30H
PRINTI  EQU     0BAFH
GETCHAR EQU     0BDEH
MAINMNU EQU     015BH
NUMCOLS EQU     7

;======================================================
; SETUP - banner and time input (timer still running)
;======================================================
START:
        CALL    PRINTI
        DB      0DH, 0AH
        DB      '28-LED Tally Clock'
        DB      0DH, 0AH, 00H

        CALL    PRINTI
        DB      'Hours (00-23): ', 00H
        CALL    GETNUM
        STA     HOURS

        CALL    PRINTI
        DB      0DH, 0AH
        DB      'Minutes (00-59): ', 00H
        CALL    GETNUM
        STA     MINUTES

        CALL    PRINTI
        DB      0DH, 0AH
        DB      'Running... ESC=exit', 0DH, 0AH, 00H

        ; Drain UART buffer
        LDA     RXBHEAD
        STA     RXBTAIL

        ; Save & stop timer
        LDA     TIMERV
        STA     SAVTMR
        XRA     A
        STA     TIMERV
        OUT     TIMER

        ; Init counters
        XRA     A
        STA     SECTICK
        STA     SECCNT
        STA     DISPMODE
        STA     MODETICK
        STA     BLINKTK
        STA     BLINKST
        STA     FLASHCNT

;======================================================
; MAIN LOOP
;======================================================
MAINLP:
        LDA     DISPMODE
        ORA     A
        JNZ     SHOWMIN

;------------------------------------------------------
; SHOW HOURS - tally bar across 24 LEDs (0-23)
;   Fills: col2 col3 col0 col1 col4 col5
;------------------------------------------------------
SHOWHR:
        LDA     HOURS
        MOV     B, A            ; B = hours (0-23)

        ; full_cols = hours / 4
        RRC
        RRC
        ANI     07H
        MOV     C, A            ; C = full columns (0-5)

        ; partial = hours & 3
        MOV     A, B
        ANI     03H
        MOV     D, A            ; D = partial bits (0-3)

        MVI     E, 0            ; E = column index

HRLOOP:
        MOV     A, E
        CMP     C               ; index vs full_cols
        JC      HRFULL          ; index < full: all 4 on
        JNZ     HREMPTY         ; index > full: all off

        ; index == full: partial fill
        MOV     A, D
        JMP     HRSET

HRFULL:
        MVI     A, 4            ; TALLYTBL[4] = 0FH
        JMP     HRSET

HREMPTY:
        XRA     A               ; TALLYTBL[0] = 00H

HRSET:
        ; A = 0-4 -> look up tally pattern
        LXI     H, TALLYTBL
        ADD     L
        MOV     L, A
        MOV     B, M            ; B = LED pattern

        ; Get physical column from HRORDER
        LXI     H, HRORDER
        MOV     A, E
        ADD     L
        MOV     L, A
        MOV     A, M            ; A = physical column

        ; COLDATA[phys_col] = B
        LXI     H, COLDATA
        ADD     L
        MOV     L, A
        MOV     M, B

        ; Restore C = full_cols (B was clobbered)
        ; C and D are preserved through this loop
        INR     E
        MOV     A, E
        CPI     6
        JNZ     HRLOOP

        JMP     SETSTAT

;------------------------------------------------------
; SHOW MINUTES - tens / fives / ones tally groups
;------------------------------------------------------
SHOWMIN:
        LDA     MINUTES
        CALL    DIV10           ; B = tens, A = remainder

        MOV     D, A            ; D = remainder (0-9)

        ; Tens -> addr high (cols 0, 1)
        MOV     A, B
        CPI     5
        JC      TNS_LO

        ; tens = 5: col0 = 0F, col1 = 01
        MVI     A, 0FH
        STA     COLDATA+0
        MVI     A, 01H
        STA     COLDATA+1
        JMP     TNS_DONE

TNS_LO:
        ; tens 0-4: col0 = TALLYTBL[tens]
        LXI     H, TALLYTBL
        ADD     L
        MOV     L, A
        MOV     A, M
        STA     COLDATA+0
        XRA     A
        STA     COLDATA+1

TNS_DONE:
        ; Fives and ones from remainder D
        MOV     A, D
        CPI     5
        JC      FIV_0

        ; fives = 1, ones = D - 5
        SUI     5
        MOV     D, A            ; D = ones (0-4)
        MVI     A, 01H
        JMP     FIV_SET

FIV_0:
        ; fives = 0, ones = D (0-4)
        XRA     A

FIV_SET:
        STA     COLDATA+2       ; col 2 (A0-A3)
        XRA     A
        STA     COLDATA+3       ; col 3 (A4-A7)

        ; Ones -> data (col 4)
        LXI     H, TALLYTBL
        MOV     A, D
        ADD     L
        MOV     L, A
        MOV     A, M
        STA     COLDATA+4
        XRA     A
        STA     COLDATA+5

;------------------------------------------------------
; STATUS LEDs (col 6, always computed)
;   S3 (bit 3) = second tick blink
;   S2 (bit 2) = PM
;   S1 (bit 1) = hours mode
;   S0 (bit 0) = minutes mode
;------------------------------------------------------
SETSTAT:
        ; S3: blink
        LDA     BLINKST
        ORA     A
        MVI     A, 0
        JZ      S_NOBLNK
        MVI     A, 08H
S_NOBLNK:

        ; S2: PM (hours >= 12)
        MOV     B, A
        LDA     HOURS
        CPI     12
        MOV     A, B
        JC      S_NOPM
        ORI     04H
S_NOPM:

        ; S1/S0: mode indicator
        MOV     B, A
        LDA     DISPMODE
        ORA     A
        MOV     A, B
        JNZ     S_ISMIN
        ORI     02H             ; bit 1 = hours
        JMP     S_SAVE
S_ISMIN:
        ORI     01H             ; bit 0 = minutes
S_SAVE:
        STA     COLDATA+6

;------------------------------------------------------
; Flash overlay on mode change
;------------------------------------------------------
        LDA     FLASHCNT
        ORA     A
        JZ      DOSCAN
        DCR     A
        STA     FLASHCNT
        MVI     A, 0FH
        STA     COLDATA+0
        STA     COLDATA+1
        STA     COLDATA+2
        STA     COLDATA+3
        STA     COLDATA+4
        STA     COLDATA+5

;======================================================
; SCAN - multiplex all 7 columns for POV
;======================================================
DOSCAN:
        MVI     D, 10H          ; 16 scan cycles

SCANLP:
        LXI     H, COLDATA
        MVI     E, 80H          ; col 0 prefix
        MVI     B, NUMCOLS

SCNCOL:
        MOV     A, M
        ORA     E               ; merge prefix + TX idle
        OUT     OUTPORT

        MVI     C, 82H          ; 130-iteration delay (cal)
COLDLY: DCR     C
        JNZ     COLDLY

        INX     H
        MOV     A, E
        ADI     10H
        MOV     E, A

        DCR     B
        JNZ     SCNCOL

        DCR     D
        JNZ     SCANLP

        ;--- Timekeeping ---
        LDA     SECTICK
        INR     A
        STA     SECTICK
        CPI     09H             ; 9 ticks ~ 1 second
        JNZ     NOSEC

        XRA     A
        STA     SECTICK
        LDA     SECCNT
        INR     A
        STA     SECCNT
        CPI     3CH             ; 60 seconds
        JNZ     NOSEC

        XRA     A
        STA     SECCNT
        LDA     MINUTES
        INR     A
        STA     MINUTES
        CPI     3CH             ; 60 minutes
        JNZ     NOSEC

        XRA     A
        STA     MINUTES
        LDA     HOURS
        INR     A
        STA     HOURS
        CPI     18H             ; 24 hours
        JNZ     NOSEC

        XRA     A
        STA     HOURS

NOSEC:
        ;--- Blink timer ---
        LDA     BLINKTK
        INR     A
        STA     BLINKTK
        CPI     05H             ; 5 ticks ~ 0.5 sec
        JNZ     NOBLNK

        XRA     A
        STA     BLINKTK
        LDA     BLINKST
        XRI     01H
        STA     BLINKST

NOBLNK:
        ;--- Mode timer ---
        LDA     MODETICK
        INR     A
        STA     MODETICK
        CPI     1BH             ; 27 ticks ~ 3 sec
        JNZ     NOMODE

        XRA     A
        STA     MODETICK
        LDA     DISPMODE
        XRI     01H
        STA     DISPMODE
        MVI     A, 3
        STA     FLASHCNT        ; trigger flash

NOMODE:
        ;--- Check UART for keypress ---
        LDA     RXBHEAD
        LXI     H, RXBTAIL
        SUB     M
        JZ      MAINLP

        ; Read key - only ESC exits
        CALL    GETCHAR
        CPI     1BH
        JNZ     MAINLP

        ;=== EXIT ===

        ; Blank all LED columns
        MVI     A, 80H
BLNKLP: OUT     OUTPORT
        ADI     10H
        JNC     BLNKLP

        ; Restore timer
        LDA     SAVTMR
        STA     TIMERV
        OUT     TIMER

        CALL    PRINTI
        DB      'Done.', 0DH, 0AH, 00H

        JMP     MAINMNU

;======================================================
; GETNUM - Read 2 ASCII digits, return binary in A
;   tens*10 + ones, using ROM GET_CHAR (echoed)
;======================================================
GETNUM:
        CALL    GETCHAR         ; read tens digit
        SUI     30H
        MOV     B, A
        ADD     A               ; x2
        ADD     A               ; x4
        ADD     B               ; x5
        ADD     A               ; x10
        STA     TEMP
        CALL    GETCHAR         ; read ones digit
        SUI     30H
        LXI     H, TEMP
        ADD     M               ; tens*10 + ones
        RET

;======================================================
; DIV10 - Divide A by 10
;   Returns: B = quotient, A = remainder
;======================================================
DIV10:
        MVI     B, 0
DIV10L:
        CPI     10
        JC      DIV10D
        SUI     10
        INR     B
        JMP     DIV10L
DIV10D:
        RET

;------------------------------------------------------
; Variables
;------------------------------------------------------
HOURS:   DB     00H
MINUTES: DB     00H
SAVTMR:  DB     00H
SECTICK: DB     00H
SECCNT:  DB     00H
DISPMODE:DB     00H
MODETICK:DB     00H
BLINKTK: DB     00H
BLINKST: DB     00H
FLASHCNT:DB     00H
TEMP:    DB     00H

; Column data bytes (indexed 0-6 = columns 0-6)
COLDATA:
        DB      00H, 00H, 00H, 00H, 00H, 00H, 00H

; Tally fill patterns: count -> LED pattern
TALLYTBL:
        DB      00H             ; 0 LEDs
        DB      01H             ; 1 LED
        DB      03H             ; 2 LEDs
        DB      07H             ; 3 LEDs
        DB      0FH             ; 4 LEDs

; Hour display column order (right-to-left on panel)
;   A0-A3(col2), A4-A7(col3), A8-A11(col0),
;   A12-A15(col1), D0-D3(col4), D4-D7(col5)
HRORDER:
        DB      02H, 03H, 00H, 01H, 04H, 05H
