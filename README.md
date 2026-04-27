6502-BIOS
=========

BIOS ROM for the [A.C. Wright 6502 project](https://github.com/acwright/6502).

## Overview

BIOS is the firmware ROM for a homebrew 6502 computer project. It occupies the upper 32KB of the address space (`$8000–$FFFF`) and provides everything the machine needs to go from power-on to a usable computing environment.

### Boot Sequence

The [A.C. Wright 6502 project](https://github.com/acwright/6502) is a computer-on-a-backplane design where every I/O card is optional. On reset, the Kernal probes each I/O slot to discover which hardware is installed and records the results in a single bitmask byte at `HW_PRESENT` (`$030D`). Only detected hardware is initialised — missing cards are silently skipped and never cause a hang.

The probe-and-boot sequence is:

1. **Clear `HW_PRESENT`** — all bits start at zero
2. **Probe each I/O slot** — RAM (read-back), RTC (NVRAM read-back), CompactFlash (BSY/RDY with timeout), Serial (TDRE after reset), GPIO/VIA (DDR read-back), SID (active oscillator), Video (VRAM read-back)
3. **Conditionally initialise** — each subsystem is only initialised if its probe succeeded
4. **Console auto-detection** — if video is present, `IO_MODE` is set to video; if only serial is present, output is routed to the serial port; if neither is found, `IO_MODE` is left unchanged (no halt — allows cartridges with their own display hardware to boot)
5. **Beep** — a short tone on the SID (skipped silently if SID absent; provides audible feedback that the system is alive)
6. **Boot vector check** — if `BOOT_VECTOR` (`$035B`) is non-zero, jump to the address stored there (cartridge or external program takes over). Otherwise continue to normal boot
7. **Console check** — verify that at least video or serial is present. If neither is found and no boot vector was set, the CPU halts (interactive boot requires a console)
8. **Splash screen** — displayed on the active console:

```
  -- 6502 BIOS v1.0 --
ENTER=BASIC  ESC=MONITOR
```

9. **Boot menu with timeout** — waits ~5 seconds for a keypress, then auto-boots BASIC

- **ENTER** (or timeout) — launches the BASIC interpreter
- **ESC** — drops into the machine-code monitor

#### Hardware Presence Flags

The `HW_PRESENT` byte at `$030D` can be read from user code or inspected in the monitor. Each bit corresponds to an I/O slot:

| Bit | Mask | Card |
|-----|------|------|
| 0 | `$01` | RAM card low (IO 1) |
| 1 | `$02` | RAM card high (IO 2) |
| 2 | `$04` | RTC DS1511Y (IO 3) |
| 3 | `$08` | CompactFlash (IO 4) |
| 4 | `$10` | Serial R65C51 (IO 5) |
| 5 | `$20` | GPIO/VIA 65C22 (IO 6) |
| 6 | `$40` | SID/ARMSID (IO 7) |
| 7 | `$80` | Video TMS9918 (IO 8) |

#### Graceful Degradation

All hardware-dependent operations are guarded at every level — Kernal, BASIC, and Monitor:

- **CompactFlash absent** — `LOAD`, `SAVE`, `DIR` in BASIC print `NO DEVICE`; Monitor `L`, `S`, `@` print `I/O ERROR`; `StWaitReady` times out instead of hanging
- **Serial absent** — IRQ handler skips serial status polling; `Chrin` flow control writes are suppressed; XModem `LOAD`/`SAVE` return an error
- **GPIO/VIA absent** — `SysDelay` falls back to a calibrated software busy-loop; `JOY()` returns 0; keyboard IRQ check is skipped
- **SID absent** — `Beep`, `SOUND`, `VOL`, `SidPlayNote`, `SidSilence` silently return
- **Video absent** — `CLS`, `LOCATE`, `COLOR` silently skip (arguments are still consumed); console auto-switches to serial
- **RTC absent** — `TIME`, `DATE`, `SETTIME`, `SETDATE`, and `NVRAM` (write) in BASIC print `NO DEVICE`; `NVRAM()` (read) returns 0

### BASIC

A full interactive floating-point BASIC interpreter is included, with a feature surface comparable to Microsoft 6502 BASIC. Programs are typed line-numbered and executed with `RUN`. Numeric variables are single-letter (`A`–`Z`) holding 5-byte (40-bit) floating-point values; string variables are `A$`–`Z$`. Each name can additionally be dimensioned as a 1-D array via `DIM`. Multiple statements per line are separated by `:`.

> **Numeric range:** ~±1.7 × 10³⁸, six significant digits. Numbers print with a leading-space sign convention (positive numbers prefixed by a space, negative by `-`). Boolean expressions evaluate to `-1` (true) or `0` (false).

**Core Statements**

| Command | Syntax | Effect |
|---------|--------|--------|
| `PRINT` | `PRINT [item [sep item ...]]` | Output items to console. Items may be string or numeric expressions. `;` = no separator (trailing `;` suppresses CRLF); `,` = advance to next 14-column print zone. Bare `PRINT` prints only CRLF |
| `INPUT` | `INPUT ["prompt"{;`&#124;`,}] var [, var ...]` | Read value(s) from the user. Numeric or string vars supported. Re-prompts with `?REDO FROM START` on bad numeric input; `?EXTRA IGNORED` if too many comma-separated values |
| `LET` | `[LET] var = expr` | Assign expression to variable. `LET` keyword is optional |
| `GOTO` | `GOTO linenum` | Jump unconditionally to line `linenum` |
| `GOSUB` | `GOSUB linenum` | Push current position and jump. Up to 64 levels deep |
| `RETURN` | `RETURN` | Pop the GOSUB stack and resume after the calling `GOSUB` |
| `IF` | `IF expr THEN stmt [ELSE stmt]` | Execute THEN branch if `expr` non-zero, else (if present) the ELSE branch. `THEN linenum` is shorthand for `THEN GOTO linenum` |
| `FOR` | `FOR var = init TO limit [STEP step]` | Counted loop. Default step is `1`. Up to 8 nested loops |
| `NEXT` | `NEXT [var [, var ...]]` | Increment loop variable and branch back to matching `FOR` if condition holds |
| `REM` | `REM [text]` | Comment — rest of line is ignored |
| `END` | `END` | Stop execution and return to `OK`. Variables preserved |
| `STOP` | `STOP` | Stop and print `BREAK IN nnnn`. Resume with `CONT` |
| `CONT` | `CONT` | Continue after `STOP` or Ctrl+C break (immediate mode only). Error if nothing to continue |
| `ON` | `ON expr GOTO l1,l2,...` / `ON expr GOSUB l1,l2,...` | Evaluate `expr`, branch to nth target. Out-of-range index silently continues |
| `DATA` | `DATA v1,v2,...` | Inline data for `READ` (numeric or string literals). Skipped during normal execution |
| `READ` | `READ var [,var ...]` | Read next value(s) from `DATA` into variables. `OUT OF DATA` if exhausted |
| `RESTORE` | `RESTORE` | Reset `DATA` pointer to start of program |
| `LIST` | `LIST` | Print the program in detokenized form. Ctrl+C interrupts |
| `RUN` | `RUN [linenum]` | Clear variables and run the program (optionally from `linenum`) |
| `NEW` | `NEW` | Erase the program and clear variables |
| `CLR` | `CLR` | Clear variables and arrays; reset GOSUB/FOR stacks. Program is kept |
| `DIM` | `DIM var(size) [, var(size) ...]` | Dimension a 1-D array (numeric or string), valid indices `0..size`. `REDIM'D ARRAY` if already dimensioned. Only one dimension is supported |
| `DEF FN` | `DEF FN A(X) = expr` | Define a single-argument numeric user function. Call with `FN A(value)` |
| `POKE` | `POKE addr, value` | Write byte `value` to memory address `addr` |
| `BRK` | `BRK` | Drop into the machine-code monitor. Return to BASIC with `X` |

**Storage & System**

| Command | Effect |
|---------|--------|
| `SYS <addr>` | Call a machine-code routine; `RTS` returns to BASIC |
| `LOAD "name"` | Load a named file from CompactFlash to `$0800` |
| `SAVE "name"` | Save the current program to CompactFlash |
| `LOAD` (no arg) | Receive a program via XModem on the serial port |
| `SAVE` (no arg) | Transmit the current program via XModem |
| `DIR` | List CompactFlash directory |
| `DEL "name"` | Delete a named file from CompactFlash |
| `BANK <n>` | Select 1KB RAM bank `n` at `$8000–$83FE` |
| `MEM` | Print free bytes and `HW_PRESENT` (hex) |

**Video & Display**

| Command | Effect |
|---------|--------|
| `CLS` | Clear the screen and reset cursor to (0, 0) |
| `LOCATE <row>, <col>` | Move cursor to row 0–23, column 0–39 |
| `COLOR <fg>, <bg>` | Set TMS9918 text foreground/background colours (0–15 each) |

**Sound**

| Command | Effect |
|---------|--------|
| `SOUND <voice>, <freq>, <dur>` | Play a tone on voice 0–2 at `freq` Hz for `dur` centiseconds, then silence |
| `VOL <n>` | Set SID master volume (0–15) |

**Timing & I/O**

| Command | Effect |
|---------|--------|
| `PAUSE <n>` | Pause for `n` centiseconds (~10 ms each) |
| `WAIT <addr>, <mask>` | Spin until `(addr) AND mask` is non-zero; Ctrl+C aborts |

**Time & Date**

| Command | Effect |
|---------|--------|
| `TIME` | Print current RTC time as `HH:MM:SS` |
| `DATE` | Print current RTC date as `CCYY-MM-DD` |
| `SETTIME <hh>, <mm>, <ss>` | Set the RTC time |
| `SETDATE <cc>, <yy>, <mm>, <dd>` | Set the RTC date |
| `NVRAM <addr>, <value>` | Write a byte to RTC NVRAM at address 0–255 |

**Functions & Expressions**

| Function | Returns |
|----------|---------|
| `ABS(x)` | Absolute value of `x` |
| `SGN(x)` | Sign of `x`: `1`, `0`, or `-1` |
| `INT(x)` | Largest integer ≤ `x` (floor) |
| `SQR(x)` | Square root of `x` (error if negative) |
| `EXP(x)` | e raised to `x` |
| `LOG(x)` | Natural logarithm (error if `x ≤ 0`) |
| `SIN(x)` / `COS(x)` / `TAN(x)` | Trig functions, radians |
| `ATN(x)` | Arctangent, radians |
| `RND(x)` | Pseudo-random float in `[0, 1)` for `x > 0`; repeats last value for `x = 0`; reseeds for `x < 0` |
| `PEEK(addr)` | Byte value at memory address `addr` |
| `FRE(x)` | Free bytes between top of variable space and bottom of string heap (argument ignored) |
| `POS(x)` | Current print column (argument ignored) |
| `LEN(s$)` | String length |
| `VAL(s$)` | Parse `s$` as a number; returns 0 if not numeric |
| `ASC(s$)` | ASCII code of first character of `s$` |
| `CHR$(n)` | One-character string with ASCII code `n` |
| `STR$(n)` | Numeric value `n` formatted as a string |
| `LEFT$(s$,n)` / `RIGHT$(s$,n)` | First / last `n` chars of `s$` |
| `MID$(s$,start[,len])` | Substring of `s$` starting at 1-based index `start` |
| `TAB(n)` | In `PRINT`, advance cursor to column `n` (no-op if already past) |
| `SPC(n)` | In `PRINT`, emit `n` spaces |
| `INKEY` | Non-blocking key read: ASCII code or `0`. No parentheses |
| `JOY(1)` / `JOY(2)` | Joystick port 1 or 2 bitmask (R-L-D-U-Y-X-B-A) |
| `NVRAM(addr)` | Read byte from RTC NVRAM (returns 0 if RTC absent) |
| `HEX(n)` | In `PRINT`, output `n` as `$xxxx` hex; in expressions, returns `n` unchanged |
| `MIN(a,b)` / `MAX(a,b)` | Smaller / larger of `a` and `b` |
| `var(index)` | Array element access. Array must be `DIM`-med first |

**Operators**

`+ - * /` — standard arithmetic. `^` — exponentiation. `+` between strings — concatenation. Comparisons `= <> < > <= >=` work on numbers and strings. Logical `AND`, `OR`, `NOT` operate bitwise on the integer parts of operands; relational comparisons return `-1` (true) or `0` (false).

**Operator Precedence** (high to low)

| Level | Operators |
|-------|-----------|
| Power | `^` |
| Unary | `-` (negate), `+` |
| Multiplicative | `*`, `/` |
| Additive | `+`, `-` |
| Relational | `=`, `<>`, `<`, `>`, `<=`, `>=` |
| Logical NOT | `NOT` |
| Logical AND | `AND` |
| Logical OR | `OR` |

> **Stack limits:** GOSUB supports up to 64 nested levels; FOR/NEXT supports up to 8 nested loops. Exceeding either limit produces an `OUT OF MEMORY` error.

> **Memory layout:** Programs grow up from `$0800`. Numeric/string scalar variables follow the program, then arrays, then the string heap which grows down from `$8000`. `MEM` and the cold-boot banner report `MEMSIZ - VARTAB` (free bytes for variables, arrays, and strings combined).

### Machine Code Monitor

A full-featured Supermon-style machine-code monitor occupies the `$EE00–$FEFF` segment. It supports memory inspection, 65C02 disassembly, register manipulation, code execution, CompactFlash and serial file I/O, and number base conversion. The monitor prompt is `.`.

The monitor is entered in three ways:
- **ESC at boot** — cold entry, prints `MONITOR` banner
- **BRK from BASIC** — prints `BRK AT $xxxx` and the current register state
- **Hardware BRK** — any `BRK` opcode in user code enters the monitor with full register display

**Memory Inspection**

| Command | Syntax | Description |
|---------|--------|-------------|
| `M` | `M [addr] [addr]` | Hex + ASCII memory dump (8 bytes/line); bare `M` continues from last address |
| `D` | `D [addr] [addr]` | Disassemble 65C02 instructions (20 lines default); supports the full WDC 65C02 + Rockwell instruction set |
| `R` | `R` | Display saved CPU registers: `PC=xxxx A=xx X=xx Y=xx SP=xx NV-BDIZC` |

**Memory Manipulation**

| Command | Syntax | Description |
|---------|--------|-------------|
| `>` | `> addr byte [byte...]` | Deposit (write) bytes starting at address |
| `F` | `F addr addr byte` | Fill memory range with a byte value |
| `T` | `T addr addr dest` | Transfer (copy) a memory block; handles overlapping regions |
| `H` | `H addr addr byte [byte...]` | Hunt (search) for a byte pattern in a range |
| `C` | `C addr addr addr` | Compare two memory regions; prints differing addresses |

**Execution Control**

| Command | Syntax | Description |
|---------|--------|-------------|
| `G` | `G [addr]` | Go — JMP to address (or saved PC); restores all registers via RTI |
| `J` | `J [addr]` | JSR — call a subroutine; RTS returns to the monitor with register display |
| `;` | `; PC xxxx A xx X xx ...` | Modify saved registers (any subset, any order) |

**File I/O & Utilities**

| Command | Syntax | Description |
|---------|--------|-------------|
| `L` | `L "file" [addr]` | Load from CompactFlash (with filename) or XModem (without) to address (default `$0800`) |
| `S` | `S "file" addr addr` | Save to CompactFlash (with filename) or XModem (without) |
| `@` | `@` | List CompactFlash directory |
| `N` | `N value` | Number conversion — hex (`$xx`), decimal (`+ddd`), or binary (`%bbbb`) input shown in all three bases |
| `X` | `X` | Exit to BASIC |

> **Wozmon easter egg:** The original Apple II Wozmon remains at `$FF00`. Enter it from the monitor with `G FF00` or from BASIC with `SYS $FF00`.

### Video

Output is displayed on a TMS9918 video chip in 40×24 text mode. The screen scrolls upward automatically when the cursor reaches the bottom. The Kernal tracks cursor position and exposes routines for direct character and cursor manipulation.

### Keyboard

Both a PS/2 keyboard (via CA1 interrupt) and a matrix keyboard (via CB1 interrupt) are supported simultaneously. Key presses are queued in a 256-byte ring buffer at `$0200–$02FF` and read via `Chrin`.

### Joystick

Two joystick ports are supported. `ReadJoystick1` and `ReadJoystick2` each return a bitmask byte in `A`:

```
Bit:  7   6   5   4   3   2   1   0
      R   L   D   U   Y   X   B   A
```

### CompactFlash Storage

A simple flat filesystem is stored on a CompactFlash card (true 8-bit IDE). The directory lives at LBA 0 and holds up to 16 entries (8.3 filenames). Data sectors follow contiguously per file. `LOAD`, `SAVE`, and `DIR` in BASIC all use this filesystem.

### Serial I/O & XModem Transfer

A 6551 ACIA provides a serial port at 19200 baud (8-N-1). The `IO_MODE` Kernal variable selects whether `Chrout` routes to video or serial. `LOAD`/`SAVE` without a filename use the standard XModem protocol (128-byte blocks with checksum) to transfer programs over serial. The receiver initiates the transfer by sending NAK; the sender responds with data blocks; each block is acknowledged before the next is sent. The last block is padded with SUB (`$1A`). Compatible with any terminal program that supports XModem (checksum mode).

When an XModem transfer is initiated, the system prints `XMODEM RX READY` (receive) or `XMODEM TX READY` (send) and waits up to ~60 seconds for the terminal program to start the transfer, giving ample time to configure and begin the transfer in your terminal program.

### Real-Time Clock

A DS1511Y RTC provides time and date. `RtcReadTime` returns hours/minutes/seconds in `A`/`X`/`Y` (binary). `RtcReadDate` returns date/month/year. 256 bytes of battery-backed NVRAM are accessible via `RtcReadNVRAM` / `RtcWriteNVRAM`.

### Sound

A SID chip provides audio output. The `Beep` Kernal routine plays a ~475 Hz tone on voice 1. Use `SidPlayNote` to play any frequency on any of the three voices, `SidSilence` to stop all voices, and `SidSetVolume` to set the master volume (0–15).

---

## Memory Map

### ROM (`$8000–$FFFF`, 32KB)

| Range | Size | Contents |
|-------|------|----------|
| `$8000–$9FFF` | 8KB | I/O space (hardware registers) |
| `$A000–$A0FF` | 256B | **Kernal jump table** (public API) |
| `$A100–$B7FF` | ~6KB | Kernal routines |
| `$B800–$BFFF` | 2KB | IBM CP437 character set (VRAM init data) |
| `$C000–$EDFF` | ~11.5KB | BASIC interpreter (5-byte floating-point) |
| `$EE00–$FEFF` | ~4KB | Machine-code monitor |
| `$FF00–$FFF9` | 250B | Wozmon (Apple I machine-code monitor) |
| `$FFFA–$FFFF` | 6B | CPU vectors (NMI / RESET / IRQ) |

### RAM (`$0000–$7FFF`, 32KB)

| Range | Size | Purpose |
|-------|------|---------|
| `$0000–$00FF` | 256B | Zero page (Kernal + BASIC workspace) |
| `$0100–$01FF` | 256B | CPU stack |
| `$0200–$02FF` | 256B | Keyboard input ring buffer |
| `$0300–$03FF` | 256B | Kernal variables (vectors, cursor, HW\_PRESENT, BOOT\_VECTOR, RTC, FS state, array descriptors) |
| `$0400–$05FF` | 512B | BASIC line-input buffer, GOSUB stack, FOR stack |
| `$0600–$07FF` | 512B | CompactFlash sector buffer (overlaps user RAM during `LOAD`/`SAVE`/`DIR`/`DEL`) |
| `$0800–$7FFF` | ~31KB | Program text grows up from `$0800`; numeric/string variables follow; arrays then string heap grow down from `$8000` |

---

## Kernal Jump Table (`$A000`)

All public Kernal entry points are accessed through stable 3-byte `jmp` slots. Call these addresses from your own code — the implementation behind each slot can change without breaking your program.

| Address | Label | Description |
|---------|-------|-------------|
| `$A000` | `Chrout` | Output one character (routed by `IO_MODE`) |
| `$A003` | `Chrin` | Read one character from the input buffer |
| `$A006` | `WriteBuffer` | Push byte into the input buffer |
| `$A009` | `ReadBuffer` | Pop byte from the input buffer |
| `$A00C` | `BufferSize` | Return number of bytes waiting in buffer |
| `$A00F` | `SetIOMode` | Set `IO_MODE`: `A`=0 (video) or 1 (serial) |
| `$A012` | `GetIOMode` | Get `IO_MODE` → `A` |
| `$A015` | `InitVideo` | Initialise TMS9918 video chip |
| `$A018` | `VideoClear` | Clear the screen |
| `$A01B` | `VideoPutChar` | Write character at current cursor position |
| `$A01E` | `VideoSetCursor` | Set cursor: `X`=column (0–39), `Y`=row (0–23) |
| `$A021` | `VideoGetCursor` | Get cursor: returns column in `X`, row in `Y` |
| `$A024` | `VideoScroll` | Scroll screen up one line |
| `$A027` | `VideoSetColor` | Set TMS9918 text colour register: `A`=`(fg<<4)\|bg` |
| `$A02A` | `VideoChroutRaw` | Output character glyph at cursor (raw, no control-code handling): `A`=char code |
| `$A02D` | `InitSID` | Initialise SID sound chip |
| `$A030` | `Beep` | Play a short beep tone |
| `$A033` | `SidPlayNote` | Play note: `A`=voice (0–2), `X`=freqLo, `Y`=freqHi |
| `$A036` | `SidSilence` | Silence all SID voices |
| `$A039` | `SidSetVolume` | Set SID master volume: `A`=0–15 |
| `$A03C` | `FsLoadFile` | Load a file from CompactFlash by name |
| `$A03F` | `FsSaveFile` | Save a file to CompactFlash by name |
| `$A042` | `FsDeleteFile` | Delete a file from CompactFlash by name |
| `$A045` | `InitKB` | Initialise VIA keyboard / joystick ports |
| `$A048` | `ReadJoystick1` | Read joystick 1 → bitmask in `A` |
| `$A04B` | `ReadJoystick2` | Read joystick 2 → bitmask in `A` |
| `$A04E` | `InitSC` | Initialise 6551 serial card (19200 8-N-1) |
| `$A051` | `SerialChrout` | Output character directly to serial (bypass `IO_MODE`) |
| `$A054` | `XModemLoad` | Receive data via XModem into memory at `XFER_PTR`; returns total bytes in `XFER_REMAIN` |
| `$A057` | `XModemSave` | Send data via XModem from `XFER_PTR`, `XFER_REMAIN` bytes |
| `$A05A` | `RtcReadTime` | Read time → `A`=hours, `X`=minutes, `Y`=seconds |
| `$A05D` | `RtcReadDate` | Read date → `A`=date, `X`=month, `Y`=year |
| `$A060` | `RtcWriteTime` | Write time ← `A`=hours, `X`=minutes, `Y`=seconds |
| `$A063` | `RtcWriteDate` | Write date ← `A`=date, `X`=month, `Y`=year |
| `$A066` | `RtcReadNVRAM` | Read NVRAM byte: `X`=address → `A`=data |
| `$A069` | `RtcWriteNVRAM` | Write NVRAM byte: `X`=address, `A`=data |
| `$A06C` | `StReadSector` | Read one 512-byte CF sector |
| `$A06F` | `StWriteSector` | Write one 512-byte CF sector |
| `$A072` | `StWaitReady` | Wait for CF ready; carry set on error |
| `$A075` | `SysDelay` | Delay `A`=count\_lo, `X`=count\_hi centiseconds (~10 ms each) using VIA T1 |
| `$A078` | `KernalInit` | Initialise all hardware (caller must reset stack pointer first; no cli, no splash). Returns via `RTS` |
| `$A07B` | `KernalVersion` | Get BIOS version → `A`=major, `X`=minor |

### Cartridge Support

Cartridges for this system overlay the ROM area from `$C000–$FFFF`. When inserted, the cartridge replaces the Monitor, BASIC, Wozmon, and CPU vectors (NMI/RESET/IRQ) with its own code. The Kernal (`$A000–$B7FF`) and character set (`$B800–$BFFF`) remain accessible.

Two Kernal facilities support cartridge development:

**`KernalInit` ($A078)** — A callable subroutine that performs the complete hardware initialisation sequence (IRQ/BRK/NMI pointers, hardware probing, peripheral init, console auto-detection) and returns via `RTS`. It clears decimal mode and disables interrupts, but does **not** reset the stack pointer (the caller must do `ldx #$ff / txs` before the `JSR`), enable interrupts (`cli`), play the beep, display the splash screen, or enter the boot menu. This gives the cartridge full control over what happens after hardware init.

**`BOOT_VECTOR` ($035B–$035C)** — A 2-byte RAM address that, if non-zero after `KernalInit`, causes the normal `Reset` flow to jump to the specified address instead of continuing to the splash screen and boot menu. `KernalInit` zeroes this variable, so a cartridge must write to it *after* calling `KernalInit` but *before* `Reset` checks it — or use Pattern B below.

#### Cart Usage Patterns

**Pattern A — Direct KernalInit call** (cart handles everything after init):

```asm
; Cart reset vector points here
CartReset:
    ldx #$ff
    txs                 ; Reset stack pointer
    jsr $A078           ; KernalInit — all hardware ready, interrupts off
    ; Override IRQ_PTR ($0300) / NMI_PTR ($0304) if needed
    cli
    jmp CartMain         ; Cart's own program entry
```

This is the simplest approach. The cartridge gets fully initialised hardware and takes complete control. No beep, no splash — the cart decides what the user sees and hears.

**Pattern B — KernalInit + Beep** (get the audible startup feedback, then take control):

```asm
; Cart reset vector points here
CartReset:
    ldx #$ff
    txs                 ; Reset stack pointer
    jsr $A078           ; KernalInit — all hardware ready, interrupts off
    jsr $A030           ; Beep — audible "system alive" feedback
    ; Override IRQ_PTR ($0300) / NMI_PTR ($0304) if needed
    cli
    jmp CartMain         ; Cart's own program entry
```

This is Pattern A with the addition of the startup beep. The beep provides audible confirmation that hardware initialised successfully, which is useful when the cartridge has its own display that may take time to set up.

> **Note on `BOOT_VECTOR`:** `KernalInit` zeroes `BOOT_VECTOR` during init. A cartridge can write to `BOOT_VECTOR` after calling `KernalInit` if it needs to redirect a later soft-reset back to the cart. However, for the initial boot, Patterns A and B above are the recommended approaches.

In practice, **Pattern A is recommended** for most cartridges.

#### What Cartridges Can Rely On

- **Kernal jump table** (`$A000–$A0FF`) — all entries remain stable across BIOS versions
- **`HW_PRESENT`** (`$030D`) — read after `KernalInit` to discover installed hardware
- **`KernalVersion`** (`$A07B`) — check BIOS compatibility (`A`=major, `X`=minor)
- **RAM vectors** — `IRQ_PTR` (`$0300`), `BRK_PTR` (`$0302`), `NMI_PTR` (`$0304`) can be overwritten to install custom interrupt handlers
- **`IO_MODE`** (`$0306`) — set via `SetIOMode` (`$A00F`) to route console output
- **No-console safe** — `KernalInit` does not halt if neither video nor serial is detected, allowing cartridges with their own display hardware to boot normally

A template project for creating cartridges for the A.C. Wright 6502 system is available here: [https://github.com/acwright/6502-CRT](https://github.com/acwright/6502-CRT).

---

## Prerequisites

### Install cc65 Toolchain

The cc65 toolchain provides the assembler and linker needed to build 6502 assembly code.

macOS (using Homebrew):
```bash
brew install cc65
```

Linux (Debian/Ubuntu):
```bash
sudo apt-get install cc65
```

Other platforms: See [cc65 documentation](https://cc65.github.io/)

### Optional: Install minipro (for EEPROM burning)

Only required if you plan to program an AT28C256 EEPROM chip:
```bash
brew install minipro
```

## Building

Build the ROM image:
```bash
make
```

This generates:
- `BIOS.bin` - 32KB ROM image ($8000-$FFFF)
- `BIOS.lst` - Assembly listing file for debugging

## Verification

View the generated binary as hex dump:
```bash
make view
```

## Programming EEPROM

To burn the ROM to an AT28C256 EEPROM chip using a TL866 programmer:
```bash
make eeprom
```

**Note:** This requires a TL866 (or compatible) programmer and the minipro software.

## Cleaning Build Artifacts

Remove generated files:
```bash
make clean
```
