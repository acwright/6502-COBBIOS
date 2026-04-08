; ***             ***
; ***   MONITOR   ***
; ***             ***

; Machine Code Monitor — Supermon-style command set
; Segment: $E800-$FEFF (~6KB)
;
; Entry points:
;   MonitorEntry    ($E800) — Cold entry from boot menu or X return
;   MonitorBrkEntry ($E803) — BRK entry with register display

; ============================================================================
; Monitor Constants
; ============================================================================

MON_LINBUF          = BAS_LINBUF         ; Share BASIC's line buffer ($0434)
MON_LINBUF_SIZE     = 200                ; Max input line length
MON_PROMPT          = '.'                ; Supermon-style prompt character

; Mnemonic Indices (for disassembler)
MN_ADC = 0
MN_AND = 1
MN_ASL = 2
MN_BBR = 3
MN_BBS = 4
MN_BCC = 5
MN_BCS = 6
MN_BEQ = 7
MN_BIT = 8
MN_BMI = 9
MN_BNE = 10
MN_BPL = 11
MN_BRA = 12
MN_BRK = 13
MN_BVC = 14
MN_BVS = 15
MN_CLC = 16
MN_CLD = 17
MN_CLI = 18
MN_CLV = 19
MN_CMP = 20
MN_CPX = 21
MN_CPY = 22
MN_DEC = 23
MN_DEX = 24
MN_DEY = 25
MN_EOR = 26
MN_INC = 27
MN_INX = 28
MN_INY = 29
MN_JMP = 30
MN_JSR = 31
MN_LDA = 32
MN_LDX = 33
MN_LDY = 34
MN_LSR = 35
MN_NOP = 36
MN_ORA = 37
MN_PHA = 38
MN_PHP = 39
MN_PHX = 40
MN_PHY = 41
MN_PLA = 42
MN_PLP = 43
MN_PLX = 44
MN_PLY = 45
MN_RMB = 46
MN_ROL = 47
MN_ROR = 48
MN_RTI = 49
MN_RTS = 50
MN_SBC = 51
MN_SEC = 52
MN_SED = 53
MN_SEI = 54
MN_SMB = 55
MN_STA = 56
MN_STP = 57
MN_STX = 58
MN_STY = 59
MN_STZ = 60
MN_TAX = 61
MN_TAY = 62
MN_TRB = 63
MN_TSB = 64
MN_TSX = 65
MN_TXA = 66
MN_TXS = 67
MN_TYA = 68
MN_WAI = 69
MN_UND = 70

; Addressing Mode Indices
AM_IMP = 0
AM_ACC = 1
AM_IMM = 2
AM_ZP  = 3
AM_ZPX = 4
AM_ZPY = 5
AM_ABS = 6
AM_ABX = 7
AM_ABY = 8
AM_IND = 9
AM_IZX = 10
AM_IZY = 11
AM_ZPI = 12
AM_REL = 13
AM_ZPR = 14
AM_AIX = 15

; ============================================================================
; Entry Points
; ============================================================================

MonitorEntry:
  jmp MonColdEntry              ; $E800 - Cold entry (boot menu / return)

MonitorBrkEntry:
  jmp MonBrkEntry               ; $C003 - BRK entry (register display)

; ============================================================================
; Cold Entry — print banner and enter command loop
; ============================================================================

MonColdEntry:
  ldx #$FF
  txs                           ; Reset stack pointer
  cld                           ; Ensure binary mode
  jsr VideoClear                ; Clear screen
  jsr MonPrintBanner            ; Print "MONITOR" banner
  jmp MonCmdLoop

; ============================================================================
; BRK Entry — print BRK address, display registers, enter command loop
; ============================================================================

MonBrkEntry:
  ldx #$FF
  txs                           ; Reset stack pointer
  cld
  jsr VideoClear                ; Clear screen
  jsr MonPrintBanner            ; Print "MONITOR" banner
  ; Print "BRK AT $"
  ldx #0
@BrkMsgLoop:
  lda MonStrBrk,x
  beq @BrkMsgDone
  jsr Chrout
  inx
  bra @BrkMsgLoop
@BrkMsgDone:
  ; Print PC address (adjusted: BRK_PC points to BRK+2, subtract 2 for actual BRK location)
  sec
  lda BRK_PCL
  sbc #2
  sta MON_ADDR
  lda BRK_PCH
  sbc #0
  sta MON_ADDR + 1
  jsr MonPrintHex4
  jsr MonPrintCRLF
  ; Display registers
  jsr MonShowRegs
  jmp MonCmdLoop

; ============================================================================
; Command Loop — prompt, read, parse, dispatch
; ============================================================================

MonCmdLoop:
  ; Print prompt
  lda #MON_PROMPT
  jsr Chrout
  lda #' '
  jsr Chrout

  ; Read input line
  jsr MonReadLine

  ; Parse and dispatch
  jsr MonParseLine

  ; Loop back for next command
  jmp MonCmdLoop

; ============================================================================
; MonReadLine — Read a line of input into MON_LINBUF
; Returns: MON_LINBUF contains null-terminated input, Y = length
; ============================================================================

MonReadLine:
  ldy #0                        ; Index into line buffer
@ReadWait:
  jsr Chrin                     ; Try to read a character (carry set = got one)
  bcc @ReadWait                 ; No char available, keep waiting
  ; Got a character in A
  cmp #$0D                      ; Carriage return?
  beq @ReadDone
  cmp #$0A                      ; Line feed? (treat same as CR)
  beq @ReadDone
  cmp #$08                      ; Backspace?
  beq @ReadBS
  cmp #$7F                      ; Delete? (treat as backspace)
  beq @ReadBS
  ; Skip non-printable characters ($00-$1F)
  cmp #$20
  bcc @ReadWait
  ; Printable character — store if room
  cpy #MON_LINBUF_SIZE
  bcs @ReadWait                 ; Buffer full, ignore
  sta MON_LINBUF,y
  iny
  bra @ReadWait
@ReadBS:
  cpy #0                        ; Anything to delete?
  beq @ReadWait                 ; No, ignore
  dey                           ; Back up one position
  bra @ReadWait
@ReadDone:
  lda #$0D                      ; Echo CR
  jsr Chrout
  lda #$0A                      ; Echo LF
  jsr Chrout
  lda #0
  sta MON_LINBUF,y              ; Null-terminate
  rts

; ============================================================================
; MonParseLine — Parse first char and dispatch to command handler
; ============================================================================

MonParseLine:
  stz MON_IDX                   ; Reset parse index
  jsr MonSkipSpaces             ; Skip leading whitespace
  ldy MON_IDX
  lda MON_LINBUF,y              ; Get command character
  beq @ParseDone                ; Empty line — just return
  ; Convert to uppercase
  cmp #'a'
  bcc @ParseNoConv
  cmp #'z'+1
  bcs @ParseNoConv
  and #$DF                      ; Convert lowercase to uppercase
@ParseNoConv:
  inc MON_IDX                   ; Advance past command char
  ; Search dispatch table
  ldx #0
@DispatchLoop:
  ldy MonCmdTable,x             ; Load command character from table
  beq @ParseError               ; End of table (null terminator) — unknown command
  cmp MonCmdTable,x             ; Compare with input character
  beq @DispatchFound
  inx                           ; Skip char
  inx                           ; Skip address low
  inx                           ; Skip address high
  bra @DispatchLoop
@DispatchFound:
  inx                           ; Point to address low byte
  lda MonCmdTable+1,x           ; Handler address high byte — push first (big-endian on stack)
  pha
  lda MonCmdTable,x             ; Handler address low byte
  pha
  rts                           ; "Return" to handler address (RTS adds 1 to address)
@ParseError:
  jsr MonPrintError
@ParseDone:
  rts

; ============================================================================
; Command Dispatch Table
; Format: command char (1 byte), handler address - 1 (2 bytes, low/high for RTS trick)
; ============================================================================

MonCmdTable:
  .byte 'X'
  .word MonCmdX - 1
  .byte 'R'
  .word MonCmdR - 1
  .byte 'M'
  .word MonCmdM - 1
  .byte 'D'
  .word MonCmdD - 1
  .byte '>'
  .word MonCmdDeposit - 1
  .byte 'F'
  .word MonCmdFill - 1
  .byte 'T'
  .word MonCmdTransfer - 1
  .byte 'H'
  .word MonCmdHunt - 1
  .byte 'C'
  .word MonCmdCompare - 1
  .byte 'G'
  .word MonCmdGo - 1
  .byte 'J'
  .word MonCmdJsr - 1
  .byte ';'
  .word MonCmdModRegs - 1
  .byte 'L'
  .word MonCmdLoad - 1
  .byte 'S'
  .word MonCmdSave - 1
  .byte '@'
  .word MonCmdDir - 1
  .byte 'N'
  .word MonCmdNum - 1
  .byte 0                       ; End of table sentinel

; ============================================================================
; MonCmdX — Exit to BASIC
; ============================================================================

MonCmdX:
  jsr VideoClear                ; Clear screen before entering BASIC
  jmp BasColdStart

; ============================================================================
; MonCmdR — Display CPU registers
; ============================================================================

MonCmdR:
  jsr MonShowRegs
  rts

; ============================================================================
; MonCmdDeposit — Deposit (write) bytes to memory
; Syntax: > ADDR XX [XX XX ...]
; ============================================================================

MonCmdDeposit:
  jsr MonSkipSpaces
  jsr MonParseHex4              ; Parse target address into MON_ADDR
  bcc @DepError                 ; No address → error
  ldy #0                        ; Byte offset from MON_ADDR
@DepLoop:
  phy                           ; Save byte offset (Y clobbered by parse routines)
  jsr MonSkipSpaces
  jsr MonParseHex2              ; Parse next byte into A
  ply                           ; Restore byte offset (PLY doesn't affect carry)
  bcc @DepDone                  ; No more bytes → done
  sta (MON_ADDR),y
  iny
  bne @DepLoop                  ; Up to 256 bytes (Y wraps)
@DepDone:
  cpy #0                        ; Did we deposit at least one byte?
  beq @DepError                 ; No bytes given → error
  rts
@DepError:
  jmp MonPrintError

; ============================================================================
; MonCmdFill — Fill memory range with a byte value
; Syntax: F ADDR1 ADDR2 XX
; ============================================================================

MonCmdFill:
  jsr MonSkipSpaces
  jsr MonParseHex4              ; Parse start address → MON_ADDR
  bcc @FillError
  lda MON_ADDR
  sta MON_TMP
  lda MON_ADDR+1
  sta MON_TMP+1                 ; Save start in MON_TMP
  jsr MonSkipSpaces
  jsr MonParseHex4              ; Parse end address → MON_ADDR
  bcc @FillError
  lda MON_ADDR
  sta MON_END
  lda MON_ADDR+1
  sta MON_END+1                 ; Save end in MON_END
  ; Restore start into MON_ADDR
  lda MON_TMP
  sta MON_ADDR
  lda MON_TMP+1
  sta MON_ADDR+1
  jsr MonSkipSpaces
  jsr MonParseHex2              ; Parse fill byte → A
  bcc @FillError
  ; A = fill byte, MON_ADDR = start, MON_END = end (inclusive)
  ldy #0
@FillLoop:
  sta (MON_ADDR),y
  ; Check if MON_ADDR == MON_END
  ldx MON_ADDR+1
  cpx MON_END+1
  bne @FillNext
  ldx MON_ADDR
  cpx MON_END
  beq @FillDone
@FillNext:
  ; Advance MON_ADDR
  pha                           ; Save fill byte
  inc MON_ADDR
  bne @FillNoHi
  inc MON_ADDR+1
@FillNoHi:
  pla                           ; Restore fill byte
  bra @FillLoop
@FillDone:
  rts
@FillError:
  jmp MonPrintError

; ============================================================================
; MonCmdTransfer — Copy memory block (handles overlapping regions)
; Syntax: T SRC_START SRC_END DEST
; ============================================================================

MonCmdTransfer:
  jsr MonSkipSpaces
  jsr MonParseHex4              ; Parse source start → MON_ADDR
  bcs @XferGotStart
  jmp @XferError                ; No address → error
@XferGotStart:
  lda MON_ADDR
  sta MON_TMP
  lda MON_ADDR+1
  sta MON_TMP+1                 ; MON_TMP = source start
  jsr MonSkipSpaces
  jsr MonParseHex4              ; Parse source end → MON_ADDR
  bcs @XferGotEnd
  jmp @XferError
@XferGotEnd:
  lda MON_ADDR
  sta MON_END
  lda MON_ADDR+1
  sta MON_END+1                 ; MON_END = source end (inclusive)
  jsr MonSkipSpaces
  jsr MonParseHex4              ; Parse dest → MON_ADDR
  bcs @XferGotDest
  jmp @XferError
@XferGotDest:
  ; MON_ADDR = dest, MON_TMP = src start, MON_END = src end
  ; Determine copy direction: if dest > src_start, copy backward to handle overlap
  lda MON_ADDR+1
  cmp MON_TMP+1
  bcc @CopyForward              ; dest < src → forward is safe
  bne @CopyBackward             ; dest > src → need backward
  lda MON_ADDR
  cmp MON_TMP
  bcc @CopyForward
  beq @XferDone                 ; dest == src → nothing to do
@CopyBackward:
  ; Compute offset = src_end - src_start
  sec
  lda MON_END
  sbc MON_TMP
  sta MON_BYTE                  ; low byte of offset
  lda MON_END+1
  sbc MON_TMP+1
  sta MON_IDX                   ; high byte of offset (reuse MON_IDX as scratch)
  ; Point MON_TMP to src_end, MON_ADDR to dest + offset
  ; MON_TMP already needs to be src_end (currently src_start)
  ; Swap: MON_TMP = MON_END (src_end)
  lda MON_END
  pha
  lda MON_END+1
  pha
  ; MON_END = src_start (save for later comparison)
  lda MON_TMP
  sta MON_END
  lda MON_TMP+1
  sta MON_END+1
  ; MON_TMP = src_end
  pla
  sta MON_TMP+1
  pla
  sta MON_TMP
  ; dest_end = MON_ADDR + offset
  clc
  lda MON_ADDR
  adc MON_BYTE
  sta MON_ADDR
  lda MON_ADDR+1
  adc MON_IDX
  sta MON_ADDR+1
@BackLoop:
  ldy #0
  lda (MON_TMP),y
  sta (MON_ADDR),y
  ; Check if MON_TMP == MON_END (src start, our stop address)
  lda MON_TMP+1
  cmp MON_END+1
  bne @BackDec
  lda MON_TMP
  cmp MON_END
  beq @XferDone
@BackDec:
  ; Decrement both pointers
  lda MON_TMP
  bne @BackDecTmpLo
  dec MON_TMP+1
@BackDecTmpLo:
  dec MON_TMP
  lda MON_ADDR
  bne @BackDecDstLo
  dec MON_ADDR+1
@BackDecDstLo:
  dec MON_ADDR
  bra @BackLoop

@CopyForward:
  ; Copy from MON_TMP (src) to MON_ADDR (dest), up to MON_END (src end)
  ldy #0
@FwdLoop:
  lda (MON_TMP),y
  sta (MON_ADDR),y
  ; Check if MON_TMP == MON_END
  lda MON_TMP+1
  cmp MON_END+1
  bne @FwdNext
  lda MON_TMP
  cmp MON_END
  beq @XferDone
@FwdNext:
  ; Advance both pointers
  inc MON_TMP
  bne @FwdNoDstCarry
  inc MON_TMP+1
@FwdNoDstCarry:
  inc MON_ADDR
  bne @FwdLoop
  inc MON_ADDR+1
  bra @FwdLoop

@XferDone:
  rts
@XferError:
  jmp MonPrintError

; ============================================================================
; MonCmdHunt — Search for byte pattern in memory range
; Syntax: H ADDR1 ADDR2 XX [XX XX ...]
; Prints address of each match on its own line.
; ============================================================================

; Hunt uses a temp buffer at end of MON_LINBUF area for the pattern.
; Pattern bytes stored at MON_LINBUF+128, max 64 pattern bytes.
MON_HUNT_PAT        = MON_LINBUF + 128
MON_HUNT_PAT_MAX    = 64

MonCmdHunt:
  jsr MonSkipSpaces
  jsr MonParseHex4              ; Parse start address → MON_ADDR
  bcc @HuntError
  lda MON_ADDR
  sta MON_TMP
  lda MON_ADDR+1
  sta MON_TMP+1                 ; MON_TMP = search start
  jsr MonSkipSpaces
  jsr MonParseHex4              ; Parse end address → MON_ADDR
  bcc @HuntError
  lda MON_ADDR
  sta MON_END
  lda MON_ADDR+1
  sta MON_END+1                 ; MON_END = search end
  ; Restore start
  lda MON_TMP
  sta MON_ADDR
  lda MON_TMP+1
  sta MON_ADDR+1
  ; Parse pattern bytes into MON_HUNT_PAT
  ldx #0                        ; Pattern length counter
@HuntParseByte:
  phx                           ; Save pattern counter (X clobbered by MonParseHex2)
  jsr MonSkipSpaces
  jsr MonParseHex2              ; Next byte → A
  plx                           ; Restore pattern counter (PLX doesn't affect carry)
  bcc @HuntParseEnd
  cpx #MON_HUNT_PAT_MAX
  bcs @HuntParseEnd             ; Pattern buffer full
  sta MON_HUNT_PAT,x
  inx
  bra @HuntParseByte
@HuntParseEnd:
  cpx #0
  beq @HuntError                ; No pattern bytes → error
  stx MON_BYTE                  ; MON_BYTE = pattern length
  ; Search: scan MON_ADDR to MON_END for pattern match
@HuntScanLoop:
  ldy #0                        ; Pattern match index
@HuntMatchLoop:
  lda (MON_ADDR),y
  cmp MON_HUNT_PAT,y
  bne @HuntNoMatch
  iny
  cpy MON_BYTE                  ; Matched all pattern bytes?
  bcc @HuntMatchLoop
  ; Full match — print address
  jsr MonPrintHex4
  jsr MonPrintCRLF
@HuntNoMatch:
  ; Check if MON_ADDR == MON_END
  lda MON_ADDR+1
  cmp MON_END+1
  bne @HuntAdvance
  lda MON_ADDR
  cmp MON_END
  beq @HuntDone
@HuntAdvance:
  inc MON_ADDR
  bne @HuntScanLoop
  inc MON_ADDR+1
  bra @HuntScanLoop
@HuntDone:
  rts
@HuntError:
  jmp MonPrintError

; ============================================================================
; MonCmdCompare — Compare two memory regions
; Syntax: C ADDR1 ADDR2 ADDR3
; Compares [addr1,addr2] with block at addr3, prints differing addresses.
; ============================================================================

MonCmdCompare:
  jsr MonSkipSpaces
  jsr MonParseHex4              ; Parse addr1 (region1 start) → MON_ADDR
  bcc @CmpError
  ; Save addr1 on stack
  lda MON_ADDR+1
  pha
  lda MON_ADDR
  pha
  jsr MonSkipSpaces
  jsr MonParseHex4              ; Parse addr2 (region1 end) → MON_ADDR
  bcc @CmpErrorPop
  lda MON_ADDR
  sta MON_END
  lda MON_ADDR+1
  sta MON_END+1                 ; MON_END = region1 end (inclusive)
  jsr MonSkipSpaces
  jsr MonParseHex4              ; Parse addr3 (region2 base) → MON_ADDR
  bcc @CmpErrorPop
  lda MON_ADDR
  sta MON_TMP
  lda MON_ADDR+1
  sta MON_TMP+1                 ; MON_TMP = region2 pointer
  ; Restore addr1 → MON_ADDR
  pla
  sta MON_ADDR
  pla
  sta MON_ADDR+1
  ; Compare loop: [MON_ADDR..MON_END] vs [MON_TMP..]
  ldy #0
@CmpLoop:
  lda (MON_ADDR),y
  cmp (MON_TMP),y
  beq @CmpMatch
  ; Mismatch — print addr1 address
  jsr MonPrintHex4
  jsr MonPrintCRLF
@CmpMatch:
  ; Check if MON_ADDR == MON_END
  lda MON_ADDR+1
  cmp MON_END+1
  bne @CmpNext
  lda MON_ADDR
  cmp MON_END
  beq @CmpDone
@CmpNext:
  ; Advance both pointers
  inc MON_ADDR
  bne @CmpNoHi1
  inc MON_ADDR+1
@CmpNoHi1:
  inc MON_TMP
  bne @CmpLoop
  inc MON_TMP+1
  bra @CmpLoop
@CmpDone:
  rts
@CmpErrorPop:
  pla                           ; Clean up stack
  pla
@CmpError:
  jmp MonPrintError

; ============================================================================
; MonCmdGo — Go (JMP to address with full register restore via RTI)
; Syntax: G [addr]
; If addr given, sets BRK_PCL/PCH. Restores A, X, Y, P, SP via RTI.
; Program runs until BRK returns to monitor or forever.
; ============================================================================

MonCmdGo:
  jsr MonSkipSpaces
  jsr MonParseHex4
  bcc @GoNoAddr
  ; Address given — store to BRK_PCL/PCH
  lda MON_ADDR
  sta BRK_PCL
  lda MON_ADDR+1
  sta BRK_PCH
@GoNoAddr:
  sei                           ; Disable interrupts during stack manipulation
  ; Restore user's stack pointer
  ; BRK_SP = SP at Break entry (user's original SP - 3 from BRK hardware push)
  ; We need SP = BRK_SP + 3 before our pushes, so RTI leaves SP at original
  ldx BRK_SP
  inx
  inx
  inx
  txs                           ; SP = user's original SP
  ; Push PCH, PCL, P for RTI (RTI pops P first, then PCL, PCH)
  lda BRK_PCH
  pha
  lda BRK_PCL
  pha
  lda BRK_P
  pha
  ; Restore registers
  ldy BRK_Y
  ldx BRK_X
  lda BRK_A
  rti                           ; Pop P, PC → jump to target with full register state

; ============================================================================
; MonCmdJsr — Call subroutine and return to monitor on RTS
; Syntax: J [addr]
; Pushes monitor return address, restores A/X/Y, JMPs to target.
; When target does RTS, saves registers and re-enters monitor.
; ============================================================================

MonCmdJsr:
  jsr MonSkipSpaces
  jsr MonParseHex4
  bcc @JsrNoAddr
  ; Address given — store to BRK_PCL/PCH
  lda MON_ADDR
  sta BRK_PCL
  lda MON_ADDR+1
  sta BRK_PCH
@JsrNoAddr:
  ; Push return address (MonJsrReturn - 1) for RTS trick
  lda #>(MonJsrReturn - 1)
  pha
  lda #<(MonJsrReturn - 1)
  pha
  ; Restore registers as inputs to subroutine
  ldy BRK_Y
  ldx BRK_X
  lda BRK_A
  jmp (BRK_PCL)                 ; Jump to target — its RTS returns to MonJsrReturn

; MonJsrReturn — Landing point when user's subroutine does RTS
MonJsrReturn:
  sta BRK_A                     ; Save returned A
  stx BRK_X                    ; Save returned X
  sty BRK_Y                    ; Save returned Y
  php                           ; Push current P
  pla
  sta BRK_P                    ; Save processor status
  tsx
  stx BRK_SP                   ; Save current stack pointer
  ; Show registers and re-enter command loop
  jsr MonShowRegs
  jmp MonCmdLoop

; ============================================================================
; MonCmdModRegs — Modify saved CPU registers
; Syntax: ; PC xxxx A xx X xx Y xx SP xx P xx
; Any subset, any order. Labels: PC, A, X, Y, SP, P
; ============================================================================

MonCmdModRegs:
@ModLoop:
  jsr MonSkipSpaces
  ldy MON_IDX
  lda MON_LINBUF,y
  bne @ModNotEnd
  jmp @ModDone                  ; End of line — trampoline (too far for beq)
@ModNotEnd:
  ; Convert to uppercase
  cmp #'a'
  bcc @ModNoConv
  cmp #'z'+1
  bcs @ModNoConv
  and #$DF
@ModNoConv:
  cmp #'P'
  beq @ModCheckPCorP
  cmp #'A'
  beq @ModA
  cmp #'X'
  beq @ModX
  cmp #'Y'
  beq @ModY
  cmp #'S'
  beq @ModCheckSP
  jmp @ModError                 ; Unknown label — trampoline (too far for bra)

@ModCheckPCorP:
  ; Could be "PC" (program counter) or "P" (processor status)
  inc MON_IDX
  ldy MON_IDX
  lda MON_LINBUF,y
  ; Convert to uppercase
  cmp #'a'
  bcc @ModPCNoConv
  cmp #'z'+1
  bcs @ModPCNoConv
  and #$DF
@ModPCNoConv:
  cmp #'C'
  beq @ModPC
  ; It's just 'P' (processor status) — don't advance past the non-'C' char
  jsr MonSkipSpaces
  jsr MonParseHex2
  bcs @ModPOk
  jmp @ModError
@ModPOk:
  sta BRK_P
  jmp @ModLoop

@ModPC:
  inc MON_IDX                   ; Advance past 'C'
  jsr MonSkipSpaces
  jsr MonParseHex4
  bcs @ModPCOk
  jmp @ModError
@ModPCOk:
  lda MON_ADDR
  sta BRK_PCL
  lda MON_ADDR+1
  sta BRK_PCH
  jmp @ModLoop

@ModA:
  inc MON_IDX                   ; Advance past 'A'
  jsr MonSkipSpaces
  jsr MonParseHex2
  bcs @ModAOk
  jmp @ModError
@ModAOk:
  sta BRK_A
  jmp @ModLoop

@ModX:
  inc MON_IDX                   ; Advance past 'X'
  jsr MonSkipSpaces
  jsr MonParseHex2
  bcs @ModXOk
  jmp @ModError
@ModXOk:
  sta BRK_X
  jmp @ModLoop

@ModY:
  inc MON_IDX                   ; Advance past 'Y'
  jsr MonSkipSpaces
  jsr MonParseHex2
  bcs @ModYOk
  jmp @ModError
@ModYOk:
  sta BRK_Y
  jmp @ModLoop

@ModCheckSP:
  ; Expect "SP" — must see 'P' next
  inc MON_IDX
  ldy MON_IDX
  lda MON_LINBUF,y
  cmp #'P'
  beq @ModSPGotP
  cmp #'p'
  beq @ModSPGotP
  jmp @ModError                 ; Just 'S' alone is invalid
@ModSPGotP:
  inc MON_IDX                   ; Advance past 'P'
  jsr MonSkipSpaces
  jsr MonParseHex2
  bcs @ModSPOk
  jmp @ModError
@ModSPOk:
  sta BRK_SP
  jmp @ModLoop

@ModError:
  jmp MonPrintError
@ModDone:
  ; Display updated registers
  jsr MonShowRegs
  rts

; ============================================================================
; MonCmdDir — Display CF directory listing
; Syntax: @
; ============================================================================

MonCmdDir:
  jsr FsDirectory
  rts

; ============================================================================
; MonCmdNum — Number base conversion
; Syntax: N $XXXX  or  N +DDDDD  or  N %BBBBBBBBBBBBBBBB
; Output: $XXXX  +DDDDD  %BBBBBBBBBBBBBBBB
; ============================================================================

MonCmdNum:
  jsr MonSkipSpaces
  ldy MON_IDX
  lda MON_LINBUF,y
  cmp #'$'
  beq @NumHex
  cmp #'+'
  beq @NumDec
  cmp #'%'
  beq @NumBin
  ; Default: try hex (no prefix)
  bra @NumHexDirect
@NumHex:
  inc MON_IDX                   ; Skip '$'
@NumHexDirect:
  jsr MonParseHex4
  bcs @NumPrint
  jmp MonPrintError
@NumDec:
  inc MON_IDX                   ; Skip '+'
  jsr MonParseDec16
  bcs @NumPrint
  jmp MonPrintError
@NumBin:
  inc MON_IDX                   ; Skip '%'
  jsr MonParseBin16
  bcs @NumPrint
  jmp MonPrintError
@NumPrint:
  ; Value is in MON_ADDR
  lda #'$'
  jsr Chrout
  jsr MonPrintHex4
  jsr MonPrintSpace
  jsr MonPrintSpace
  lda #'+'
  jsr Chrout
  jsr MonPrintDec16
  jsr MonPrintSpace
  jsr MonPrintSpace
  lda #'%'
  jsr Chrout
  jsr MonPrintBin16
  jsr MonPrintCRLF
  rts

; ============================================================================
; MonCmdLoad — Load from CF (with quoted filename) or serial (without)
; Syntax: L ["FILE"] [ADDR]
; CF path:     L "FILENAME" [ADDR] — load file to addr (default $0800)
; Serial path: L [ADDR]            — receive binary to addr (default $0800)
; ============================================================================

MonCmdLoad:
  jsr MonSkipSpaces
  ldy MON_IDX
  lda MON_LINBUF,y
  cmp #'"'
  bne @LoadSerial
  jmp @LoadCF

  ; --- Serial path ---
@LoadSerial:
  jsr MonParseHex4              ; Optional address
  bcc @LoadSerDefault
  ; Got address
  lda MON_ADDR
  sta XFER_PTR
  lda MON_ADDR+1
  sta XFER_PTR+1
  bra @LoadSerStart
@LoadSerDefault:
  lda #<PROGRAM_START
  sta XFER_PTR
  lda #>PROGRAM_START
  sta XFER_PTR+1
@LoadSerStart:
  ; Save load address for success message
  lda XFER_PTR
  sta MON_END
  lda XFER_PTR+1
  sta MON_END+1
  ; Switch to serial I/O
  lda IO_MODE
  sta XFER_IO_SAVE
  lda #$01
  sta IO_MODE
  ; Print "READY TO RECEIVE" via serial
  lda #<MonStrReady
  sta STR_PTR
  lda #>MonStrReady
  sta STR_PTR+1
  jsr MonSerialPrintStr
  ; Read 2-byte size (lo/hi)
@SerWaitSzLo:
  jsr BufferSize
  beq @SerWaitSzLo
  jsr ReadBuffer
  sta XFER_REMAIN
@SerWaitSzHi:
  jsr BufferSize
  beq @SerWaitSzHi
  jsr ReadBuffer
  sta XFER_REMAIN+1
  ; Check for zero-length
  lda XFER_REMAIN
  ora XFER_REMAIN+1
  beq @LoadSerOk
  ; Receive data bytes
  ldy #0
@LoadSerByte:
  jsr BufferSize
  beq @LoadSerByte
  jsr ReadBuffer
  sta (XFER_PTR),y
  inc XFER_PTR
  bne @LoadSerNoPage
  inc XFER_PTR+1
@LoadSerNoPage:
  lda XFER_REMAIN
  bne @LoadSerDecLo
  dec XFER_REMAIN+1
@LoadSerDecLo:
  dec XFER_REMAIN
  lda XFER_REMAIN
  ora XFER_REMAIN+1
  bne @LoadSerByte
@LoadSerOk:
  ; Restore IO_MODE
  lda XFER_IO_SAVE
  sta IO_MODE
  ; Calculate bytes loaded = XFER_PTR - MON_END
  sec
  lda XFER_PTR
  sbc MON_END
  sta MON_ADDR
  lda XFER_PTR+1
  sbc MON_END+1
  sta MON_ADDR+1
  jsr MonPrintLoaded            ; Print "LOADED nnnn BYTES AT $xxxx"
  rts

  ; --- CF path ---
@LoadCF:
  inc MON_IDX                   ; Skip opening quote
  ; Point STR_PTR into line buffer at the filename
  ldy MON_IDX
  tya
  clc
  adc #<MON_LINBUF
  sta STR_PTR
  lda #>MON_LINBUF
  adc #0
  sta STR_PTR+1
  ; Find closing quote and null-terminate
@LoadCFFindQ:
  lda MON_LINBUF,y
  beq @LoadCFQDone              ; End of line — use as-is
  cmp #'"'
  beq @LoadCFGotQ
  iny
  bra @LoadCFFindQ
@LoadCFGotQ:
  lda #0
  sta MON_LINBUF,y              ; Null-terminate at closing quote
  iny                           ; Advance past closing quote
@LoadCFQDone:
  sty MON_IDX
  ; Parse filename into FS_FNAME_BUF
  jsr FsParseName
  ; Read directory
  jsr FsReadDir
  bcc @LoadCFReadOk
  jmp @LoadCFErr
@LoadCFReadOk:
  ; Find file
  jsr FsFindFile
  bcc @LoadCFFound
  jmp @LoadCFNotFound
@LoadCFFound:
  ; Read file metadata
  ldy #FS_ENTRY_START
  lda (CF_BUF_PTR),y
  sta FS_START_SEC
  iny
  lda (CF_BUF_PTR),y
  sta FS_START_SEC+1
  ldy #FS_ENTRY_FSIZE
  lda (CF_BUF_PTR),y
  sta FS_FILE_SIZE
  iny
  lda (CF_BUF_PTR),y
  sta FS_FILE_SIZE+1
  ; Calculate sector count = ceil(size / 512)
  lda FS_FILE_SIZE+1
  lsr a
  sta FS_SEC_COUNT
  lda FS_FILE_SIZE+1
  and #$01
  bne @LoadCFRound
  lda FS_FILE_SIZE
  beq @LoadCFNoRound
@LoadCFRound:
  inc FS_SEC_COUNT
@LoadCFNoRound:
  ; Parse optional load address
  jsr MonSkipSpaces
  jsr MonParseHex4
  bcc @LoadCFDefAddr
  ; Got address — use it
  lda MON_ADDR
  sta CF_BUF_PTR
  lda MON_ADDR+1
  sta CF_BUF_PTR+1
  bra @LoadCFSetLBA
@LoadCFDefAddr:
  lda #<PROGRAM_START
  sta CF_BUF_PTR
  lda #>PROGRAM_START
  sta CF_BUF_PTR+1
@LoadCFSetLBA:
  ; Save load base address for message
  lda CF_BUF_PTR
  sta MON_END
  lda CF_BUF_PTR+1
  sta MON_END+1
  ; Set up LBA
  lda FS_START_SEC
  sta CF_LBA
  lda FS_START_SEC+1
  sta CF_LBA+1
  stz CF_LBA+2
  stz CF_LBA+3
  ; Read sectors
  ldx FS_SEC_COUNT
  beq @LoadCFOk
@LoadCFSec:
  phx
  jsr StReadSector              ; Reads 512 bytes, advances CF_BUF_PTR
  bcs @LoadCFSecErr
  inc CF_LBA
  bne @LoadCFSecNext
  inc CF_LBA+1
@LoadCFSecNext:
  plx
  dex
  bne @LoadCFSec
@LoadCFOk:
  ; Print success
  lda FS_FILE_SIZE
  sta MON_ADDR
  lda FS_FILE_SIZE+1
  sta MON_ADDR+1
  jsr MonPrintLoaded            ; Print "LOADED nnnn BYTES AT $xxxx"
  rts
@LoadCFSecErr:
  plx                           ; Balance stack
@LoadCFErr:
  jsr MonPrintIOErr
  rts
@LoadCFNotFound:
  ldx #0
@LoadCFNFLoop:
  lda MonStrNotFound,x
  beq @LoadCFNFDone
  jsr Chrout
  inx
  bra @LoadCFNFLoop
@LoadCFNFDone:
  jsr MonPrintCRLF
  rts

; ============================================================================
; MonCmdSave — Save to CF (with quoted filename) or serial (without)
; Syntax: S ["FILE"] ADDR1 ADDR2
; CF path:     S "FILENAME" ADDR1 ADDR2 — save [addr1,addr2) to file
; Serial path: S ADDR1 ADDR2            — send [addr1,addr2) via serial
; ============================================================================

MonCmdSave:
  jsr MonSkipSpaces
  ldy MON_IDX
  lda MON_LINBUF,y
  cmp #'"'
  bne @SaveSerial
  jmp @SaveCF

  ; --- Serial path ---
@SaveSerial:
  jsr MonParseHex4              ; Parse start address
  bcs @SaveSerGotStart
  jmp @SaveError
@SaveSerGotStart:
  lda MON_ADDR
  sta XFER_PTR
  lda MON_ADDR+1
  sta XFER_PTR+1
  jsr MonSkipSpaces
  jsr MonParseHex4              ; Parse end address
  bcs @SaveSerGotEnd
  jmp @SaveError
@SaveSerGotEnd:
  ; Calculate size = end - start
  sec
  lda MON_ADDR
  sbc XFER_PTR
  sta XFER_REMAIN
  lda MON_ADDR+1
  sbc XFER_PTR+1
  sta XFER_REMAIN+1
  ; Save size for message
  lda XFER_REMAIN
  sta MON_END
  lda XFER_REMAIN+1
  sta MON_END+1
  ; Switch to serial I/O
  lda IO_MODE
  sta XFER_IO_SAVE
  lda #$01
  sta IO_MODE
  ; Send 2-byte size (lo/hi)
  lda XFER_REMAIN
  jsr SerialChrout
  lda XFER_REMAIN+1
  jsr SerialChrout
  ; Check for zero-length
  lda XFER_REMAIN
  ora XFER_REMAIN+1
  beq @SaveSerDone
  ; Send data bytes
  ldy #0
@SaveSerByte:
  lda (XFER_PTR),y
  jsr SerialChrout
  inc XFER_PTR
  bne @SaveSerNoPage
  inc XFER_PTR+1
@SaveSerNoPage:
  lda XFER_REMAIN
  bne @SaveSerDecLo
  dec XFER_REMAIN+1
@SaveSerDecLo:
  dec XFER_REMAIN
  lda XFER_REMAIN
  ora XFER_REMAIN+1
  bne @SaveSerByte
@SaveSerDone:
  ; Restore IO_MODE
  lda XFER_IO_SAVE
  sta IO_MODE
  ; Print "SAVED nnnn BYTES"
  lda MON_END
  sta MON_ADDR
  lda MON_END+1
  sta MON_ADDR+1
  jsr MonPrintSaved
  rts

  ; --- CF path ---
@SaveCF:
  inc MON_IDX                   ; Skip opening quote
  ; Point STR_PTR into line buffer at the filename
  ldy MON_IDX
  tya
  clc
  adc #<MON_LINBUF
  sta STR_PTR
  lda #>MON_LINBUF
  adc #0
  sta STR_PTR+1
  ; Find closing quote and null-terminate
@SaveCFFindQ:
  lda MON_LINBUF,y
  beq @SaveCFQDone
  cmp #'"'
  beq @SaveCFGotQ
  iny
  bra @SaveCFFindQ
@SaveCFGotQ:
  lda #0
  sta MON_LINBUF,y              ; Null-terminate at closing quote
  iny
@SaveCFQDone:
  sty MON_IDX
  ; Parse filename
  jsr FsParseName
  ; Parse start address
  jsr MonSkipSpaces
  jsr MonParseHex4
  bcs @SaveCFGotStart
  jmp @SaveError
@SaveCFGotStart:
  lda MON_ADDR
  sta MON_TMP                   ; MON_TMP = start address
  lda MON_ADDR+1
  sta MON_TMP+1
  ; Parse end address
  jsr MonSkipSpaces
  jsr MonParseHex4
  bcs @SaveCFGotEnd
  jmp @SaveError
@SaveCFGotEnd:
  ; Calculate size = end - start
  sec
  lda MON_ADDR
  sbc MON_TMP
  sta FS_FILE_SIZE
  lda MON_ADDR+1
  sbc MON_TMP+1
  sta FS_FILE_SIZE+1
  ; Read directory
  jsr FsReadDir
  bcc @SaveCFReadOk
  jmp @SaveCFIOErr
@SaveCFReadOk:
  ; Try to find existing file with same name
  jsr FsFindFile
  bcc @SaveCFOverwrite
  ; Not found — find a free slot
  jsr FsFindFree
  bcc @SaveCFAlloc
  jmp @SaveCFDirFull
@SaveCFOverwrite:
  ; Clear old entry's flags
  ldy #FS_ENTRY_FLAGS
  lda #$00
  sta (CF_BUF_PTR),y
  ; Find a free slot (could be the one we just freed)
  jsr FsFindFree
  bcc @SaveCFAllocOk
  jmp @SaveCFDirFull
@SaveCFAllocOk:
@SaveCFAlloc:
  ; Save CF_BUF_PTR (points to free entry)
  lda CF_BUF_PTR
  pha
  lda CF_BUF_PTR+1
  pha
  ; Calculate next free sector
  jsr FsCalcNextSec
  ; Restore CF_BUF_PTR
  pla
  sta CF_BUF_PTR+1
  pla
  sta CF_BUF_PTR
  ; Calculate sectors needed
  lda FS_FILE_SIZE+1
  lsr a
  sta FS_SEC_COUNT
  lda FS_FILE_SIZE+1
  and #$01
  bne @SaveCFRound
  lda FS_FILE_SIZE
  beq @SaveCFNoRound
@SaveCFRound:
  inc FS_SEC_COUNT
@SaveCFNoRound:
  ; Fill in directory entry
  ; Copy filename (11 bytes)
  ldy #0
@SaveCFCopyName:
  lda FS_FNAME_BUF,y
  sta (CF_BUF_PTR),y
  iny
  cpy #11
  bne @SaveCFCopyName
  ; Set flags = in use
  lda #FS_FLAG_USED
  sta (CF_BUF_PTR),y            ; Y = 11 = FS_ENTRY_FLAGS
  ; Set start sector
  ldy #FS_ENTRY_START
  lda FS_NEXT_SEC
  sta (CF_BUF_PTR),y
  sta FS_START_SEC
  iny
  lda FS_NEXT_SEC+1
  sta (CF_BUF_PTR),y
  sta FS_START_SEC+1
  ; Set file size
  ldy #FS_ENTRY_FSIZE
  lda FS_FILE_SIZE
  sta (CF_BUF_PTR),y
  iny
  lda FS_FILE_SIZE+1
  sta (CF_BUF_PTR),y
  ; Clear reserved bytes
  ldy #$10
  lda #$00
@SaveCFClrRsv:
  sta (CF_BUF_PTR),y
  iny
  cpy #FS_ENTRY_SIZE
  bne @SaveCFClrRsv
  ; Write updated directory
  jsr FsWriteDir
  bcs @SaveCFIOErr
  ; Write data sectors from user-specified start address (MON_TMP)
  lda FS_START_SEC
  sta CF_LBA
  lda FS_START_SEC+1
  sta CF_LBA+1
  stz CF_LBA+2
  stz CF_LBA+3
  ; Source = MON_TMP (start address)
  lda MON_TMP
  sta CF_BUF_PTR
  lda MON_TMP+1
  sta CF_BUF_PTR+1
  ldx FS_SEC_COUNT
  beq @SaveCFOk
@SaveCFSec:
  phx
  jsr StWriteSector             ; Writes 512 bytes, advances CF_BUF_PTR
  bcs @SaveCFSecErr
  inc CF_LBA
  bne @SaveCFSecNext
  inc CF_LBA+1
@SaveCFSecNext:
  plx
  dex
  bne @SaveCFSec
@SaveCFOk:
  lda FS_FILE_SIZE
  sta MON_ADDR
  lda FS_FILE_SIZE+1
  sta MON_ADDR+1
  jsr MonPrintSaved             ; Print "SAVED nnnn BYTES"
  rts
@SaveCFSecErr:
  plx                           ; Balance stack
@SaveCFIOErr:
  jsr MonPrintIOErr
  rts
@SaveCFDirFull:
  ldx #0
@SaveCFDFLoop:
  lda MonStrDirFull,x
  beq @SaveCFDFDone
  jsr Chrout
  inx
  bra @SaveCFDFLoop
@SaveCFDFDone:
  jsr MonPrintCRLF
  rts
@SaveError:
  jmp MonPrintError

; ============================================================================
; MonCmdM — Memory dump (hex + ASCII, 8 bytes/row)
; Syntax: M [addr] [addr]
; Default: 8 lines (64 bytes). Remembers position for continuation.
; ============================================================================

MonCmdM:
  jsr MonSkipSpaces
  jsr MonParseHex4
  bcc @UseDefault               ; No address given — use current MON_ADDR
  ; Got first address in MON_ADDR — save it
  lda MON_ADDR
  sta MON_TMP
  lda MON_ADDR+1
  sta MON_TMP+1
  jsr MonSkipSpaces
  jsr MonParseHex4
  bcc @StartOnly
  ; Got second address (end) in MON_ADDR
  lda MON_ADDR
  sta MON_END
  lda MON_ADDR+1
  sta MON_END+1
  ; Restore start address
  lda MON_TMP
  sta MON_ADDR
  lda MON_TMP+1
  sta MON_ADDR+1
  bra @DumpRange
@StartOnly:
  ; Only start address — restore from MON_TMP
  lda MON_TMP
  sta MON_ADDR
  lda MON_TMP+1
  sta MON_ADDR+1
@UseDefault:
  ; Set end = start + 63 (8 lines x 8 bytes)
  clc
  lda MON_ADDR
  adc #63
  sta MON_END
  lda MON_ADDR+1
  adc #0
  sta MON_END+1
@DumpRange:
  jsr MonDumpLine
  bcs @DumpDone                 ; Carry set = address wrapped past $FFFF
  ; Check if MON_ADDR > MON_END
  lda MON_END+1
  cmp MON_ADDR+1
  bcc @DumpDone
  bne @DumpRange
  lda MON_END
  cmp MON_ADDR
  bcs @DumpRange
@DumpDone:
  rts

; MonDumpLine — Dump 8 bytes at MON_ADDR as hex + ASCII, advance by 8

MonDumpLine:
  ; Print ".:ADDR " (39 chars/line avoids 40-col auto-wrap + CRLF double-newline)
  lda #'.'
  jsr Chrout
  lda #':'
  jsr Chrout
  jsr MonPrintHex4
  jsr MonPrintSpace
  ; Print 8 hex bytes
  ldy #0
@HexLoop:
  lda (MON_ADDR),y
  phy
  jsr MonPrintHex2
  jsr MonPrintSpace
  ply
  iny
  cpy #8
  bcc @HexLoop
  ; Print 8 ASCII characters (no extra space — fits 40 cols)
  ldy #0
@AsciiLoop:
  lda (MON_ADDR),y
  cmp #$20
  bcc @NotPrint
  cmp #$7F
  bcc @DoPrint
@NotPrint:
  lda #'.'
@DoPrint:
  phy
  jsr Chrout
  ply
  iny
  cpy #8
  bcc @AsciiLoop
  ; Advance MON_ADDR by 8
  clc
  lda MON_ADDR
  adc #8
  sta MON_ADDR
  bcc @NoCarry
  inc MON_ADDR+1
  beq @Wrapped                  ; High byte became $00 = wrapped past $FFFF
@NoCarry:
  jsr MonPrintCRLF
  clc                           ; Signal no overflow
  rts
@Wrapped:
  jsr MonPrintCRLF
  sec                           ; Signal overflow
  rts

; ============================================================================
; MonCmdD — Disassemble 65C02 instructions
; Syntax: D [addr] [addr]
; Default: 20 lines. Remembers position for continuation.
; ============================================================================

MonCmdD:
  jsr MonSkipSpaces
  jsr MonParseHex4
  bcc @UseDefault
  ; Got first address
  lda MON_ADDR
  sta MON_TMP
  lda MON_ADDR+1
  sta MON_TMP+1
  jsr MonSkipSpaces
  jsr MonParseHex4
  bcc @StartOnly
  ; Got end address
  lda MON_ADDR
  sta MON_END
  lda MON_ADDR+1
  sta MON_END+1
  lda MON_TMP
  sta MON_ADDR
  lda MON_TMP+1
  sta MON_ADDR+1
  bra @DisRange
@StartOnly:
  lda MON_TMP
  sta MON_ADDR
  lda MON_TMP+1
  sta MON_ADDR+1
@UseDefault:
  ; Disassemble 20 lines
  ldx #20
@DisCountLoop:
  phx
  jsr DisOneLine
  plx
  bcs @DisDone                  ; Carry set = address wrapped past $FFFF
  dex
  bne @DisCountLoop
  rts
@DisRange:
  jsr DisOneLine
  bcs @DisDone                  ; Carry set = address wrapped past $FFFF
  ; Check if MON_ADDR > MON_END
  lda MON_END+1
  cmp MON_ADDR+1
  bcc @DisDone
  bne @DisRange
  lda MON_END
  cmp MON_ADDR
  bcs @DisRange
@DisDone:
  rts

; ============================================================================
; DisOneLine — Disassemble one instruction at MON_ADDR
; Prints line, advances MON_ADDR by instruction length.
; Uses: MON_BYTE=opcode, MON_TMP=mnemonic idx, MON_TMP+1=mode
;       Stack holds instruction length throughout.
; ============================================================================

DisOneLine:
  ; Read opcode and look up table
  ldy #0
  lda (MON_ADDR),y
  sta MON_BYTE                  ; save opcode
  asl a                         ; opcode * 2 for table index
  tax
  bcc @LowHalf                  ; carry clear = opcodes $00-$7F
  lda DisOpcodeTable+256,x      ; opcodes $80-$FF: offset by 256
  sta MON_TMP                   ; mnemonic index
  lda DisOpcodeTable+257,x
  sta MON_TMP+1                 ; addressing mode
  bra @GotEntry
@LowHalf:
  lda DisOpcodeTable,x
  sta MON_TMP                   ; mnemonic index
  lda DisOpcodeTable+1,x
  sta MON_TMP+1                 ; addressing mode
@GotEntry:
  ; Get instruction length from mode
  ldx MON_TMP+1
  lda DisModeSizes,x
  inc a                         ; +1 for opcode = total length
  pha                           ; save on stack (stays until end)
  ; Print prefix ".,ADDR" (no space — consistent with M command's .:ADDR)
  lda #'.'
  jsr Chrout
  lda #','
  jsr Chrout
  ; Print address
  jsr MonPrintHex4
  jsr MonPrintSpace
  jsr MonPrintSpace
  ; Print opcode byte
  lda MON_BYTE
  jsr MonPrintHex2
  ; Print 2nd byte or padding
  pla
  pha                           ; peek at length
  cmp #2
  bcc @Pad1
  jsr MonPrintSpace
  ldy #1
  lda (MON_ADDR),y
  jsr MonPrintHex2
  bra @Check3
@Pad1:
  jsr MonPrintSpace
  jsr MonPrintSpace
  jsr MonPrintSpace
@Check3:
  pla
  pha
  cmp #3
  bcc @Pad2
  jsr MonPrintSpace
  ldy #2
  lda (MON_ADDR),y
  jsr MonPrintHex2
  bra @AfterBytes
@Pad2:
  jsr MonPrintSpace
  jsr MonPrintSpace
  jsr MonPrintSpace
@AfterBytes:
  ; Separator before mnemonic
  jsr MonPrintSpace
  jsr MonPrintSpace
  ; Print mnemonic (3 chars)
  jsr DisPrintMnemonic
  ; For RMB/SMB/BBR/BBS, append bit number digit
  lda MON_TMP
  cmp #MN_BBR
  beq @BitNum
  cmp #MN_BBS
  beq @BitNum
  cmp #MN_RMB
  beq @BitNum
  cmp #MN_SMB
  beq @BitNum
  jsr MonPrintSpace             ; normal mnemonic — space separator
  bra @Operand
@BitNum:
  lda MON_BYTE                  ; opcode encodes bit in upper nibble
  lsr a
  lsr a
  lsr a
  lsr a
  and #$07
  clc
  adc #'0'
  jsr Chrout
  jsr MonPrintSpace
@Operand:
  ; Print operand based on addressing mode
  lda MON_TMP+1
  jsr DisPrintOperand
  ; CRLF
  jsr MonPrintCRLF
  ; Advance MON_ADDR by instruction length
  pla                           ; length from stack
  clc
  adc MON_ADDR
  sta MON_ADDR
  bcc @NoWrap
  inc MON_ADDR+1
  beq @DisWrapped               ; High byte became $00 = wrapped past $FFFF
@NoWrap:
  clc                           ; Signal no overflow
  rts
@DisWrapped:
  sec                           ; Signal overflow
  rts

; DisPrintMnemonic — Print 3-char mnemonic from MON_TMP index

DisPrintMnemonic:
  lda MON_TMP                   ; mnemonic index
  asl a                         ; index * 2
  clc
  adc MON_TMP                   ; + index = index * 3
  tax
  lda DisMnemonics,x
  phx
  jsr Chrout
  plx
  lda DisMnemonics+1,x
  phx
  jsr Chrout
  plx
  lda DisMnemonics+2,x
  jmp Chrout

; DisPrintOperand — Dispatch to addressing mode operand printer
; Input: A = addressing mode index

DisPrintOperand:
  asl a                         ; mode * 2 for word table index
  tax
  jmp (DisOperandJmpTable,x)    ; handler does RTS to our caller

; ============================================================================
; Addressing Mode Operand Handlers
; Each handler prints the operand and returns via RTS.
; ============================================================================

DisOpImp:
  rts

DisOpAcc:
  lda #'A'
  jmp Chrout

DisOpImm:
  lda #'#'
  jsr Chrout
  lda #'$'
  jsr Chrout
  ldy #1
  lda (MON_ADDR),y
  jmp MonPrintHex2

DisOpZp:
  lda #'$'
  jsr Chrout
  ldy #1
  lda (MON_ADDR),y
  jmp MonPrintHex2

DisOpZpx:
  jsr DisOpZp
  lda #','
  jsr Chrout
  lda #'X'
  jmp Chrout

DisOpZpy:
  jsr DisOpZp
  lda #','
  jsr Chrout
  lda #'Y'
  jmp Chrout

DisOpAbs:
  lda #'$'
  jsr Chrout
  ldy #2
  lda (MON_ADDR),y              ; high byte
  jsr MonPrintHex2
  ldy #1
  lda (MON_ADDR),y              ; low byte
  jmp MonPrintHex2

DisOpAbx:
  jsr DisOpAbs
  lda #','
  jsr Chrout
  lda #'X'
  jmp Chrout

DisOpAby:
  jsr DisOpAbs
  lda #','
  jsr Chrout
  lda #'Y'
  jmp Chrout

DisOpInd:
  lda #'('
  jsr Chrout
  jsr DisOpAbs
  lda #')'
  jmp Chrout

DisOpIzx:
  lda #'('
  jsr Chrout
  jsr DisOpZp
  lda #','
  jsr Chrout
  lda #'X'
  jsr Chrout
  lda #')'
  jmp Chrout

DisOpIzy:
  lda #'('
  jsr Chrout
  jsr DisOpZp
  lda #')'
  jsr Chrout
  lda #','
  jsr Chrout
  lda #'Y'
  jmp Chrout

DisOpZpi:
  lda #'('
  jsr Chrout
  jsr DisOpZp
  lda #')'
  jmp Chrout

DisOpRel:
  ; Target = current_addr + 2 + signed_offset
  ldy #1
  lda (MON_ADDR),y              ; offset byte
  bmi @Neg
  ; Positive offset
  clc
  adc MON_ADDR
  sta MON_TMP
  lda MON_ADDR+1
  adc #0
  sta MON_TMP+1
  bra @Add2
@Neg:
  clc
  adc MON_ADDR
  sta MON_TMP
  lda MON_ADDR+1
  adc #$FF                      ; sign extension
  sta MON_TMP+1
@Add2:
  clc
  lda MON_TMP
  adc #2
  sta MON_TMP
  lda MON_TMP+1
  adc #0
  sta MON_TMP+1
  ; Print "$XXXX"
  lda #'$'
  jsr Chrout
  lda MON_TMP+1
  jsr MonPrintHex2
  lda MON_TMP
  jmp MonPrintHex2

DisOpZpr:
  ; ZP byte first
  lda #'$'
  jsr Chrout
  ldy #1
  lda (MON_ADDR),y
  jsr MonPrintHex2
  lda #','
  jsr Chrout
  ; Branch target = addr + 3 + signed_offset(byte 2)
  ldy #2
  lda (MON_ADDR),y
  bmi @Neg
  clc
  adc MON_ADDR
  sta MON_TMP
  lda MON_ADDR+1
  adc #0
  sta MON_TMP+1
  bra @Add3
@Neg:
  clc
  adc MON_ADDR
  sta MON_TMP
  lda MON_ADDR+1
  adc #$FF
  sta MON_TMP+1
@Add3:
  clc
  lda MON_TMP
  adc #3
  sta MON_TMP
  lda MON_TMP+1
  adc #0
  sta MON_TMP+1
  lda #'$'
  jsr Chrout
  lda MON_TMP+1
  jsr MonPrintHex2
  lda MON_TMP
  jmp MonPrintHex2

DisOpAix:
  lda #'('
  jsr Chrout
  jsr DisOpAbs
  lda #','
  jsr Chrout
  lda #'X'
  jsr Chrout
  lda #')'
  jmp Chrout

; ============================================================================
; MonShowRegs — Print saved register state
; Format: PC=xxxx A=xx X=xx Y=xx SP=xx NV-BDIZC
; ============================================================================

MonShowRegs:
  ; "PC="
  lda #'P'
  jsr Chrout
  lda #'C'
  jsr Chrout
  lda #'='
  jsr Chrout
  ; Print PC (adjusted: BRK_PC - 2)
  sec
  lda BRK_PCL
  sbc #2
  sta MON_ADDR
  lda BRK_PCH
  sbc #0
  sta MON_ADDR + 1
  jsr MonPrintHex4
  lda #' '
  jsr Chrout

  ; "A="
  lda #'A'
  jsr Chrout
  lda #'='
  jsr Chrout
  lda BRK_A
  jsr MonPrintHex2
  lda #' '
  jsr Chrout

  ; "X="
  lda #'X'
  jsr Chrout
  lda #'='
  jsr Chrout
  lda BRK_X
  jsr MonPrintHex2
  lda #' '
  jsr Chrout

  ; "Y="
  lda #'Y'
  jsr Chrout
  lda #'='
  jsr Chrout
  lda BRK_Y
  jsr MonPrintHex2
  lda #' '
  jsr Chrout

  ; "SP="
  lda #'S'
  jsr Chrout
  lda #'P'
  jsr Chrout
  lda #'='
  jsr Chrout
  lda BRK_SP
  jsr MonPrintHex2
  lda #' '
  jsr Chrout

  ; Flags: NV-BDIZC
  lda BRK_P
  sta MON_BYTE                  ; Save flags for bit testing
  ldx #0
@FlagLoop:
  lda MonFlagChars,x
  beq @FlagsDone
  asl MON_BYTE                  ; Shift next flag bit into carry
  bcs @FlagSet
  lda #'-'                      ; Flag clear — print dash
  bra @FlagPrint
@FlagSet:
  ; A already has the flag character
  lda MonFlagChars,x
@FlagPrint:
  jsr Chrout
  inx
  bra @FlagLoop
@FlagsDone:
  jsr MonPrintCRLF
  rts

MonFlagChars:
  .byte "NV-BDIZC", 0

; ============================================================================
; Hex Parsing Utilities
; ============================================================================

; MonParseHex4 — Parse up to 4 hex digits from MON_LINBUF into MON_ADDR
; Input:  MON_IDX points to current position in MON_LINBUF
; Output: MON_ADDR/MON_ADDR+1 = parsed 16-bit value, carry set if valid
;         MON_IDX advanced past parsed digits

MonParseHex4:
  stz MON_ADDR
  stz MON_ADDR + 1
  ldx #0                        ; Digit count
@ParseLoop:
  ldy MON_IDX
  lda MON_LINBUF,y
  jsr MonCharToNibble           ; Convert ASCII to 0-15, carry clear if valid
  bcs @ParseDone                ; Not a hex digit — stop
  ; Shift result left 4 bits and OR in new nibble
  asl MON_ADDR
  rol MON_ADDR + 1
  asl MON_ADDR
  rol MON_ADDR + 1
  asl MON_ADDR
  rol MON_ADDR + 1
  asl MON_ADDR
  rol MON_ADDR + 1
  ora MON_ADDR
  sta MON_ADDR
  inc MON_IDX
  inx
  cpx #4                        ; Max 4 digits
  bcc @ParseLoop
@ParseDone:
  cpx #0                        ; Did we parse at least one digit?
  beq @ParseFail
  sec                           ; Success
  rts
@ParseFail:
  clc                           ; Failure — no digits parsed
  rts

; MonParseHex2 — Parse up to 2 hex digits from MON_LINBUF into A
; Input:  MON_IDX points to current position in MON_LINBUF
; Output: A = parsed 8-bit value, carry set if valid
;         MON_IDX advanced past parsed digits

MonParseHex2:
  stz MON_BYTE
  ldx #0                        ; Digit count
@ParseLoop:
  ldy MON_IDX
  lda MON_LINBUF,y
  jsr MonCharToNibble
  bcs @ParseDone
  asl MON_BYTE
  asl MON_BYTE
  asl MON_BYTE
  asl MON_BYTE
  ora MON_BYTE
  sta MON_BYTE
  inc MON_IDX
  inx
  cpx #2
  bcc @ParseLoop
@ParseDone:
  cpx #0
  beq @ParseFail
  lda MON_BYTE
  sec
  rts
@ParseFail:
  clc
  rts

; MonCharToNibble — Convert ASCII hex char in A to nibble value 0-15
; Input:  A = ASCII character
; Output: A = 0-15 if valid hex digit, carry clear
;         carry set if not a valid hex digit (A preserved)

MonCharToNibble:
  cmp #'0'
  bcc @NotHex
  cmp #'9'+1
  bcc @IsDigit
  cmp #'A'
  bcc @CheckLower
  cmp #'F'+1
  bcc @IsUpper
@CheckLower:
  cmp #'a'
  bcc @NotHex
  cmp #'f'+1
  bcs @NotHex
  ; Lowercase a-f
  sec
  sbc #('a' - 10)
  clc
  rts
@IsDigit:
  sec
  sbc #'0'
  clc
  rts
@IsUpper:
  sec
  sbc #('A' - 10)
  clc
  rts
@NotHex:
  sec
  rts

; MonSkipSpaces — Advance MON_IDX past whitespace in MON_LINBUF

MonSkipSpaces:
  ldy MON_IDX
  lda MON_LINBUF,y
  cmp #' '
  bne @Done
  inc MON_IDX
  bra MonSkipSpaces
@Done:
  rts

; ============================================================================
; Decimal & Binary Parsing Utilities
; ============================================================================

; MonParseDec16 — Parse decimal digits from MON_LINBUF into MON_ADDR
; Input:  MON_IDX points to current position in MON_LINBUF
; Output: MON_ADDR = parsed 16-bit value, carry set if valid
;         MON_IDX advanced past parsed digits
; Modifies: A, X, Y, MON_ADDR, MON_TMP

MonParseDec16:
  stz MON_ADDR
  stz MON_ADDR+1
  ldx #0                        ; Digit count
@DecLoop:
  ldy MON_IDX
  lda MON_LINBUF,y
  cmp #'0'
  bcc @DecDone
  cmp #'9'+1
  bcs @DecDone
  sec
  sbc #'0'                      ; A = digit 0-9
  pha                           ; Save digit
  ; MON_ADDR = MON_ADDR * 10 + digit
  ; *10 = (*2 + *8): save *2, then *8, add
  asl MON_ADDR
  rol MON_ADDR+1
  lda MON_ADDR
  sta MON_TMP
  lda MON_ADDR+1
  sta MON_TMP+1                 ; MON_TMP = *2
  asl MON_ADDR
  rol MON_ADDR+1                ; *4
  asl MON_ADDR
  rol MON_ADDR+1                ; *8
  clc
  lda MON_ADDR
  adc MON_TMP
  sta MON_ADDR
  lda MON_ADDR+1
  adc MON_TMP+1
  sta MON_ADDR+1                ; *10
  ; + digit
  pla
  clc
  adc MON_ADDR
  sta MON_ADDR
  bcc @DecNoCarry
  inc MON_ADDR+1
@DecNoCarry:
  inc MON_IDX
  inx
  cpx #5                        ; Max 5 digits (65535)
  bcc @DecLoop
@DecDone:
  cpx #0
  beq @DecFail
  sec                           ; Success
  rts
@DecFail:
  clc                           ; Failure
  rts

; MonParseBin16 — Parse binary digits from MON_LINBUF into MON_ADDR
; Input:  MON_IDX points to current position in MON_LINBUF
; Output: MON_ADDR = parsed 16-bit value, carry set if valid
;         MON_IDX advanced past parsed digits
; Modifies: A, X, Y, MON_ADDR

MonParseBin16:
  stz MON_ADDR
  stz MON_ADDR+1
  ldx #0                        ; Digit count
@BinLoop:
  ldy MON_IDX
  lda MON_LINBUF,y
  cmp #'0'
  beq @BinGot
  cmp #'1'
  beq @BinGot
  bra @BinDone
@BinGot:
  sec
  sbc #'0'                      ; A = 0 or 1
  lsr a                         ; Bit into carry
  rol MON_ADDR
  rol MON_ADDR+1
  inc MON_IDX
  inx
  cpx #16                       ; Max 16 bits
  bcc @BinLoop
@BinDone:
  cpx #0
  beq @BinFail
  sec                           ; Success
  rts
@BinFail:
  clc                           ; Failure
  rts

; ============================================================================
; Decimal & Binary Output Utilities
; ============================================================================

; MonPrintDec16 — Print MON_ADDR as up to 5 decimal digits
; Uses successive subtraction of powers of 10
; Modifies: A, X, Y, MON_TMP, MON_BYTE

MonPrintDec16:
  ; Copy value to MON_TMP so we don't destroy MON_ADDR
  lda MON_ADDR
  sta MON_TMP
  lda MON_ADDR+1
  sta MON_TMP+1
  ldx #0                        ; Leading zero suppression flag
  ldy #0                        ; Power-of-10 index
@Dec16Loop:
  lda #'0'-1
  sta MON_BYTE                  ; Digit scratch
@Dec16Sub:
  inc MON_BYTE
  lda MON_TMP
  sec
  sbc @Dec16Pow10Lo,y
  pha
  lda MON_TMP+1
  sbc @Dec16Pow10Hi,y
  bcc @Dec16Digit               ; Underflow — digit done
  sta MON_TMP+1
  pla
  sta MON_TMP
  bra @Dec16Sub
@Dec16Digit:
  pla                           ; Discard underflowed low byte
  lda MON_BYTE
  cmp #'0'
  bne @Dec16Print               ; Non-zero → print
  cpx #0
  beq @Dec16Skip                ; Leading zero → skip
@Dec16Print:
  phx
  phy
  jsr Chrout
  ply
  plx
  inx                           ; Mark we've printed a digit
@Dec16Skip:
  iny
  cpy #4                        ; 4 powers: 10000, 1000, 100, 10
  bne @Dec16Loop
  ; Always print ones digit
  lda MON_TMP
  ora #'0'
  jsr Chrout
  rts
@Dec16Pow10Lo: .byte <10000, <1000, <100, <10
@Dec16Pow10Hi: .byte >10000, >1000, >100, >10

; MonPrintBin16 — Print MON_ADDR as 16 binary digits (MSB first)
; Modifies: A, X

MonPrintBin16:
  lda MON_ADDR+1                ; High byte first
  jsr @PrintBin8
  lda MON_ADDR                  ; Then low byte
@PrintBin8:
  ldx #8
@BinBitLoop:
  asl a                         ; Shift MSB into carry
  pha
  lda #'0'
  adc #0                        ; +1 if carry → '1'
  jsr Chrout
  pla
  dex
  bne @BinBitLoop
  rts

; ============================================================================
; Message Print Helpers (Phase 5)
; ============================================================================

; MonPrintLoaded — Print "LOADED nnnn BYTES AT $xxxx"
; Input: MON_ADDR = byte count, MON_END = load address
; Modifies: A, X, Y, MON_TMP, MON_BYTE

MonPrintLoaded:
  ldx #0
@PLoop1:
  lda MonStrLoadPfx,x
  beq @PDone1
  jsr Chrout
  inx
  bra @PLoop1
@PDone1:
  jsr MonPrintDec16             ; Print byte count from MON_ADDR
  ldx #0
@PLoop2:
  lda MonStrBytesAt,x
  beq @PDone2
  jsr Chrout
  inx
  bra @PLoop2
@PDone2:
  ; Print address from MON_END
  lda MON_END
  sta MON_ADDR
  lda MON_END+1
  sta MON_ADDR+1
  jsr MonPrintHex4
  jmp MonPrintCRLF

; MonPrintSaved — Print "SAVED nnnn BYTES"
; Input: MON_ADDR = byte count
; Modifies: A, X, Y, MON_TMP, MON_BYTE

MonPrintSaved:
  ldx #0
@SLoop1:
  lda MonStrSavePfx,x
  beq @SDone1
  jsr Chrout
  inx
  bra @SLoop1
@SDone1:
  jsr MonPrintDec16             ; Print byte count from MON_ADDR
  ldx #0
@SLoop2:
  lda MonStrBytes,x
  beq @SDone2
  jsr Chrout
  inx
  bra @SLoop2
@SDone2:
  jmp MonPrintCRLF

; MonPrintIOErr — Print "I/O ERROR"
; Modifies: A, X

MonPrintIOErr:
  ldx #0
@ELoop:
  lda MonStrIOErr,x
  beq @EDone
  jsr Chrout
  inx
  bra @ELoop
@EDone:
  jmp MonPrintCRLF

; MonSerialPrintStr — Print null-terminated string at STR_PTR via serial
; Input: STR_PTR points to string
; Modifies: A, Y

MonSerialPrintStr:
  ldy #0
@SrLoop:
  lda (STR_PTR),y
  beq @SrDone
  jsr SerialChrout
  iny
  bne @SrLoop
@SrDone:
  rts

; ============================================================================
; Hex Output Utilities
; ============================================================================

; MonPrintHex2 — Print A as two hex digits
; Input:  A = byte to print
; Modifies: A, flags

MonPrintHex2:
  pha                           ; Save original byte
  lsr                           ; Shift high nibble down
  lsr
  lsr
  lsr
  jsr @PrintNibble              ; Print high nibble
  pla                           ; Restore original byte
  and #$0F                      ; Isolate low nibble
@PrintNibble:
  cmp #10
  bcc @IsDigit
  clc
  adc #('A' - 10)
  jmp Chrout
@IsDigit:
  clc
  adc #'0'
  jmp Chrout

; MonPrintHex4 — Print MON_ADDR as four hex digits
; Input:  MON_ADDR, MON_ADDR+1 = 16-bit value
; Modifies: A, flags

MonPrintHex4:
  lda MON_ADDR + 1              ; High byte first
  jsr MonPrintHex2
  lda MON_ADDR                  ; Then low byte
  jmp MonPrintHex2

; MonPrintSpace — Print a space character

MonPrintSpace:
  lda #' '
  jmp Chrout

; MonPrintCRLF — Print carriage return + line feed

MonPrintCRLF:
  lda #$0D
  jsr Chrout
  lda #$0A
  jmp Chrout

; MonPrintError — Print "?" for unrecognized command

MonPrintError:
  lda #'?'
  jsr Chrout
  jmp MonPrintCRLF

; MonPrintBanner — Print the monitor banner string

MonPrintBanner:
  ldx #0
@Loop:
  lda MonStrBanner,x
  beq @Done
  jsr Chrout
  inx
  bra @Loop
@Done:
  rts

; ============================================================================
; String Data
; ============================================================================

MonStrBanner:
  .byte "6502 MONITOR v1.0", $0D, $0A, 0
MonStrBrk:
  .byte "BRK AT $", 0
MonStrReady:
  .byte $0D, $0A, "READY TO RECEIVE", $0D, $0A, 0
MonStrNotFound:
  .byte "FILE NOT FOUND", 0
MonStrDirFull:
  .byte "DIRECTORY FULL", 0
MonStrLoadPfx:
  .byte "LOADED ", 0
MonStrSavePfx:
  .byte "SAVED ", 0
MonStrBytesAt:
  .byte " BYTES AT $", 0
MonStrBytes:
  .byte " BYTES", 0
MonStrIOErr:
  .byte "I/O ERROR", 0

; ============================================================================
; Disassembler Data Tables
; ============================================================================

; Mnemonic string table — 71 entries x 3 chars = 213 bytes
DisMnemonics:
  .byte "ADC"              ; 0
  .byte "AND"              ; 1
  .byte "ASL"              ; 2
  .byte "BBR"              ; 3
  .byte "BBS"              ; 4
  .byte "BCC"              ; 5
  .byte "BCS"              ; 6
  .byte "BEQ"              ; 7
  .byte "BIT"              ; 8
  .byte "BMI"              ; 9
  .byte "BNE"              ; 10
  .byte "BPL"              ; 11
  .byte "BRA"              ; 12
  .byte "BRK"              ; 13
  .byte "BVC"              ; 14
  .byte "BVS"              ; 15
  .byte "CLC"              ; 16
  .byte "CLD"              ; 17
  .byte "CLI"              ; 18
  .byte "CLV"              ; 19
  .byte "CMP"              ; 20
  .byte "CPX"              ; 21
  .byte "CPY"              ; 22
  .byte "DEC"              ; 23
  .byte "DEX"              ; 24
  .byte "DEY"              ; 25
  .byte "EOR"              ; 26
  .byte "INC"              ; 27
  .byte "INX"              ; 28
  .byte "INY"              ; 29
  .byte "JMP"              ; 30
  .byte "JSR"              ; 31
  .byte "LDA"              ; 32
  .byte "LDX"              ; 33
  .byte "LDY"              ; 34
  .byte "LSR"              ; 35
  .byte "NOP"              ; 36
  .byte "ORA"              ; 37
  .byte "PHA"              ; 38
  .byte "PHP"              ; 39
  .byte "PHX"              ; 40
  .byte "PHY"              ; 41
  .byte "PLA"              ; 42
  .byte "PLP"              ; 43
  .byte "PLX"              ; 44
  .byte "PLY"              ; 45
  .byte "RMB"              ; 46
  .byte "ROL"              ; 47
  .byte "ROR"              ; 48
  .byte "RTI"              ; 49
  .byte "RTS"              ; 50
  .byte "SBC"              ; 51
  .byte "SEC"              ; 52
  .byte "SED"              ; 53
  .byte "SEI"              ; 54
  .byte "SMB"              ; 55
  .byte "STA"              ; 56
  .byte "STP"              ; 57
  .byte "STX"              ; 58
  .byte "STY"              ; 59
  .byte "STZ"              ; 60
  .byte "TAX"              ; 61
  .byte "TAY"              ; 62
  .byte "TRB"              ; 63
  .byte "TSB"              ; 64
  .byte "TSX"              ; 65
  .byte "TXA"              ; 66
  .byte "TXS"              ; 67
  .byte "TYA"              ; 68
  .byte "WAI"              ; 69
  .byte "???"              ; 70 (undefined)

; Addressing mode operand size table (bytes beyond opcode)
DisModeSizes:
  .byte 0                  ; AM_IMP  = 0
  .byte 0                  ; AM_ACC  = 1
  .byte 1                  ; AM_IMM  = 2
  .byte 1                  ; AM_ZP   = 3
  .byte 1                  ; AM_ZPX  = 4
  .byte 1                  ; AM_ZPY  = 5
  .byte 2                  ; AM_ABS  = 6
  .byte 2                  ; AM_ABX  = 7
  .byte 2                  ; AM_ABY  = 8
  .byte 2                  ; AM_IND  = 9
  .byte 1                  ; AM_IZX  = 10
  .byte 1                  ; AM_IZY  = 11
  .byte 1                  ; AM_ZPI  = 12
  .byte 1                  ; AM_REL  = 13
  .byte 2                  ; AM_ZPR  = 14
  .byte 2                  ; AM_AIX  = 15

; Operand print dispatch table (16 addressing modes)
DisOperandJmpTable:
  .word DisOpImp             ; AM_IMP  = 0
  .word DisOpAcc             ; AM_ACC  = 1
  .word DisOpImm             ; AM_IMM  = 2
  .word DisOpZp              ; AM_ZP   = 3
  .word DisOpZpx             ; AM_ZPX  = 4
  .word DisOpZpy             ; AM_ZPY  = 5
  .word DisOpAbs             ; AM_ABS  = 6
  .word DisOpAbx             ; AM_ABX  = 7
  .word DisOpAby             ; AM_ABY  = 8
  .word DisOpInd             ; AM_IND  = 9
  .word DisOpIzx             ; AM_IZX  = 10
  .word DisOpIzy             ; AM_IZY  = 11
  .word DisOpZpi             ; AM_ZPI  = 12
  .word DisOpRel             ; AM_REL  = 13
  .word DisOpZpr             ; AM_ZPR  = 14
  .word DisOpAix             ; AM_AIX  = 15

; 65C02 Opcode Table — 256 entries x 2 bytes (mnemonic index, addressing mode)
DisOpcodeTable:
  ; --- $0x ---
  .byte MN_BRK,AM_IMP, MN_ORA,AM_IZX, MN_UND,AM_IMP, MN_UND,AM_IMP  ; $00-$03
  .byte MN_TSB,AM_ZP,  MN_ORA,AM_ZP,  MN_ASL,AM_ZP,  MN_RMB,AM_ZP   ; $04-$07
  .byte MN_PHP,AM_IMP, MN_ORA,AM_IMM, MN_ASL,AM_ACC, MN_UND,AM_IMP  ; $08-$0B
  .byte MN_TSB,AM_ABS, MN_ORA,AM_ABS, MN_ASL,AM_ABS, MN_BBR,AM_ZPR  ; $0C-$0F
  ; --- $1x ---
  .byte MN_BPL,AM_REL, MN_ORA,AM_IZY, MN_ORA,AM_ZPI, MN_UND,AM_IMP  ; $10-$13
  .byte MN_TRB,AM_ZP,  MN_ORA,AM_ZPX, MN_ASL,AM_ZPX, MN_RMB,AM_ZP   ; $14-$17
  .byte MN_CLC,AM_IMP, MN_ORA,AM_ABY, MN_INC,AM_ACC, MN_UND,AM_IMP  ; $18-$1B
  .byte MN_TRB,AM_ABS, MN_ORA,AM_ABX, MN_ASL,AM_ABX, MN_BBR,AM_ZPR  ; $1C-$1F
  ; --- $2x ---
  .byte MN_JSR,AM_ABS, MN_AND,AM_IZX, MN_UND,AM_IMP, MN_UND,AM_IMP  ; $20-$23
  .byte MN_BIT,AM_ZP,  MN_AND,AM_ZP,  MN_ROL,AM_ZP,  MN_RMB,AM_ZP   ; $24-$27
  .byte MN_PLP,AM_IMP, MN_AND,AM_IMM, MN_ROL,AM_ACC, MN_UND,AM_IMP  ; $28-$2B
  .byte MN_BIT,AM_ABS, MN_AND,AM_ABS, MN_ROL,AM_ABS, MN_BBR,AM_ZPR  ; $2C-$2F
  ; --- $3x ---
  .byte MN_BMI,AM_REL, MN_AND,AM_IZY, MN_AND,AM_ZPI, MN_UND,AM_IMP  ; $30-$33
  .byte MN_BIT,AM_ZPX, MN_AND,AM_ZPX, MN_ROL,AM_ZPX, MN_RMB,AM_ZP   ; $34-$37
  .byte MN_SEC,AM_IMP, MN_AND,AM_ABY, MN_DEC,AM_ACC, MN_UND,AM_IMP  ; $38-$3B
  .byte MN_BIT,AM_ABX, MN_AND,AM_ABX, MN_ROL,AM_ABX, MN_BBR,AM_ZPR  ; $3C-$3F
  ; --- $4x ---
  .byte MN_RTI,AM_IMP, MN_EOR,AM_IZX, MN_UND,AM_IMP, MN_UND,AM_IMP  ; $40-$43
  .byte MN_UND,AM_IMP, MN_EOR,AM_ZP,  MN_LSR,AM_ZP,  MN_RMB,AM_ZP   ; $44-$47
  .byte MN_PHA,AM_IMP, MN_EOR,AM_IMM, MN_LSR,AM_ACC, MN_UND,AM_IMP  ; $48-$4B
  .byte MN_JMP,AM_ABS, MN_EOR,AM_ABS, MN_LSR,AM_ABS, MN_BBR,AM_ZPR  ; $4C-$4F
  ; --- $5x ---
  .byte MN_BVC,AM_REL, MN_EOR,AM_IZY, MN_EOR,AM_ZPI, MN_UND,AM_IMP  ; $50-$53
  .byte MN_UND,AM_IMP, MN_EOR,AM_ZPX, MN_LSR,AM_ZPX, MN_RMB,AM_ZP   ; $54-$57
  .byte MN_CLI,AM_IMP, MN_EOR,AM_ABY, MN_PHY,AM_IMP, MN_UND,AM_IMP  ; $58-$5B
  .byte MN_UND,AM_IMP, MN_EOR,AM_ABX, MN_LSR,AM_ABX, MN_BBR,AM_ZPR  ; $5C-$5F
  ; --- $6x ---
  .byte MN_RTS,AM_IMP, MN_ADC,AM_IZX, MN_UND,AM_IMP, MN_UND,AM_IMP  ; $60-$63
  .byte MN_STZ,AM_ZP,  MN_ADC,AM_ZP,  MN_ROR,AM_ZP,  MN_RMB,AM_ZP   ; $64-$67
  .byte MN_PLA,AM_IMP, MN_ADC,AM_IMM, MN_ROR,AM_ACC, MN_UND,AM_IMP  ; $68-$6B
  .byte MN_JMP,AM_IND, MN_ADC,AM_ABS, MN_ROR,AM_ABS, MN_BBR,AM_ZPR  ; $6C-$6F
  ; --- $7x ---
  .byte MN_BVS,AM_REL, MN_ADC,AM_IZY, MN_ADC,AM_ZPI, MN_UND,AM_IMP  ; $70-$73
  .byte MN_STZ,AM_ZPX, MN_ADC,AM_ZPX, MN_ROR,AM_ZPX, MN_RMB,AM_ZP   ; $74-$77
  .byte MN_SEI,AM_IMP, MN_ADC,AM_ABY, MN_PLY,AM_IMP, MN_UND,AM_IMP  ; $78-$7B
  .byte MN_JMP,AM_AIX, MN_ADC,AM_ABX, MN_ROR,AM_ABX, MN_BBR,AM_ZPR  ; $7C-$7F
  ; --- $8x ---
  .byte MN_BRA,AM_REL, MN_STA,AM_IZX, MN_UND,AM_IMP, MN_UND,AM_IMP  ; $80-$83
  .byte MN_STY,AM_ZP,  MN_STA,AM_ZP,  MN_STX,AM_ZP,  MN_SMB,AM_ZP   ; $84-$87
  .byte MN_DEY,AM_IMP, MN_BIT,AM_IMM, MN_TXA,AM_IMP, MN_UND,AM_IMP  ; $88-$8B
  .byte MN_STY,AM_ABS, MN_STA,AM_ABS, MN_STX,AM_ABS, MN_BBS,AM_ZPR  ; $8C-$8F
  ; --- $9x ---
  .byte MN_BCC,AM_REL, MN_STA,AM_IZY, MN_STA,AM_ZPI, MN_UND,AM_IMP  ; $90-$93
  .byte MN_STY,AM_ZPX, MN_STA,AM_ZPX, MN_STX,AM_ZPY, MN_SMB,AM_ZP   ; $94-$97
  .byte MN_TYA,AM_IMP, MN_STA,AM_ABY, MN_TXS,AM_IMP, MN_UND,AM_IMP  ; $98-$9B
  .byte MN_STZ,AM_ABS, MN_STA,AM_ABX, MN_STZ,AM_ABX, MN_BBS,AM_ZPR  ; $9C-$9F
  ; --- $Ax ---
  .byte MN_LDY,AM_IMM, MN_LDA,AM_IZX, MN_LDX,AM_IMM, MN_UND,AM_IMP  ; $A0-$A3
  .byte MN_LDY,AM_ZP,  MN_LDA,AM_ZP,  MN_LDX,AM_ZP,  MN_SMB,AM_ZP   ; $A4-$A7
  .byte MN_TAY,AM_IMP, MN_LDA,AM_IMM, MN_TAX,AM_IMP, MN_UND,AM_IMP  ; $A8-$AB
  .byte MN_LDY,AM_ABS, MN_LDA,AM_ABS, MN_LDX,AM_ABS, MN_BBS,AM_ZPR  ; $AC-$AF
  ; --- $Bx ---
  .byte MN_BCS,AM_REL, MN_LDA,AM_IZY, MN_LDA,AM_ZPI, MN_UND,AM_IMP  ; $B0-$B3
  .byte MN_LDY,AM_ZPX, MN_LDA,AM_ZPX, MN_LDX,AM_ZPY, MN_SMB,AM_ZP   ; $B4-$B7
  .byte MN_CLV,AM_IMP, MN_LDA,AM_ABY, MN_TSX,AM_IMP, MN_UND,AM_IMP  ; $B8-$BB
  .byte MN_LDY,AM_ABX, MN_LDA,AM_ABX, MN_LDX,AM_ABY, MN_BBS,AM_ZPR  ; $BC-$BF
  ; --- $Cx ---
  .byte MN_CPY,AM_IMM, MN_CMP,AM_IZX, MN_UND,AM_IMP, MN_UND,AM_IMP  ; $C0-$C3
  .byte MN_CPY,AM_ZP,  MN_CMP,AM_ZP,  MN_DEC,AM_ZP,  MN_SMB,AM_ZP   ; $C4-$C7
  .byte MN_INY,AM_IMP, MN_CMP,AM_IMM, MN_DEX,AM_IMP, MN_WAI,AM_IMP  ; $C8-$CB
  .byte MN_CPY,AM_ABS, MN_CMP,AM_ABS, MN_DEC,AM_ABS, MN_BBS,AM_ZPR  ; $CC-$CF
  ; --- $Dx ---
  .byte MN_BNE,AM_REL, MN_CMP,AM_IZY, MN_CMP,AM_ZPI, MN_UND,AM_IMP  ; $D0-$D3
  .byte MN_UND,AM_IMP, MN_CMP,AM_ZPX, MN_DEC,AM_ZPX, MN_SMB,AM_ZP   ; $D4-$D7
  .byte MN_CLD,AM_IMP, MN_CMP,AM_ABY, MN_PHX,AM_IMP, MN_STP,AM_IMP  ; $D8-$DB
  .byte MN_UND,AM_IMP, MN_CMP,AM_ABX, MN_DEC,AM_ABX, MN_BBS,AM_ZPR  ; $DC-$DF
  ; --- $Ex ---
  .byte MN_CPX,AM_IMM, MN_SBC,AM_IZX, MN_UND,AM_IMP, MN_UND,AM_IMP  ; $E0-$E3
  .byte MN_CPX,AM_ZP,  MN_SBC,AM_ZP,  MN_INC,AM_ZP,  MN_SMB,AM_ZP   ; $E4-$E7
  .byte MN_INX,AM_IMP, MN_SBC,AM_IMM, MN_NOP,AM_IMP, MN_UND,AM_IMP  ; $E8-$EB
  .byte MN_CPX,AM_ABS, MN_SBC,AM_ABS, MN_INC,AM_ABS, MN_BBS,AM_ZPR  ; $EC-$EF
  ; --- $Fx ---
  .byte MN_BEQ,AM_REL, MN_SBC,AM_IZY, MN_SBC,AM_ZPI, MN_UND,AM_IMP  ; $F0-$F3
  .byte MN_UND,AM_IMP, MN_SBC,AM_ZPX, MN_INC,AM_ZPX, MN_SMB,AM_ZP   ; $F4-$F7
  .byte MN_SED,AM_IMP, MN_SBC,AM_ABY, MN_PLX,AM_IMP, MN_UND,AM_IMP  ; $F8-$FB
  .byte MN_UND,AM_IMP, MN_SBC,AM_ABX, MN_INC,AM_ABX, MN_BBS,AM_ZPR  ; $FC-$FF