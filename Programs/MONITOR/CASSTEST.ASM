; ====================================================
; CASSTEST.ASM - Cassette Port Test
; Author: kayto
; Version date: 28/02/2026
; Licensed under the MIT License. See LICENSE file in the project root for full license text.
; ====================================================
; Assembler syntax: asmx -C 8080 -e -w -o CASSTEST.hex CASSTEST.ASM
;
; Monitor program for the Altaid 8800.
; Load via the : (Intel HEX) command, run with G 8000.
;
; Tests the cassette output port (44H) by toggling it
; to produce square-wave tones.  Connect a small
; speaker or buzzer to the cassette output to hear
; the output.
;
; No LEDs are driven - this keeps the tone generation
; loop tight and free of timing artifacts.
;
; Controls via serial terminal:
;   1-8   Select tone frequency (1=lowest, 8=highest)
;   S     Sweep mode - auto-sweep through all tones
;   SPACE Silence (stop tone)
;   ESC   Exit to monitor
;
; Port 44H is a simple output latch.  Writing 1 or 0
; sets the cassette output line high or low.  Toggling
; it at different rates creates different frequencies.
;
; Timer ISR must be stopped to prevent C0H conflicts.
; UART RX buffer is checked directly for commands.
;
; Assemble: asmx -C 8080 -e -w -o CASSTEST.hex CASSTEST.ASM
; ====================================================

        ORG     8000H

;------------------------------------------------------
; ROM / hardware equates
;------------------------------------------------------
PRINTI      EQU 0BAFH       ; Print inline null-terminated string
MAIN_MENU   EQU 015BH       ; Monitor main menu entry
OUTPORT     EQU 0C0H        ; LED + TX output port
CASSETTE    EQU 044H        ; Cassette output port
TIMER       EQU 046H        ; Timer control port
TIMERV      EQU 0FF45H      ; TIMER_RUN variable in RAM
RXBHEAD     EQU 0FF2EH      ; UART RX buffer head pointer
RXBTAIL     EQU 0FF30H      ; UART RX buffer tail pointer
GETCHAR     EQU 0BDEH       ; ROM blocking char read

;======================================================
START:
        ; --- Print banner ---
        CALL    PRINTI
        DB      0DH,0AH
        DB      'CASSTEST - Cassette Port Test',0DH,0AH
        DB      '1-8=tone  S=sweep  SPACE=off  ESC=exit'
        DB      0DH,0AH,0

        ; --- Save and stop timer ---
        LDA     TIMERV
        STA     SAVTMR
        XRA     A
        STA     TIMERV
        OUT     TIMER

        ; --- Init state ---
        MVI     A,04H           ; start with mid-range tone
        STA     TONEIDX
        XRA     A
        STA     SWEEP           ; sweep mode off
        STA     CASSOUT         ; cassette output state
        STA     SWPDIR          ; sweep direction (0=up)

        ; --- Announce initial tone ---
        CALL    PRINTI
        DB      'Tone: 4',0DH,0AH,0

;------------------------------------------------------
; Main loop
;------------------------------------------------------
MAINLP:
        ; --- Check for serial keypress ---
        LDA     RXBHEAD
        LXI     H,RXBTAIL
        SUB     M
        JZ      NOKEY

        ; Key available - read it
        CALL    GETCHAR

        ; ESC = exit
        CPI     1BH
        JZ      EXIT

        ; SPACE = silence
        CPI     20H
        JZ      SILENCE

        ; 'S' or 's' = sweep mode toggle
        CPI     'S'
        JZ      SETSWEEP
        CPI     's'
        JZ      SETSWEEP

        ; '1'-'8' = select tone
        CPI     '1'
        JC      NOKEY           ; below '1', ignore
        CPI     '9'
        JNC     NOKEY           ; above '8', ignore

        ; Convert ASCII '1'-'8' to index 1-8
        SUI     '0'
        STA     TONEIDX

        ; Turn off sweep when manually selecting
        XRA     A
        STA     SWEEP

        ; Print selected tone
        CALL    PRINTI
        DB      'Tone: ',0
        LDA     TONEIDX
        ADI     '0'
        CALL    PUTCH
        CALL    PRINTI
        DB      0DH,0AH,0

NOKEY:

;------------------------------------------------------
; Generate tone: fully self-contained loop.
; Sweep uses a 16-bit countdown timer decremented by
; the tone delay value each half-cycle, so every tone
; holds for the same wall-clock duration.
;------------------------------------------------------
DOTONE:
        LDA     TONEIDX
        ORA     A
        JZ      DOSILENCE       ; index 0 = silence

        ; --- Look up half-period delay from table ---
        CALL    LOADTONE        ; sets CURDELAY from TONEIDX

        ; --- Continuous tone loop ---
TONELP:
        ; Toggle cassette output
        LDA     CASSOUT
        XRI     01H
        STA     CASSOUT
        OUT     CASSETTE

        ; Half-period delay
        LDA     CURDELAY
        MOV     B,A
HDLY:   DCR     B
        JNZ     HDLY

        ; Check for keypress
        LDA     RXBHEAD
        LXI     H,RXBTAIL
        SUB     M
        JNZ     MAINLP          ; key pressed - go handle it

        ; --- Sweep timer ---
        LDA     SWEEP
        ORA     A
        JZ      TONELP          ; not sweeping

        ; Subtract CURDELAY from 16-bit sweep timer
        LDA     CURDELAY
        MOV     B,A
        LHLD    SWPTMR
        MOV     A,L
        SUB     B
        MOV     L,A
        MOV     A,H
        SBI     0
        MOV     H,A
        SHLD    SWPTMR
        JNC     TONELP          ; timer not expired

        ; --- Timer expired: advance to next tone ---
        LXI     H,SWPTIME
        SHLD    SWPTMR          ; reload timer

        LDA     SWPDIR
        ORA     A
        JNZ     SWPDN

        ; Sweeping up
        LDA     TONEIDX
        INR     A
        STA     TONEIDX
        CPI     9
        JC      SWPUPD
        MVI     A,8
        STA     TONEIDX
        MVI     A,1
        STA     SWPDIR
        JMP     SWPUPD

SWPDN:  ; Sweeping down
        LDA     TONEIDX
        DCR     A
        STA     TONEIDX
        ORA     A
        JNZ     SWPUPD
        MVI     A,1
        STA     TONEIDX
        XRA     A
        STA     SWPDIR

        ; Reload delay for new tone and continue
SWPUPD: CALL    LOADTONE
        JMP     TONELP

; Sweep hold time (16-bit). Each half-cycle subtracts
; CURDELAY, so elapsed time is constant regardless of
; pitch.  ~30000 gives roughly 0.5 sec per tone step.
SWPTIME EQU     30000

;------------------------------------------------------
; LOADTONE - Load CURDELAY from TONETBL[TONEIDX-1]
;------------------------------------------------------
LOADTONE:
        LDA     TONEIDX
        DCR     A
        MOV     E,A
        MVI     D,0
        LXI     H,TONETBL
        DAD     D
        MOV     A,M
        STA     CURDELAY
        RET

;------------------------------------------------------
; Silence mode - idle loop (no tone)
;------------------------------------------------------
DOSILENCE:
        ; Cassette output low
        XRA     A
        STA     CASSOUT
        OUT     CASSETTE

        ; Small idle delay so we don't spin too fast
        MVI     B,0
SILL:   DCR     B
        JNZ     SILL

        JMP     MAINLP

;------------------------------------------------------
; SILENCE - user pressed space
;------------------------------------------------------
SILENCE:
        XRA     A
        STA     TONEIDX
        STA     SWEEP
        STA     CASSOUT
        OUT     CASSETTE

        CALL    PRINTI
        DB      'Off',0DH,0AH,0
        JMP     MAINLP

;------------------------------------------------------
; SETSWEEP - toggle sweep mode
;------------------------------------------------------
SETSWEEP:
        LDA     SWEEP
        XRI     01H
        STA     SWEEP

        ORA     A
        JZ      SWPOFF

        ; Sweep on - init
        MVI     A,1
        STA     TONEIDX
        XRA     A
        STA     SWPDIR
        LXI     H,SWPTIME
        SHLD    SWPTMR

        CALL    PRINTI
        DB      'Sweep ON',0DH,0AH,0
        JMP     MAINLP

SWPOFF:
        CALL    PRINTI
        DB      'Sweep OFF',0DH,0AH,0
        JMP     MAINLP

;------------------------------------------------------
; Exit: silence cassette, restore timer, return
;------------------------------------------------------
EXIT:
        ; Cassette off
        XRA     A
        OUT     CASSETTE

        ; Restore timer
        LDA     SAVTMR
        STA     TIMERV
        OUT     TIMER

        CALL    PRINTI
        DB      0DH,0AH,'Done.',0DH,0AH,0

        JMP     MAIN_MENU

;------------------------------------------------------
; PUTCH - Print character in A via ROM routine
;------------------------------------------------------
PUTCH   EQU     0BF6H           ; ROM PUT_CHAR

;------------------------------------------------------
; Tone half-period table (flat delay loop count)
; Each iteration ~ 15 cycles.  Approx frequencies
; assume ~2 MHz clock + toggle overhead (~50 cyc).
;------------------------------------------------------
TONETBL:
        DB      250             ; tone 1 - ~200 Hz
        DB      200             ; tone 2 - ~260 Hz
        DB      150             ; tone 3 - ~350 Hz
        DB      110             ; tone 4 - ~490 Hz
        DB      80              ; tone 5 - ~690 Hz
        DB      55              ; tone 6 - ~1050 Hz
        DB      35              ; tone 7 - ~1700 Hz
        DB      20              ; tone 8 - ~3000 Hz

;------------------------------------------------------
; Data
;------------------------------------------------------
TONEIDX:    DB  04H            ; current tone (1-8, 0=off)
CASSOUT:    DB  00H            ; current cassette output state
SWEEP:      DB  00H            ; sweep mode flag
SWPDIR:     DB  00H            ; sweep direction (0=up, 1=down)
SWPTMR:     DW  30000          ; 16-bit sweep countdown timer
CURDELAY:   DB  00H            ; current tone delay
SAVTMR:     DB  00H            ; saved timer state

        END     START
