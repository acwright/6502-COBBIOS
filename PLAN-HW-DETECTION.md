# Hardware Detection & Defensive Boot

## Prompt

You are implementing hardware detection and defensive boot measures for a 6502 backplane computer BIOS (the "COB"). The system is a computer-on-a-backplane arrangement where IO cards (Serial, RTC, CompactFlash, SID sound, Video, GPIO/keyboard) may be absent. The BIOS must boot gracefully regardless of which cards are installed.

Execute each phase in order. After completing each phase, verify the project still assembles cleanly with `make` before proceeding. Commit after each phase.

---

## Architecture Context

### Memory Map
- `$0000-$00FF` — Zero Page (see BIOS.inc for layout)
- `$0100-$01FF` — CPU Stack
- `$0200-$02FF` — Input Buffer (256B circular)
- `$0300-$03FF` — Kernal Variables (IRQ/BRK/NMI pointers, IO_MODE, cursor state, etc.)
- `$0400-$07FF` — User Variables / BASIC workspace
- `$0800-$7FFF` — Program Space (31KB)
- `$8000-$9FFF` — I/O Space (memory-mapped hardware cards)
- `$A000-$FFFF` — ROM (Kernal, Chars, Monitor, BASIC, Wozmon, Vectors)

### I/O Card Addresses
- IO 1: RAM Card Low (`$8000-$83FF`) — optional (banked SRAM)
- IO 2: RAM Card High (`$8400-$87FF`) — optional (banked SRAM)
- IO 3: RTC DS1511Y (`$8800-$881F`) — optional
- IO 4: CompactFlash 8-bit IDE (`$8C00-$8C07`) — optional
- IO 5: Serial R65C51 (`$9000-$9003`) — optional
- IO 6: GPIO/VIA 65C22 (`$9400-$940F`) — optional (keyboard + joysticks)
- IO 7: SID/ARMSID (`$9800-$981C`) — optional
- IO 8: Video TMS9918/pico9918 (`$9C00-$9C01`) — optional

### Current Boot Flow (Reset in Kernal.asm)
```
Reset → cld, sei, init stack
      → set IRQ_PTR, BRK_PTR, NMI_PTR
      → InitBuffer (circular buffer pointers)
      → InitSC (serial 6551: write SC_CTRL, SC_CMD)
      → InitSID (clear 29 SID regs, set volume max)
      → InitVideo (TMS9918: write 8 registers)
      → InitCharacters (copy 2KB charset to VRAM)
      → InitKB (VIA: set DDRB/DDRA, PCR, IER)
      → StInit (CF: StWaitReady → Set Features 8-bit) ← HANGS if CF absent
      → IO_MODE = 0 (video default)
      → init cursor state
      → Beep (SID tone via SidPlayNote + busy delay) ← HANGS if GPIO absent (SysDelay polls VIA T1)
      → Splash (VideoClear + print title/menu)
      → cli (enable interrupts)
      → @BootWait loop (infinite poll for keypress) ← never times out
      → ENTER=BASIC, ESC=Monitor
```

### Key Problems With Missing Hardware
1. **CompactFlash absent**: `StWaitReady` polls `ST_STATUS` in infinite loop (BSY/RDY never stabilize) → **hard hang**
2. **GPIO/VIA absent**: `SysDelayImpl` polls `GPIO_IFR` T1 flag forever → **hard hang** (called by `BeepImpl`)
3. **Serial absent**: IRQ handler always reads `SC_STATUS` — floating bus may inject garbage into input buffer; `ChrinImpl` unconditionally writes `SC_CMD` for RTS flow control
4. **Video absent**: Splash screen invisible; boot menu unanswerable (but no hang)
5. **RTC absent**: TIME/DATE return garbage (no hang)
6. **SID absent**: Beep has no audible output (writes are harmless, no hang)

### Design Decisions
- **Minimum config**: CPU + RAM + ROM + at least Video OR Serial (auto-detect which)
- **RAM cards**: Banked SRAM on IO 1/IO 2 — probed but not required for boot; presence recorded for userland
- **Boot timeout**: Auto-boot BASIC after ~5 seconds if no keypress
- **Absent SID**: Skip beep silently (no software delay substitute)
- **Error reporting**: Silent — set `HW_PRESENT` flags only, no visible "NOT FOUND" messages
- **Console fallback**: If video absent but serial present, auto-switch `IO_MODE` to serial
- **`HW_PRESENT` location**: `$030D` in Kernal Vars (currently reserved)

### Existing Code Conventions
- Jump table labels = public API (`Chrout`, `Chrin`, etc.) at `$A000+`
- Implementation labels = `*Impl` suffix (`ChrinImpl`, `InitKBImpl`, etc.)
- Carry flag convention: clear = success, set = error (used by CF routines, etc.)
- 65C02 instruction set (includes `stz`, `bra`, `phx`/`plx`, `phy`/`ply`)
- ca65 assembler syntax (`:=` for constants, `.byte`, `.asciiz`, `.repeat`, etc.)

---

## Phase 1 — Define HW_PRESENT Infrastructure

### BIOS.inc
Add `HW_PRESENT` variable and bit constants. Location: after the `RTC_TMP := $030C` line, replacing the `$030D-$030F Reserved` comment.

```
HW_PRESENT          := $030D             ; Hardware present bitmask (set during Reset probe)
; HW_PRESENT bit definitions (bit order matches IO slot numbers)
HW_RAM_L            = %00000001          ; Bit 0: RAM card low  (IO 1, $8000-$83FF)
HW_RAM_H            = %00000010          ; Bit 1: RAM card high (IO 2, $8400-$87FF)
HW_RTC              = %00000100          ; Bit 2: RTC card (IO 3, DS1511Y)
HW_CF               = %00001000          ; Bit 3: Storage card (IO 4, CompactFlash)
HW_SC               = %00010000          ; Bit 4: Serial card (IO 5, R65C51)
HW_GPIO             = %00100000          ; Bit 5: GPIO card (IO 6, 65C22 VIA — keyboard/joysticks)
HW_SID              = %01000000          ; Bit 6: Sound card (IO 7, SID/ARMSID)
HW_VID              = %10000000          ; Bit 7: Video card (IO 8, TMS9918/pico9918)
```

Update the reserved comment to reflect only `$030E-$030F` remaining reserved.

Note: bit order matches IO slot numbers (IO 1 = bit 0 through IO 8 = bit 7).

### Kernal.asm
In the `Reset` routine, add `stz HW_PRESENT` immediately before the first hardware init call (`jsr InitBuffer`). This ensures all bits start clear.

---

## Phase 2 — Hardware Probes

Add probe routines to Kernal.asm (near the existing `Init*` routines). Each probe tests for device presence and sets the corresponding bit in `HW_PRESENT` on success. The `Reset` routine must be restructured to: probe → conditionally init each device.

### Probe Methods

**ProbeRAM** — Banked SRAM read-back test (covers IO 1 and IO 2):
```
; For each RAM bank (low/high):
; Select bank 0 via RAM_BANK_L / RAM_BANK_H
; Read existing value from RAM_DATA_L / RAM_DATA_H, save it
; Write $A5, read back — if match, write $5A, read back — if both match → set HW_RAM_L / HW_RAM_H
; Restore original value afterward
; Two-pattern test ($A5 then $5A) reduces false positives from floating bus
```

**ProbeVideo** — TMS9918 VRAM read-back test:
```
; Write $A5 to VRAM address $0000, read it back
; TMS9918 write: send low addr byte to VC_REG, then (high | $40) to VC_REG, then data to VC_DATA
; TMS9918 read: send low addr byte to VC_REG, then high byte (bit 6 clear) to VC_REG, then read VC_DATA
; If read-back matches → set HW_VID
```

**ProbeGPIO** — VIA DDR register read-back test:
```
; GPIO_DDRB is a read/write register
; Write $AA to GPIO_DDRB, read it back
; If match → set HW_GPIO
; Restore GPIO_DDRB to $00 afterward (will be set properly by InitKBImpl)
```

**ProbeSerial** — R65C51 TDRE-after-reset test:
```
; Write $00 to SC_RESET (programmatic reset)
; Read SC_STATUS — after reset, the R65C51 sets TDRE (bit 4) = 1
; On a floating bus, bit 4 won't reliably be set
; If (SC_STATUS & SC_STATUS_TDRE) != 0 → set HW_SC
; Note: the R65C51 has a known bug where TDRE is always set; this works in our favor as a probe
```

**ProbeSID** — Active oscillator test:
```
; Configure voice 3 with a known frequency and noise waveform (fast-changing output)
; Write frequency, set gate + noise waveform on V3
; Brief software delay (~100 iterations)
; Read SID_OSC3 — if non-zero or non-$FF → SID is present, set HW_SID
; Clean up: silence voice 3
; Fallback: if probe is unreliable on real hardware, default HW_SID to set
```

**ProbeRTC** — DS1511Y NVRAM read-back test:
```
; Write $00 to RTC_RAM_ADDR (select NVRAM address 0)
; Read existing value from RTC_RAM_DATA, save it
; Write $A5 to RTC_RAM_DATA
; Read back RTC_RAM_DATA
; If match → set HW_RTC
; Restore original value to RTC_RAM_DATA
```

**CompactFlash** — Handled by timeout in Phase 3. CF presence determined by whether `StWaitReady` returns before timeout. Set `HW_CF` in `StInit` on success.

### Reset Restructure
Replace the current sequential init block with probe-then-init pattern:
```
  stz HW_PRESENT              ; Clear all hardware flags

  jsr InitBuffer               ; Always — RAM-only, no hardware

  jsr ProbeRAM                 ; Sets HW_RAM_L / HW_RAM_H if present (no init needed)

  ; Probe and conditionally init each card (IO slot order):
  jsr ProbeRTC                 ; Sets HW_RTC if present (no init needed)

  jsr StInit                   ; CF: timeout handles absent card, sets HW_CF on success

  jsr ProbeSerial              ; Sets HW_SC if present
  lda HW_PRESENT
  and #HW_SC
  beq @SkipSerial
  jsr InitSCImpl
@SkipSerial:

  jsr ProbeGPIO                ; Sets HW_GPIO if present
  lda HW_PRESENT
  and #HW_GPIO
  beq @SkipGPIO
  jsr InitKBImpl
@SkipGPIO:

  jsr ProbeSID                 ; Sets HW_SID if present
  lda HW_PRESENT
  and #HW_SID
  beq @SkipSID
  jsr InitSIDImpl
@SkipSID:

  jsr ProbeVideo               ; Sets HW_VID if present
  lda HW_PRESENT
  and #HW_VID
  beq @SkipVideo
  jsr InitVideoImpl
  jsr InitCharacters
@SkipVideo:
```

---

## Phase 3 — Add Timeouts to Polling Loops

### StWaitReadyImpl
Replace the infinite BSY/RDY poll with an outer X/Y countdown. ~65536 iterations before timeout.

```asm
StWaitReadyImpl:
  ldx #$00                      ; Outer timeout counter (256 × 256 = 65536 iterations)
  ldy #$00
@StWaitBsy:
  lda ST_STATUS
  and #ST_STATUS_BSY
  beq @StCheckRdy               ; BSY clear — check RDY
  dey
  bne @StWaitBsy
  dex
  bne @StWaitBsy
  sec                           ; Timed out — no device
  rts
@StCheckRdy:
  lda ST_STATUS
  and #ST_STATUS_RDY
  bne @StCheckErr               ; RDY set — check for errors
  dey
  bne @StWaitBsy
  dex
  bne @StWaitBsy
  sec                           ; Timed out
  rts
@StCheckErr:
  lda ST_STATUS
  and #ST_STATUS_ERR
  bne @StWaitErr
  clc                           ; Ready, no error
  rts
@StWaitErr:
  sec
  rts
```

### StWaitDrq
Same timeout pattern — X/Y countdown wrapping the BSY/DRQ poll.

### StInit Update
After the first `StWaitReady` returns successfully, set the `HW_CF` bit:
```asm
StInit:
  jsr StWaitReady
  bcs @StInitDone               ; Timeout or error — CF not present
  ; CF responded — set presence flag
  lda HW_PRESENT
  ora #HW_CF
  sta HW_PRESENT
  ; Continue with Set Features for 8-bit mode
  lda #ST_FEAT_8BIT
  sta ST_FEATURE
  ...
```

### SysDelayImpl Guard
Check `HW_GPIO` at entry. If GPIO absent, fall back to a pure software busy-wait loop:
```asm
SysDelayImpl:
  sta DELAY_CNT
  stx DELAY_CNT + 1
  ora DELAY_CNT + 1
  beq @DelayDone
  ; Check if VIA is present for hardware timer
  lda HW_PRESENT
  and #HW_GPIO
  bne @DelayHardware
  ; Software fallback — calibrated busy loop (~10ms per centisecond at 1MHz)
  ; Inner loop: 5 cycles × 2000 iterations ≈ 10000 cycles ≈ 10ms
@DelaySoftLoop:
  ldy #$00                      ; 256 outer iterations
  ldx #8                        ; ~8 × 256 × 5 ≈ 10240 cycles
@DelaySoftInner:
  dey
  bne @DelaySoftInner
  dex
  bne @DelaySoftInner
  ; 16-bit decrement of DELAY_CNT
  lda DELAY_CNT
  bne @SoftDecLo
  dec DELAY_CNT + 1
@SoftDecLo:
  dec DELAY_CNT
  lda DELAY_CNT
  ora DELAY_CNT + 1
  bne @DelaySoftLoop
  rts
@DelayHardware:
  ; ... existing VIA T1 code ...
```

---

## Phase 4 — Guard IRQ Handler

In the `Irq` handler, gate the serial and keyboard checks behind `HW_PRESENT` flags.

### Guard Serial Check
At `@IrqSc`, before reading `SC_STATUS`:
```asm
@IrqSc:
  lda HW_PRESENT
  and #HW_SC
  beq @IrqCheckKB               ; Serial not present — skip
  lda SC_STATUS
  and #SC_STATUS_IRQ
  ...
```

### Guard Keyboard Check
At `@IrqCheckKB`, before reading `GPIO_IFR`:
```asm
@IrqCheckKB:
  lda HW_PRESENT
  and #HW_GPIO
  beq @IrqExit                  ; GPIO not present — skip
  lda GPIO_IFR
  and #GPIO_INT_CB1
  ...
```

---

## Phase 5 — Guard ChrinImpl Flow Control

Wrap the `SC_CMD` writes for RTS flow control with a serial presence check:
```asm
  ; After reading from buffer and echoing...
  jsr BufferSize
  cmp #$B0
  bcc @ChrinNotFull
  ; Only touch SC_CMD if serial is present
  lda HW_PRESENT
  and #HW_SC
  beq @ChrinExit
  lda #$01                      ; RTSB high
  sta SC_CMD
  bra @ChrinExit
@ChrinNotFull:
  lda HW_PRESENT
  and #HW_SC
  beq @ChrinExit
  lda #$09                      ; RTSB low
  sta SC_CMD
@ChrinExit:
  ...
```

---

## Phase 6 — Guard Boot-Time Routines

### BeepImpl
Add early exit if SID absent:
```asm
BeepImpl:
  lda HW_PRESENT
  and #HW_SID
  bne @BeepStart
  rts                           ; No SID — skip silently
@BeepStart:
  ; ... existing beep code ...
```

### Splash
Guard all video calls:
```asm
Splash:
  lda HW_PRESENT
  and #HW_VID
  bne @SplashStart
  rts                           ; No video — skip
@SplashStart:
  jsr VideoClear
  ; ... existing splash code ...
```

---

## Phase 7 — Console Auto-Detection & Boot Menu Timeout

### Console Fallback in Reset
After all probes and inits complete, determine which console to use:
```asm
  ; Console auto-detection
  lda HW_PRESENT
  and #HW_VID
  bne @ConsoleVideo             ; Video present — use it
  lda HW_PRESENT
  and #HW_SC
  bne @ConsoleSerial            ; Serial present — use it
  ; Neither — halt (no console available)
@Halt:
  bra @Halt

@ConsoleVideo:
  lda #$00                      ; IO_MODE = video
  sta IO_MODE
  stz VID_CURSOR_X
  stz VID_CURSOR_Y
  stz VID_CURSOR_ADDR
  stz VID_CURSOR_ADDR + 1
  bra @ConsoleDone

@ConsoleSerial:
  lda #$01                      ; IO_MODE = serial
  sta IO_MODE

@ConsoleDone:
  jsr Beep                      ; (guarded by Phase 6)
  jsr Splash                    ; (guarded by Phase 6)
  cli
```

### Boot Menu Timeout
Replace the infinite `@BootWait` loop with a ~5-second timeout that auto-boots BASIC.

Strategy: Use an outer counter. Each iteration calls `SysDelay` for 10 centiseconds (100ms), then checks for keypress. After 50 iterations (50 × 100ms = 5s) with no key → auto-boot BASIC.

```asm
  ldx #50                       ; 50 × 100ms = 5 seconds
@BootWait:
  phx                           ; Save timeout counter
  lda #10                       ; 10 centiseconds (100ms)
  ldx #$00                      ; High byte = 0
  jsr SysDelay
  jsr BufferSize
  plx                           ; Restore timeout counter
  bne @BootGotKey               ; Key available — process it
  dex
  bne @BootWait                 ; No key yet — keep waiting
  bra @BootBASIC                ; Timeout — auto-boot BASIC

@BootGotKey:
  jsr ReadBuffer
  cmp #$0D                      ; ENTER?
  beq @BootBASIC
  cmp #$1B                      ; ESC?
  beq @BootMonitor
  bra @BootWait                 ; Ignore other keys (note: X still has counter)

@BootBASIC:
  jsr VideoClear                ; (safe — VideoClearImpl writes are harmless if no video)
  jmp BasEntry

@BootMonitor:
  brk
```

Note: The `bra @BootWait` after ignoring a key needs careful handling — X was restored from the stack but the counter wasn't pushed again. Restructure to re-push or use a ZP byte for the counter.

---

## Phase 8 — Guard BASIC Hardware Commands

### LOAD/SAVE/DIR (CompactFlash)
At the top of `BasCmdLoad` CF path, `BasCmdSave` CF path, and `BasCmdDir`:
```asm
  lda HW_PRESENT
  and #HW_CF
  bne @HasCF
  ; Print "NO DEVICE" error and return
  lda #<BasStrNoDevice
  sta BAS_TMP1
  lda #>BasStrNoDevice
  sta BAS_TMP1 + 1
  jsr BasPrintStr
  rts
@HasCF:
  ; ... existing code ...
```

Add string: `BasStrNoDevice: .asciiz "NO DEVICE"`

Similarly guard serial LOAD/SAVE paths with `HW_SC` check.

### TIME/DATE (RTC)
At entry to `BasCmdTime` and `BasCmdDate`, check `HW_RTC`. If absent → print "NO DEVICE" and return.

### SOUND/VOL (SID)
At entry to `BasCmdSound` and `BasCmdVol`, check `HW_SID`. If absent → silently return (no error message — consistent with silent beep skip).

---

## Phase 9 — Guard Remaining Hardware Paths (Monitor, Kernal, BASIC)

Phase 8 covered BASIC's LOAD/SAVE/DIR/TIME/DATE/SOUND/VOL/BANK commands. This final phase guards every remaining unprotected hardware access: Monitor I/O commands, Kernal-level serial transfer routines, BASIC video commands, the JOY() function, and the SID/joystick Kernal implementations exposed through the jump table.

### 9A — Guard Monitor Commands (L, S, @)

**MonCmdDir** — Currently calls `FsDirectory` unconditionally, which reads CF sector 0.
```asm
MonCmdDir:
  lda HW_PRESENT
  and #HW_CF
  bne @DirHasCF
  jsr MonPrintIOErr              ; Reuse existing "I/O ERROR" message
  rts
@DirHasCF:
  jsr FsDirectory
  rts
```

**MonCmdLoad** — Two paths: CF (quoted filename) and serial (no filename).
- CF path: guard with `HW_CF` before calling any `Fs*`/`St*` routines.
- Serial path: guard with `HW_SC` before calling serial receive routines.
```asm
MonCmdLoad:
  jsr MonSkipSpaces
  ldy MON_IDX
  lda MON_LINBUF,y
  cmp #'"'
  bne @LoadSerial
  ; --- CF path ---
  lda HW_PRESENT
  and #HW_CF
  bne @LoadCF
  jsr MonPrintIOErr
  rts
@LoadCF:
  jmp @LoadCFBody               ; Continue to existing CF load logic

@LoadSerial:
  lda HW_PRESENT
  and #HW_SC
  bne @LoadSerialBody
  jsr MonPrintIOErr
  rts
@LoadSerialBody:
  ; ... existing serial load code ...
```

**MonCmdSave** — Same dual-path pattern as Load.
- CF path: guard with `HW_CF`.
- Serial path: guard with `HW_SC`.
```asm
MonCmdSave:
  jsr MonSkipSpaces
  ldy MON_IDX
  lda MON_LINBUF,y
  cmp #'"'
  bne @SaveSerial
  ; --- CF path ---
  lda HW_PRESENT
  and #HW_CF
  bne @SaveCF
  jsr MonPrintIOErr
  rts
@SaveCF:
  jmp @SaveCFBody               ; Continue to existing CF save logic

@SaveSerial:
  lda HW_PRESENT
  and #HW_SC
  bne @SaveSerialBody
  jsr MonPrintIOErr
  rts
@SaveSerialBody:
  ; ... existing serial save code ...
```

### 9B — Guard Kernal Serial Transfer Routines

**AsciiLoadImpl** — Called from BASIC `LOAD` (serial path) and jump table. Guard at implementation entry:
```asm
AsciiLoadImpl:
  lda HW_PRESENT
  and #HW_SC
  bne @AsciiLoadStart
  sec                           ; Return carry set = error
  rts
@AsciiLoadStart:
  ; ... existing code (save IO_MODE, switch to serial, etc.) ...
```

**AsciiSaveImpl** — Same pattern:
```asm
AsciiSaveImpl:
  lda HW_PRESENT
  and #HW_SC
  bne @AsciiSaveStart
  sec                           ; Return carry set = error
  rts
@AsciiSaveStart:
  ; ... existing code ...
```

### 9C — Guard BASIC Video Commands

**BasCmdCls** — Calls `VideoClear` without checking for video hardware:
```asm
BasCmdCls:
  lda HW_PRESENT
  and #HW_VID
  beq @ClsDone                  ; No video — silently skip
  jsr VideoClear
@ClsDone:
  rts
```

**BasCmdLocate** — Calls `VideoSetCursor` to position the cursor:
```asm
BasCmdLocate:
  lda HW_PRESENT
  and #HW_VID
  bne @LocateStart
  ; Still consume the arguments to avoid parse errors, then return
  jsr BasExpr                   ; Consume row
  jsr BasExpectComma
  jsr BasExpr                   ; Consume col
  rts
@LocateStart:
  ; ... existing LOCATE code ...
```

**BasCmdColor** — Calls `VideoSetColor` to set foreground/background:
```asm
BasCmdColor:
  lda HW_PRESENT
  and #HW_VID
  bne @ColorStart
  ; Consume arguments to avoid parse errors
  jsr BasExpr                   ; Consume fg
  jsr BasExpectComma
  jsr BasExpr                   ; Consume bg
  rts
@ColorStart:
  ; ... existing COLOR code ...
```

Note: For CLS, we silently skip (no arguments to consume). For LOCATE and COLOR, we must still parse arguments so the tokenizer/executor stays in sync with the program stream. This prevents `LOCATE 10,5 : PRINT "HI"` from failing on the `:` after LOCATE.

### 9D — Guard BASIC JOY() Function

**BasFnJoy** — Calls `ReadJoystick1` or `ReadJoystick2` which access GPIO ports directly:
```asm
BasFnJoy:
  ; ... parse argument (1 or 2) into BAS_ACC ...
  lda HW_PRESENT
  and #HW_GPIO
  bne @JoyHasGPIO
  stz BAS_ACC                   ; Return 0 if GPIO absent
  stz BAS_ACC + 1
  rts
@JoyHasGPIO:
  ; ... existing joystick read code ...
```

### 9E — Guard Kernal Jump Table Implementations

These implementations are exposed through the jump table and can be called directly by user programs. Guard them at the implementation level so callers don't need to check `HW_PRESENT` themselves.

**SidPlayNoteImpl** — Writes to SID voice registers. Phase 6 guards `BeepImpl` (the boot caller) but not this entry point:
```asm
SidPlayNoteImpl:
  lda HW_PRESENT
  and #HW_SID
  bne @SidPlayStart
  rts                           ; No SID — silently return
@SidPlayStart:
  ; ... existing code ...
```

**SidSilenceImpl** — Clears SID registers. Same guard:
```asm
SidSilenceImpl:
  lda HW_PRESENT
  and #HW_SID
  bne @SidSilenceStart
  rts
@SidSilenceStart:
  ; ... existing code ...
```

**SidSetVolumeImpl** — Sets SID master volume:
```asm
SidSetVolumeImpl:
  lda HW_PRESENT
  and #HW_SID
  bne @SidVolStart
  rts
@SidVolStart:
  ; ... existing code ...
```

**ReadJoystick1Impl / ReadJoystick2Impl** — Manipulate GPIO PCR and read ports:
```asm
ReadJoystick1Impl:
  lda HW_PRESENT
  and #HW_GPIO
  bne @Joy1Start
  lda #$00                      ; Return 0 (no buttons/directions)
  rts
@Joy1Start:
  ; ... existing code (sei, set CB2 high, read PORTB, restore PCR, cli) ...

ReadJoystick2Impl:
  lda HW_PRESENT
  and #HW_GPIO
  bne @Joy2Start
  lda #$00
  rts
@Joy2Start:
  ; ... existing code ...
```

### 9F — Verification Checklist

After completing all guards, verify the full set of protected paths. Every routine that touches I/O space (`$8000-$9FFF`) must either:
1. Be behind an `HW_PRESENT` guard in its own implementation, **or**
2. Only be reachable from a caller that is itself guarded.

**Audit table** (all entries should be ✓ after Phase 9):

| Routine | Hardware | Guarded By |
|---------|----------|------------|
| `InitSCImpl` | Serial | Phase 2 (conditional call in Reset) |
| `InitKBImpl` | GPIO | Phase 2 (conditional call in Reset) |
| `InitSIDImpl` | SID | Phase 2 (conditional call in Reset) |
| `InitVideoImpl` | Video | Phase 2 (conditional call in Reset) |
| `InitCharacters` | Video | Phase 2 (conditional call in Reset) |
| `StInit` / `StWaitReadyImpl` | CF | Phase 3 (timeout + HW_CF set on success) |
| `StWaitDrq` | CF | Phase 3 (timeout) |
| `StReadSectorImpl` | CF | Callers guarded (Phase 8 BASIC, Phase 9A Monitor) |
| `StWriteSectorImpl` | CF | Callers guarded (Phase 8 BASIC, Phase 9A Monitor) |
| `SysDelayImpl` | GPIO (timer) | Phase 3 (software fallback) |
| `Irq` — serial check | Serial | Phase 4 |
| `Irq` — keyboard check | GPIO | Phase 4 |
| `ChrinImpl` — flow control | Serial | Phase 5 |
| `BeepImpl` | SID | Phase 6 |
| `Splash` | Video | Phase 6 |
| `SidPlayNoteImpl` | SID | **Phase 9E** |
| `SidSilenceImpl` | SID | **Phase 9E** |
| `SidSetVolumeImpl` | SID | **Phase 9E** |
| `ReadJoystick1Impl` | GPIO | **Phase 9E** |
| `ReadJoystick2Impl` | GPIO | **Phase 9E** |
| `AsciiLoadImpl` | Serial | **Phase 9B** |
| `AsciiSaveImpl` | Serial | **Phase 9B** |
| `MonCmdDir` | CF | **Phase 9A** |
| `MonCmdLoad` — CF path | CF | **Phase 9A** |
| `MonCmdLoad` — serial path | Serial | **Phase 9A** |
| `MonCmdSave` — CF path | CF | **Phase 9A** |
| `MonCmdSave` — serial path | Serial | **Phase 9A** |
| `BasCmdLoad` — CF path | CF | Phase 8 |
| `BasCmdLoad` — serial path | Serial | Phase 8 (via AsciiLoad → **Phase 9B**) |
| `BasCmdSave` — CF path | CF | Phase 8 |
| `BasCmdSave` — serial path | Serial | Phase 8 (via AsciiSave → **Phase 9B**) |
| `BasCmdDir` | CF | Phase 8 |
| `BasCmdTime` | RTC | Phase 8 |
| `BasCmdDate` | RTC | Phase 8 |
| `BasCmdSound` | SID | Phase 8 |
| `BasCmdVol` | SID | Phase 8 |
| `BasCmdBank` | RAM | Already guarded (pre-existing) |
| `BasCmdCls` | Video | **Phase 9C** |
| `BasCmdLocate` | Video | **Phase 9C** |
| `BasCmdColor` | Video | **Phase 9C** |
| `BasFnJoy` | GPIO | **Phase 9D** |

**Final steps:**
1. Run `make` — verify clean assembly with no errors.
2. Grep the codebase for all direct references to I/O addresses (`$8000`–`$9FFF` range constants from BIOS.inc) and confirm each access site is covered.
3. Commit with message: `phase 9: guard remaining hw paths (monitor, kernal, BASIC)`

---

## Phase 9 — Guard Monitor Hardware Commands

### Monitor L/S CF Paths
When Monitor `L` or `S` command detects a quoted filename (CF mode), check `HW_CF` before calling `FsLoadFile`/`FsSaveFile`/`FsDirectory`. If absent → call `MonPrintIOErr` and return.

### Monitor L/S Serial Paths
When Monitor `L` or `S` has no filename (serial transfer mode), check `HW_SC` before entering serial protocol. If absent → call `MonPrintIOErr` and return.

### Monitor @ (Directory)
Guard the `@` command's call to `FsDirectory` with `HW_CF` check.

---

## Verification Checklist

After all phases, verify:

1. [ ] `make` assembles cleanly with no errors or warnings
2. [ ] Full hardware: boot splash → menu → BASIC/Monitor works identically to current behavior
3. [ ] RAM cards removed: `HW_RAM_L`/`HW_RAM_H` bits clear; BANK commands report no device
4. [ ] CF removed: system boots without hanging (`StWaitReady` times out, `HW_CF`=0)
5. [ ] SID removed: boots silently (no beep, no hang)
6. [ ] Serial removed: no spurious keypresses at boot menu; keyboard works; serial LOAD/SAVE errors gracefully
7. [ ] RTC removed: BASIC TIME/DATE prints "NO DEVICE" instead of garbage
8. [ ] No keypress: BASIC auto-starts after ~5 seconds
9. [ ] Serial-only (no video): IO_MODE auto-switches to serial; splash/menu appear on terminal
10. [ ] Monitor: examine `$030D` — correct bits match installed hardware (bit order = IO slot order)
11. [ ] IRQ stability: rapid keyboard input with serial removed — no buffer corruption

## Hardware Probe Notes

- **RAM probe**: Banked SRAM at `RAM_DATA_L`/`RAM_DATA_H` is freely R/W. Use two-pattern test ($A5 then $5A) to distinguish real RAM from floating bus (which may echo $A5 transiently). Select bank 0 via `RAM_BANK_L`/`RAM_BANK_H` before probing. Restore original byte afterward.
- **SID probe reliability**: `SID_OSC3` may return `$00` when oscillators are idle, same as floating bus. Use an *active* probe: configure voice 3 with noise waveform + high frequency, brief delay, then read `SID_OSC3`. Non-static value confirms presence. Add ~1ms to boot.
- **Video probe timing**: TMS9918 VRAM read-back requires writing the read address then reading data. The pico9918 replica may have different timing — test on real hardware and add NOP padding between register writes if needed.
- **Serial probe**: R65C51 TDRE (bit 4) is always set after reset (known hardware bug). Use this as presence signal — write `SC_RESET` to trigger programmatic reset, then check `SC_STATUS & TDRE`. Floating bus won't reliably produce bit 4 set.
- **VIA probe**: DDR registers (GPIO_DDRB/GPIO_DDRA) are fully read/write. Write `$AA`, read back, compare. Restore to `$00` after probe (InitKBImpl will set final values).
- **RTC probe**: DS1511Y NVRAM at addresses `$8810`/`$8813` is freely R/W. Write `$A5`, read back, compare. Restore original value to avoid corrupting stored data.
