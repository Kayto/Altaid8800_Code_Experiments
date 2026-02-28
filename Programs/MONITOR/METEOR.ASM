; ========================
; METEOR.ASM - Twin Shooting Stars
; Author: kayto
; Version date: 28/02/2026
; Licensed under the MIT License. See LICENSE file in the project root for full license text.
; ========================
; Assembler syntax: asmx -C 8080 -e -w -o METEOR.hex METEOR.ASM
;
; Monitor program for the Altaid 8800.
; Load via ':' command, run with 'G 8000'.
;
; Two meteors race across all 28 front panel LEDs
; in opposite directions. Each has a bright head
; (all 4 bits lit) and a 3-step fading tail.
; Where they cross, patterns merge together.
;
; Meteor A sweeps right-to-left (address -> data).
; Meteor B sweeps left-to-right (data -> address).
;
; Status column uses reversed bit patterns to
; match its physical LED orientation.
;
; Press any key to exit.
;=====================================================

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
MAINMNU EQU     015BH
GETCHAR EQU     0BDEH
NUMCOLS EQU     7
NUMPOS  EQU     7

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
        DB      'METEOR - Twin Shooting Stars'
        DB      0DH, 0AH
        DB      'ESC=exit'
        DB      0DH, 0AH, 00H

        ; --- Init meteor positions ---
        XRA     A
        STA     HEAD_A          ; A starts at position 0
        MVI     A, 4
        STA     HEAD_B          ; B starts offset at 4

;======================================================
; MAIN LOOP
;======================================================
MAINLP:
        ; --- Clear all column data ---
        LXI     H, COLDATA
        MVI     B, NUMCOLS
CLRLP:  MVI     M, 00H
        INX     H
        DCR     B
        JNZ     CLRLP

        ;--- Meteor A (sweeps right->left) ---
        ;    Trail behind = DEC positions
        LDA     HEAD_A
        MOV     E, A
        MVI     A, 0            ; head segment
        CALL    SETONE
        CALL    DEC_E
        MVI     A, 1            ; tail 1
        CALL    SETONE
        CALL    DEC_E
        MVI     A, 2            ; tail 2
        CALL    SETONE
        CALL    DEC_E
        MVI     A, 3            ; tail 3
        CALL    SETONE

        ;--- Meteor B (sweeps left->right) ---
        ;    Trail behind = INC positions
        LDA     HEAD_B
        MOV     E, A
        MVI     A, 0            ; head segment
        CALL    SETONE
        CALL    INC_E
        MVI     A, 1            ; tail 1
        CALL    SETONE
        CALL    INC_E
        MVI     A, 2            ; tail 2
        CALL    SETONE
        CALL    INC_E
        MVI     A, 3            ; tail 3
        CALL    SETONE

;======================================================
; SCAN - multiplex all 7 columns for POV
;======================================================
        MVI     D, 20H          ; 32 scan cycles per step

SCANLP:
        LXI     H, COLDATA
        MVI     E, 80H          ; column 0 prefix
        MVI     B, NUMCOLS

SCNCOL:
        MOV     A, M
        ORA     E               ; merge prefix + TX idle
        OUT     OUTPORT

        MVI     C, 80H          ; 128-iteration delay
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

        ;--- Advance meteor A (increment position) ---
        LDA     HEAD_A
        INR     A
        CPI     NUMPOS
        JNZ     NWA
        XRA     A
NWA:    STA     HEAD_A

        ;--- Advance meteor B (decrement position) ---
        LDA     HEAD_B
        DCR     A
        JP      NWB
        MVI     A, NUMPOS-1
NWB:    STA     HEAD_B

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
; SETONE - Set one trail segment into COLDATA
;   E = logical sweep position (0-6)
;   A = trail index (0=head, 1-3=tail)
;   ORs pattern into COLDATA[physical_column]
;======================================================
SETONE:
        PUSH    PSW
        ; Get physical column from COLORDER[E]
        LXI     H, COLORDER
        MOV     A, E
        ADD     L
        MOV     L, A
        MOV     C, M            ; C = physical column

        POP     PSW             ; A = trail index

        ; If status column (6), use reversed patterns
        MOV     D, A            ; save trail index
        MOV     A, C
        CPI     06H
        MOV     A, D            ; restore trail index
        JNZ     SO_NORM
        ADI     04H             ; offset to reversed table
SO_NORM:
        ; Look up trail pattern
        LXI     H, TRLTBL
        ADD     L
        MOV     L, A
        MOV     D, M            ; D = pattern

        ; COLDATA[C] |= D
        LXI     H, COLDATA
        MOV     A, C
        ADD     L
        MOV     L, A
        MOV     A, M
        ORA     D
        MOV     M, A
        RET

;======================================================
; DEC_E / INC_E - adjust position with mod-7 wrap
;======================================================
DEC_E:
        DCR     E
        MOV     A, E
        CPI     0FFH
        RNZ
        MVI     E, 6
        RET

INC_E:
        INR     E
        MOV     A, E
        CPI     NUMPOS
        RNZ
        MVI     E, 0
        RET

;------------------------------------------------------
; Data
;------------------------------------------------------
SAVTMR: DB      00H
HEAD_A: DB      00H
HEAD_B: DB      00H

; Column data bytes (indexed 0-6 = physical columns 0-6)
COLDATA:
        DB      00H, 00H, 00H, 00H, 00H, 00H, 00H

; Sweep order: right-to-left across the panel
; Address -> Status -> Data
COLORDER:
        DB      02H, 03H, 00H, 01H, 06H, 04H, 05H

; Trail brightness patterns
; Normal (address/data): fills bit 0 up
TRLTBL:
        DB      0FH             ; head: ****
        DB      07H             ; tail 1: ***-
        DB      03H             ; tail 2: **--
        DB      01H             ; tail 3: *---
; Reversed (status): fills bit 3 down
        DB      0FH             ; head: ****
        DB      0EH             ; tail 1: -***
        DB      0CH             ; tail 2: --**
        DB      08H             ; tail 3: ---*
