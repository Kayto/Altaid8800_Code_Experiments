
; ====================================================
; MORSE.ASM - Morse Code Tape Reader
; Author: kayto
; Version date: 28/02/2026
; Licensed under the MIT License. See LICENSE file in the project root for full license text.
; ====================================================
; Assembler syntax: asmx -C 8080 -e -w -o MORSE.hex MORSE.ASM
;
; Type characters on the serial terminal and watch the Morse
; code scroll across all 28 LEDs like a paper tape reader.
;
; The two LED rows form a continuous 28-bit scrolling strip:
;   Top row:    Address LEDs A15..A0  (16 LEDs)
;   Bottom row: Data D7..D0 + Status S3..S0  (12 LEDs)
;
; New dots and dashes enter at the bottom right (status LEDs)
; and scroll left through data, then across the address row.
;
;   Dot   = 1 unit on
;   Dash  = 3 units on
;   Gap between elements = 1 unit off
;   Gap between letters  = 3 units off
;   Gap between words    = 7 units off
;
; LED display: standard Morse timing (1:3 dot-to-dash ratio).
; MORSE2/MORSE3 use a compact 2-LED dash for a denser display.
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

; =============================================================
START:
        XRA     A
        OUT     46H             ; stop hardware timer

        CALL    PRINTI
        DB      0DH, 0AH
        DB      'MORSE - Tape Reader'
        DB      0DH, 0AH
        DB      'Type to see Morse on LEDs. ESC=exit'
        DB      0DH, 0AH, 0

        ; Clear tape shift register
        XRA     A
        STA     TAPE
        STA     TAPE+1
        STA     TAPE+2
        STA     TAPE+3

; -------------------------------------------------------------
; Main loop - wait for character with active LED refresh
; -------------------------------------------------------------
MAIN:
        CALL    SHOWLED
        CALL    KEYCHK
        JZ      MAIN            ; no key, keep refreshing

        CALL    GETCHAR         ; char in A (already in buffer)

        CPI     1BH             ; ESC = exit
        JZ      EXIT

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
        CALL    UNITDLY
        CALL    SHIFT0
        CALL    UNITDLY

        JMP     MAIN

; -------------------------------------------------------------
; Word space: 7 off-units
; -------------------------------------------------------------
DOWORD:
        MVI     C, 7
DWLP:
        CALL    SHIFT0
        CALL    UNITDLY
        DCR     C
        JNZ     DWLP
        JMP     MAIN

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
; DOMORSE - Process Morse byte (sentinel encoding)
;   Input: A = Morse byte
;   Sentinel encoding: highest set bit is a sentinel marker,
;   remaining bits below it are elements (0=dot, 1=dash).
;   Example: A (.-) = 05H = 00000101
;            sentinel=bit2, then bit1=0(dot), bit0=1(dash)
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
        CALL    UNITDLY
        JMP     MEGAP

MDASH:
        ; Dash: 3 units on
        CALL    SHIFT1
        CALL    UNITDLY
        CALL    SHIFT1
        CALL    UNITDLY
        CALL    SHIFT1
        CALL    UNITDLY

MEGAP:
        ; Inter-element gap: 1 unit off
        CALL    SHIFT0
        CALL    UNITDLY

        DCR     C
        JNZ     MELM

MRDONE:
        POP     B
        RET

; =============================================================
; SHIFT1 / SHIFT0 - Shift a bit into the 28-bit tape register
;   New bit enters at position 0 (status S3, bottom right).
;   Oldest bit falls off position 27 (A15, top left).
; =============================================================
SHIFT1:
        STC                     ; CY = 1
        JMP     DOSHIFT

SHIFT0:
        ORA     A               ; CY = 0

DOSHIFT:
        LDA     TAPE            ; LDA/STA don't affect flags
        RAL                     ; CY -> bit0, bit7 -> CY
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
; UNITDLY - One Morse time unit with active LED refresh
; =============================================================
UNITDLY:
        PUSH    B
        PUSH    D
        ; TIMING: B = refresh count (speed), D = inner pause (brightness)
        ; Increase B to slow down. Keep D >= 60 for flicker-free.
        MVI     B, 80           ; refresh iterations  (speed)
        MVI     D, 100          ; inner pause per refresh (brightness)
UDLP:
        CALL    SHOWLED
        PUSH    D               ; preserve D across inner loop
UDPAUSE:
        DCR     D
        JNZ     UDPAUSE
        POP     D
        DCR     B
        JNZ     UDLP
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
        OUT     0C0H

        ; Col 4 (D0-D3) - TAPE bits 7:4
        LDA     TAPE
        RRC
        RRC
        RRC
        RRC
        ANI     0FH
        ORI     0C0H
        OUT     0C0H

        ; Col 5 (D4-D7) - TAPE+1 bits 3:0
        LDA     TAPE+1
        ANI     0FH
        ORI     0D0H
        OUT     0C0H

        ; Col 2 (A0-A3) - TAPE+1 bits 7:4
        LDA     TAPE+1
        RRC
        RRC
        RRC
        RRC
        ANI     0FH
        ORI     0A0H
        OUT     0C0H

        ; Col 3 (A4-A7) - TAPE+2 bits 3:0
        LDA     TAPE+2
        ANI     0FH
        ORI     0B0H
        OUT     0C0H

        ; Col 0 (A8-A11) - TAPE+2 bits 7:4
        LDA     TAPE+2
        RRC
        RRC
        RRC
        RRC
        ANI     0FH
        ORI     80H
        OUT     0C0H

        ; Col 1 (A12-A15) - TAPE+3 bits 3:0
        LDA     TAPE+3
        ANI     0FH
        ORI     90H
        OUT     0C0H

        RET

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
        JNZ     GOTKEY
        MOV     A, L
        CMP     E
GOTKEY:
        POP     H
        RET

; =============================================================
; Morse code lookup tables (sentinel encoding)
;   Highest set bit = sentinel, remaining bits = elements
;   Element bit: 0 = dot (dit), 1 = dash (dah)
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

        END     START
