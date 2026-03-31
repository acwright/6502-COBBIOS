6502-COBBIOS
============

BIOS ROM for the "COB" computer in the [A.C. Wright 6502 project](https://github.com/acwright/6502).

## Overview

COBBIOS is the firmware ROM for the COB, a homebrew 6502 single-board computer. It occupies the upper 32KB of the address space (`$8000–$FFFF`) and provides everything the machine needs to go from power-on to a usable computing environment.

### Boot Sequence

The COB is a computer-on-a-backplane design where every I/O card is optional. On reset, the Kernal probes each I/O slot to discover which hardware is installed and records the results in a single bitmask byte at `HW_PRESENT` (`$030D`). Only detected hardware is initialised — missing cards are silently skipped and never cause a hang.

The probe-and-boot sequence is:

1. **Clear `HW_PRESENT`** — all bits start at zero
2. **Probe each I/O slot** — RAM (read-back), RTC (NVRAM read-back), CompactFlash (BSY/RDY with timeout), Serial (TDRE after reset), GPIO/VIA (DDR read-back), SID (active oscillator), Video (VRAM read-back)
3. **Conditionally initialise** — each subsystem is only initialised if its probe succeeded
4. **Console auto-detection** — if video is present, `IO_MODE` is set to video; if only serial is present, output is routed to the serial port; if neither is found, the CPU halts
5. **Beep** — a short tone on the SID (skipped silently if SID absent)
6. **Splash screen** — displayed on the active console:

```
  -- The 'COB' v1.0 --
ENTER=BASIC  ESC=MONITOR
```

7. **Boot menu with timeout** — waits ~5 seconds for a keypress, then auto-boots BASIC

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
- **RTC absent** — `TIME` and `DATE` in BASIC print `NO DEVICE`

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
| `LIST` | `LIST` | Print the entire program in detokenized form. Ctrl+C interrupts |
| `RUN` | `RUN` | Clear all variables and run the program from the first line |
| `NEW` | `NEW` | Erase the program and clear variables. No `OK` is printed afterward |
| `CLR` | `CLR` | Clear all variables (A–Z) to zero and reset GOSUB/FOR stacks. Program is kept |
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
| `JOY(1)` / `JOY(2)` | Joystick bitmask for port 1 or 2 (bit order: R-L-D-U-Y-X-B-A) |
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

A SID chip provides audio output. The `Beep` Kernal routine plays a ~1000 Hz tone on voice 1. Use `SidPlayNote` to play any frequency on any of the three voices, `SidSilence` to stop all voices, and `SidSetVolume` to set the master volume (0–15).

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
| `$0300–$03FF` | 256B | Kernal variables (vectors, cursor, HW\_PRESENT, RTC, FS state) |
| `$0400–$07FF` | 1KB | User / BASIC variables |
| `$0800–$7FFF` | ~31KB | Program space |

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
| `$A00F` | `InitVideo` | Initialise TMS9918 video chip |
| `$A012` | `InitKB` | Initialise VIA keyboard / joystick ports |
| `$A015` | `InitSC` | Initialise 6551 serial card (19200 8-N-1) |
| `$A018` | `InitSID` | Initialise SID sound chip |
| `$A01B` | `Beep` | Play a short beep tone |
| `$A01E` | `VideoClear` | Clear the screen |
| `$A021` | `VideoPutChar` | Write character at current cursor position |
| `$A024` | `VideoSetCursor` | Set cursor: `X`=column (0–39), `Y`=row (0–23) |
| `$A027` | `VideoGetCursor` | Get cursor: returns column in `X`, row in `Y` |
| `$A02A` | `VideoScroll` | Scroll screen up one line |
| `$A02D` | `SerialChrout` | Output character directly to serial (bypass `IO_MODE`) |
| `$A030` | `ReadJoystick1` | Read joystick 1 → bitmask in `A` |
| `$A033` | `ReadJoystick2` | Read joystick 2 → bitmask in `A` |
| `$A036` | `RtcReadTime` | Read time → `A`=hours, `X`=minutes, `Y`=seconds |
| `$A039` | `RtcWriteTime` | Write time ← `A`=hours, `X`=minutes, `Y`=seconds |
| `$A03C` | `RtcReadDate` | Read date → `A`=date, `X`=month, `Y`=year |
| `$A03F` | `RtcWriteDate` | Write date ← `A`=date, `X`=month, `Y`=year |
| `$A042` | `RtcReadNVRAM` | Read NVRAM byte: `X`=address → `A`=data |
| `$A045` | `RtcWriteNVRAM` | Write NVRAM byte: `X`=address, `A`=data |
| `$A048` | `StReadSector` | Read one 512-byte CF sector |
| `$A04B` | `StWriteSector` | Write one 512-byte CF sector |
| `$A04E` | `StWaitReady` | Wait for CF ready; carry set on error |
| `$A051` | `SetIOMode` | Set `IO_MODE`: `A`=0 (video) or 1 (serial) |
| `$A054` | `GetIOMode` | Get `IO_MODE` → `A` |
| `$A057` | `AsciiLoad` | Receive raw binary over serial into `$0800` |
| `$A05A` | `AsciiSave` | Send current program as raw binary over serial |
| `$A05D` | `SidPlayNote` | Play note: `A`=voice (0–2), `X`=freqLo, `Y`=freqHi |
| `$A060` | `SidSilence` | Silence all SID voices |
| `$A063` | `FsDeleteFile` | Delete a file from CompactFlash by name |
| `$A066` | `SysDelay` | Delay `A`=count\_lo, `X`=count\_hi centiseconds (~10 ms each) using VIA T1 |
| `$A069` | `SidSetVolume` | Set SID master volume: `A`=0–15 |
| `$A06C` | `VideoSetColor` | Set TMS9918 text colour register: `A`=`(fg<<4)\|bg` |
| `$A06F` | `VideoChroutRaw` | Output character glyph at cursor (raw, no control-code handling): `A`=char code |

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
