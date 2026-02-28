;=====================================================
; HELLO.ASM - Hello from HEX! test program
; Author: kayto
; Version date: 28/02/2026
; Licensed under the MIT License. See LICENSE file in the project root for full license text.
;
; Monitor program for the Altaid 8800.
; Load via the : (Intel HEX) command, run with G 8000.
;
; Uses ROM routine PRINTI to print an inline string,
; then returns to the monitor main menu.
;
; Assemble: asmx -C 8080 -e -w -o HELLO.hex HELLO.ASM
;=====================================================

        ORG     8000H

;------------------------------------------------------
; ROM routine equates
;------------------------------------------------------
PRINTI      EQU 0BAFH       ; Print inline null-terminated string
MAIN_MENU   EQU 015BH       ; Monitor main menu entry

;======================================================
START:
        CALL    PRINTI
        DB      0DH,0AH,'Hello from HEX!',0DH,0AH,0

        JMP     MAIN_MENU

        END     START
