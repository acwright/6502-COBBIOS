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

- **ENTER** (or timeout) — launches the Integer BASIC interpreter
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
- **Serial absent** — IRQ handler skips serial status polling; `Chrin` flow control writes are suppressed; serial `LOAD`/`SAVE` return an error
- **GPIO/VIA absent** — `SysDelay` falls back to a calibrated software busy-loop; `JOY()` returns 0; keyboard IRQ check is skipped
- **SID absent** — `Beep`, `SOUND`, `VOL`, `SidPlayNote`, `SidSilence` silently return
- **Video absent** — `CLS`, `LOCATE`, `COLOR` silently skip (arguments are still consumed); console auto-switches to serial
- **RTC absent** — `TIME`, `DATE`, `SETTIME`, `SETDATE`, and `NVRAM` (write) in BASIC print `NO DEVICE`; `NVRAM()` (read) returns 0

### Integer BASIC

A full interactive BASIC interpreter is included. Programs are typed line-numbered and executed with `RUN`. All variables are single-letter (`A`–`Z`), signed 16-bit integers. Multiple statements per line are separated by `:`.

**Core Statements**

| Command | Syntax | Effect |
|---------|--------|--------|
| `PRINT` | `PRINT [item [sep item ...]]` | Output items to console. Items can be string literals or expressions. `;` continues on the same line (trailing `;` suppresses the CRLF); `,` inserts two spaces. Bare `PRINT` prints only CRLF |
| `INPUT` | `INPUT ["prompt"{;`&#124;`,}] var` | Read an integer from the user into `var`. With `;` appends `? ` to the prompt; with `,` prints the prompt only. Re-prompts with `?REDO` on non-numeric input |
| `LET` | `LET var = expr` | Assign expression result to variable. `LET` is optional — `var = expr` is equivalent |
| `GOTO` | `GOTO expr` | Jump unconditionally to the line numbered `expr`. `expr` can be any expression |
| `GOSUB` | `GOSUB expr` | Push current position and jump to `expr`. Up to 64 levels deep |
| `RETURN` | `RETURN` | Pop the GOSUB stack and resume after the calling `GOSUB` |
| `IF` | `IF expr THEN stmt` | Execute `stmt` (or `GOTO linenum`) if `expr` is non-zero. No `ELSE` — false skips to the next line |
| `FOR` | `FOR var = init TO limit [STEP step]` | Counted loop. Default step is `1`. Condition is `var ≤ limit` for positive step, `var ≥ limit` for negative. Up to 8 nested loops |
| `NEXT` | `NEXT var` | Increment loop variable and branch back to matching `FOR` if condition holds |
| `REM` | `REM [text]` | Comment — rest of line is ignored |
| `END` | `END` | Stop execution and return to the `OK` prompt. Variables are preserved |
| `STOP` | `STOP` | Stop execution and print `BREAK IN {linenum}`. Variables are preserved; resume with `CONT` |
| `CONT` | `CONT` | Continue execution after a `STOP` or Ctrl+C break (immediate mode only). Error if nothing to continue |
| `ON` | `ON expr GOTO l1,l2,...` | Evaluate `expr`, jump to the nth line number in the list. `ON expr GOSUB ...` also supported. Out-of-range index silently continues |
| `DATA` | `DATA v1,v2,...` | Store inline numeric data for `READ`. Skipped during normal execution |
| `READ` | `READ var [,var ...]` | Read the next value(s) from `DATA` statements into variables. `OUT OF DATA` error if exhausted |
| `RESTORE` | `RESTORE` | Reset the `DATA` pointer so the next `READ` starts from the first `DATA` statement |
| `LIST` | `LIST` | Print the entire program in detokenized form. Ctrl+C interrupts |
| `RUN` | `RUN` | Clear all variables and run the program from the first line |
| `NEW` | `NEW` | Erase the program and clear variables. No `OK` is printed afterward |
| `CLR` | `CLR` | Clear all variables (A–Z) to zero, reset GOSUB/FOR stacks, and release all arrays. Program is kept |
| `DIM` | `DIM var(size) [, var(size) ...]` | Dimension one or more arrays with indices `0` to `size`. Arrays are stored at the top of RAM, growing downward. `REDIM'D ARRAY` error if already dimensioned; released by `CLR`, `RUN`, or `NEW` |
| `POKE` | `POKE addr, value` | Write the low byte of `value` to memory address `addr` |
| `BRK` | `BRK` | Drop into the machine-code monitor. Return to BASIC with `X` in the monitor |

**Storage & System**

| Command | Effect |
|---------|--------|
| `SYS <addr>` | Call a machine-code routine at the given address; `RTS` returns to BASIC |
| `LOAD "name"` | Load a named file from CompactFlash into program space (`$0800`) |
| `SAVE "name"` | Save the current BASIC program to CompactFlash |
| `LOAD` (no arg) | Receive a program over the serial port (raw binary) |
| `SAVE` (no arg) | Transmit the current program over the serial port (raw binary) |
| `DIR` | List all files stored on CompactFlash |
| `DEL "name"` | Delete a named file from CompactFlash and reclaim its directory entry |
| `BANK <n>` | Select 1KB RAM bank `n` at `$8000–$83FE` via the bank latch |
| `MEM` | Print system info: free bytes, hardware-present flags (as hex), and active I/O mode |

**Video & Display**

| Command | Effect |
|---------|--------|
| `CLS` | Clear the screen and reset cursor to (0, 0) |
| `LOCATE <row>, <col>` | Move cursor to the given row (0–23) and column (0–39) |
| `COLOR <fg>, <bg>` | Set TMS9918 text foreground and background colours (0–15 each) |

**Sound**

| Command | Effect |
|---------|--------|
| `SOUND <voice>, <freq>, <dur>` | Play a tone on voice 1–3 at the given SID frequency value for `dur` centiseconds, then silence |
| `VOL <n>` | Set SID master volume (0–15) |

**Timing & I/O**

| Command | Effect |
|---------|--------|
| `PAUSE <n>` | Pause execution for `n` centiseconds (~10 ms each) |
| `WAIT <addr>, <mask>` | Spin until `(addr) AND mask` is non-zero; Ctrl+C aborts |

**Time & Date**

| Command | Effect |
|---------|--------|
| `TIME` | Print current RTC time as `HH:MM:SS` |
| `DATE` | Print current RTC date as `CCYY-MM-DD` |
| `SETTIME <hh>, <mm>, <ss>` | Set the RTC time (hours, minutes, seconds in binary) |
| `SETDATE <cc>, <yy>, <mm>, <dd>` | Set the RTC date (century, year, month, day in binary) |
| `NVRAM <addr>, <value>` | Write a byte to RTC battery-backed NVRAM at address `0`–`255` |

**Functions & Expressions**

| Function / Literal | Returns |
|--------------------|---------|
| `ABS(x)` | Absolute value of `x` |
| `RND(x)` | Pseudo-random integer in `[0, x)` for `x > 0`; raw PRNG value (0–32767) for `x ≤ 0` |
| `SGN(x)` | Sign of `x`: `1`, `0`, or `-1` |
| `PEEK(addr)` | Byte value at memory address `addr` (0–255) |
| `NOT expr` | Logical NOT: `1` if `expr` is zero, `0` otherwise |
| `expr AND expr` | Logical AND: `1` if both operands are non-zero, `0` otherwise |
| `expr OR expr` | Logical OR: `1` if either operand is non-zero, `0` otherwise |
| `expr MOD expr` | Integer remainder after division; sign follows the dividend. `DIVISION BY ZERO` if right side is zero |
| `CHR(n)` | In `PRINT`, draws the CP437 glyph for code `n` directly (bypasses control-code handling). In expressions, returns `n` unchanged |
| `SQR(n)` | Integer square root of `n`. Error if `n` is negative |
| `MIN(a,b)` | Returns the smaller of `a` and `b` |
| `MAX(a,b)` | Returns the larger of `a` and `b` |
| `POW(b,e)` | Integer exponentiation: `b` raised to the power `e`. Negative exponent returns `0` |
| `INKEY` | Non-blocking key read: returns the ASCII code of a pressed key, or `0` if no key is waiting. No parentheses |
| `ASC(n)` | Identity function — returns `n` unchanged. Convenience for readability (e.g. `A = ASC(INKEY)`) |
| `TAB(n)` | In `PRINT`, advances cursor to column `n` by emitting spaces. Does nothing if already at or past column `n`. In expressions, returns `n` unchanged |
| `HEX(n)` | In `PRINT`, outputs `n` as a 4-digit hexadecimal value with `$` prefix (e.g. `$00FF`). In expressions, returns `n` unchanged |
| `JOY(1)` / `JOY(2)` | Joystick bitmask for port 1 or 2 (bit order: R-L-D-U-Y-X-B-A) |
| `FREE` | Returns free bytes between program end and array space. No parentheses |
| `NVRAM(addr)` | Read a byte from RTC battery-backed NVRAM at address `0`–`255`. Returns `0` if RTC is absent |
| `var(index)` | Array element access. Array must be previously dimensioned with `DIM`. `BAD SUBSCRIPT` error if index is out of range |
| `$xxxx` | Hexadecimal integer literal (e.g. `$FF` = 255, `$1000` = 4096) |

**Operator Precedence** (high to low)

| Level | Operators |
|-------|-----------|
| Unary | `-` (negate), `NOT` |
| Multiplicative | `*`, `/`, `MOD` |
| Additive | `+`, `-` |
| Relational | `=`, `<>`, `<`, `>`, `<=`, `>=` |
| Logical AND | `AND` |
| Logical OR | `OR` |

> **Note on integer range:** BASIC uses signed 16-bit integers (`-32768` to `32767`). Hex literals above `$7FFF` print as negative numbers (e.g. `$A000` = `-24576`).

> **Stack limits:** GOSUB supports up to 64 nested levels; FOR/NEXT supports up to 8 nested loops. Exceeding either limit produces an `OUT OF MEMORY` error.

> **Arrays:** Each variable A–Z can optionally be dimensioned as a 1D array with `DIM`. Arrays are allocated from the top of RAM downward; `FREE` reports the gap between the program and array space. Elements are 0-indexed signed 16-bit integers, initialised to zero.

### Machine Code Monitor

A full-featured Supermon-style machine-code monitor occupies the `$C000–$DFFF` segment. It supports memory inspection, 65C02 disassembly, register manipulation, code execution, CompactFlash and serial file I/O, and number base conversion. The monitor prompt is `.`.

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
| `L` | `L "file" [addr]` | Load from CompactFlash (with filename) or serial (without) to address (default `$0800`) |
| `S` | `S "file" addr addr` | Save to CompactFlash (with filename) or serial (without) |
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

### Serial I/O & ASCII Transfer

A 6551 ACIA provides a serial port at 19200 baud (8-N-1). The `IO_MODE` Kernal variable selects whether `Chrout` routes to video or serial. `LOAD`/`SAVE` without a filename switch to serial mode and exchange programs as raw binary data: a 2-byte size header (low byte first) followed by the program bytes.

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
| `$C000–$DFFF` | 8KB | Machine-code monitor |
| `$E000–$FEFF` | ~8KB | Integer BASIC interpreter |
| `$FF00–$FFF9` | 250B | Wozmon (Apple II machine-code monitor) |
| `$FFFA–$FFFF` | 6B | CPU vectors (NMI / RESET / IRQ) |

### RAM (`$0000–$7FFF`, 32KB)

| Range | Size | Purpose |
|-------|------|---------|
| `$0000–$00FF` | 256B | Zero page (Kernal + BASIC workspace) |
| `$0100–$01FF` | 256B | CPU stack |
| `$0200–$02FF` | 256B | Keyboard input ring buffer |
| `$0300–$03FF` | 256B | Kernal variables (vectors, cursor, HW\_PRESENT, BOOT\_VECTOR, RTC, FS state, array descriptors) |
| `$0400–$07FF` | 1KB | User / BASIC variables |
| `$0800–$7FFF` | ~31KB | Program space (programs grow up from `$0800`; arrays grow down from `$7FFF`) |

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
| `$A054` | `AsciiLoad` | Receive raw binary over serial into `$0800` |
| `$A057` | `AsciiSave` | Send current program as raw binary over serial |
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
