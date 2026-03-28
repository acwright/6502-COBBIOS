# Plan: Supermon-style Machine Code Monitor

## TL;DR
Implement a full-featured machine code monitor in the 8KB MONITOR segment ($C000-$DFFF) inspired by Supermon64's command set. The monitor provides memory inspection/manipulation, 65C02 disassembly, register display/modification, code execution, unified load/save (CF with filename, serial without — mirroring BASIC's LOAD/SAVE pattern), CF directory listing, and number conversion. BRK enters the monitor with full register display; X exits back to BASIC. Wozmon remains at $FF00 as an easter egg. Estimated ~4KB of the 8KB budget.

## Command Set

| Cmd | Syntax | Description |
|-----|--------|-------------|
| **M** | `M [addr] [addr]` | Memory dump (hex + ASCII, 8 bytes/line) |
| **D** | `D [addr] [addr]` | Disassemble 65C02 (20 lines default) |
| **>** | `> addr byte [byte...]` | Modify/deposit memory bytes |
| **F** | `F addr addr byte` | Fill memory range with byte |
| **T** | `T addr1 addr2 dest` | Transfer (copy) memory block |
| **H** | `H addr1 addr2 byte [byte...]` | Hunt (search) for byte pattern |
| **C** | `C addr1 addr2 addr3` | Compare two memory regions |
| **R** | `R` | Display CPU registers |
| **;** | `; PC xxxx A xx X xx Y xx SP xx` | Modify registers |
| **G** | `G [addr]` | Go — JMP to address (or saved PC) |
| **J** | `J [addr]` | JSR — call subroutine, return to monitor |
| **L** | `L ["file"] [addr]` | Load — CF if filename given, serial if not |
| **S** | `S ["file"] addr addr` | Save — CF if filename given, serial if not |
| **@** | `@` | CF directory listing |
| **N** | `N value` | Number conversion (hex/dec/bin) |
| **X** | `X` | Exit to BASIC |

## Architecture Context

### ROM Memory Map
- `$A000-$B7FF` — KERNAL (6KB) — Core routines + IRQ handlers
- `$B800-$BFFF` — CHARS (2KB) — IBM CP437 character set
- `$C000-$DFFF` — MONITOR (8KB) — Target segment for this implementation
- `$E000-$FEFF` — BASIC (7.9KB) — Integer BASIC interpreter
- `$FF00-$FFFA` — WOZMON (250B) — Apple II monitor (easter egg)
- `$FFFA-$FFFF` — VECTORS (6B) — NMI, RESET, IRQ vectors

### RAM Map
- `$0000-$00FF` — Zero Page (see ZP layout below)
- `$0100-$01FF` — CPU Stack
- `$0200-$02FF` — Input Buffer (256B ring buffer for keyboard)
- `$0300-$03FF` — Kernal Variables (IRQ/BRK/NMI pointers, video state, FS vars)
- `$0400-$07FF` — User Variables (BASIC: variables A-Z, line buffer, work stacks, token/scratch)
- `$0800-$7FFF` — Program Space (31KB)
- `$8000-$9FFF` — I/O Space

### ZP Layout
- `$00` READ_PTR, `$01` WRITE_PTR, `$02-$03` STR_PTR (Kernal)
- `$04-$23` BASIC workspace (BAS_TXTPTR, BAS_CURLINE, etc.)
- `$24-$25` CF_BUF_PTR (sector data pointer)
- `$26-$29` CF_LBA (28-bit LBA address)
- `$2A-$2B` XFER_PTR (serial transfer data pointer)
- `$2C-$2D` DELAY_CNT (SysDelay counter)
- `$2E-$35` **NEW: Monitor variables** (see Phase 1)

### Kernal Jump Table (key entries)
- `$A000` Chrout (dispatched: video or serial based on IO_MODE)
- `$A003` Chrin (read from buffer or serial)
- `$A006` WriteBuffer, `$A009` ReadBuffer, `$A00C` BufferSize
- `$A01E` VideoClear, `$A021` VideoPutChar, `$A024` VideoSetCursor
- `$A02D` SerialChrout (direct serial, bypasses IO_MODE)
- `$A048` StReadSector, `$A04B` StWriteSector, `$A04E` StWaitReady
- `$A057` AsciiLoad, `$A05A` AsciiSave (serial binary transfer)
- `$A063` FsDeleteFile, `$A066` SysDelay

### Kernal FS Internals (accessible from MONITOR segment)
- `FsParseName` — null-terminated string → 8+3 padded in FS_FNAME_BUF
- `FsFindFile` — scan directory for matching name, returns entry pointer + index
- `FsFindFree` — find first unused directory slot
- `FsCalcNextSec` — find next free sector
- `FsReadDir` / `FsWriteDir` — read/write LBA 0 directory sector
- `FsDirectory` — print directory listing
- `FsLoadFile` — load file to $0800 (hardcoded PROGRAM_START)
- `FsSaveFile` — save from $0800 (hardcoded)

### Kernal Variables ($0300+)
- `$0300-$0301` IRQ_PTR
- `$0302-$0303` BRK_PTR
- `$0304-$0305` NMI_PTR
- `$0306` IO_MODE (bit 0: 0=video, 1=serial)
- `$0307` VID_CURSOR_X, `$0308` VID_CURSOR_Y, `$0309-$030A` VID_CURSOR_ADDR
- `$0310` BRK_P, `$0311` BRK_PCL, `$0312` BRK_PCH
- `$0313` **NEW: BRK_A**, `$0314` **NEW: BRK_X**, `$0315` **NEW: BRK_Y**, `$0316` **NEW: BRK_SP**
- `$0317-$0318` XFER_REMAIN, `$0319` XFER_IO_SAVE
- `$0320-$0347` SCROLL_BUF (40-byte video scroll temp)
- `$0348-$035A` FS temp vars (FS_START_SEC, FS_FILE_SIZE, etc.)
- `$0600-$07FF` FS_SECTOR_BUF (512B, overlaps BAS_TOKBUF/BAS_STRBUF)

### BRK Flow (current)
1. CPU executes BRK → pushes PCH, PCL, P to stack → jumps to ($FFFE)
2. IRQ handler at ($FFFE) checks B flag (bit 4) in saved P register
3. If B=1 (BRK): restores A/X/Y pushed by IRQ preamble, `cli`, `jmp (BRK_PTR)`
4. BRK_PTR → `Break` handler: pulls P/PCL/PCH from stack, saves to BRK_P/BRK_PCL/BRK_PCH
5. Currently: `jmp MonitorEntry` → `jmp WozMon` (stub)

### BASIC BRK Command
- Token `$9D` (TOK_BRK)
- Handler `BasCmdBrk`: `stz BAS_FLAGS` (clear run flag) then `brk` → triggers above flow
- No changes needed to BASIC — hardware BRK path enters new monitor automatically

### Boot Menu
- After init + splash screen, waits for keypress
- ENTER → `jsr VideoClear` + `jmp BasEntry`
- ESC → `jsr VideoClear` + `jmp MonitorEntry` ($C000)

### Wozmon ZP Usage ($24-$2B) — conflicts, but irrelevant
- WOZ_XAML/H ($24-$25), WOZ_STL/H ($26-$27), WOZ_L/H ($28-$29), WOZ_YSAV ($2A), WOZ_MODE ($2B)
- Overlaps CF_BUF_PTR, CF_LBA, XFER_PTR — acceptable since Wozmon is standalone easter egg

### Build System
- `cl65 -t none -C BIOS.cfg -l BIOS.lst -o BIOS.bin BIOS.asm` (cc65 toolchain)
- BIOS.cfg defines all memory segments
- BIOS.asm includes all source files via `.include`

## Phases

### Phase 1: Core Infrastructure + BRK Integration
*Foundation — everything else depends on this.*

1. **Define monitor variables in BIOS.inc**
   - ZP: MON_ADDR ($2E-$2F), MON_END ($30-$31), MON_TMP ($32-$33), MON_BYTE ($34), MON_IDX ($35)
   - RAM: BRK_A ($0313), BRK_X ($0314), BRK_Y ($0315), BRK_SP ($0316) — extend existing BRK_P/PCL/PCH block
   - Monitor uses BAS_LINBUF ($0434, 204 bytes) for command line input (safe: BASIC isn't reading while monitor is active)

2. **Fix Break handler in Kernal.asm** to save full CPU state
   - On entry from IRQ BRK path: A/X/Y are the user's original values (IRQ handler restores them before `jmp (BRK_PTR)`)
   - Save A→BRK_A, X→BRK_X, Y→BRK_Y before pulling P/PC from stack
   - Save SP (adjusted for CPU's push of PCH/PCL/P) to BRK_SP
   - Change final jump: `jmp MonitorEntry` → `jmp MonitorBrkEntry` (separate entry that prints registers)

3. **Implement monitor core in Monitor.asm** (replace current 3-line stub)
   - `MonitorEntry` — cold entry (from boot menu / exit-then-return): print banner "MONITOR", fall into command loop
   - `MonitorBrkEntry` — BRK entry: print "BRK AT $xxxx", display registers (R command output), fall into command loop
   - `MonReadLine` — read input line into BAS_LINBUF via Kernal Chrin/Chrout, handle backspace, CR terminates
   - `MonParseLine` — skip spaces, dispatch first char to command handler
   - Hex parsing utilities: `MonParseHex4` (parse 4-digit hex → 16-bit), `MonParseHex2` (parse 2-digit hex → 8-bit), `MonSkipSpaces`
   - Hex output utilities: `MonPrintHex2` (A → "XX"), `MonPrintHex4` (MON_ADDR → "XXXX"), `MonPrintSpace`, `MonPrintCRLF`
   - Command dispatch table (single char → handler address)
   - `MonCmdX` — exit: `jmp BasColdStart` (preserves program in memory, re-inits BASIC state)
   - Error handler: print "?" for unrecognized command, return to prompt

4. **Wire up system integration**
   - Break handler already reached via BRK→IRQ→BRK_PTR — just update handler code
   - Boot menu ESC already jmps to MonitorEntry ($C000) — no change needed
   - BASIC BRK command already executes `brk` opcode → triggers IRQ → Break → MonitorBrkEntry — automatic

5. **Preserve Wozmon** — remains at $FF00, no changes needed. MonitorEntry no longer redirects to WozMon.

**Verification:** Boot → ESC enters monitor with "." prompt. Type "X" → returns to BASIC. In BASIC, type `BRK` → monitor shows registers. Unknown commands show "?".

### Phase 2: Memory Inspection (M, D, R)
*Depends on Phase 1. The most essential monitoring features.*

6. **M command — Memory dump**
   - Format: `.: ADDR  XX XX XX XX XX XX XX XX  ABCDEFGH` (8 bytes/row, printable ASCII sidebar)
   - Default: 8 lines (64 bytes). With range: dump entire range.
   - Remembers last end address → subsequent bare `M` continues where left off.

7. **R command — Register display**
   - Format: `PC=xxxx A=xx X=xx Y=xx SP=xx NV-BDIZC` with actual flag letters or dashes
   - Reads from BRK_P, BRK_PCL/PCH, BRK_A, BRK_X, BRK_Y, BRK_SP

8. **D command — Disassembler** *(largest single component ~1.2KB)*
   - Full 65C02 opcode table: 256 entries × 2 bytes each (mnemonic index + addressing mode) = 512 bytes
   - ~70 unique mnemonics (full WDC 65C02 set including Rockwell BBR/BBS/SMB/RMB, STZ, TRB, TSB, PHX/PHY/PLX/PLY, WAI, STP)
   - Mnemonic string table: 3 chars × ~70 = 210 bytes
   - 16 addressing modes with format handlers
   - Output format: `., ADDR  OP [OP OP]  MNE operand`
   - Default: 20 lines. Remembers position for continuation.
   - Branch targets shown as absolute addresses (relative offset + PC + 2)

**Verification:** `M 0800 0840` shows hex dump. `D C000` disassembles monitor's own code. `R` shows current register state.

### Phase 3: Memory Manipulation (>, F, T, H, C)
*Depends on Phase 1. Can be built in parallel with Phase 2.*

9. **> command — Deposit bytes**
   - `> ADDR XX [XX XX ...]` — write bytes starting at addr
   - Parse hex bytes separated by spaces until end of line

10. **F command — Fill**
    - `F ADDR1 ADDR2 XX` — fill range [addr1, addr2] with byte value

11. **T command — Transfer (copy)**
    - `T SRC_START SRC_END DEST` — block copy
    - Handle overlapping regions correctly (copy forward or backward depending on direction)

12. **H command — Hunt (search)**
    - `H ADDR1 ADDR2 XX [XX XX ...]` — search for byte pattern in range
    - Print each matching address on its own line

13. **C command — Compare**
    - `C ADDR1 ADDR2 ADDR3` — compare [addr1,addr2] with block at addr3
    - Print addresses where bytes differ

**Verification:** `> 0800 EA EA EA` deposits three NOPs. `F 0900 09FF 00` fills with zeros. `H 0800 09FF EA` finds the NOPs. `T 0800 0802 0900` copies. `C 0800 0802 0900` shows no differences.

### Phase 4: Execution Control (G, J, ;)
*Depends on Phase 1 (register save/restore) and Phase 2 (R command).*

14. **G command — Go (JMP)**
    - `G [ADDR]` — if addr given, set BRK_PCL/PCH. Restore all saved registers (A, X, Y, P) via RTI to target address.
    - The program runs until BRK (returns to monitor) or forever.

15. **J command — JSR (call and return)**
    - `J [ADDR]` — push monitor re-entry address onto stack, JMP to target.
    - When called code does RTS, returns to monitor, saves registers, displays them.

16. **; command — Modify registers**
    - `; PC XXXX A XX X XX Y XX SP XX` — parse labeled register values and update BRK_* variables
    - Flexible: any subset of registers can be specified in any order

**Verification:** `> 0800 A9 42 00` deposits LDA #$42 / BRK. `G 0800` → monitor re-enters, R shows A=42. `; A 00` resets A. `J 0800` → same but returns via BRK, shows A=42.

### Phase 5: File I/O & Utilities (L, S, @, N)
*Depends on Phase 1. Reuses Kernal routines.*

17. **L command — Load (CF or serial)**
    - Dispatch: if next non-space char is `"`, use CF path; otherwise use serial path (same pattern as BASIC LOAD/SAVE)
    - **CF path:** `L "FILENAME" [ADDR]` — parse filename, call FsParseName, FsFindFile, then multi-sector read loop
      - If addr specified: set CF_BUF_PTR to that address (override default $0800)
      - If no addr: load to $0800 (same as BASIC LOAD)
      - Reuse Kernal FS internal routines (FsParseName, FsFindFile, FsReadDir, StReadSector) — replicate the sector read loop with custom target address since FsLoadFile hardcodes PROGRAM_START
      - Print "LOADED nnnn BYTES AT $xxxx" on success, "FILE NOT FOUND" on failure
    - **Serial path:** `L [ADDR]` — receive binary via serial (reuse AsciiLoad protocol: 2-byte size header + raw data)
      - If addr specified: set XFER_PTR to that address
      - If no addr: load to $0800 (default PROGRAM_START)
      - Calls AsciiLoad Kernal routine (or adapted version)
      - Print "LOADED nnnn BYTES AT $xxxx" on success

18. **S command — Save (CF or serial)**
    - Dispatch: if next non-space char is `"`, use CF path; otherwise use serial path
    - **CF path:** `S "FILENAME" ADDR1 ADDR2` — save bytes [addr1, addr2) to CF
      - Compute size = addr2 - addr1
      - Reuse/adapt FS internals with custom source address and size
      - Print "SAVED nnnn BYTES" on success
    - **Serial path:** `S ADDR1 ADDR2` — send binary via serial
      - Compute size, set XFER_PTR, call AsciiSave Kernal routine (or adapted version)
      - Print "SAVED nnnn BYTES" on success

19. **@ command — Directory**
    - Calls Kernal FsDirectory directly (prints all used entries with name.ext + size)

20. **N command — Number conversion**
    - `N $XX` or `N $XXXX` or `N +DDD` or `N %BBBBBBBB` — parse hex, decimal, or binary input
    - Output all three representations: `$XXXX  +DDDDD  %BBBBBBBBBBBBBBBB`

**Verification:** `@` shows CF directory. `S "TEST" 0800 0810` saves 16 bytes to CF, `L "TEST" 0900` loads them at $0900, `C 0800 080F 0900` confirms match. `S 0800 0810` sends 16 bytes via serial, `L 0900` receives via serial to $0900. `N $FF` shows `$00FF  +255  %0000000011111111`.

## Files to Modify

| File | Change |
|------|--------|
| **BIOS.inc** | Add monitor ZP vars ($2E-$35) and RAM vars (BRK_A/X/Y/SP at $0313-$0316) |
| **Monitor.asm** | **Replace entirely**: command loop, all command handlers, disassembler tables, hex I/O utilities (~3.5-4KB) |
| **Kernal.asm** | Modify `Break` handler (~line 1884) to save A/X/Y/SP; change final jmp to MonitorBrkEntry |
| **BIOS.cfg** | No changes (MONITOR segment already $C000-$DFFF) |
| **Wozmon.asm** | No changes (remains at $FF00 as easter egg) |
| **BASIC.asm** | No changes (BRK command already triggers hardware BRK → new handler) |

## Verification Checklist

1. **Build check:** `make` compiles without errors, ROM binary ≤ 32KB, MONITOR segment usage reported in listing file
2. **Boot integration:** ESC at splash → monitor banner + "." prompt (not WozMon)
3. **BRK from BASIC:** Start BASIC, type `BRK` → shows "BRK AT $xxxx" + registers + "." prompt
4. **Exit to BASIC:** In monitor, type `X` → BASIC welcome banner, previous program intact
5. **Memory commands:** M, D, >, F, T, H, C all operate correctly on known memory patterns
6. **Execution:** G/J execute code and return on BRK with correct register state
7. **File I/O:** L/S round-trip a file on CF (with quoted filename); L/S round-trip via serial (without filename)
8. **Wozmon easter egg:** `G FF00` from monitor (or SYS $FF00 from BASIC) enters WozMon

## Design Decisions

- **Mini-assembler (A command):** Deferred to future phase
- **Single-step/trace:** Deferred to future phase
- **Breakpoint table:** Deferred; use manual BRK opcodes for now
- **Register format:** Compact single-line: `PC=xxxx A=xx X=xx Y=xx SP=xx NV-BDIZC`
- **Register modify:** `;` command (`.` is reserved as the prompt character)
- **Load address:** User-specified (default $0800 if omitted)
- **Unified L/S:** Filename in quotes → CF; no filename → serial (mirrors BASIC LOAD/SAVE dispatch)
- **Exit to BASIC:** `jmp BasColdStart` for clean re-entry (preserves program in memory but re-initializes BASIC state)
- **Prompt character:** `.` (period) — Supermon style
- **Line prefix style:** No space between prefix punctuation and hex address. M uses `.:ADDR`, D uses `.,ADDR`. This keeps lines under 40 columns to avoid double-newline from video auto-wrap + CRLF.
- **Monitor line buffer:** Shares BAS_LINBUF ($0434) — safe since BASIC is suspended during monitor use
- **ZP sharing:** Monitor ZP ($2E-$35) doesn't overlap Kernal ($00-$03), BASIC ($04-$23), or CF/serial ($24-$2D)
- **Wozmon:** Untouched at $FF00, accessible via `G FF00`
- **Opcode table encoding:** 256×2 byte table (512B) with mnemonic index + addressing mode — fast lookup, acceptable size
- **65C02 coverage:** Full WDC 65C02 set including Rockwell extensions (BBR/BBS/SMB/RMB), STZ, TRB, TSB, PHX/PHY, WAI, STP

## Further Considerations

1. **BasColdStart vs BasWarmStart for X command:** BasColdStart reinitializes variables and prints banner but preserves the program in memory. A warm return (jumping to BasMainLoop) would preserve variables too but requires BASIC ZP to be undisturbed. Use BasColdStart for safety — monitor doesn't touch BASIC ZP ($04-$23), but a fresh start is more predictable. Could add `XW` (warm exit) later.

2. **L/S Kernal reuse strategy:** BASIC's LOAD/SAVE dispatch on the presence of a quoted filename — monitor L/S uses the identical pattern. For CF: BASIC's internal FsLoadFile/FsSaveFile hardcode PROGRAM_START as the data address, so the monitor replicates the sector-read/write loop with CF_BUF_PTR set to the user's target address. For serial: calls AsciiLoad/AsciiSave with XFER_PTR set to the user's target address. This avoids any Kernal changes while reusing StReadSector/StWriteSector, FsParseName, FsFindFile, FsReadDir/FsWriteDir, AsciiLoad, and AsciiSave.

3. **Future phases (not in current plan):**
   - Mini-assembler (A command) — enter 65C02 mnemonics directly
   - Software breakpoint table (B command) — insert/remove BRK opcodes automatically
   - Single-step/trace (T as trace, rename current T to something else)
   - Sprite/graphics inspection tools
