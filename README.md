# Altaid 8800

**A custom Intel 8080A computer system designed by Lee Hart with monitor by Josh Bensadon, capable of running CP/M-80.**

[https://sunrise-ev.com/8080.htm](https://sunrise-ev.com/8080.htm)

The Altaid 8800 is a retrocomputer inspired by the MITS Altair 8800, featuring a front panel with switches and LEDs, a 512KB banked RAM disk, shadow ROM architecture, and a built-in monitor/BIOS ROM (`altaid05`).

This repo provides some program samples and experiments.

- - -

## Files in This Repository


```
├── README.md
├── Programs/
│   └── MONITOR/              Monitor-loadable HEX programs
│       ├── ALLWAVE.ASM/.HEX/.LST   Full panel wave demo
│       ├── BUTTONS.ASM/.HEX/.LST   Front panel switch test
│       ├── CASSTEST.ASM/.HEX/.LST  Cassette port tone test
│       ├── COLLATZ.ASM/.HEX/.LST   Collatz conjecture explorer
│       ├── FPCLOCK28.ASM/.HEX/.LST 28-LED tally clock
│       ├── HELLO.ASM/.HEX/.LST     Hello World test program
│       ├── METEOR.ASM/.HEX/.LST    Twin shooting stars demo
│       ├── MORSE.ASM/.HEX/.LST     Morse code tape reader
│       ├── MORSE2.ASM/.HEX/.LST    Compact Morse (blink=dash)
│       ├── MORSE3.ASM/.HEX/.LST    Morse tape + audio tones
│       ├── WALK.ASM/.HEX/.LST      Walking bit data LED demo
│       ├── compile.py              Cross-assembler (asmx -> .HEX)
│       └── compile_local.example.py Example local config for asmx path
```

- - -

## Building Programs

Programs can be assembled on a PC using asmx (cross-assembler).

### Cross-Assembling on PC

Requires [asmx](http://xi6.com/projects/asmx/) multi-CPU assembler.

**Monitor .HEX programs** (Intel HEX for terminal load):

```
cd Programs/MONITOR
python compile.py                  # all programs
python compile.py HELLO.ASM        # one program
python compile.py WALK.ASM -v      # with listing
```

Both scripts use `asmx.exe` with `-C 8080`. Configure the path in a file named  `compile_local.py` if required. An example `compile_local_example.py`is provided, once updated rename to `compile_local/py`.

- - -

## Monitor Programs

Standalone programs loaded into memory via the monitor's Intel HEX load capability. These run outside CP/M at addresses above `8000H` and use ROM routines directly.

### HELLO — Hello World

Minimal test program (26 bytes at `8000H`). Prints a message using the ROM's `PRINTI` routine and returns to the monitor menu.

```
> (send HELLO.HEX via term)
HEX TRANSFER COMPLETE ERRORS=00
> G 8000

Hello from HEX!
>
```

### WALK — Walking Bit

Walking bit demo for the data LEDs (135 bytes at `8000H`). A single lit LED moves across all 8 data LEDs using proper column 4/5 multiplexing. Stops the hardware timer for direct port `C0H` control, checks UART for exit, then restores the timer and returns to the monitor.

```
> (send WALK.HEX via Term)
HEX TRANSFER COMPLETE ERRORS=00
> G 8000
(data LEDs animate - ESC=exit)
Done.
>
```

### ALLWAVE — Full Panel Wave

Wave wash across ALL front panel LEDs (283 bytes at `8000H`). Sweeps 28 LEDs — 16 address + 4 status + 8 data — filling right-to-left then draining, following the physical panel layout: address → status → data. Status LEDs fill left-to-right (opposite direction) to match their physical orientation. Multiplexes all 7 LED columns for POV.

```
> (send ALLWAVE.HEX via Term)
HEX TRANSFER COMPLETE ERRORS=00
> G 8000

ALLWAVE - Full Panel Wave
(all LEDs animate - ESC=exit)
Done.
>
```

### METEOR — Twin Shooting Stars

Two meteors race across all 28 LEDs in opposite directions (327 bytes at `8000H`). Each has a bright 4-LED head and a 3-step fading tail. Meteor A sweeps right-to-left, meteor B sweeps left-to-right. Where they cross, the patterns merge together via OR, creating bright flares at the intersection.

```
> (send METEOR.HEX via Term)
HEX TRANSFER COMPLETE ERRORS=00
> G 8000

METEOR - Twin Shooting Stars
(LEDs animate - ESC=exit)
Done.
>
```

### MORSE / MORSE2 / MORSE3 — Morse Code Tape Readers

Type characters on the serial terminal and watch Morse code scroll across all 28 LEDs like a paper tape reader. The two LED rows form a continuous 28-bit scrolling strip — new dots and dashes enter at the bottom right (status LEDs) and scroll left through data, then across the address row. All three support A-Z, 0-9 and space, use sentinel-encoded lookup tables, and exit with ESC.

| Version | Size | Dash Display | Audio | Notes |
| ------- | ---- | ------------ | ----- | ----- |
| MORSE | 491 B | 3 LEDs (standard 1:3 ratio) | No | Standard Morse timing, 7-unit word gap |
| MORSE2 | 494 B | 2 LEDs (compact) | No | Compact display |
| MORSE3 | 696 B | 2 LEDs (compact) | Yes (\~1.2 kHz via port 44H) | 32-byte type-ahead buffer, Enter clears display, 7-unit word gap |

**Display compactness:** MORSE uses the standard 3-LED dash (strict Morse compliance). MORSE2 and MORSE3 use a 2-LED dash to fit more of the message on the 28-LED strip. In MORSE3, the audio tone still plays for the full 3-unit dash duration even though only 2 LEDs are lit.

**MORSE3 audio:** Connect a speaker or piezo buzzer to the cassette output port (44H). The tone plays during on-elements and is silent during gaps.

```
MORSE - Tape Reader
Type to see Morse on LEDs. ESC=exit

MORSE2 - Compact Tape Reader
Type to see Morse on LEDs. ESC=exit

MORSE3 - Tape Reader + Audio
Type to see/hear Morse. ESC=exit
```

```
SOS displayed (MORSE2/MORSE3 compact):  *-*-*---**-**-**---*-*-*
  * = lit LED  - = off LED
  dot = 1 wide, dash = 2 wide
```

### COLLATZ — Conjecture Explorer

Puts the 8080 to work on the famous Collatz conjecture (598 bytes at `8000H`). Starting from N=2 and auto-advancing, the CPU iterates: if even, divide by 2; if odd, compute 3N+1. The conjecture says every positive integer eventually reaches 1 — but the path is chaotic. Internal arithmetic is 24-bit so intermediate values that overflow 16 bits are handled correctly.

| LEDs | Shows |
| ---- | ----- |
| Address (A0-A15) | Current value in binary — bounces wildly |
| Data (D0-D7) | Step count (wraps at 256) |
| Status S3+S1 | Odd step (3N+1 — value grows) |
| Status S2+S0 | Even step (N/2 — value shrinks) |
| Status all | Goal reached (N=1) |

When a number reaches 1 the LEDs flash in celebration, then the next starting number loads automatically. Serial output logs one line per number:

```
> (send COLLATZ.HEX via Term)
HEX TRANSFER COMPLETE ERRORS=00
> G 8000

COLLATZ - Conjecture Explorer
N=2: 1
N=3: 7
N=4: 2
N=5: 5
N=6: 8
N=7: 16
N=27: 111
(ESC=exit)
Done.
>
```

### FPCLOCK28 — 28-LED Tally Clock

Human-readable clock using all 28 LEDs (628 bytes at `8000H`). Alternates between two screens every \~3 seconds with a brief flash on transition.

**NOTE**: I have yet to fix the timing accuracy :)

**Hour screen** — count the lit LEDs across address + data = hour (0-23, 24h format):

```
Data      Status  Address
--------  .H..    --------***-----  =  3:xx  (3 LEDs lit)
--------  .H..    ************----  = 12:xx  (12 LEDs lit)
*******-  .H..    ****************  = 23:xx  (23 LEDs lit)
```

**Minute screen** — three tally groups:

```
Data      Status  Addr high   Addr low
(x1 min)          (x10 min)   (x5 min)

**------  ..M.    ***-----    *-------  = 30+5+2 = 37 min
****----  P.M.    *****---    *-------  = 50+5+4 = 59 min
--------  ..M.    *-------    --------  = 10+0+0 = 10 min
```

**Status LEDs** (always visible, left to right):

* **S3**: Blinks each second
* **S2**: PM indicator (lit = PM)
* **S1**: Lit when showing hours (H)
* **S0**: Lit when showing minutes (M)

```
> (send FPCLOCK28.HEX via Term)
HEX TRANSFER COMPLETE ERRORS=00
> G 8000

28-LED Tally Clock
Hours (00-23): 14
Minutes (00-59): 37
Running... ESC=exit
(LEDs show clock - ESC=exit)
Done.
>
```

### BUTTONS — Switch Test

Interactive test program for all 11 software-readable buttons (507 bytes at `8000H`). Reads the front panel switches by scanning columns 4, 5, and 6 through the multiplexed I/O bus. Pressed buttons light the corresponding LEDs in real time — data switches D0–D7 mirror on the data LEDs, control switches RUN/MODE/NEXT mirror on the status LEDs (S0/S1/S2).

When the button state changes, a status line is printed on the serial terminal showing the hex value and which buttons are pressed:

```
> (send BUTTONS.HEX via Term)
HEX TRANSFER COMPLETE ERRORS=00
> G 8000

BUTTONS - Switch Test
Press buttons to test. ESC=exit
D=01 Ctl=00  .. .. .. .. .. .. .. D0  ... ... ...
D=03 Ctl=00  .. .. .. .. .. .. D1 D0  ... ... ...
D=80 Ctl=00  D7 .. .. .. .. .. .. ..  ... ... ...
D=00 Ctl=01  .. .. .. .. .. .. .. ..  RUN ... ...
D=00 Ctl=04  .. .. .. .. .. .. .. ..  ... ... NXT
Done.
>
```

Useful for verifying all switches are working and understanding the multiplexed I/O.

### CASSTEST — Cassette Port Tone Test

Tests the cassette output port `44H` by generating square-wave tones (475 bytes at `8000H`). Connect a small speaker or piezo buzzer to the cassette output to hear the tones. This is the first program to use the cassette port — all other programs leave it untouched.

Eight selectable tone frequencies from \~200 Hz to \~3 kHz. Sweep mode auto-cycles through all tones with uniform timing. No LEDs are driven — the tone loop is kept tight for clean waveforms.

| Key | Function |
| --- | -------- |
| `1`–`8` | Select tone (1=lowest, 8=highest) |
| `S` | Toggle sweep mode (cycles 1→8→1→...) |
| `SPACE` | Silence |
| `ESC` | Exit to monitor |

```
> (send CASSTEST.HEX via Term)
HEX TRANSFER COMPLETE ERRORS=00
> G 8000

CASSTEST - Cassette Port Test
1-8=tone  S=sweep  SPACE=off  ESC=exit
Tone: 4
(tone plays - press keys to change)
Done.
>
```

### Loading HEX Programs

1. Use your terminal's "Send File" feature to transfer the `.HEX` file
2. After `HEX TRANSFER COMPLETE ERRORS=00`, type `G 8000` to run

- - -

## Author

**kayto [https://github.com/Kayto](https://github.com/Kayto)**

## ROM Version

`altaid05` — Version 5 of the Altaid monitor/BIOS ROM by Josh Bensadon