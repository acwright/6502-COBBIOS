; ***             ***
; ***   KERNAL    ***
; ***             ***

; === Kernal Jump Table ($A000-$A0FF) ===
; 85 slots of 3-byte JMP instructions plus 1 padding byte
; Provides stable entry points for external code and cartridges

Chrout:         jmp ChroutDispatch      ; $A000 - Output char (dispatched by IO_MODE)
Chrin:          jmp ChrinImpl           ; $A003 - Input char from buffer
WriteBuffer:    jmp WriteBufferImpl     ; $A006 - Write byte to input buffer
ReadBuffer:     jmp ReadBufferImpl      ; $A009 - Read byte from input buffer
BufferSize:     jmp BufferSizeImpl      ; $A00C - Get buffer count
InitVideo:      jmp InitVideoImpl       ; $A00F - Initialize TMS9918
InitKB:         jmp InitKBImpl          ; $A012 - Initialize GPIO/VIA keyboard
InitSC:         jmp InitSCImpl          ; $A015 - Initialize serial 6551
InitSID:        jmp InitSIDImpl         ; $A018 - Initialize SID
Beep:           jmp BeepImpl            ; $A01B - Play beep tone
VideoClear:     jmp VideoClearImpl      ; $A01E - Clear video screen
VideoPutChar:   jmp VideoPutCharImpl    ; $A021 - Write char at cursor
VideoSetCursor: jmp VideoSetCursorImpl  ; $A024 - Set cursor (X=col, Y=row)
VideoGetCursor: jmp VideoGetCursorImpl  ; $A027 - Get cursor position
VideoScroll:    jmp VideoScrollImpl     ; $A02A - Scroll screen up one line
SerialChrout:   jmp SerialChroutImpl    ; $A02D - Direct serial output (bypass IO_MODE)
ReadJoystick1:  jmp ReadJoystick1Impl   ; $A030 - Read joystick 1
ReadJoystick2:  jmp ReadJoystick2Impl   ; $A033 - Read joystick 2
RtcReadTime:    jmp RtcReadTimeImpl     ; $A036 - Read RTC time
RtcReadDate:    jmp RtcReadDateImpl     ; $A039 - Read RTC date
RtcWriteTime:   jmp RtcWriteTimeImpl    ; $A03C - Set RTC time
RtcWriteDate:   jmp RtcWriteDateImpl    ; $A03F - Set RTC date
RtcReadNVRAM:   jmp RtcReadNVRAMImpl    ; $A042 - Read NVRAM byte
RtcWriteNVRAM:  jmp RtcWriteNVRAMImpl   ; $A045 - Write NVRAM byte
StReadSector:   jmp StReadSectorImpl    ; $A048 - Read CF sector
StWriteSector:  jmp StWriteSectorImpl   ; $A04B - Write CF sector
StWaitReady:    jmp StWaitReadyImpl     ; $A04E - Wait CF ready
SetIOMode:      jmp SetIOModeImpl       ; $A051 - Set IO_MODE
GetIOMode:      jmp GetIOModeImpl       ; $A054 - Get IO_MODE
AsciiLoad:      jmp AsciiLoadImpl       ; $A057 - Load raw binary via serial
AsciiSave:      jmp AsciiSaveImpl       ; $A05A - Save raw binary via serial
SidPlayNote:    jmp SidPlayNoteImpl     ; $A05D - Play note (A=voice, X=freqLo, Y=freqHi)
SidSilence:     jmp SidSilenceImpl      ; $A060 - Silence all voices
FsDeleteFile:   jmp FsDeleteFileImpl    ; $A063 - Delete file from CF

SysDelay:       jmp SysDelayImpl        ; $A066 - Delay A=cnt_lo, X=cnt_hi centiseconds
SidSetVolume:   jmp SidSetVolumeImpl    ; $A069 - Set SID master volume (A=0-15)
VideoSetColor:  jmp VideoSetColorImpl   ; $A06C - Set TMS9918 text color (A=reg7 byte: hi=fg, lo=bg)

; Reserved entries ($A06F-$A0FE)
.repeat 48
                jmp UnimplementedStub
.endrepeat
.byte $00                             ; Pad to 256 bytes ($A0FF)

; === Kernal Implementation ===

; Stub for unimplemented jump table entries
UnimplementedStub:
  rts

; Chrout dispatcher — routes output based on IO_MODE
; Input: A = character to output
; Modifies: Flags
ChroutDispatch:
  pha
  lda IO_MODE
  and #$01                      ; Bit 0: 0=video, 1=serial
  bne @Serial
  pla
  jmp VideoChroutImpl
@Serial:
  pla
  jmp SerialChroutImpl

; Set IO_MODE
; Input: A = mode (bit 0: 0=video, 1=serial)
SetIOModeImpl:
  sta IO_MODE
  rts

; Get IO_MODE
; Output: A = current IO_MODE
GetIOModeImpl:
  lda IO_MODE
  rts

; === TMS9918 Video Driver ===

; VideoClear — Fill name table (960 bytes at VRAM $0000) with spaces, reset cursor to (0,0)
; Modifies: Flags, A, X, Y
VideoClearImpl:
  ; Set VRAM write address to $0000 (name table base)
  lda #$00
  sta VC_REG
  lda #$40                      ; High byte $00 OR $40 for write mode
  sta VC_REG
  ; Fill 960 bytes with space ($20) — 3 full pages + 192 bytes
  lda #$20
  ldy #$00
  ldx #$03                      ; 3 full pages (768 bytes)
@VideoClearPage:
  sta VC_DATA
  iny
  bne @VideoClearPage
  dex
  bne @VideoClearPage
  ; Remaining 192 bytes (960 - 768)
  ldy #192
@VideoClearRem:
  sta VC_DATA
  dey
  bne @VideoClearRem
  ; Reset cursor to (0,0)
  stz VID_CURSOR_X
  stz VID_CURSOR_Y
  stz VID_CURSOR_ADDR
  stz VID_CURSOR_ADDR + 1
  rts

; VideoSetCursor — Set cursor position
; Input: X = column (0-39), Y = row (0-23)
; Calculates VRAM address = Y * 40 + X and stores in VID_CURSOR_ADDR
; Modifies: Flags, A
VideoSetCursorImpl:
  stx VID_CURSOR_X
  sty VID_CURSOR_Y
  ; Calculate VRAM address = Y * 40 + X
  ; Y * 40 = Y * 32 + Y * 8
  lda #$00
  sta VID_CURSOR_ADDR + 1       ; Clear high byte
  tya                           ; A = row
  ; Multiply by 8: shift left 3
  asl a
  rol VID_CURSOR_ADDR + 1
  asl a
  rol VID_CURSOR_ADDR + 1
  asl a
  rol VID_CURSOR_ADDR + 1
  sta VID_CURSOR_ADDR           ; Store Y*8 low byte
  ; Save Y*8 for later addition
  pha
  lda VID_CURSOR_ADDR + 1
  pha
  ; Multiply original row by 32: shift left 5 total (Y*8 << 2)
  lda VID_CURSOR_ADDR
  asl a
  rol VID_CURSOR_ADDR + 1
  asl a
  rol VID_CURSOR_ADDR + 1
  sta VID_CURSOR_ADDR           ; Now holds Y*32 low byte
  ; Add Y*8 + Y*32
  pla                           ; Restore Y*8 high byte
  adc VID_CURSOR_ADDR + 1       ; Carry still valid from last rol
  sta VID_CURSOR_ADDR + 1
  pla                           ; Restore Y*8 low byte
  clc
  adc VID_CURSOR_ADDR
  sta VID_CURSOR_ADDR
  bcc @NoCarry
  inc VID_CURSOR_ADDR + 1
@NoCarry:
  ; Add X (column)
  txa
  clc
  adc VID_CURSOR_ADDR
  sta VID_CURSOR_ADDR
  bcc @SetCursorDone
  inc VID_CURSOR_ADDR + 1
@SetCursorDone:
  rts

; VideoGetCursor — Get cursor position
; Output: X = column (0-39), Y = row (0-23)
; Modifies: Flags
VideoGetCursorImpl:
  ldx VID_CURSOR_X
  ldy VID_CURSOR_Y
  rts

; VideoPutChar — Write a single character to VRAM at VID_CURSOR_ADDR
; Input: A = character to write
; Modifies: Flags
VideoPutCharImpl:
  pha
  ; Set VRAM write address from VID_CURSOR_ADDR
  lda VID_CURSOR_ADDR
  sta VC_REG                    ; Low byte of address
  lda VID_CURSOR_ADDR + 1
  ora #$40                      ; Set bit 6 for write mode
  sta VC_REG                    ; High byte with write flag
  pla
  sta VC_DATA                   ; Write character to VRAM
  rts

; VideoScroll — Scroll screen up one line
; Copies VRAM rows 1-23 to rows 0-22 (920 bytes), clears row 23 with spaces
; Uses SCROLL_BUF ($0320, 40 bytes) as temporary storage
; Modifies: Flags, A, X, Y
VideoScrollImpl:
  ; Save STR_PTR (may be in use by caller, e.g. VideoPrintStr)
  lda STR_PTR
  pha
  lda STR_PTR + 1
  pha
  ; Source starts at row 1 (VRAM offset 40=$28), dest at row 0 (offset 0)
  ; We process 23 rows, copying each row up by one
  lda #<40                      ; Source address low = 40 (row 1)
  sta STR_PTR
  lda #>40
  sta STR_PTR + 1

  ldx #23                       ; 23 rows to copy
@ScrollRowLoop:
  phx                           ; Save row counter

  ; Set VRAM read address (source row)
  lda STR_PTR
  sta VC_REG
  lda STR_PTR + 1
  sta VC_REG                    ; Bit 6 clear = read mode
  ; Read 40 bytes into SCROLL_BUF
  ldy #$00
@ScrollRead:
  lda VC_DATA
  sta SCROLL_BUF,y
  iny
  cpy #40
  bne @ScrollRead

  ; Set VRAM write address (dest = source - 40)
  lda STR_PTR
  sec
  sbc #40
  sta VC_REG                    ; Dest address low
  lda STR_PTR + 1
  sbc #$00
  ora #$40                      ; Set bit 6 for write mode
  sta VC_REG                    ; Dest address high

  ; Write 40 bytes from SCROLL_BUF
  ldy #$00
@ScrollWrite:
  lda SCROLL_BUF,y
  sta VC_DATA
  iny
  cpy #40
  bne @ScrollWrite

  ; Advance source pointer by 40 for next row
  lda STR_PTR
  clc
  adc #40
  sta STR_PTR
  bcc @ScrollNoCarry
  inc STR_PTR + 1
@ScrollNoCarry:
  plx                           ; Restore row counter
  dex
  bne @ScrollRowLoop

  ; Clear bottom row (row 23) with spaces
  ; Row 23 address = 23 * 40 = 920 = $0398
  lda #$98                      ; Low byte of $0398
  sta VC_REG
  lda #$03
  ora #$40                      ; Write mode
  sta VC_REG
  lda #$20                      ; Space character
  ldy #40
@ScrollClearBottom:
  sta VC_DATA
  dey
  bne @ScrollClearBottom
  ; Restore STR_PTR
  pla
  sta STR_PTR + 1
  pla
  sta STR_PTR
  rts

; VideoChrout — Output character to video display
; Handles control characters: CR ($0D), LF ($0A), BS ($08), BEL ($07)
; Auto-wraps at column 40, auto-scrolls at row 24
; Input: A = character to output
; Preserves: A, X, Y (callers like ChrinImpl, BasPrintStr and Wozmon depend on this)
; Modifies: Flags
VideoChroutImpl:
  pha
  phx
  phy
  cmp #$0D                      ; Carriage Return?
  beq @VideoCR
  cmp #$0A                      ; Line Feed?
  beq @VideoLF
  cmp #$08                      ; Backspace?
  beq @VideoBS
  cmp #$07                      ; Bell?
  beq @VideoBEL
  ; Regular printable character — write at cursor and advance
  jsr VideoPutChar              ; Write char to VRAM at cursor
  ; Advance cursor
  inc VID_CURSOR_X
  ; Increment VRAM address
  inc VID_CURSOR_ADDR
  bne @CheckWrap
  inc VID_CURSOR_ADDR + 1
@CheckWrap:
  lda VID_CURSOR_X
  cmp #40                       ; Past last column?
  bcc @VideoChroutDone          ; No, done
  ; Auto-wrap: CR + LF
  stz VID_CURSOR_X
  inc VID_CURSOR_Y
  lda VID_CURSOR_Y
  cmp #24                       ; Past last row?
  bcc @WrapRecalc
  ; Need to scroll
  jsr VideoScroll
  lda #23
  sta VID_CURSOR_Y
@WrapRecalc:
  ldx VID_CURSOR_X
  ldy VID_CURSOR_Y
  jsr VideoSetCursor            ; Recalculate VRAM address
@VideoChroutDone:
  ply
  plx
  pla
  rts

@VideoCR:
  stz VID_CURSOR_X              ; Column = 0
  ldx #$00
  ldy VID_CURSOR_Y
  jsr VideoSetCursor            ; Recalculate VRAM address
  bra @VideoChroutDone

@VideoLF:
  inc VID_CURSOR_Y
  lda VID_CURSOR_Y
  cmp #24                       ; Past last row?
  bcc @LFRecalc
  jsr VideoScroll
  lda #23
  sta VID_CURSOR_Y
@LFRecalc:
  ldx VID_CURSOR_X
  ldy VID_CURSOR_Y
  jsr VideoSetCursor
  bra @VideoChroutDone

@VideoBS:
  lda VID_CURSOR_X
  beq @VideoChroutDone          ; Already at column 0, ignore
  dec VID_CURSOR_X
  ldx VID_CURSOR_X
  ldy VID_CURSOR_Y
  jsr VideoSetCursor            ; Recalculate VRAM address
  lda #$20                      ; Write space to erase character
  jsr VideoPutChar
  bra @VideoChroutDone

@VideoBEL:
  jsr Beep
  bra @VideoChroutDone

; VideoPrintStr — Print null-terminated string to video
; Input: STR_PTR ($02-$03) points to string
; Modifies: Flags, A, X, Y
VideoPrintStrImpl:
  ldy #$00
@VideoPrintStrLoop:
  lda (STR_PTR),y
  beq @VideoPrintStrDone        ; Exit on null terminator
  phy
  jsr VideoChroutImpl           ; Output character via video
  ply
  iny
  bne @VideoPrintStrLoop        ; Max 256 chars per string
@VideoPrintStrDone:
  rts

; Main entry point
Reset:
  cld                           ; Clear decimal mode
  sei                           ; Disable interrupts

  ldx #$ff                      
  txs                           ; Reset the stack pointer

  lda #<Irq                     ; Initialize the IRQ pointer
  sta IRQ_PTR
  lda #>Irq
  sta IRQ_PTR + 1

  lda #<Break                   ; Initialize the BRK pointer
  sta BRK_PTR
  lda #>Break
  sta BRK_PTR + 1

  lda #<Nmi                     ; Initialize the NMI pointer
  sta NMI_PTR
  lda #>Nmi
  sta NMI_PTR + 1

  stz HW_PRESENT                ; Clear all hardware flags

  jsr InitBuffer                ; Initialize the input buffer (RAM-only, no hardware)

  jsr ProbeRAM                  ; Sets HW_RAM_L / HW_RAM_H if present (no init needed)

  jsr ProbeRTC                  ; Sets HW_RTC if present (no init needed)

  jsr StInit                    ; CF: timeout will handle absent card in Phase 3, sets HW_CF on success

  jsr ProbeSerial               ; Sets HW_SC if present
  lda HW_PRESENT
  and #HW_SC
  beq @SkipSerial
  jsr InitSCImpl
@SkipSerial:

  jsr ProbeGPIO                 ; Sets HW_GPIO if present
  lda HW_PRESENT
  and #HW_GPIO
  beq @SkipGPIO
  jsr InitKBImpl
@SkipGPIO:

  jsr ProbeSID                  ; Sets HW_SID if present
  lda HW_PRESENT
  and #HW_SID
  beq @SkipSID
  jsr InitSIDImpl
@SkipSID:

  jsr ProbeVideo                ; Sets HW_VID if present
  lda HW_PRESENT
  and #HW_VID
  beq @SkipVideo
  jsr InitVideoImpl
  jsr InitCharacters
@SkipVideo:

  lda #$00                      ; Default to video output mode
  sta IO_MODE
  stz VID_CURSOR_X              ; Initialize video cursor state
  stz VID_CURSOR_Y
  stz VID_CURSOR_ADDR
  stz VID_CURSOR_ADDR + 1

  jsr Beep                      ; Play the startup beep
  jsr Splash                    ; Draw the splash screen

  cli                           ; Enable interrupts

  ; Boot menu — wait for keypress
@BootWait:
  jsr BufferSize
  beq @BootWait                 ; Loop until a key is pressed
  jsr ReadBuffer                ; Read the keypress
  cmp #$0D                      ; ENTER?
  beq @BootBASIC
  cmp #$1B                      ; ESC?
  beq @BootMonitor
  bra @BootWait                 ; Ignore other keys
@BootBASIC:
  jsr VideoClear                ; Clear screen before entering BASIC
  jmp BasEntry
@BootMonitor:
  brk                           ; Enter monitor through BRK vector (saves/displays registers)

; Initialize the Keyboard via VIA (IO 6)
; Configures Port B (matrix) and Port A (PS/2) as inputs
; CB2 low (enable matrix encoder), CA2 low (enable PS/2 encoder)
; CB1 and CA1 falling-edge IRQs enabled
; Modifies: Flags, A
InitKBImpl:
  lda #$00                      ; Port B all inputs (matrix keyboard data bus)
  sta GPIO_DDRB
  lda #$00                      ; Port A all inputs (PS/2 keyboard data bus)
  sta GPIO_DDRA
  ; PCR: CB2 low + CB1 neg + CA2 low + CA1 neg
  lda #(GPIO_PCR_CB2_LO | GPIO_PCR_CB1_NEG | GPIO_PCR_CA2_LO | GPIO_PCR_CA1_NEG)
  sta GPIO_PCR
  ; Enable both CB1 and CA1 interrupts
  lda #(GPIO_IER_SET | GPIO_INT_CB1 | GPIO_INT_CA1)
  sta GPIO_IER
  rts
  
; Initialize the Serial Card (6551)
; Modifies: Flags, A
InitSCImpl:
  lda     #$1F                  ; 8-N-1, 19200 baud
  sta     SC_CTRL
  lda     #$09                  ; No parity, no echo, RTSB low, TX interrupts disabled, RX interrupts enabled
  sta     SC_CMD
  rts

; Initialze the Sound Card (6581)
; Modifies: Flags, A, X
InitSIDImpl:
  lda #$00
  ldx #$1D                      ; Clear all 29 SID registers
@InitSIDLoop:
  sta SID_V1_FREQ_LO,x          ; Clear register
  dex
  bpl @InitSIDLoop              ; Loop until all registers cleared
  lda #$0F                      ; Set volume to maximum
  sta SID_MODE_VOL
  rts

; Initialize the Video Card (TMS9918)
; Modifies: Flags, A, X
InitVideoImpl:
  ldx #$00                      ; Start with register 0
@InitVideoLoop:
  lda @InitVideoRegData,x       ; Load register value
  sta VC_REG                    ; Write data byte
  txa                           
  ora #$80                      ; Set bit 7 to indicate register write
  sta VC_REG                    ; Write register number
  inx
  cpx #$08                      ; Check if all 8 registers written
  bne @InitVideoLoop            ; Continue until done
  rts
@InitVideoRegData:
  .byte $00                     ; R0: Mode control (no external video)
  .byte $D0                     ; R1: 16K, display on, interrupt off, text mode M1
  .byte $00                     ; R2: Name table at $0000 (0x00 * 0x400)
  .byte $00                     ; R3: Color table (not used in text mode)
  .byte $01                     ; R4: Pattern table at $0800 (0x01 * 0x800)
  .byte $00                     ; R5: Sprite attribute table (not used in text mode)
  .byte $00                     ; R6: Sprite pattern table (not used in text mode)
  .byte $F0                     ; R7: White text on black background

; Initialize the character set
; Modifies: Flags, A, X, Y
InitCharacters:
  ; Set VRAM write address to $0800 (pattern table base)
  lda #$00                      ; Low byte of address
  sta VC_REG
  lda #$48                      ; High byte ($08) OR $40 for write mode
  sta VC_REG
  ; Set up source pointer
  lda #<CharacterSet
  sta STR_PTR                   ; Use STR_PTR ($02-$03) for character set pointer
  lda #>CharacterSet
  sta STR_PTR + 1
  ; Copy 2048 bytes (8 pages of 256 bytes each)
  ldx #$08                      ; 8 pages to copy
  ldy #$00                      ; Byte counter within page
@InitCharPageLoop:
  lda (STR_PTR),y               ; Load from character set
  sta VC_DATA                   ; Write to VRAM
  iny
  bne @InitCharPageLoop         ; Loop until page complete (256 bytes)
  inc STR_PTR + 1               ; Move to next page
  dex
  bne @InitCharPageLoop         ; Loop for all 8 pages
  rts

; Initialize the INPUT_BUFFER
; Modifies: Flags, A
InitBuffer:
  lda #$00
  sta READ_PTR                  ; Init read and write pointers
  sta WRITE_PTR
  rts

; Write a character from the A register to the INPUT_BUFFER
; Modifies: Flags, X
WriteBufferImpl:
  ldx WRITE_PTR
  sta INPUT_BUFFER,x
  inc WRITE_PTR
  rts

; Read a character from the INPUT_BUFFER and store it in A register
; Modifies: Flags, X, A
ReadBufferImpl:
  ldx READ_PTR
  lda INPUT_BUFFER,x
  inc READ_PTR
  rts

; Return in A register the number of unread bytes in the INPUT_BUFFER
; Modifies: Flags, A
BufferSizeImpl:  
  lda WRITE_PTR
  sec
  sbc READ_PTR
  rts

; Get a character from the INPUT_BUFFER if available
; On return, carry flag indicates whether a character was available
; If character available the character will be in the A register
; Modifies: Flags, A
ChrinImpl:
  phx
  jsr BufferSize                ; Check for character available
  beq @ChrinNoChar              ; Branch if no character available
  jsr ReadBuffer                ; Read the character from the buffer
  jsr Chrout                    ; Echo
  pha                           
  jsr BufferSize                
  cmp #$B0                      ; Check if buffer is mostly full
  bcc @ChrinNotFull             ; Branch if buffer size < $B0
  lda #$01                      ; No parity, no echo, RTSB high, TX interrupts disabled, RX interrupts enabled
  sta SC_CMD
  bra @ChrinExit
@ChrinNotFull:
  lda #$09                      ; No parity, no echo, RTSB low, TX interrupts disabled, RX interrupts enabled
  sta SC_CMD
@ChrinExit:
  pla
  plx
  sec
  rts
@ChrinNoChar:
  plx
  clc
  rts

; Output a character from the A register to the Serial Card
; Modifies: Flags
SerialChroutImpl:
  sta SC_DATA
  pha
@ChroutWait:
  lda SC_STATUS
  and #SC_STATUS_TDRE           ; Check if TX buffer not empty
  beq @ChroutWait               ; Loop if TX buffer not empty
  pla
  rts

; SidPlayNote — Play a note on a SID voice
; Input: A = voice (0-2), X = frequency low byte, Y = frequency high byte
; Uses triangle waveform with standard ADSR (Attack=0, Decay=9, Sustain=A, Release=2)
; Modifies: Flags, A
SidPlayNoteImpl:
  cmp #$01
  beq @Voice2
  cmp #$02
  beq @Voice3
  ; Voice 0
  stx SID_V1_FREQ_LO
  sty SID_V1_FREQ_HI
  lda #$09                      ; Attack = 0, Decay = 9
  sta SID_V1_AD
  lda #$A2                      ; Sustain = A, Release = 2
  sta SID_V1_SR
  lda #$11                      ; Triangle wave + Gate on
  sta SID_V1_CTRL
  rts
@Voice2:
  stx SID_V2_FREQ_LO
  sty SID_V2_FREQ_HI
  lda #$09
  sta SID_V2_AD
  lda #$A2
  sta SID_V2_SR
  lda #$11
  sta SID_V2_CTRL
  rts
@Voice3:
  stx SID_V3_FREQ_LO
  sty SID_V3_FREQ_HI
  lda #$09
  sta SID_V3_AD
  lda #$A2
  sta SID_V3_SR
  lda #$11
  sta SID_V3_CTRL
  rts

; SidSilence — Silence all 3 SID voices
; Gates off all voices and zeros their frequencies
; Modifies: Flags, A
SidSilenceImpl:
  lda #$10                      ; Triangle wave, Gate off
  sta SID_V1_CTRL
  sta SID_V2_CTRL
  sta SID_V3_CTRL
  lda #$00
  sta SID_V1_FREQ_LO
  sta SID_V1_FREQ_HI
  sta SID_V2_FREQ_LO
  sta SID_V2_FREQ_HI
  sta SID_V3_FREQ_LO
  sta SID_V3_FREQ_HI
  rts

; Play a short beep sound
; Uses SidPlayNote on voice 0 with ~1000 Hz tone, then silences
; Modifies: Flags, A, X, Y
BeepImpl:
  lda #$00                      ; Voice 0
  ldx #$20                      ; Frequency low byte (~1000 Hz)
  ldy #$1F                      ; Frequency high byte
  jsr SidPlayNote
  ; Override ADSR for beep: fast decay, no sustain
  lda #$09                      ; Attack = 0, Decay = 9
  sta SID_V1_AD
  lda #$00                      ; Sustain = 0, Release = 0
  sta SID_V1_SR
  ; Delay for beep duration
  ldx #$F0                      ; Outer loop counter
@BeepDelay1:
  ldy #$FF                      ; Inner loop counter
@BeepDelay2:
  dey
  bne @BeepDelay2
  dex
  bne @BeepDelay1
  jsr SidSilence                ; Gate off all voices
  rts

; SysDelay — Delay for a specified number of centiseconds
; Input: A = count low byte, X = count high byte
; Uses VIA T1 in one-shot mode. 9999 cycles @ 1MHz = ~10ms per tick.
; Modifies: Flags, A
SysDelayImpl:
  sta DELAY_CNT
  stx DELAY_CNT + 1
  ; Return immediately if count is zero
  ora DELAY_CNT + 1
  beq @DelayDone
  ; Check if VIA is present for hardware timer
  lda HW_PRESENT
  and #HW_GPIO
  bne @DelayHardware
  ; Software fallback — calibrated busy loop (~10ms per centisecond at 1MHz)
  ; Inner loop: 5 cycles × 256 iterations × 8 = ~10240 cycles ≈ 10ms
@DelaySoftLoop:
  ldy #$00                      ; 256 outer iterations
  ldx #8
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
  ; Configure T1 one-shot mode: clear ACR bit 6
  lda GPIO_ACR
  and #%10111111
  sta GPIO_ACR
@DelayLoop:
  ; Load T1 latch: 9999 = $270F
  lda #$0F
  sta GPIO_T1LL
  lda #$27
  sta GPIO_T1LH
  ; Write T1CH to start countdown (also clears IFR T1 flag)
  lda #$27
  sta GPIO_T1CH
@DelayPoll:
  lda GPIO_IFR
  and #%01000000                ; T1 timeout flag
  beq @DelayPoll
  ; Clear flag by reading T1CL
  lda GPIO_T1CL
  ; 16-bit decrement
  lda DELAY_CNT
  bne @DelayDecLo
  dec DELAY_CNT + 1
@DelayDecLo:
  dec DELAY_CNT
  ; Loop until both bytes zero
  lda DELAY_CNT
  ora DELAY_CNT + 1
  bne @DelayLoop
@DelayDone:
  rts

; SidSetVolume — Set SID master volume
; Input: A = volume (0-15); upper nibble of SID_MODE_VOL is cleared (no filter)
; Modifies: Flags, A
SidSetVolumeImpl:
  and #$0F
  sta SID_MODE_VOL
  rts

; VideoSetColor — Set TMS9918 text color register
; Input: A = color byte (high nibble = fg color, low nibble = bg color)
; Modifies: Flags, A
VideoSetColorImpl:
  sta VC_REG                    ; Data byte
  lda #$87                      ; Register 7 | $80 (write mode flag)
  sta VC_REG
  rts

; KBDisable — Disable both keyboard encoders for raw port access
; Sets CB2 high (disable matrix encoder) and CA2 high (disable PS/2 encoder)
; Modifies: Flags, A
KBDisable:
  lda #(GPIO_PCR_CB2_HI | GPIO_PCR_CB1_NEG | GPIO_PCR_CA2_HI | GPIO_PCR_CA1_NEG)
  sta GPIO_PCR
  rts

; KBEnable — Re-enable both keyboard encoders
; Sets CB2 low (enable matrix encoder) and CA2 low (enable PS/2 encoder)
; Modifies: Flags, A
KBEnable:
  lda #(GPIO_PCR_CB2_LO | GPIO_PCR_CB1_NEG | GPIO_PCR_CA2_LO | GPIO_PCR_CA1_NEG)
  sta GPIO_PCR
  rts

; ReadJoystick1 — Read joystick 1 on Port B
; Temporarily disables matrix keyboard encoder (CB2 high) to read raw port data
; Output: A = joystick bitmask (bits: R-L-D-U-Y-X-B-A)
; Modifies: Flags, A
ReadJoystick1Impl:
  sei                           ; Disable interrupts during raw port read
  lda GPIO_PCR
  pha                           ; Save current PCR state
  ; Set CB2 high to disable matrix encoder, preserve CA2 state
  lda #(GPIO_PCR_CB2_HI | GPIO_PCR_CB1_NEG | GPIO_PCR_CA2_LO | GPIO_PCR_CA1_NEG)
  sta GPIO_PCR
  lda GPIO_PORTB                ; Read raw joystick data from Port B
  tax                           ; Save result in X
  pla                           ; Restore original PCR state
  sta GPIO_PCR
  txa                           ; Return result in A
  cli                           ; Re-enable interrupts
  rts

; ReadJoystick2 — Read joystick 2 on Port A
; Temporarily disables PS/2 keyboard encoder (CA2 high) to read raw port data
; Output: A = joystick bitmask (bits: R-L-D-U-Y-X-B-A)
; Modifies: Flags, A
ReadJoystick2Impl:
  sei                           ; Disable interrupts during raw port read
  lda GPIO_PCR
  pha                           ; Save current PCR state
  ; Set CA2 high to disable PS/2 encoder, preserve CB2 state
  lda #(GPIO_PCR_CB2_LO | GPIO_PCR_CB1_NEG | GPIO_PCR_CA2_HI | GPIO_PCR_CA1_NEG)
  sta GPIO_PCR
  lda GPIO_PORTA                ; Read raw joystick data from Port A
  tax                           ; Save result in X
  pla                           ; Restore original PCR state
  sta GPIO_PCR
  txa                           ; Return result in A
  cli                           ; Re-enable interrupts
  rts

; === BCD Conversion Helpers ===

; BcdToBin — Convert BCD byte to binary
; Input: A = BCD value (e.g. $35 represents 35)
; Output: A = binary value (e.g. 35 = $23)
; Modifies: Flags
BcdToBin:
  pha
  lsr a                         ; Shift tens digit to low nibble
  lsr a
  lsr a
  lsr a                         ; A = tens digit (0-9)
  asl a                         ; A = tens * 2
  sta RTC_TMP
  asl a                         ; A = tens * 4
  asl a                         ; A = tens * 8
  clc
  adc RTC_TMP                   ; A = tens * 10 (8 + 2)
  sta RTC_TMP
  pla
  and #$0F                      ; A = ones digit
  clc
  adc RTC_TMP                   ; A = tens * 10 + ones = binary
  rts

; BinToBcd — Convert binary byte to BCD
; Input: A = binary value (0-99)
; Output: A = BCD value
; Modifies: Flags, X
BinToBcd:
  ldx #$FF                      ; Tens counter (starts at -1)
@BinToBcdLoop:
  inx
  sec
  sbc #10
  bcs @BinToBcdLoop             ; Count tens
  adc #10                       ; Restore ones (carry clear, so adds 10 + 0)
  sta RTC_TMP                   ; Save ones digit
  txa                           ; A = tens digit
  asl a
  asl a
  asl a
  asl a                         ; Shift tens to high nibble
  ora RTC_TMP                   ; Combine with ones
  rts

; === DS1511Y RTC Routines ===

; RtcReadTime — Read current time from DS1511Y
; Output: A = hours (binary), X = minutes (binary), Y = seconds (binary)
; Modifies: Flags
RtcReadTimeImpl:
  lda RTC_HR
  jsr BcdToBin
  pha                           ; Save hours
  lda RTC_MIN
  jsr BcdToBin
  tax                           ; X = minutes
  lda RTC_SEC
  jsr BcdToBin
  tay                           ; Y = seconds
  pla                           ; A = hours
  rts

; RtcReadDate — Read current date from DS1511Y
; Output: A = day of month (binary), X = month (binary), Y = year (binary)
;         RTC_BUF_CENT = century (binary)
; Modifies: Flags
RtcReadDateImpl:
  lda RTC_CENT
  jsr BcdToBin
  sta RTC_BUF_CENT              ; Store century in buffer
  lda RTC_MON
  jsr BcdToBin
  tax                           ; X = month
  lda RTC_YR
  jsr BcdToBin
  tay                           ; Y = year
  lda RTC_DATE
  jsr BcdToBin                  ; A = day of month
  rts

; RtcWriteTime — Set DS1511Y time
; Input: A = hours (binary), X = minutes (binary), Y = seconds (binary)
; Modifies: Flags, A, X
RtcWriteTimeImpl:
  pha                           ; Save hours
  phx                           ; Save minutes
  phy                           ; Save seconds
  ; Set TE bit to inhibit update transfers
  lda RTC_CTRL_B
  ora #RTC_CTRL_B_TE
  sta RTC_CTRL_B
  ; Write seconds
  pla                           ; A = seconds
  jsr BinToBcd
  sta RTC_SEC
  ; Write minutes
  pla                           ; A = minutes
  jsr BinToBcd
  sta RTC_MIN
  ; Write hours
  pla                           ; A = hours
  jsr BinToBcd
  sta RTC_HR
  ; Clear TE bit to resume updates
  lda RTC_CTRL_B
  and #<~RTC_CTRL_B_TE
  sta RTC_CTRL_B
  rts

; RtcWriteDate — Set DS1511Y date
; Input: A = day of month (binary), X = month (binary), Y = year (binary)
;        RTC_BUF_CENT = century (binary)
; Modifies: Flags, A, X
RtcWriteDateImpl:
  pha                           ; Save day
  phx                           ; Save month
  phy                           ; Save year
  ; Set TE bit to inhibit update transfers
  lda RTC_CTRL_B
  ora #RTC_CTRL_B_TE
  sta RTC_CTRL_B
  ; Write century
  lda RTC_BUF_CENT
  jsr BinToBcd
  sta RTC_CENT
  ; Write year
  pla                           ; A = year
  jsr BinToBcd
  sta RTC_YR
  ; Write month
  pla                           ; A = month
  jsr BinToBcd
  sta RTC_MON
  ; Write day
  pla                           ; A = day
  jsr BinToBcd
  sta RTC_DATE
  ; Clear TE bit to resume updates
  lda RTC_CTRL_B
  and #<~RTC_CTRL_B_TE
  sta RTC_CTRL_B
  rts

; RtcReadNVRAM — Read a byte from DS1511Y NVRAM
; Input: X = NVRAM address ($00-$FF)
; Output: A = data byte
; Modifies: Flags
RtcReadNVRAMImpl:
  stx RTC_RAM_ADDR
  lda RTC_RAM_DATA
  rts

; RtcWriteNVRAM — Write a byte to DS1511Y NVRAM
; Input: X = NVRAM address ($00-$FF), A = data byte
; Modifies: Flags
RtcWriteNVRAMImpl:
  stx RTC_RAM_ADDR
  sta RTC_RAM_DATA
  rts

; === Hardware Probes ===

; ProbeRAM — Test for banked SRAM on IO 1 and IO 2
; Two-pattern read-back test ($A5 then $5A) on bank 0 data byte
; Sets HW_RAM_L / HW_RAM_H in HW_PRESENT on success
; Modifies: Flags, A
ProbeRAM:
  ; --- Probe RAM Low (IO 1) ---
  stz RAM_BANK_L                ; Select bank 0
  lda RAM_DATA_L                ; Save existing value
  pha
  lda #$A5
  sta RAM_DATA_L
  cmp RAM_DATA_L
  bne @RAMLDone                 ; First pattern failed
  lda #$5A
  sta RAM_DATA_L
  cmp RAM_DATA_L
  bne @RAMLDone                 ; Second pattern failed
  lda HW_PRESENT
  ora #HW_RAM_L
  sta HW_PRESENT
@RAMLDone:
  pla
  sta RAM_DATA_L                ; Restore original value
  ; --- Probe RAM High (IO 2) ---
  stz RAM_BANK_H                ; Select bank 0
  lda RAM_DATA_H                ; Save existing value
  pha
  lda #$A5
  sta RAM_DATA_H
  cmp RAM_DATA_H
  bne @RAMHDone                 ; First pattern failed
  lda #$5A
  sta RAM_DATA_H
  cmp RAM_DATA_H
  bne @RAMHDone                 ; Second pattern failed
  lda HW_PRESENT
  ora #HW_RAM_H
  sta HW_PRESENT
@RAMHDone:
  pla
  sta RAM_DATA_H                ; Restore original value
  rts

; ProbeVideo — TMS9918 VRAM read-back test
; Writes $A5 to VRAM address $0000, reads it back
; Sets HW_VID in HW_PRESENT on success
; Modifies: Flags, A
ProbeVideo:
  ; Write $A5 to VRAM $0000
  lda #$00
  sta VC_REG                    ; Low byte of address
  lda #$40                      ; High byte $00 OR $40 for write mode
  sta VC_REG
  lda #$A5
  sta VC_DATA                   ; Write data byte
  ; Read back from VRAM $0000
  lda #$00
  sta VC_REG                    ; Low byte of address
  lda #$00                      ; High byte $00, bit 6 clear for read mode
  sta VC_REG
  lda VC_DATA                   ; Read data byte
  cmp #$A5
  bne @ProbeVideoDone
  lda HW_PRESENT
  ora #HW_VID
  sta HW_PRESENT
@ProbeVideoDone:
  rts

; ProbeGPIO — VIA DDR register read-back test
; Writes $AA to GPIO_DDRB, reads it back
; Sets HW_GPIO in HW_PRESENT on success
; Restores GPIO_DDRB to $00 afterward
; Modifies: Flags, A
ProbeGPIO:
  lda #$AA
  sta GPIO_DDRB
  cmp GPIO_DDRB
  bne @ProbeGPIODone
  lda HW_PRESENT
  ora #HW_GPIO
  sta HW_PRESENT
@ProbeGPIODone:
  stz GPIO_DDRB                 ; Restore to inputs (InitKBImpl will configure properly)
  rts

; ProbeSerial — R65C51 TDRE-after-reset test
; Issues programmatic reset, checks for TDRE (bit 4) set in status
; Sets HW_SC in HW_PRESENT on success
; Modifies: Flags, A
ProbeSerial:
  stz SC_RESET                  ; Programmatic reset (write any value)
  lda SC_STATUS
  and #SC_STATUS_TDRE           ; TDRE should be set after reset
  beq @ProbeSerialDone
  lda HW_PRESENT
  ora #HW_SC
  sta HW_PRESENT
@ProbeSerialDone:
  rts

; ProbeSID — Active oscillator test using voice 3
; Configures voice 3 noise waveform, brief delay, reads SID_OSC3
; Non-zero and non-$FF result indicates SID present
; Sets HW_SID in HW_PRESENT on success
; Modifies: Flags, A, X, Y
ProbeSID:
  ; Set voice 3 frequency to a fast value
  lda #$FF
  sta SID_V3_FREQ_LO
  sta SID_V3_FREQ_HI
  ; Gate on + noise waveform
  lda #(SID_CTRL_GATE | SID_CTRL_NOISE)
  sta SID_V3_CTRL
  ; Brief software delay for oscillator to run
  ldy #$00
@ProbeSIDDelay:
  dey
  bne @ProbeSIDDelay            ; ~1280 cycles
  ; Read oscillator 3 output
  lda SID_OSC3
  beq @ProbeSIDCleanup          ; Zero → no SID
  cmp #$FF
  beq @ProbeSIDCleanup          ; $FF → likely floating bus
  ; SID detected
  pha
  lda HW_PRESENT
  ora #HW_SID
  sta HW_PRESENT
  pla
@ProbeSIDCleanup:
  ; Silence voice 3
  stz SID_V3_CTRL
  stz SID_V3_FREQ_LO
  stz SID_V3_FREQ_HI
  rts

; ProbeRTC — DS1511Y NVRAM read-back test
; Writes test pattern to NVRAM address 0, reads it back
; Sets HW_RTC in HW_PRESENT on success
; Restores original NVRAM value afterward
; Modifies: Flags, A
ProbeRTC:
  stz RTC_RAM_ADDR              ; Select NVRAM address 0
  lda RTC_RAM_DATA              ; Save existing value
  pha
  lda #$A5
  sta RTC_RAM_DATA              ; Write test pattern
  cmp RTC_RAM_DATA              ; Read back
  bne @ProbeRTCDone
  lda HW_PRESENT
  ora #HW_RTC
  sta HW_PRESENT
@ProbeRTCDone:
  pla
  sta RTC_RAM_DATA              ; Restore original value
  rts

; === CompactFlash Storage Driver (True 8-bit IDE Mode) ===

; StWaitReady — Wait for CompactFlash to become ready
; Polls ST_STATUS until BSY=0 and RDY=1, with X/Y timeout (~65536 iterations)
; Output: Carry clear = ready, Carry set = error or timeout
; Modifies: Flags, A, X, Y
StWaitReadyImpl:
  ldx #$00                      ; Outer timeout counter (256 × 256 = 65536 iterations)
  ldy #$00
@StWaitBsy:
  lda ST_STATUS
  and #ST_STATUS_BSY            ; Check BSY bit
  beq @StCheckRdy               ; BSY clear — check RDY
  dey
  bne @StWaitBsy
  dex
  bne @StWaitBsy
  sec                           ; Timed out — no device
  rts
@StCheckRdy:
  lda ST_STATUS
  and #ST_STATUS_RDY            ; Check RDY bit
  bne @StCheckErr               ; RDY set — check for errors
  dey
  bne @StWaitBsy
  dex
  bne @StWaitBsy
  sec                           ; Timed out
  rts
@StCheckErr:
  lda ST_STATUS
  and #ST_STATUS_ERR            ; Check ERR bit
  bne @StWaitErr
  clc                           ; Ready, no error
  rts
@StWaitErr:
  sec                           ; Error condition
  rts

; StWaitDrq — Wait for CompactFlash data request
; Polls ST_STATUS until BSY=0 and DRQ=1, with X/Y timeout (~65536 iterations)
; Output: Carry clear = DRQ active, Carry set = error or timeout
; Modifies: Flags, A, X, Y
StWaitDrq:
  ldx #$00                      ; Outer timeout counter (256 × 256 = 65536 iterations)
  ldy #$00
@StDrqBsy:
  lda ST_STATUS
  and #ST_STATUS_BSY
  beq @StDrqCheckDrq            ; BSY clear — check DRQ
  dey
  bne @StDrqBsy
  dex
  bne @StDrqBsy
  sec                           ; Timed out — no device
  rts
@StDrqCheckDrq:
  lda ST_STATUS
  and #ST_STATUS_ERR
  bne @StDrqErr
  lda ST_STATUS
  and #ST_STATUS_DRQ
  bne @StDrqOk                  ; DRQ set — ready for data
  dey
  bne @StDrqBsy
  dex
  bne @StDrqBsy
  sec                           ; Timed out
  rts
@StDrqOk:
  clc
  rts
@StDrqErr:
  sec
  rts

; StInit — Initialize CompactFlash for 8-bit data transfers
; Issues Set Features command with subcommand $01 (enable 8-bit I/O)
; Output: Carry clear = success, Carry set = error
; Modifies: Flags, A
StInit:
  jsr StWaitReady
  bcs @StInitDone               ; Timeout or error — CF not present
  ; CF responded — set presence flag
  lda HW_PRESENT
  ora #HW_CF
  sta HW_PRESENT
  lda #ST_FEAT_8BIT             ; Feature: enable 8-bit data I/O
  sta ST_FEATURE
  lda #ST_CMD_SET_FEAT          ; Set Features command
  sta ST_CMD
  jsr StWaitReady               ; Wait for command completion
@StInitDone:
  rts

; StSetupLba — Set up LBA registers from CF_LBA zero page variables
; Also sets sector count to 1 and selects master drive in LBA mode
; Modifies: Flags, A
StSetupLba:
  lda #$01
  sta ST_SECT_CNT               ; Always 1 sector
  lda CF_LBA
  sta ST_LBA_0                  ; LBA bits 0-7
  lda CF_LBA + 1
  sta ST_LBA_1                  ; LBA bits 8-15
  lda CF_LBA + 2
  sta ST_LBA_2                  ; LBA bits 16-23
  lda CF_LBA + 3
  and #$0F                      ; Mask to 4 bits (LBA 24-27)
  ora #ST_LBA3_MASTER           ; LBA mode, master drive
  sta ST_LBA_3
  rts

; StReadSector — Read one 512-byte sector from CompactFlash
; Input: CF_LBA ($26-$29) = LBA address, CF_BUF_PTR ($24-$25) = destination pointer
; Output: Carry clear = success, Carry set = error
;         CF_BUF_PTR advanced by 512 bytes on success
; Modifies: Flags, A, X, Y
StReadSectorImpl:
  jsr StWaitReady
  bcs @StReadDone
  jsr StSetupLba
  lda #ST_CMD_READ              ; Issue read command
  sta ST_CMD
  jsr StWaitDrq                 ; Wait for data ready
  bcs @StReadDone
  ; Read 512 bytes: 2 pages of 256 bytes
  ldy #$00
  ldx #$02                      ; 2 pages
@StReadPage:
  lda ST_DATA                   ; Read byte from CF
  sta (CF_BUF_PTR),y            ; Store to destination
  iny
  bne @StReadPage               ; Loop for 256 bytes
  inc CF_BUF_PTR + 1            ; Next page
  dex
  bne @StReadPage
  clc                           ; Success
@StReadDone:
  rts

; StWriteSector — Write one 512-byte sector to CompactFlash
; Input: CF_LBA ($26-$29) = LBA address, CF_BUF_PTR ($24-$25) = source pointer
; Output: Carry clear = success, Carry set = error
;         CF_BUF_PTR advanced by 512 bytes on success
; Modifies: Flags, A, X, Y
StWriteSectorImpl:
  jsr StWaitReady
  bcs @StWriteDone
  jsr StSetupLba
  lda #ST_CMD_WRITE             ; Issue write command
  sta ST_CMD
  jsr StWaitDrq                 ; Wait for data request
  bcs @StWriteDone
  ; Write 512 bytes: 2 pages of 256 bytes
  ldy #$00
  ldx #$02                      ; 2 pages
@StWritePage:
  lda (CF_BUF_PTR),y            ; Load from source
  sta ST_DATA                   ; Write byte to CF
  iny
  bne @StWritePage              ; Loop for 256 bytes
  inc CF_BUF_PTR + 1            ; Next page
  dex
  bne @StWritePage
  jsr StWaitReady               ; Wait for write to complete
@StWriteDone:
  rts

; === Simple Custom Filesystem ===
; Directory at LBA 0: 16 entries x 32 bytes = 512 bytes
; Entry format:
;   $00-$07: 8-byte filename (space-padded)
;   $08-$0A: 3-byte extension (space-padded)
;   $0B:     flags (bit 0 = in use)
;   $0C-$0D: start sector (little-endian)
;   $0E-$0F: file size in bytes (little-endian)
;   $10-$1F: reserved (16 bytes)

; FsParseName — Parse null-terminated filename at STR_PTR into FS_FNAME_BUF
; Converts "NAME.EXT" into 8+3 space-padded format
; Input: STR_PTR ($02-$03) points to null-terminated filename
; Output: FS_FNAME_BUF filled with padded 8+3 name
; Modifies: Flags, A, X, Y
FsParseName:
  ; Fill FS_FNAME_BUF with spaces
  lda #$20
  ldx #10
@FsParseClr:
  sta FS_FNAME_BUF,x
  dex
  bpl @FsParseClr
  ; Copy name part (up to 8 chars, stop at '.' or null)
  ldy #$00                      ; Source index
  ldx #$00                      ; Dest index (name portion)
@FsParseName:
  lda (STR_PTR),y
  beq @FsParseDone              ; Null terminator — no extension
  cmp #'.'
  beq @FsParseExt               ; Found dot — start extension
  cpx #$08
  bcs @FsParseSkipName          ; Already 8 chars, skip extras
  ; Convert lowercase to uppercase
  cmp #'a'
  bcc @FsStoreNameChar
  cmp #'z' + 1
  bcs @FsStoreNameChar
  and #$DF                      ; Clear bit 5 to uppercase
@FsStoreNameChar:
  sta FS_FNAME_BUF,x
  inx
@FsParseSkipName:
  iny
  bra @FsParseName
@FsParseExt:
  iny                           ; Skip the dot
  ldx #$08                      ; Extension starts at offset 8
@FsParseExtLoop:
  lda (STR_PTR),y
  beq @FsParseDone              ; Null terminator
  cpx #$0B
  bcs @FsParseDone              ; Max 3 ext chars
  ; Convert lowercase to uppercase
  cmp #'a'
  bcc @FsStoreExtChar
  cmp #'z' + 1
  bcs @FsStoreExtChar
  and #$DF
@FsStoreExtChar:
  sta FS_FNAME_BUF,x
  inx
  iny
  bra @FsParseExtLoop
@FsParseDone:
  rts

; FsReadDir — Read directory sector (LBA 0) into FS_SECTOR_BUF
; Output: Carry clear = success, Carry set = error
; Modifies: Flags, A, X, Y, CF_LBA, CF_BUF_PTR
FsReadDir:
  stz CF_LBA                    ; LBA = 0 (directory sector)
  stz CF_LBA + 1
  stz CF_LBA + 2
  stz CF_LBA + 3
  lda #<FS_SECTOR_BUF
  sta CF_BUF_PTR
  lda #>FS_SECTOR_BUF
  sta CF_BUF_PTR + 1
  jmp StReadSector

; FsWriteDir — Write directory sector from FS_SECTOR_BUF to LBA 0
; Output: Carry clear = success, Carry set = error
; Modifies: Flags, A, X, Y, CF_LBA, CF_BUF_PTR
FsWriteDir:
  stz CF_LBA
  stz CF_LBA + 1
  stz CF_LBA + 2
  stz CF_LBA + 3
  lda #<FS_SECTOR_BUF
  sta CF_BUF_PTR
  lda #>FS_SECTOR_BUF
  sta CF_BUF_PTR + 1
  jmp StWriteSector

; FsFindFile — Search directory for filename in FS_FNAME_BUF
; Must call FsReadDir first to load directory into FS_SECTOR_BUF
; Output: Carry clear = found, X = entry index (0-15), CF_BUF_PTR points to entry
;         Carry set = not found
; Modifies: Flags, A, X, Y, CF_BUF_PTR
FsFindFile:
  lda #<FS_SECTOR_BUF
  sta CF_BUF_PTR
  lda #>FS_SECTOR_BUF
  sta CF_BUF_PTR + 1
  ldx #$00                      ; Entry index
@FsFindLoop:
  ; Check if entry is in use
  ldy #FS_ENTRY_FLAGS
  lda (CF_BUF_PTR),y
  and #FS_FLAG_USED
  beq @FsFindNext               ; Skip unused entries
  ; Compare 11-byte filename
  ldy #$00
@FsFindCmp:
  lda (CF_BUF_PTR),y
  cmp FS_FNAME_BUF,y
  bne @FsFindNext               ; Mismatch
  iny
  cpy #11
  bne @FsFindCmp
  ; Match found
  stx FS_DIR_IDX
  clc
  rts
@FsFindNext:
  ; Advance CF_BUF_PTR by 32 (FS_ENTRY_SIZE)
  lda CF_BUF_PTR
  clc
  adc #FS_ENTRY_SIZE
  sta CF_BUF_PTR
  bcc @FsFindNoCarry
  inc CF_BUF_PTR + 1
@FsFindNoCarry:
  inx
  cpx #FS_MAX_FILES
  bne @FsFindLoop
  sec                           ; Not found
  rts

; FsFindFree — Find first free directory entry
; Must call FsReadDir first
; Output: Carry clear = found, X = entry index, CF_BUF_PTR points to entry
;         Carry set = directory full
; Modifies: Flags, A, X, Y, CF_BUF_PTR
FsFindFree:
  lda #<FS_SECTOR_BUF
  sta CF_BUF_PTR
  lda #>FS_SECTOR_BUF
  sta CF_BUF_PTR + 1
  ldx #$00
@FsFreeLoop:
  ldy #FS_ENTRY_FLAGS
  lda (CF_BUF_PTR),y
  and #FS_FLAG_USED
  beq @FsFreeFound              ; Found unused entry
  ; Advance by 32
  lda CF_BUF_PTR
  clc
  adc #FS_ENTRY_SIZE
  sta CF_BUF_PTR
  bcc @FsFreeNoCarry
  inc CF_BUF_PTR + 1
@FsFreeNoCarry:
  inx
  cpx #FS_MAX_FILES
  bne @FsFreeLoop
  sec                           ; Directory full
  rts
@FsFreeFound:
  stx FS_DIR_IDX
  clc
  rts

; FsCalcNextSec — Calculate next free sector by scanning all directory entries
; Must call FsReadDir first
; Output: FS_NEXT_SEC = first free sector after all used files
; Modifies: Flags, A, X, Y
FsCalcNextSec:
  lda #<FS_DATA_START           ; Start with first data sector
  sta FS_NEXT_SEC
  lda #>FS_DATA_START
  sta FS_NEXT_SEC + 1
  ; Scan all entries to find highest used sector + file sector count
  lda #<FS_SECTOR_BUF
  sta CF_BUF_PTR
  lda #>FS_SECTOR_BUF
  sta CF_BUF_PTR + 1
  ldx #$00
@FsCalcLoop:
  ldy #FS_ENTRY_FLAGS
  lda (CF_BUF_PTR),y
  and #FS_FLAG_USED
  beq @FsCalcNext               ; Skip unused
  ; Get start sector + ceil(size/512)
  ldy #FS_ENTRY_START
  lda (CF_BUF_PTR),y
  sta FS_START_SEC
  iny
  lda (CF_BUF_PTR),y
  sta FS_START_SEC + 1
  ; Get file size
  ldy #FS_ENTRY_FSIZE
  lda (CF_BUF_PTR),y
  sta FS_FILE_SIZE
  iny
  lda (CF_BUF_PTR),y
  sta FS_FILE_SIZE + 1
  ; Calculate sectors used = (size + 511) / 512 = (size + 511) >> 9
  ; = (size_hi + 1) if size_lo > 0, else size_hi / 2... simplify:
  ; sectors = (size >> 9) rounded up = high_byte >> 1, plus 1 if any remainder
  lda FS_FILE_SIZE + 1          ; High byte of size
  lsr a                         ; Divide by 2 (each sector = 512 = 2 pages)
  sta FS_SEC_COUNT
  ; Check if there's a remainder (low byte != 0 or high byte bit 0 was set)
  lda FS_FILE_SIZE + 1
  and #$01                      ; Was high byte odd?
  bne @FsCalcRound
  lda FS_FILE_SIZE              ; Low byte non-zero?
  beq @FsCalcNoRound
@FsCalcRound:
  inc FS_SEC_COUNT              ; Round up
@FsCalcNoRound:
  ; End sector = start + sector count
  lda FS_START_SEC
  clc
  adc FS_SEC_COUNT
  pha
  lda FS_START_SEC + 1
  adc #$00
  tax                           ; X = end sector high
  pla                           ; A = end sector low
  ; Compare with FS_NEXT_SEC — keep the larger value
  cpx FS_NEXT_SEC + 1
  bcc @FsCalcNext               ; End < FS_NEXT_SEC, skip
  bne @FsCalcUpdate             ; End high > FS_NEXT_SEC high, update
  cmp FS_NEXT_SEC
  bcc @FsCalcNext               ; End low < FS_NEXT_SEC low
@FsCalcUpdate:
  sta FS_NEXT_SEC
  stx FS_NEXT_SEC + 1
@FsCalcNext:
  ; Advance CF_BUF_PTR by 32
  lda CF_BUF_PTR
  clc
  adc #FS_ENTRY_SIZE
  sta CF_BUF_PTR
  bcc @FsCalcNoCarry
  inc CF_BUF_PTR + 1
@FsCalcNoCarry:
  inx
  cpx #FS_MAX_FILES
  bne @FsCalcLoop
  rts

; FsDirectory — Print directory listing of all used entries
; Output via Chrout (respects current IO_MODE)
; Modifies: Flags, A, X, Y
FsDirectory:
  jsr FsReadDir                 ; Load directory sector
  bcc @FsDirStart
  rts                           ; Error reading directory
@FsDirStart:
  lda #<FS_SECTOR_BUF
  sta CF_BUF_PTR
  lda #>FS_SECTOR_BUF
  sta CF_BUF_PTR + 1
  ldx #$00                      ; Entry counter
@FsDirLoop:
  phx
  ldy #FS_ENTRY_FLAGS
  lda (CF_BUF_PTR),y
  and #FS_FLAG_USED
  beq @FsDirNext                ; Skip unused entries
  ; Print filename (8 chars)
  ldy #$00
@FsDirName:
  lda (CF_BUF_PTR),y
  jsr Chrout
  iny
  cpy #$08
  bne @FsDirName
  ; Print dot separator
  lda #'.'
  jsr Chrout
  ; Print extension (3 chars)
@FsDirExt:
  lda (CF_BUF_PTR),y
  jsr Chrout
  iny
  cpy #$0B
  bne @FsDirExt
  ; Print space
  lda #' '
  jsr Chrout
  ; Print file size in decimal
  ldy #FS_ENTRY_FSIZE
  lda (CF_BUF_PTR),y
  sta FS_FILE_SIZE
  iny
  lda (CF_BUF_PTR),y
  sta FS_FILE_SIZE + 1
  jsr FsPrintSize
  ; Print newline
  lda #$0D
  jsr Chrout
  lda #$0A
  jsr Chrout
@FsDirNext:
  ; Advance CF_BUF_PTR by 32
  lda CF_BUF_PTR
  clc
  adc #FS_ENTRY_SIZE
  sta CF_BUF_PTR
  bcc @FsDirNoCarry
  inc CF_BUF_PTR + 1
@FsDirNoCarry:
  plx
  inx
  cpx #FS_MAX_FILES
  bne @FsDirLoop
  rts

; FsPrintSize — Print 16-bit value in FS_FILE_SIZE as decimal
; Modifies: Flags, A, X, Y
FsPrintSize:
  ; Convert 16-bit value to decimal digits (up to 5 digits for 0-65535)
  ; Use successive subtraction of powers of 10
  ldx #$00                      ; Digit index / leading zero suppression
  ldy #$00                      ; Power-of-10 table index
@FsPrintSizeLoop:
  lda #'0' - 1                  ; Start character below '0'
  sta FS_DIR_IDX                ; Reuse as digit scratch
@FsPrintSub:
  inc FS_DIR_IDX
  lda FS_FILE_SIZE
  sec
  sbc @FsPow10Lo,y
  pha
  lda FS_FILE_SIZE + 1
  sbc @FsPow10Hi,y
  bcc @FsPrintSizeDig           ; Underflow — done subtracting
  sta FS_FILE_SIZE + 1
  pla
  sta FS_FILE_SIZE
  bra @FsPrintSub
@FsPrintSizeDig:
  pla                           ; Discard underflowed low byte
  lda FS_DIR_IDX
  cmp #'0'
  bne @FsPrintSizeOut           ; Non-zero digit
  cpx #$00
  beq @FsPrintSizeSkip          ; Suppress leading zeros
@FsPrintSizeOut:
  jsr Chrout
  inx                           ; Mark that we've printed a digit
@FsPrintSizeSkip:
  iny
  cpy #$04                      ; 4 powers of 10 (10000, 1000, 100, 10)
  bne @FsPrintSizeLoop
  ; Always print ones digit
  lda FS_FILE_SIZE
  ora #'0'                      ; Low byte is 0-9 at this point
  jsr Chrout
  rts
@FsPow10Lo: .byte <10000, <1000, <100, <10
@FsPow10Hi: .byte >10000, >1000, >100, >10

; FsLoadFile — Load file from CF into PROGRAM_START ($0800)
; Input: STR_PTR ($02-$03) points to null-terminated filename
; Output: Carry clear = success, FS_FILE_SIZE = bytes loaded
;         Carry set = file not found or read error
; Modifies: Flags, A, X, Y, CF_LBA, CF_BUF_PTR
FsLoadFile:
  jsr FsParseName               ; Parse filename into FS_FNAME_BUF
  jsr FsReadDir                 ; Read directory sector
  bcs @FsLoadErr
  jsr FsFindFile                ; Search for filename
  bcs @FsLoadErr                ; Not found
  ; Read file metadata from entry
  ldy #FS_ENTRY_START
  lda (CF_BUF_PTR),y
  sta FS_START_SEC
  iny
  lda (CF_BUF_PTR),y
  sta FS_START_SEC + 1
  ldy #FS_ENTRY_FSIZE
  lda (CF_BUF_PTR),y
  sta FS_FILE_SIZE
  iny
  lda (CF_BUF_PTR),y
  sta FS_FILE_SIZE + 1
  ; Calculate number of sectors to read
  lda FS_FILE_SIZE + 1
  lsr a
  sta FS_SEC_COUNT
  lda FS_FILE_SIZE + 1
  and #$01
  bne @FsLoadRound
  lda FS_FILE_SIZE
  beq @FsLoadNoRound
@FsLoadRound:
  inc FS_SEC_COUNT
@FsLoadNoRound:
  ; Set up LBA starting at file's start sector
  lda FS_START_SEC
  sta CF_LBA
  lda FS_START_SEC + 1
  sta CF_LBA + 1
  stz CF_LBA + 2
  stz CF_LBA + 3
  ; Set destination pointer to PROGRAM_START
  lda #<PROGRAM_START
  sta CF_BUF_PTR
  lda #>PROGRAM_START
  sta CF_BUF_PTR + 1
  ; Read sectors
  ldx FS_SEC_COUNT
  beq @FsLoadOk                 ; Zero-size file
@FsLoadSec:
  phx
  jsr StReadSector              ; Read sector (advances CF_BUF_PTR by 512)
  bcs @FsLoadSecErr
  ; Increment LBA
  inc CF_LBA
  bne @FsLoadSecNext
  inc CF_LBA + 1
@FsLoadSecNext:
  plx
  dex
  bne @FsLoadSec
@FsLoadOk:
  clc
  rts
@FsLoadSecErr:
  plx                           ; Balance stack
@FsLoadErr:
  sec
  rts

; FsSaveFile — Save data from PROGRAM_START to CF
; Input: STR_PTR ($02-$03) points to null-terminated filename
;        FS_FILE_SIZE ($034A-$034B) = number of bytes to save
; Output: Carry clear = success, Carry set = error (directory full or write error)
; Modifies: Flags, A, X, Y, CF_LBA, CF_BUF_PTR
FsSaveFile:
  jsr FsParseName               ; Parse filename into FS_FNAME_BUF
  jsr FsReadDir                 ; Read directory sector
  bcc @FsSaveReadOk
  jmp @FsSaveErr
@FsSaveReadOk:
  ; Try to find existing file with same name
  jsr FsFindFile
  bcc @FsSaveOverwrite
  ; Not found — find a free slot
  jsr FsFindFree
  bcc @FsSaveAlloc
  jmp @FsSaveErr                ; Directory full
@FsSaveOverwrite:
  ; CF_BUF_PTR already points to the existing entry — clear old flags
  ldy #FS_ENTRY_FLAGS
  lda #$00
  sta (CF_BUF_PTR),y            ; Mark old entry as free
  ; Find a free slot (could be the one we just freed or another)
  jsr FsFindFree
  bcc @FsSaveAlloc
  jmp @FsSaveErr
@FsSaveAlloc:
  ; Save CF_BUF_PTR (points to free entry from FsFindFree)
  lda CF_BUF_PTR
  pha
  lda CF_BUF_PTR + 1
  pha
  ; Calculate next free sector (clobbers CF_BUF_PTR)
  jsr FsCalcNextSec
  ; Restore CF_BUF_PTR to the free directory entry
  pla
  sta CF_BUF_PTR + 1
  pla
  sta CF_BUF_PTR
  ; Calculate sectors needed
  lda FS_FILE_SIZE + 1
  lsr a
  sta FS_SEC_COUNT
  lda FS_FILE_SIZE + 1
  and #$01
  bne @FsSaveRound
  lda FS_FILE_SIZE
  beq @FsSaveNoRound
@FsSaveRound:
  inc FS_SEC_COUNT
@FsSaveNoRound:
  ; Fill in directory entry at CF_BUF_PTR
  ; Copy filename (11 bytes)
  ldy #$00
@FsSaveCopyName:
  lda FS_FNAME_BUF,y
  sta (CF_BUF_PTR),y
  iny
  cpy #11
  bne @FsSaveCopyName
  ; Set flags = in use
  lda #FS_FLAG_USED
  sta (CF_BUF_PTR),y            ; Y = 11 = FS_ENTRY_FLAGS
  ; Set start sector
  ldy #FS_ENTRY_START
  lda FS_NEXT_SEC
  sta (CF_BUF_PTR),y
  sta FS_START_SEC
  iny
  lda FS_NEXT_SEC + 1
  sta (CF_BUF_PTR),y
  sta FS_START_SEC + 1
  ; Set file size
  ldy #FS_ENTRY_FSIZE
  lda FS_FILE_SIZE
  sta (CF_BUF_PTR),y
  iny
  lda FS_FILE_SIZE + 1
  sta (CF_BUF_PTR),y
  ; Clear reserved bytes
  ldy #$10
  lda #$00
@FsSaveClearRsv:
  sta (CF_BUF_PTR),y
  iny
  cpy #FS_ENTRY_SIZE
  bne @FsSaveClearRsv
  ; Write updated directory back to CF
  jsr FsWriteDir
  bcs @FsSaveErr
  ; Now write file data sectors
  lda FS_START_SEC
  sta CF_LBA
  lda FS_START_SEC + 1
  sta CF_LBA + 1
  stz CF_LBA + 2
  stz CF_LBA + 3
  ; Source = PROGRAM_START
  lda #<PROGRAM_START
  sta CF_BUF_PTR
  lda #>PROGRAM_START
  sta CF_BUF_PTR + 1
  ldx FS_SEC_COUNT
  beq @FsSaveOk                 ; Zero-size file
@FsSaveSec:
  phx
  jsr StWriteSector             ; Write sector (advances CF_BUF_PTR by 512)
  bcs @FsSaveSecErr
  ; Increment LBA
  inc CF_LBA
  bne @FsSaveSecNext
  inc CF_LBA + 1
@FsSaveSecNext:
  plx
  dex
  bne @FsSaveSec
@FsSaveOk:
  clc
  rts
@FsSaveSecErr:
  plx                           ; Balance stack
@FsSaveErr:
  sec
  rts

; FsDeleteFile — Delete a file from the CompactFlash filesystem
; Input: STR_PTR ($02-$03) points to null-terminated filename
; Output: Carry clear = success, Carry set = file not found or error
; Modifies: Flags, A, X, Y, CF_LBA, CF_BUF_PTR
FsDeleteFileImpl:
  jsr FsParseName               ; Parse filename into FS_FNAME_BUF
  jsr FsReadDir                 ; Read directory sector
  bcs @FsDelErr
  jsr FsFindFile                ; Search for filename
  bcs @FsDelErr                 ; Not found
  ; Clear the flags byte to mark entry as unused
  ldy #FS_ENTRY_FLAGS
  lda #$00
  sta (CF_BUF_PTR),y
  ; Write updated directory back to CF
  jsr FsWriteDir
  ; Carry already set/clear from FsWriteDir
  rts
@FsDelErr:
  sec
  rts

; === Serial ASCII LOAD/SAVE ===
; Plain binary transfer protocol over serial
; Load: receives 2-byte size (lo/hi) then raw data bytes into PROGRAM_START
; Save: sends 2-byte size (lo/hi) then raw data bytes from PROGRAM_START

; --- ASCII Load ---

; AsciiLoadImpl — Receive raw binary data via serial into program memory
; Switches IO_MODE to serial, receives 2-byte size then raw data bytes
; Data is written starting at PROGRAM_START ($0800)
; Output: Carry clear = success, XFER_PTR points past last byte written
; Modifies: Flags, A, X, Y
AsciiLoadImpl:
  ; Save and switch IO_MODE to serial
  lda IO_MODE
  sta XFER_IO_SAVE
  lda #$01                      ; Serial mode
  sta IO_MODE
  ; Print prompt
  lda #$0D
  jsr SerialChrout
  lda #$0A
  jsr SerialChrout
  lda #<@AsciiLoadMsg
  sta STR_PTR
  lda #>@AsciiLoadMsg
  sta STR_PTR + 1
  jsr @SerialPrintStr
  ; Read 2-byte size (low byte first)
@AsciiWaitSzLo:
  jsr BufferSize
  beq @AsciiWaitSzLo
  jsr ReadBuffer
  sta XFER_REMAIN
@AsciiWaitSzHi:
  jsr BufferSize
  beq @AsciiWaitSzHi
  jsr ReadBuffer
  sta XFER_REMAIN + 1
  ; Initialize write pointer to PROGRAM_START
  lda #<PROGRAM_START
  sta XFER_PTR
  lda #>PROGRAM_START
  sta XFER_PTR + 1
  ; Check for zero-length transfer
  lda XFER_REMAIN
  ora XFER_REMAIN + 1
  beq @AsciiLoadOk
  ; Receive data bytes (Y stays 0, pointer is advanced each byte)
  ldy #$00
@AsciiLoadByte:
  jsr BufferSize
  beq @AsciiLoadByte
  jsr ReadBuffer
  sta (XFER_PTR),y              ; Write byte to target address
  ; Advance write pointer
  inc XFER_PTR
  bne @AsciiLoadNoPage
  inc XFER_PTR + 1
@AsciiLoadNoPage:
  ; Decrement remaining count
  lda XFER_REMAIN
  bne @AsciiLoadDecLo
  dec XFER_REMAIN + 1
@AsciiLoadDecLo:
  dec XFER_REMAIN
  ; Check if done
  lda XFER_REMAIN
  ora XFER_REMAIN + 1
  bne @AsciiLoadByte
@AsciiLoadOk:
  ; XFER_PTR now points past last byte written
  ; Print success message
  lda #$0D
  jsr SerialChrout
  lda #$0A
  jsr SerialChrout
  lda #<@AsciiOkMsg
  sta STR_PTR
  lda #>@AsciiOkMsg
  sta STR_PTR + 1
  jsr @SerialPrintStr
  ; Restore IO_MODE
  lda XFER_IO_SAVE
  sta IO_MODE
  clc                           ; Success
  rts

; Internal: print null-terminated string via serial
; Input: STR_PTR points to string
@SerialPrintStr:
  ldy #$00
@SerialPrintLoop:
  lda (STR_PTR),y
  beq @SerialPrintDone
  jsr SerialChrout
  iny
  bne @SerialPrintLoop
@SerialPrintDone:
  rts

@AsciiLoadMsg: .asciiz "READY TO RECEIVE"
@AsciiOkMsg:   .asciiz "OK"

; --- ASCII Save ---

; AsciiSaveImpl — Transmit program memory as raw binary via serial
; Sends 2-byte size (lo/hi) then raw data bytes from PROGRAM_START to BAS_PRGEND
; Output: Carry clear = success
; Modifies: Flags, A, X, Y
AsciiSaveImpl:
  ; Save and switch IO_MODE to serial
  lda IO_MODE
  sta XFER_IO_SAVE
  lda #$01
  sta IO_MODE
  ; Initialize save pointer
  lda #<PROGRAM_START
  sta XFER_PTR
  lda #>PROGRAM_START
  sta XFER_PTR + 1
  ; Calculate remaining bytes = BAS_PRGEND - PROGRAM_START
  lda z:BAS_PRGEND
  sec
  sbc #<PROGRAM_START
  sta XFER_REMAIN
  lda z:BAS_PRGEND + 1
  sbc #>PROGRAM_START
  sta XFER_REMAIN + 1
  ; Send 2-byte size (low byte first)
  lda XFER_REMAIN
  jsr SerialChrout
  lda XFER_REMAIN + 1
  jsr SerialChrout
  ; Check for zero-length program
  lda XFER_REMAIN
  ora XFER_REMAIN + 1
  beq @AsciiSaveDone
  ; Send data bytes (Y stays 0, pointer is advanced each byte)
  ldy #$00
@AsciiSaveByte:
  lda (XFER_PTR),y
  jsr SerialChrout
  ; Advance read pointer
  inc XFER_PTR
  bne @AsciiSaveNoPage
  inc XFER_PTR + 1
@AsciiSaveNoPage:
  ; Decrement remaining count
  lda XFER_REMAIN
  bne @AsciiSaveDecLo
  dec XFER_REMAIN + 1
@AsciiSaveDecLo:
  dec XFER_REMAIN
  ; Check if done
  lda XFER_REMAIN
  ora XFER_REMAIN + 1
  bne @AsciiSaveByte
@AsciiSaveDone:
  ; Restore IO_MODE
  lda XFER_IO_SAVE
  sta IO_MODE
  clc                           ; Success
  rts

; Draw the splash screen
; Uses video output to display centered title and boot menu
; Modifies: Flags, A, X, Y
Splash:
  jsr VideoClear                ; Clear the video screen
  ; Position cursor at row 10, col 10 for title
  ldx #10
  ldy #10
  jsr VideoSetCursor
  lda #<@SplashTitle
  sta STR_PTR
  lda #>@SplashTitle
  sta STR_PTR + 1
  jsr VideoPrintStrImpl
  ; Position cursor at row 12, col 8 for boot menu (centered: (40-24)/2 = 8)
  ldx #8
  ldy #12
  jsr VideoSetCursor
  lda #<@SplashMenu
  sta STR_PTR
  lda #>@SplashMenu
  sta STR_PTR + 1
  jsr VideoPrintStrImpl
  rts
@SplashTitle: .asciiz "-- The 'COB' v1.0 --"
@SplashMenu:  .asciiz "ENTER=BASIC  ESC=MONITOR"

; NMI Handler
Nmi:
  rti

; BRK Handler — saves full CPU state and enters monitor
; On entry from @IrqBrk: A/X/Y are the user's original values (restored by IRQ handler).
; The CPU's hardware push left P/PCL/PCH on the stack.
Break:
  sta BRK_A                     ; Save user's A register
  stx BRK_X                     ; Save user's X register
  sty BRK_Y                     ; Save user's Y register
  tsx                           ; Get current SP
  stx BRK_SP                   ; Save SP (points below P/PCL/PCH on stack)
  pla                           ; Pull saved P
  sta BRK_P
  pla                           ; Pull saved PCL (PC+2)
  sta BRK_PCL
  pla                           ; Pull saved PCH
  sta BRK_PCH
  jmp MonitorBrkEntry

; IRQ Handler
Irq:
  pha
  phy
  phx
  tsx                           ; Get stack pointer to check saved status register
  lda $104,x                    ; Load saved P (SP+4: past X, Y, A we pushed)
  and #$10                      ; Test B flag — set by BRK, clear by hardware IRQ
  bne @IrqBrk                   ; Branch if this was a BRK instruction
@IrqSc:
  lda SC_STATUS
  and #SC_STATUS_IRQ            ; Check if serial data caused the interrupt
  beq @IrqCheckKB               ; If not, check keyboard
  lda SC_DATA                   ; Read the data from serial register
  jsr WriteBuffer               ; Store to the input buffer
  jsr BufferSize
  cmp #$F0                      ; Is the buffer almost full?
  bcc @IrqExit                  ; If not, exit
  lda #$01                      ; No parity, no echo, RTSB high, TX interrupts disabled, RX interrupts enabled
  sta SC_CMD                    ; Otherwise, signal not ready for receiving (RTSB high)
  bra @IrqExit
@IrqCheckKB:
  lda GPIO_IFR
  and #GPIO_INT_CB1             ; Check if CB1 (matrix keyboard data ready) caused the interrupt
  beq @IrqCheckPS2              ; If not, check PS/2 keyboard
  lda GPIO_PORTB                ; Read ASCII byte from matrix keyboard (also clears CB1 IFR flag)
  jsr WriteBuffer               ; Store to the input buffer
  bra @IrqExit
@IrqCheckPS2:
  lda GPIO_IFR
  and #GPIO_INT_CA1             ; Check if CA1 (PS/2 keyboard data ready) caused the interrupt
  beq @IrqExit                  ; If not, exit
  lda GPIO_PORTA                ; Read ASCII byte from PS/2 keyboard (also clears CA1 IFR flag)
  jsr WriteBuffer               ; Store to the input buffer
@IrqExit:
  plx
  ply
  pla
  rti
@IrqBrk:
  plx                           ; Restore saved registers
  ply
  pla
  cli                           ; Re-enable interrupts — abandoning interrupt context
  jmp (BRK_PTR)                 ; BRK — dispatch with P/PCL/PCH still on stack

; NMI Vector
NmiVec:
  jmp (NMI_PTR)                 ; Indirect jump through NMI pointer to the NMI handler

; Reset Vector
ResetVec:
  jmp Reset                     ; Initialize the system

; IRQ Vector
IrqVec:
  jmp (IRQ_PTR)                 ; Indirect jump through IRQ pointer to the IRQ handler