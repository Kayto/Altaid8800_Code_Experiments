; ====================================================
; ALLWAVE.ASM - Full Panel LED Wave Demo
; Author: kayto
; Version date: 28/02/2026
; Licensed under the MIT License. See LICENSE file in the project root for full license text.
; ====================================================
; Assembler syntax: asmx -C 8080 -e -w -o ALLWAVE.hex ALLWAVE.ASM
;
; Monitor program for the Altaid 8800.
; Load via ':' command, run with 'G 8000'.
;
; Sweeps a wave across ALL front panel LEDs:
;   Address (16), Data (8), Status (4) = 28 LEDs.
;   Fills right-to-left, then drains right-to-left,
;   repeating continuously.
;
; Wave order (right-to-left on the panel):
;   A0-A3 (col 2), A4-A7 (col 3), A8-A11 (col 0),
;   A12-A15 (col 1), Status (col 6), D0-D3 (col 4),
;   D4-D7 (col 5)
;
; 56 animation steps: 28 fill + 28 drain.
; Each step fills or drains one bit in one column.
;
; Press ESC to exit.
; ====================================================

        ORG     8000H

;------------------------------------------------------
; System equates
;------------------------------------------------------
OUTPORT EQU     0C0H            ; LED + TX output port
TIMER   EQU     046H            ; Timer control port
TIMERV  EQU     0FF45H          ; TIMER_RUN variable
RXBHEAD EQU     0FF2EH          ; UART RX buffer head
RXBTAIL EQU     0FF30H          ; UART RX buffer tail
PRINTI  EQU     0BAFH           ; ROM print inline string
MAINMNU EQU     015BH           ; ROM monitor menu
GETCHAR EQU     0BDEH           ; ROM blocking char read

NUMCOLS EQU     7               ; 7 LED columns total
TOTSTEP EQU     38H             ; 56 steps (28 fill + 28 drain)
HALFSTP EQU     1CH             ; 28 = fill/drain boundary

;======================================================
START:
        ; --- Save & stop timer ---
        LDA     TIMERV
        STA     SAVTMR
        XRA     A
        STA     TIMERV
        OUT     TIMER

        ; --- Banner ---
        CALL    PRINTI
        DB      0DH, 0AH
        DB      'ALLWAVE - Full Panel Wave'
        DB      0DH, 0AH
        DB      'ESC=exit'
        DB      0DH, 0AH, 00H

        ; --- Clear all column data ---
        LXI     H, COLDATA
        MVI     B, NUMCOLS
CLRLP:  MVI     M, 00H
        INX     H
        DCR     B
        JNZ     CLRLP

        ; --- Init step counter ---
        XRA     A
        STA     STEP

;======================================================
; MAIN LOOP
;======================================================
MAINLP:
        LDA     STEP

        ; Wrap at 56
        CPI     TOTSTEP
        JC      NOWRAP
        XRA     A
        STA     STEP

NOWRAP:
        ; Fill or drain?
        CPI     HALFSTP
        JNC     DRAIN

        ;--- FILL phase (steps 0-27) ---
        ; col_group = step / 4
        MOV     B, A            ; B = step
        RRC
        RRC
        ANI     07H             ; col_group
        LXI     H, COLORDER
        ADD     L
        MOV     L, A
        MOV     E, M            ; E = physical column index

        ; sub_step = step & 3
        MOV     A, B
        ANI     03H
        MOV     C, A            ; save sub_step
        MOV     A, E
        CPI     06H             ; status column?
        MOV     A, C
        JNZ     NORMFIL
        ADI     04H             ; offset to RFILTBL
NORMFIL:
        LXI     H, FILLTBL
        ADD     L
        MOV     L, A
        MOV     A, M            ; A = fill pattern

        ; COLDATA[E] = fill pattern
        LXI     H, COLDATA
        MOV     D, A
        MOV     A, E
        ADD     L
        MOV     L, A
        MOV     M, D
        JMP     DOSCAN

        ;--- DRAIN phase (steps 28-55) ---
DRAIN:
        SUI     HALFSTP         ; A = drain index (0-27)
        MOV     B, A
        RRC
        RRC
        ANI     07H             ; col_group
        LXI     H, COLORDER
        ADD     L
        MOV     L, A
        MOV     E, M            ; E = physical column index

        MOV     A, B
        ANI     03H
        MOV     C, A
        MOV     A, E
        CPI     06H             ; status column?
        MOV     A, C
        JNZ     NORMDRN
        ADI     04H             ; offset to RFILTBL
NORMDRN:
        LXI     H, FILLTBL
        ADD     L
        MOV     L, A
        MOV     A, M
        XRI     0FH             ; invert for drain

        ; COLDATA[E] = drain pattern
        LXI     H, COLDATA
        MOV     D, A
        MOV     A, E
        ADD     L
        MOV     L, A
        MOV     M, D

;======================================================
; SCAN - multiplex all 7 columns for POV
;======================================================
DOSCAN:
        MVI     D, 14H          ; 20 scan cycles per step

SCANLP:
        LXI     H, COLDATA
        MVI     E, 80H          ; column 0 prefix
        MVI     B, NUMCOLS

SCNCOL:
        MOV     A, M            ; column data (bits 3:0)
        ORA     E               ; merge prefix + TX idle
        OUT     OUTPORT

        MVI     C, 80H          ; 128-iteration delay
COLDLY: DCR     C
        JNZ     COLDLY

        INX     H               ; next column byte
        MOV     A, E
        ADI     10H             ; next column prefix
        MOV     E, A

        DCR     B
        JNZ     SCNCOL

        DCR     D
        JNZ     SCANLP

        ; --- Advance step ---
        LDA     STEP
        INR     A
        STA     STEP

        ; --- Check UART for keypress ---
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

;------------------------------------------------------
; Data
;------------------------------------------------------
SAVTMR: DB      00H
STEP:   DB      00H

; Column data bytes (indexed 0-6 = columns 0-6)
COLDATA:
        DB      00H, 00H, 00H, 00H, 00H, 00H, 00H

; Wave sweep order: right-to-left across the panel
; Physical layout: Address - Status - Data
;   A0-A3 (col 2), A4-A7 (col 3), A8-A11 (col 0),
;   A12-A15 (col 1), Status (col 6), D0-D3 (col 4),
;   D4-D7 (col 5)
COLORDER:
        DB      02H, 03H, 00H, 01H, 06H, 04H, 05H

; Fill patterns for 4 bits within a column
; Address/Data: right-to-left (bit 0 up)
; Status:       left-to-right (bit 3 down)
FILLTBL:
        DB      01H, 03H, 07H, 0FH
RFILTBL:
        DB      08H, 0CH, 0EH, 0FH
