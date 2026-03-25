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
RtcReadPRAM:    jmp RtcReadPRAMImpl     ; $A042 - Read PRAM byte
RtcWritePRAM:   jmp RtcWritePRAMImpl    ; $A045 - Write PRAM byte
StReadSector:   jmp StReadSectorImpl    ; $A048 - Read CF sector
StWriteSector:  jmp StWriteSectorImpl   ; $A04B - Write CF sector
StWaitReady:    jmp StWaitReadyImpl     ; $A04E - Wait CF ready
SetIOMode:      jmp SetIOModeImpl       ; $A051 - Set IO_MODE
GetIOMode:      jmp GetIOModeImpl       ; $A054 - Get IO_MODE
HexLoad:        jmp HexLoadImpl         ; $A057 - Load Intel HEX via serial
HexSave:        jmp HexSaveImpl         ; $A05A - Save Intel HEX via serial
SidPlayNote:    jmp SidPlayNoteImpl     ; $A05D - Play note (A=voice, X=freqLo, Y=freqHi)
SidSilence:     jmp SidSilenceImpl      ; $A060 - Silence all voices

; Reserved entries ($A063-$A0FE)
.repeat 52
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

  jsr InitBuffer                ; Initialize the input buffer
  jsr InitSC                    ; Initialize the Serial Card (6551)
  jsr InitSID                   ; Initialize the Sound Card (6581)
  jsr InitVideo                 ; Initialize the Video Card (TMS9918)
  jsr InitCharacters            ; Initialize the character set
  jsr InitKB                    ; Initialize the keyboard (VIA)
  jsr StInit                    ; Initialize CompactFlash (8-bit mode)

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
  jsr VideoClear                ; Clear screen before entering Monitor
  jmp MonitorEntry

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

; RtcReadPRAM — Read a byte from DS1511Y PRAM
; Input: X = PRAM address ($00-$FF)
; Output: A = data byte
; Modifies: Flags
RtcReadPRAMImpl:
  stx RTC_RAM_ADDR
  lda RTC_RAM_DATA
  rts

; RtcWritePRAM — Write a byte to DS1511Y PRAM
; Input: X = PRAM address ($00-$FF), A = data byte
; Modifies: Flags
RtcWritePRAMImpl:
  stx RTC_RAM_ADDR
  sta RTC_RAM_DATA
  rts

; === CompactFlash Storage Driver (True 8-bit IDE Mode) ===

; StWaitReady — Wait for CompactFlash to become ready
; Polls ST_STATUS until BSY=0 and RDY=1
; Output: Carry clear = ready, Carry set = error (ERR bit set)
; Modifies: Flags, A
StWaitReadyImpl:
@StWaitBsy:
  lda ST_STATUS
  and #ST_STATUS_BSY            ; Check BSY bit
  bne @StWaitBsy                ; Loop while busy
  lda ST_STATUS
  and #ST_STATUS_RDY            ; Check RDY bit
  beq @StWaitBsy                ; Loop until ready
  lda ST_STATUS
  and #ST_STATUS_ERR            ; Check ERR bit
  bne @StWaitErr
  clc                           ; Ready, no error
  rts
@StWaitErr:
  sec                           ; Error condition
  rts

; StWaitDrq — Wait for CompactFlash data request
; Polls ST_STATUS until BSY=0 and DRQ=1
; Output: Carry clear = DRQ active, Carry set = error
; Modifies: Flags, A
StWaitDrq:
@StDrqBsy:
  lda ST_STATUS
  and #ST_STATUS_BSY
  bne @StDrqBsy
  lda ST_STATUS
  and #ST_STATUS_ERR
  bne @StDrqErr
  lda ST_STATUS
  and #ST_STATUS_DRQ
  beq @StDrqBsy
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
  bcs @StInitDone
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

; === Serial Intel HEX LOAD/SAVE ===
; Intel HEX record format: :LLAAAATT[DD...]CC
;   : = start code
;   LL = byte count (2 hex digits)
;   AAAA = address (4 hex digits, big-endian)
;   TT = record type (00=data, 01=EOF)
;   DD = data bytes (2 hex digits each)
;   CC = checksum (two's complement of sum of all bytes LL..DD)

; --- Hex Conversion Utilities ---

; HexToNibble — Convert ASCII hex char to 4-bit value
; Input: A = ASCII hex character ('0'-'9', 'A'-'F', 'a'-'f')
; Output: A = 0-15, Carry clear = valid, Carry set = invalid
; Modifies: Flags
HexToNibble:
  cmp #'0'
  bcc @HexNibInvalid
  cmp #'9' + 1
  bcc @HexNibDigit              ; '0'-'9'
  cmp #'A'
  bcc @HexNibInvalid
  cmp #'F' + 1
  bcc @HexNibAlpha              ; 'A'-'F'
  cmp #'a'
  bcc @HexNibInvalid
  cmp #'f' + 1
  bcs @HexNibInvalid
  ; 'a'-'f': subtract $57 to get 10-15
  sec
  sbc #$57
  clc
  rts
@HexNibDigit:
  sec
  sbc #'0'                      ; Convert '0'-'9' → 0-9
  clc
  rts
@HexNibAlpha:
  sec
  sbc #$37                      ; Convert 'A'-'F' → 10-15
  clc
  rts
@HexNibInvalid:
  sec
  rts

; NibbleToHex — Convert 4-bit value to ASCII hex character
; Input: A = value (low nibble only, 0-15)
; Output: A = ASCII hex character ('0'-'9', 'A'-'F')
; Modifies: Flags
NibbleToHex:
  and #$0F
  cmp #$0A
  bcc @NibHexDigit
  clc
  adc #$37                      ; 10-15 → 'A'-'F'
  rts
@NibHexDigit:
  clc
  adc #'0'                      ; 0-9 → '0'-'9'
  rts

; SerialPrintHexByte — Print a byte as 2 hex ASCII chars to serial
; Input: A = byte to print
; Modifies: Flags, A
SerialPrintHexByte:
  pha
  lsr a                         ; Shift high nibble down
  lsr a
  lsr a
  lsr a
  jsr NibbleToHex
  jsr SerialChrout              ; Print high nibble
  pla
  pha
  jsr NibbleToHex               ; Low nibble (and #$0F inside NibbleToHex)
  jsr SerialChrout              ; Print low nibble
  pla
  rts

; SerialReadHexByte — Read 2 hex ASCII chars from serial, return byte
; Blocks until 2 valid hex chars received
; Output: A = byte value, Carry clear = success, Carry set = invalid char
; Also adds result to HEX_CHKSUM
; Modifies: Flags, A
SerialReadHexByte:
  ; Wait for first hex char (high nibble)
@SrHexWait1:
  jsr BufferSize
  beq @SrHexWait1
  jsr ReadBuffer
  jsr HexToNibble
  bcs @SrHexErr                 ; Invalid hex char
  asl a                         ; Shift to high nibble
  asl a
  asl a
  asl a
  sta HEX_RECTYPE               ; Temp storage for high nibble (reuse HEX_RECTYPE briefly)
  ; Wait for second hex char (low nibble)
@SrHexWait2:
  jsr BufferSize
  beq @SrHexWait2
  jsr ReadBuffer
  jsr HexToNibble
  bcs @SrHexErr
  ora HEX_RECTYPE               ; Combine high and low nibbles
  ; Add to running checksum
  pha
  clc
  adc HEX_CHKSUM
  sta HEX_CHKSUM
  pla
  clc                           ; Success
  rts
@SrHexErr:
  sec
  rts

; --- Intel HEX Load ---

; HexLoadImpl — Receive Intel HEX records via serial and write to memory
; Switches IO_MODE to serial, parses records, validates checksums
; On data records (type $00): writes bytes to addresses specified in records
; On EOF record (type $01): finishes loading
; Output: Carry clear = success, Carry set = error (checksum fail or parse error)
;         On success, HEX_ADDR contains the last address written + 1
; Modifies: Flags, A, X, Y
HexLoadImpl:
  ; Save and switch IO_MODE to serial
  lda IO_MODE
  sta HEX_IO_SAVE
  lda #$01                      ; Serial mode
  sta IO_MODE
  ; Print prompt
  lda #$0D
  jsr SerialChrout
  lda #$0A
  jsr SerialChrout
  lda #<@HexLoadMsg
  sta STR_PTR
  lda #>@HexLoadMsg
  sta STR_PTR + 1
  jsr @SerialPrintStr

@HexLoadRecord:
  ; Wait for start code ':'
@HexWaitColon:
  jsr BufferSize
  beq @HexWaitColon
  jsr ReadBuffer
  cmp #':'
  bne @HexWaitColon             ; Ignore chars until ':'
  ; Reset checksum
  stz HEX_CHKSUM
  ; Read byte count (LL)
  jsr SerialReadHexByte
  bcs @HexLoadFail
  sta HEX_BYTECNT
  ; Read address high byte (AA)
  jsr SerialReadHexByte
  bcs @HexLoadFail
  sta HEX_PTR + 1
  ; Read address low byte (AA)
  jsr SerialReadHexByte
  bcs @HexLoadFail
  sta HEX_PTR
  ; Read record type (TT)
  jsr SerialReadHexByte
  bcs @HexLoadFail
  sta HEX_RECTYPE
  ; Check record type
  cmp #$01                      ; EOF record?
  beq @HexLoadEOF
  cmp #$00                      ; Data record?
  bne @HexLoadFail              ; Unknown record type — error
  ; Data record — read data bytes
  ldy #$00
@HexLoadData:
  cpy HEX_BYTECNT
  beq @HexLoadChecksum          ; All data bytes read
  jsr SerialReadHexByte
  bcs @HexLoadFail
  sta (HEX_PTR),y               ; Write byte to target address
  iny
  bra @HexLoadData
@HexLoadChecksum:
  ; Read checksum byte
  jsr SerialReadHexByte
  bcs @HexLoadFail
  ; Verify: running checksum (including checksum byte) should be $00
  lda HEX_CHKSUM
  bne @HexLoadFail              ; Checksum error
  ; Advance HEX_PTR by byte count for tracking end position
  lda HEX_PTR
  clc
  adc HEX_BYTECNT
  sta HEX_PTR
  bcc @HexLoadNoCarry
  inc HEX_PTR + 1
@HexLoadNoCarry:
  ; Print '.' progress indicator
  lda #'.'
  jsr SerialChrout
  bra @HexLoadRecord            ; Next record
@HexLoadEOF:
  ; EOF record — read and verify checksum
  jsr SerialReadHexByte
  bcs @HexLoadFail
  lda HEX_CHKSUM
  bne @HexLoadFail              ; Checksum error on EOF
  ; Print success message
  lda #$0D
  jsr SerialChrout
  lda #$0A
  jsr SerialChrout
  lda #<@HexOkMsg
  sta STR_PTR
  lda #>@HexOkMsg
  sta STR_PTR + 1
  jsr @SerialPrintStr
  ; Restore IO_MODE
  lda HEX_IO_SAVE
  sta IO_MODE
  clc                           ; Success
  rts
@HexLoadFail:
  ; Print error message
  lda #$0D
  jsr SerialChrout
  lda #$0A
  jsr SerialChrout
  lda #<@HexErrMsg
  sta STR_PTR
  lda #>@HexErrMsg
  sta STR_PTR + 1
  jsr @SerialPrintStr
  ; Restore IO_MODE
  lda HEX_IO_SAVE
  sta IO_MODE
  sec                           ; Error
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

@HexLoadMsg: .asciiz "READY TO RECEIVE"
@HexOkMsg:   .asciiz "OK"
@HexErrMsg:  .asciiz "ERROR"

; --- Intel HEX Save ---

; HexSaveImpl — Transmit program memory as Intel HEX records via serial
; Generates 16-byte data records from PROGRAM_START ($0800) to BAS_PRGEND
; Ends with EOF record :00000001FF
; Output: Carry clear = success
; Modifies: Flags, A, X, Y
HexSaveImpl:
  ; Save and switch IO_MODE to serial
  lda IO_MODE
  sta HEX_IO_SAVE
  lda #$01
  sta IO_MODE
  ; Print CRLF
  lda #$0D
  jsr SerialChrout
  lda #$0A
  jsr SerialChrout
  ; Initialize save pointer
  lda #<PROGRAM_START
  sta HEX_PTR
  lda #>PROGRAM_START
  sta HEX_PTR + 1
  ; Calculate remaining bytes = BAS_PRGEND - PROGRAM_START
  lda z:BAS_PRGEND
  sec
  sbc #<PROGRAM_START
  sta HEX_REMAIN
  lda z:BAS_PRGEND + 1
  sbc #>PROGRAM_START
  sta HEX_REMAIN + 1
  ; Check for zero-length program
  ora HEX_REMAIN
  bne @HexSaveRecord
  jmp @HexSaveEOF
@HexSaveRecord:
  ; Determine byte count for this record: min(16, HEX_REMAIN)
  lda HEX_REMAIN + 1
  bne @HexSave16                ; High byte > 0, at least 256 remaining
  lda HEX_REMAIN
  cmp #17
  bcc @HexSavePartial           ; Less than 17 bytes, use actual count
@HexSave16:
  lda #16
  bra @HexSaveEmit
@HexSavePartial:
  lda HEX_REMAIN                ; Use actual remaining count
@HexSaveEmit:
  sta HEX_BYTECNT
  ; Reset checksum
  stz HEX_CHKSUM
  ; Print start code
  lda #':'
  jsr SerialChrout
  ; Print byte count
  lda HEX_BYTECNT
  clc
  adc HEX_CHKSUM
  sta HEX_CHKSUM
  lda HEX_BYTECNT
  jsr SerialPrintHexByte
  ; Print address (high byte first)
  lda HEX_PTR + 1
  clc
  adc HEX_CHKSUM
  sta HEX_CHKSUM
  lda HEX_PTR + 1
  jsr SerialPrintHexByte
  ; Address low byte
  lda HEX_PTR
  clc
  adc HEX_CHKSUM
  sta HEX_CHKSUM
  lda HEX_PTR
  jsr SerialPrintHexByte
  ; Print record type 00 (data)
  lda #$00
  jsr SerialPrintHexByte        ; Prints "00", checksum unaffected (adding 0)
  ; Print data bytes
  ldy #$00
@HexSaveData:
  cpy HEX_BYTECNT
  beq @HexSaveChksum
  lda (HEX_PTR),y
  pha
  clc
  adc HEX_CHKSUM
  sta HEX_CHKSUM
  pla
  jsr SerialPrintHexByte
  iny
  bra @HexSaveData
@HexSaveChksum:
  ; Print checksum = two's complement of running sum
  lda HEX_CHKSUM
  eor #$FF
  clc
  adc #$01                      ; Two's complement
  jsr SerialPrintHexByte
  ; Print CRLF after record
  lda #$0D
  jsr SerialChrout
  lda #$0A
  jsr SerialChrout
  ; Advance save pointer
  lda HEX_PTR
  clc
  adc HEX_BYTECNT
  sta HEX_PTR
  bcc @HexSaveNoCarry
  inc HEX_PTR + 1
@HexSaveNoCarry:
  ; Subtract from remaining
  lda HEX_REMAIN
  sec
  sbc HEX_BYTECNT
  sta HEX_REMAIN
  bcs @HexSaveNoBorrow
  dec HEX_REMAIN + 1
@HexSaveNoBorrow:
  ; Check if done
  lda HEX_REMAIN
  ora HEX_REMAIN + 1
  beq @HexSaveDone
  jmp @HexSaveRecord            ; More bytes to send
@HexSaveDone:
@HexSaveEOF:
  ; Send EOF record :00000001FF
  lda #':'
  jsr SerialChrout
  lda #$00
  jsr SerialPrintHexByte        ; Byte count = 0
  lda #$00
  jsr SerialPrintHexByte        ; Address high = 0
  lda #$00
  jsr SerialPrintHexByte        ; Address low = 0
  lda #$01
  jsr SerialPrintHexByte        ; Type = 01 (EOF)
  lda #$FF
  jsr SerialPrintHexByte        ; Checksum = FF
  lda #$0D
  jsr SerialChrout
  lda #$0A
  jsr SerialChrout
  ; Restore IO_MODE
  lda HEX_IO_SAVE
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

; BRK Handler — default dispatches to WozMon
; On entry the stack holds the processor-pushed state from the BRK:
;   SP+1 = saved P, SP+2 = PCL (PC+2), SP+3 = PCH
; State is saved to BRK_P/BRK_PCL/BRK_PCH for inspection by a custom handler.
Break:
  pla                           ; Pull saved P
  sta BRK_P
  pla                           ; Pull saved PCL (PC+2)
  sta BRK_PCL
  pla                           ; Pull saved PCH
  sta BRK_PCH
  jmp MonitorEntry

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