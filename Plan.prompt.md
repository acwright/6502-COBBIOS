# Plan: COBBIOS Refactor — Video/Keyboard I/O, Storage, and Kernal Restructure

Refactor the COB 6502 BIOS ROM to transition from serial-only I/O to TMS9918 video output and GPIO keyboard input as the primary interface, while retaining serial for LOAD/SAVE via Intel HEX. Add a Kernal jump table, video driver, keyboard driver, joystick support, RTC routines, CF storage with a simple custom filesystem, and new BASIC commands (LOAD, SAVE, SYS, DIR). Restructure the Kernal for cartridge compatibility by keeping all reusable routines below $C000.

---

## Architecture Decisions

- **Output mode**: Switchable — a Kernal `IO_MODE` byte selects video OR serial. `Chrout` dispatches based on this flag.
- **Serial LOAD/SAVE**: Intel HEX format (`:LLAAAATT[DD...]CC`)
- **CF storage**: Simple custom filesystem — directory sector at LBA 0, contiguous raw data sectors per file, max 16 files
- **SYS command**: Simple JSR to address, RTS returns to BASIC
- **Monitor ($C000-$DFFF)**: Stub entry points redirecting to Wozmon
- **Keyboards**: Both matrix (CB1) and PS/2 (CA1) active simultaneously, both feed `INPUT_BUFFER`
- **Video**: TMS9918 40×24 text with cursor tracking and vertical scrolling
- **Joystick**: Simple `ReadJoystick` returning RLDUXYBA bitmask byte

---

## Phase 1: Kernal Restructure & Jump Table

*Foundation — everything depends on this.*

1. Define jump table at `$A000-$A0FF` in Kernal.asm — 85 slots of 3-byte `jmp` instructions, unused slots → `jmp UnimplementedStub`
2. Add Kernal state variables in `$0306-$032F` of KERNAL_VARS: `IO_MODE` ($0306, bit 0 = output device: 0=video/1=serial), `VID_CURSOR_X` ($0307), `VID_CURSOR_Y` ($0308), `VID_CURSOR_ADDR` ($0309-$030A)
3. Refactor `Chrout` to dispatch based on `IO_MODE` → `VideoChrout` or `SerialChrout`
4. `Chrin` — no changes needed (already reads from `INPUT_BUFFER` regardless of source)
5. Update BIOS.inc with new variable addresses
6. Verify BIOS.cfg segment sizes (KERNAL = $A000-$B7FF = 6KB; jump table uses 256B, leaving ~5.75KB)

### Jump Table Layout ($A000-$A0FF)

| Address | Routine | Purpose |
|---------|---------|---------|
| $A000 | `Chrout` | Output char (dispatched by IO_MODE) |
| $A003 | `Chrin` | Input char from buffer |
| $A006 | `WriteBuffer` | Write byte to input buffer |
| $A009 | `ReadBuffer` | Read byte from input buffer |
| $A00C | `BufferSize` | Get buffer count |
| $A00F | `InitVideo` | Initialize TMS9918 |
| $A012 | `InitKB` | Initialize GPIO/VIA keyboard |
| $A015 | `InitSC` | Initialize serial 6551 |
| $A018 | `InitSID` | Initialize SID |
| $A01B | `Beep` | Play beep tone |
| $A01E | `VideoClear` | Clear video screen |
| $A021 | `VideoPutChar` | Write char at cursor |
| $A024 | `VideoSetCursor` | Set cursor (X=col, Y=row) |
| $A027 | `VideoGetCursor` | Get cursor position |
| $A02A | `VideoScroll` | Scroll screen up one line |
| $A02D | `SerialChrout` | Direct serial output (bypass IO_MODE) |
| $A030 | `ReadJoystick1` | Read joystick 1 → A |
| $A033 | `ReadJoystick2` | Read joystick 2 → A |
| $A036 | `RtcReadTime` | Read RTC time |
| $A039 | `RtcReadDate` | Read RTC date |
| $A03C | `RtcWriteTime` | Set RTC time |
| $A03F | `RtcWriteDate` | Set RTC date |
| $A042 | `RtcReadPRAM` | Read PRAM byte |
| $A045 | `RtcWritePRAM` | Write PRAM byte |
| $A048 | `StReadSector` | Read CF sector |
| $A04B | `StWriteSector` | Write CF sector |
| $A04E | `StWaitReady` | Wait CF ready |
| $A051 | `SetIOMode` | Set IO_MODE |
| $A054 | `GetIOMode` | Get IO_MODE |
| $A057-$A0FF | Reserved | `jmp UnimplementedStub` |

### Relevant Files
- Kernal.asm — primary file: add jump table, refactor Chrout/Chrin, add IO_MODE
- BIOS.inc — add new Kernal variable addresses ($0306+)
- BIOS.cfg — verify segment sizes remain valid

### Verification
- Assemble with `make` — confirm no segment overflow errors
- Verify jump table entries appear at correct addresses in BIOS.lst
- Confirm existing `Reset` flow still works (init hardware → splash → BASIC)

---

## Phase 2: TMS9918 Video Driver

*Depends on: Phase 1*

1. Implement `VideoChrout` — write char to VRAM at cursor position, handle control chars (CR=$0D, LF=$0A, BS=$08, BEL=$07→Beep), auto-wrap at column 40, auto-scroll at row 24
2. Implement `VideoClear` — fill name table (960 bytes at VRAM $0000) with $20, reset cursor to (0,0)
3. Implement `VideoScroll` — copy VRAM rows 1-23 to 0-22 (920 bytes), clear row 23 with spaces. VRAM write: address → `VC_REG` (low byte, then high|$40), data → `VC_DATA` sequentially
4. Implement `VideoSetCursor` / `VideoGetCursor` — convert (X,Y) ↔ VRAM address (addr = Y×40 + X)
5. Implement `VideoPutChar` — low-level single-byte VRAM write at `VID_CURSOR_ADDR`
6. Implement `VideoPrintStr` — loop over null-terminated string at `STR_PTR`, calling `VideoChrout`
7. Update `Splash` — use video: clear screen, center "-- The 'COB' v1.0 --", display "ENTER=BASIC  ESC=MONITOR"
8. Update `Reset` — init all hardware → set IO_MODE=video → Splash → wait for keypress (ENTER→BASIC, ESC→Monitor)

### TMS9918 VRAM Layout (Text Mode)
- $0000-$03BF: Name table (40×24 = 960 bytes)
- $0800-$0FFF: Pattern table (character definitions, loaded from Chars.asm)

### Relevant Files
- Kernal.asm — add all Video* routines
- BIOS.inc — TMS9918 addresses already defined (VC_DATA=$9C00, VC_REG=$9C01)

### Verification
- Assemble: `make`
- Boot ROM → splash screen appears on video output
- Test control characters (CR, LF, BS) produce correct cursor movement
- Test scrolling: print >24 lines, verify screen scrolls and bottom line clears
- Test line wrap: print >40 characters without CR/LF

---

## Phase 3: Keyboard & Joystick Input

*Depends on: Phase 1. Parallel with Phase 2.*

1. Enhance `InitKB` — enable both CB2 low (matrix encoder) and CA2 low (PS/2 encoder); enable both CB1 and CA1 interrupts via `GPIO_IER`
2. Enhance `Irq` handler — add CA1 check (`GPIO_IFR` bit 1) in addition to existing CB1 check; on CA1: read `GPIO_PORTA` → `WriteBuffer`; on CB1: read `GPIO_PORTB` → `WriteBuffer` (existing)
3. Implement `KBDisable` — set CB2 high, CA2 high via PCR (disables both encoders for raw port access)
4. Implement `KBEnable` — set CB2 low, CA2 low via PCR
5. Implement `ReadJoystick1` — temporarily disable matrix encoder (CB2 high), read `GPIO_PORTB`, re-enable; return byte with bits R-L-D-U-Y-X-B-A
6. Implement `ReadJoystick2` — same pattern via CA2/`GPIO_PORTA`
7. **Note**: Joystick reads conflict with keyboard since they share ports. The read routines must briefly disable encoding, read, and re-enable. This is a known timing constraint to document.

### Relevant Files
- Kernal.asm — modify InitKB, Irq handler; add KBDisable, KBEnable, ReadJoystick1/2
- BIOS.inc — GPIO constants already defined; may need to add CA1/CA2 PCR bit constants

### Verification
- Matrix keyboard: press key → character appears on screen
- PS/2 keyboard: same test
- Both keyboards simultaneously
- Joystick read: call ReadJoystick1 via SYS, display bitmask
- KBDisable/KBEnable cycle preserves keyboard functionality

---

## Phase 4: RTC Routines

*Depends on: Phase 1. Parallel with Phase 3.*

1. Implement `RtcReadTime` — read `RTC_HR`, `RTC_MIN`, `RTC_SEC`; handle BCD↔binary conversion; return A=hours, X=minutes, Y=seconds
2. Implement `RtcReadDate` — read `RTC_YR`, `RTC_MON`, `RTC_DATE`, `RTC_CENT`; return in registers or buffer at KERNAL_VARS
3. Implement `RtcWriteTime` / `RtcWriteDate` — set DS1511Y TE bit in `RTC_CTRL_B` before writing, clear after
4. Implement `RtcReadPRAM` — read a byte from DS1511Y PRAM; input X=address ($00-$FF), output A=data byte; write address to `RTC_RAM_ADDR`, read data from `RTC_RAM_DATA`
5. Implement `RtcWritePRAM` — write a byte to DS1511Y PRAM; input X=address ($00-$FF), A=data byte; write address to `RTC_RAM_ADDR`, write data to `RTC_RAM_DATA`

### Relevant Files
- Kernal.asm — add RTC routines
- BIOS.inc — RTC addresses already defined ($8800-$8813)

### Verification
- Read time, display via BASIC PEEK of Kernal variables
- Set time, read back, confirm it advances

---

## Phase 5: CompactFlash Storage Driver

*Depends on: Phase 1.*

1. Implement `StWaitReady` — poll `ST_STATUS` until BSY=0 and RDY=1
2. Implement `StReadSector` — set LBA in `ST_LBA_0..3`, sector count=1, issue read ($20), wait DRQ, read 512 bytes from `ST_DATA`; LBA address and destination pointer passed in ZP
3. Implement `StWriteSector` — same setup, write command ($30), wait DRQ, write 512 bytes
4. Define **simple custom filesystem**: directory sector (LBA 0) with 16 × 32-byte entries: `[8B name][3B ext][1B flags][2B start_sector][2B size][16B reserved]`; data in contiguous sectors at LBA 1+
5. Implement `FsLoadFile` — scan directory for filename match, read data sectors into $0800+, return size
6. Implement `FsSaveFile` — find empty/matching dir slot, write data sectors, update directory
7. Implement `FsDirectory` — print directory listing of used entries

### Relevant Files
- Kernal.asm — add CF storage routines and filesystem logic
- BIOS.inc — CF/Storage addresses already defined ($8C00-$8C07)

### Verification
- Test StReadSector/StWriteSector with known data
- Save BASIC program → list directory → load back → RUN — compare output
- Fill all 16 directory slots
- Overwrite existing file

---

## Phase 6: Serial Intel HEX LOAD/SAVE

*Depends on: Phase 1.*

1. Implement `HexLoad` — switch IO_MODE to serial, parse incoming Intel HEX records (type $00=data, $01=EOF), validate checksums, write data to specified addresses ($0800+), abort on checksum error
2. Implement `HexSave` — generate Intel HEX records (16 bytes/record) from $0800 to PRGEND, transmit via `SerialChrout`, end with EOF record `:00000001FF`
3. Add byte↔hex ASCII conversion utilities (reusable by Monitor future work too)

### Relevant Files
- Kernal.asm — add HexLoad, HexSave, hex conversion utilities

### Verification
- Generate test Intel HEX file on host computer
- LOAD via serial → verify data in memory matches
- SAVE via serial → capture on host → verify valid Intel HEX format
- Round-trip: SAVE → LOAD → compare memory

---

## Phase 7: BASIC Enhancements

*Depends on: Phases 5 & 6.*

1. Add new tokens: `$9E`=SYS, `$9F`=LOAD, `$A0`=SAVE, `$A1`=DIR
2. Add keyword strings to `BasKeywordTable` (maintain longest-first ordering)
3. Implement `BasCmdSys` — evaluate address expression, JSR to it (use `jmp (addr)` with RTS trick)
4. Implement `BasCmdLoad` — `LOAD "filename"` → CF via `FsLoadFile`; `LOAD` (no arg) → serial via `HexLoad`; update `BAS_PRGEND` after load
5. Implement `BasCmdSave` — `SAVE "filename"` → CF via `FsSaveFile`; `SAVE` (no arg) → serial via `HexSave`; save $0800 to `BAS_PRGEND`
6. Implement `BasCmdDir` — call `FsDirectory` to list CF files
7. Update `BasDispatch` table with new token→handler mappings
8. Update boot flow — splash screen waits for ENTER (→BASIC) or ESC (→Monitor)

### Relevant Files
- BASIC.asm — add tokens, keywords, command handlers
- Kernal.asm — boot menu logic in Reset/Splash

### Verification
- `SYS $0800` calls machine code, returns to BASIC
- `SAVE "TEST"` → `NEW` → `LOAD "TEST"` → `LIST` — program matches original
- `SAVE` / `LOAD` (serial Intel HEX) round-trip succeeds
- `DIR` shows saved files
- Boot menu: ENTER → BASIC, ESC → Monitor

---

## Phase 8: Monitor Stub

*Parallel with other phases. Minimal dependency.*

1. Add `MonitorEntry` at $C000 in Monitor.asm → `jmp WozMon`
2. Add stub entry points: $C003 `MonitorExamine`, $C006 `MonitorDeposit` → both redirect to WozMon
3. Update `Break` handler in Kernal.asm to jump to `MonitorEntry` ($C000) instead of `WozMon` directly
4. Update NMI_PTR/BRK_PTR initialization in `Reset`

### Relevant Files
- Monitor.asm — replace empty stub with redirect code
- Kernal.asm — update Break handler target

### Verification
- BRK instruction → enters Wozmon via $C000 redirect
- Monitor entry from boot menu (ESC) works

---

## Phase 9: Sound Enhancements

*Parallel with other phases.*

1. Implement `SidPlayNote` — A=voice(0-2), X=freqLo, Y=freqHi; set frequency regs, gate on with triangle waveform, standard ADSR
2. Implement `SidSilence` — gate off all 3 voices, zero frequencies
3. Refactor `Beep` to use `SidPlayNote` internally with short delay then silence

### Relevant Files
- Kernal.asm — add SID routines

### Verification
- Beep at boot — confirm audible tone
- SidPlayNote with different frequencies via SYS from BASIC

---

## Dependency Graph

```
Phase 1 (Jump Table & IO_MODE)
  ├─→ Phase 2 (Video Driver)
  ├─→ Phase 3 (Keyboard/Joystick)    ← parallel with 2
  ├─→ Phase 4 (RTC)                  ← parallel with 2, 3
  ├─→ Phase 5 (CF Storage)           ← parallel with 2, 3, 4
  ├─→ Phase 6 (Serial Intel HEX)     ← parallel with 2-5
  ├─→ Phase 8 (Monitor Stub)         ← parallel, minimal deps
  └─→ Phase 9 (Sound)                ← parallel, minimal deps
Phase 7 (BASIC Enhancements)          ← depends on 5 & 6
```

---

## Relevant Files (All Phases)

| File | Changes |
|------|---------|
| Kernal.asm | Jump table, video driver, keyboard/joystick, RTC, CF storage, serial HEX, sound, boot flow — majority of new code |
| BASIC.asm | New tokens (SYS/LOAD/SAVE/DIR), keyword table, command handlers |
| Monitor.asm | Stub entry points → Wozmon redirect |
| BIOS.inc | New Kernal variable addresses ($0306-$032F), new constants |
| BIOS.cfg | Verify/adjust segment sizes if Kernal grows |
| Chars.asm | No changes |
| Wozmon.asm | No changes |
| Vectors.asm | No changes |
| BIOS.asm | No changes |

---

## End-to-End Verification

1. `make` — ROM assembles, fits in 32KB, no segment overflows
2. Inspect BIOS.lst — jump table at $A000, Monitor at $C000, BASIC at $E000
3. Boot: splash screen on video, beep plays
4. Boot menu: ENTER → BASIC prompt on video; ESC → Wozmon via Monitor stub
5. BASIC I/O: type program, LIST, RUN — output on video screen, input from keyboard
6. Both keyboards work simultaneously (matrix + PS/2)
7. `SYS $0800` — calls machine code, returns to BASIC
8. `SAVE "TEST"` → `NEW` → `LOAD "TEST"` → `LIST` — program matches original
9. `SAVE` / `LOAD` (serial Intel HEX) — round-trip succeeds
10. `DIR` — lists files on CF card
11. BRK → enters Wozmon via $C000 Monitor redirect
12. Scrolling — LIST of >24-line program scrolls video correctly

---

## Scope Boundaries

**In scope**: Jump table, video driver, keyboard/joystick, RTC, CF custom filesystem, serial Intel HEX, BASIC LOAD/SAVE/SYS/DIR, monitor stub, sound enhancements, boot menu

**Excluded**: Full monitor implementation, string variables/functions in BASIC, FAT16/FAT32, graphics modes, extended RAM card routines ($8000-$87FF), networking
