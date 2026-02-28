
; ====================================================
; MORSE3.ASM - Morse Code Tape Reader with Audio Tones
; Author: kayto
; Version date: 28/02/2026
; Licensed under the MIT License. See LICENSE file in the project root for full license text.
; ====================================================
; Assembler syntax: asmx -C 8080 -e -w -o MORSE3.hex MORSE3.ASM
;
; Type characters on the serial terminal and watch Morse code
; scroll across all 28 LEDs while hearing the corresponding
; dits and dahs.  The tone plays during on-elements (dots and
; dashes) and is silent during gaps.
;
; The two LED rows form a continuous 28-bit scrolling strip:
;   Top row:    Address LEDs A15..A0  (16 LEDs)
;   Bottom row: Data D7..D0 + Status S3..S0  (12 LEDs)
;
; New dots and dashes enter at the bottom right (status LEDs)
; and scroll left through data, then across the address row.
;
;   Dot   = 1 unit on  (tone plays, 1 LED lit)
;   Dash  = 2 units on (tone plays, 2 LEDs lit)
;   Gap between elements = 1 unit off (silent)
;   Gap between letters  = 3 units off (silent)
;   Gap between words    = 7 units off (silent)
;
; LED display: compact Morse timing (1:2 dot-to-dash ratio).
; MORSE.ASM uses the standard 1:3 ratio for strict Morse compliance.
;
; Supports A-Z, 0-9 and space.  Press ESC to exit.
; ====================================================

        ORG     8000H

; --- ROM entry points ---
PRINTI  EQU     0BAFH
GETCHAR EQU     0BDEH           ; blocking read with echo
MAINMNU EQU     015BH

; --- UART RX buffer pointers ---
RXBHEAD EQU     0FF2EH
RXBTAIL EQU     0FF30H

; --- Timer ---
TMRVAL  EQU     0FF45H

; --- Hardware ports ---
OUTPORT EQU     0C0H            ; LED + TX output port
CASSETTE EQU    044H            ; Cassette output port

; --- Tone timing ---
; TONEDLY = half-period delay for the square-wave tone.
; Each inner loop iteration is ~15 cycles.
TONEDLY EQU     50              ; ~1.2 kHz tone
SPEED   EQU     40              ; refresh iterations per unit
TBUFSZ  EQU     32              ; type-ahead buffer size

; =============================================================
START:
        XRA     A
        OUT     46H             ; stop hardware timer

        ; Silence cassette
        OUT     CASSETTE

        CALL    PRINTI
        DB      0DH, 0AH
        DB      'MORSE3 - Tape Reader + Audio'
        DB      0DH, 0AH
        DB      'Type to see/hear Morse. ESC=exit'
        DB      0DH, 0AH, 0

        ; Clear tape shift register
        XRA     A
        STA     TAPE
        STA     TAPE+1
        STA     TAPE+2
        STA     TAPE+3
        STA     CASSOUT

        ; Clear type-ahead buffer
        STA     TBCNT
        STA     TBWR
        STA     TBRD

; -------------------------------------------------------------
; Main loop - wait for character with active LED refresh
; -------------------------------------------------------------
MAIN:
        ; Drain any pending UART chars into type-ahead buffer
        CALL    DRAIN

        ; Check type-ahead buffer first
        LDA     TBCNT
        ORA     A
        JNZ     TBPOP           ; have buffered char, use it

        ; Nothing buffered - refresh LEDs and loop
        CALL    SHOWLED
        JMP     MAIN

; Read one char from type-ahead buffer
TBPOP:
        LXI     H, TBUF
        LDA     TBRD
        ADD     L
        MOV     L, A
        MOV     A, H
        ACI     0
        MOV     H, A
        MOV     A, M            ; A = buffered char
        PUSH    PSW
        LDA     TBRD
        INR     A
        CPI     TBUFSZ
        JC      TBNW
        XRA     A
TBNW:   STA     TBRD
        LDA     TBCNT
        DCR     A
        STA     TBCNT
        POP     PSW

        CPI     1BH             ; ESC = exit
        JZ      EXIT

        CPI     0DH             ; CR = clear display
        JZ      DOCLEAR

        CPI     20H             ; space = word gap
        JZ      DOWORD

        ; Convert lowercase to uppercase
        CPI     'a'
        JC      NOTLC
        CPI     'z'+1
        JNC     NOTLC
        SUI     20H
NOTLC:
        ; Look up A-Z
        CPI     'A'
        JC      TRYNUM
        CPI     'Z'+1
        JNC     MAIN            ; unsupported, ignore
        SUI     'A'
        LXI     H, MTBL_AZ
        JMP     LOOKUP

TRYNUM:
        ; Look up 0-9
        CPI     '0'
        JC      MAIN
        CPI     '9'+1
        JNC     MAIN
        SUI     '0'
        LXI     H, MTBL_09

LOOKUP:
        ; A = table index, HL = table base
        ADD     L
        MOV     L, A
        MOV     A, H
        ACI     0
        MOV     H, A
        MOV     A, M            ; Morse byte (sentinel encoding)

        ORA     A
        JZ      MAIN            ; 0 = invalid, skip

        CALL    DOMORSE

        ; Inter-letter gap: 2 more off-units (1 already from DOMORSE)
        CALL    SHIFT0
        CALL    UNITOFF
        CALL    SHIFT0
        CALL    UNITOFF

        JMP     MAIN

; -------------------------------------------------------------
; Return: clear display and send CR+LF to serial
; -------------------------------------------------------------
DOCLEAR:
        CALL    PRINTI
        DB      0DH, 0AH, 0
        MVI     C, 28
DCLRLP:
        CALL    SHIFT0
        DCR     C
        JNZ     DCLRLP
        CALL    SHOWLED
        JMP     MAIN

; -------------------------------------------------------------
; Word space: 7 off-units total (3 already from inter-letter)
; -------------------------------------------------------------
DOWORD:
        MVI     C, 4
DWLP:
        CALL    SHIFT0
        CALL    UNITOFF
        DCR     C
        JNZ     DWLP
        JMP     MAIN

; -------------------------------------------------------------
; Exit to monitor
; -------------------------------------------------------------
EXIT:
        ; Silence cassette
        XRA     A
        OUT     CASSETTE

        LDA     TMRVAL
        OUT     46H             ; restore timer ISR
        CALL    PRINTI
        DB      0DH, 0AH
        DB      'Done.'
        DB      0DH, 0AH, 0
        JMP     MAINMNU

; =============================================================
; DOMORSE - Process Morse byte (sentinel encoding)
;   Input: A = Morse byte
;   Sentinel encoding: highest set bit is a sentinel marker,
;   remaining bits below it are elements (0=dot, 1=dash).
; =============================================================
DOMORSE:
        PUSH    B
        MOV     B, A            ; B = work copy
        MVI     C, 8            ; bit counter

        ; Left-justify: shift until sentinel reaches bit 7
FNDSEN:
        MOV     A, B
        ADD     A               ; shift left, bit7 -> CY
        MOV     B, A
        JC      GOTSEN          ; CY=1: sentinel found
        DCR     C
        JNZ     FNDSEN
        JMP     MRDONE          ; no sentinel (shouldn't happen)

GOTSEN:
        DCR     C               ; C = remaining element bits
        JZ      MRDONE          ; no elements after sentinel

        ; Process each element from MSB down
MELM:
        MOV     A, B
        ADD     A               ; next element bit -> CY
        MOV     B, A
        JC      MDASH

        ; Dot: 1 unit on
        CALL    SHIFT1
        CALL    UNITON
        CALL    CASSOFF
        JMP     MEGAP

MDASH:
        ; Dash: 3 units tone, only 2 LEDs lit (compact display)
        CALL    SHIFT1
        CALL    UNITON          ; unit 1: LED on, tone
        CALL    SHIFT1
        CALL    UNITON          ; unit 2: LED on, tone
        CALL    UNITON          ; unit 3: tone only (no shift)
        CALL    CASSOFF

MEGAP:
        ; Inter-element gap: 1 unit off (silent)
        CALL    SHIFT0
        CALL    UNITOFF

        DCR     C
        JNZ     MELM

MRDONE:
        POP     B
        RET

; =============================================================
; SHIFT1 / SHIFT0 - Shift a bit into the 28-bit tape register
; =============================================================
SHIFT1:
        STC                     ; CY = 1
        JMP     DOSHIFT

SHIFT0:
        ORA     A               ; CY = 0

DOSHIFT:
        LDA     TAPE
        RAL
        STA     TAPE
        LDA     TAPE+1
        RAL
        STA     TAPE+1
        LDA     TAPE+2
        RAL
        STA     TAPE+2
        LDA     TAPE+3
        RAL
        ANI     0FH             ; keep only 4 bits (28 total)
        STA     TAPE+3
        RET

; =============================================================
; UNITON - One Morse time unit with tone
; =============================================================
UNITON:
        PUSH    B
        PUSH    D
        MVI     B, SPEED        ; refresh iterations per unit

UONLP:
        CALL    SHOWLED         ; refresh LEDs once

        ; Play several tone half-cycles per LED refresh
        MVI     D, 6            ; half-cycles per refresh
TONLP:
        ; Toggle cassette output
        LDA     CASSOUT
        XRI     01H
        STA     CASSOUT
        OUT     CASSETTE

        ; Tone half-period delay
        MVI     E, TONEDLY
TONDLY: DCR     E
        JNZ     TONDLY

        DCR     D
        JNZ     TONLP

        DCR     B
        JNZ     UONLP

        POP     D
        POP     B
        RET

; =============================================================
; CASSOFF - Silence cassette output (clean tone cutoff)
; =============================================================
CASSIOFF:
CASSOFF:
        XRA     A
        STA     CASSOUT
        OUT     CASSETTE
        RET

; =============================================================
; UNITOFF - One Morse time unit with LED refresh, NO tone
;
; Same total duration as UNITDOT/UNITDAH but cassette stays
; silent.  Uses DAHDLY for the delay to roughly match timing.
; =============================================================
UNITOFF:
        PUSH    B
        PUSH    D
        MVI     B, SPEED        ; same refresh count as UNITON

UOFFLP:
        CALL    SHOWLED         ; refresh LEDs once

        ; Match UNITON's tone timing with equivalent delay
        MVI     D, 6            ; same loop count
SILHC:
        ; Equivalent delay to tone half-cycle (no toggle)
        MVI     E, TONEDLY
SILDLY: DCR     E
        JNZ     SILDLY

        DCR     D
        JNZ     SILHC

        DCR     B
        JNZ     UOFFLP

        POP     D
        POP     B
        RET

; =============================================================
; SHOWLED - Display 28-bit tape across all 7 LED columns
;
; Tape bit-to-LED mapping (position 0 = bottom right):
;   Bits  3:0  -> Col 6  Status S3..S0 (bit-reversed for hw)
;   Bits  7:4  -> Col 4  Data D0..D3
;   Bits 11:8  -> Col 5  Data D4..D7
;   Bits 15:12 -> Col 2  Addr A0..A3
;   Bits 19:16 -> Col 3  Addr A4..A7
;   Bits 23:20 -> Col 0  Addr A8..A11
;   Bits 27:24 -> Col 1  Addr A12..A15
; =============================================================
SHOWLED:
        ; Col 6 (Status, bottom right) - bit-reversed
        LDA     TAPE
        ANI     0FH
        LXI     H, REVTBL
        ADD     L
        MOV     L, A
        MOV     A, H
        ACI     0
        MOV     H, A
        MOV     A, M            ; reversed nibble
        ORI     0E0H
        OUT     OUTPORT

        ; Col 4 (D0-D3) - TAPE bits 7:4
        LDA     TAPE
        RRC
        RRC
        RRC
        RRC
        ANI     0FH
        ORI     0C0H
        OUT     OUTPORT

        ; Col 5 (D4-D7) - TAPE+1 bits 3:0
        LDA     TAPE+1
        ANI     0FH
        ORI     0D0H
        OUT     OUTPORT

        ; Col 2 (A0-A3) - TAPE+1 bits 7:4
        LDA     TAPE+1
        RRC
        RRC
        RRC
        RRC
        ANI     0FH
        ORI     0A0H
        OUT     OUTPORT

        ; Col 3 (A4-A7) - TAPE+2 bits 3:0
        LDA     TAPE+2
        ANI     0FH
        ORI     0B0H
        OUT     OUTPORT

        ; Col 0 (A8-A11) - TAPE+2 bits 7:4
        LDA     TAPE+2
        RRC
        RRC
        RRC
        RRC
        ANI     0FH
        ORI     80H
        OUT     OUTPORT

        ; Col 1 (A12-A15) - TAPE+3 bits 3:0
        LDA     TAPE+3
        ANI     0FH
        ORI     90H
        OUT     OUTPORT

        ; Blank display so last column doesn't stay lit
        ; Use 80H (not 00H) to keep bit 7 / TX high
        MVI     A, 80H
        OUT     OUTPORT

        RET

; =============================================================
; DRAIN - Move all pending UART chars into type-ahead buffer
; =============================================================
DRAIN:
        CALL    KEYCHK
        RZ                      ; nothing in UART
        CALL    GETCHAR         ; A = char from ROM buffer
        ; Store in type-ahead buffer if room
        PUSH    H
        PUSH    PSW
        LDA     TBCNT
        CPI     TBUFSZ
        JNC     DRFUL           ; buffer full, discard
        POP     PSW
        PUSH    PSW
        LXI     H, TBUF
        LDA     TBWR
        ADD     L
        MOV     L, A
        MOV     A, H
        ACI     0
        MOV     H, A
        POP     PSW
        MOV     M, A            ; store char
        PUSH    PSW
        LDA     TBWR
        INR     A
        CPI     TBUFSZ
        JC      DRNW
        XRA     A
DRNW:   STA     TBWR
        LDA     TBCNT
        INR     A
        STA     TBCNT
DRFUL:  POP     PSW
        POP     H
        JMP     DRAIN           ; check for more

; =============================================================
; KEYCHK - Test for keypress (Z = none, NZ = key waiting)
; =============================================================
KEYCHK:
        PUSH    H
        LHLD    RXBHEAD
        XCHG
        LHLD    RXBTAIL
        MOV     A, H
        CMP     D
        JNZ     GKEY
        MOV     A, L
        CMP     E
GKEY:
        POP     H
        RET

; =============================================================
; Morse code lookup tables (sentinel encoding)
; =============================================================
MTBL_AZ:
        DB      05H             ; A  .-
        DB      18H             ; B  -...
        DB      1AH             ; C  -.-.
        DB      0CH             ; D  -..
        DB      02H             ; E  .
        DB      12H             ; F  ..-.
        DB      0EH             ; G  --.
        DB      10H             ; H  ....
        DB      04H             ; I  ..
        DB      17H             ; J  .---
        DB      0DH             ; K  -.-
        DB      14H             ; L  .-..
        DB      07H             ; M  --
        DB      06H             ; N  -.
        DB      0FH             ; O  ---
        DB      16H             ; P  .--.
        DB      1DH             ; Q  --.-
        DB      0AH             ; R  .-.
        DB      08H             ; S  ...
        DB      03H             ; T  -
        DB      09H             ; U  ..-
        DB      11H             ; V  ...-
        DB      0BH             ; W  .--
        DB      19H             ; X  -..-
        DB      1BH             ; Y  -.--
        DB      1CH             ; Z  --..

MTBL_09:
        DB      3FH             ; 0  -----
        DB      2FH             ; 1  .----
        DB      27H             ; 2  ..---
        DB      23H             ; 3  ...--
        DB      21H             ; 4  ....-
        DB      20H             ; 5  .....
        DB      30H             ; 6  -....
        DB      38H             ; 7  --...
        DB      3CH             ; 8  ---..
        DB      3EH             ; 9  ----.

; 4-bit reversal table for status column hardware
REVTBL:
        DB      00H, 08H, 04H, 0CH, 02H, 0AH, 06H, 0EH
        DB      01H, 09H, 05H, 0DH, 03H, 0BH, 07H, 0FH

; =============================================================
; Variables
; =============================================================
TAPE:   DS      4               ; 28-bit shift register (LE)
CASSOUT: DB     00H             ; cassette output state
TBUF:   DS      TBUFSZ          ; type-ahead circular buffer
TBCNT:  DB      00H             ; chars in buffer
TBWR:   DB      00H             ; write index
TBRD:   DB      00H             ; read index
        END     START
