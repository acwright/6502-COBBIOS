6502-COBBIOS
============

BIOS ROM for the "COB" computer in the [A.C. Wright 6502 project](https://github.com/acwright/6502).

## Overview

COBBIOS is the firmware ROM for the COB, a homebrew 6502 single-board computer. It occupies the upper 32KB of the address space (`$8000–$FFFF`) and provides everything the machine needs to go from power-on to a usable computing environment.

### Boot Sequence

On reset, the Kernal initialises all hardware subsystems (video, keyboard, serial, sound, RTC, and CompactFlash storage), plays a short beep, and displays a splash screen:

```
-- The 'COB' v1.0 --
ENTER=BASIC  ESC=MONITOR
```

- **ENTER** — launches the Integer BASIC interpreter
- **ESC** — drops into the machine-code monitor

### Integer BASIC

A full interactive BASIC interpreter is included. Programs are typed line-numbered and executed with `RUN`. Beyond the core integer dialect, the following additional commands and functions are available:

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
| `JOY(1)` / `JOY(2)` | Joystick bitmask byte for port 1 or 2 (R-L-D-U-Y-X-B-A) |
| `SGN(<x>)` | Sign of x: `1`, `0`, or `-1` |
| `$xxxx` | Hexadecimal integer literal (e.g. `$FF` = 255, `$1000` = 4096) |

> **Note on integer range:** BASIC uses signed 16-bit integers (`-32768` to `32767`). Hex literals above `$7FFF` print as negative numbers (e.g. `$A000` = `-24576`).

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
| `$0300–$03FF` | 256B | Kernal variables (vectors, cursor, RTC, FS state) |
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
