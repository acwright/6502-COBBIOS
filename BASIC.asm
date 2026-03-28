; ***                         ***
; ***   Integer BASIC v1.0    ***
; ***   for 6502-COBBIOS      ***
; ***   $E000-$FEFF (7936B)   ***
; ***                         ***

; ============================================================================
; Zero Page — BASIC Interpreter Workspace ($04-$23)
; ============================================================================
; $00-$03 reserved by Kernal (READ_PTR, WRITE_PTR, STR_PTR)

BAS_TXTPTR          := $04               ; $04-$05 - Current parse/exec pointer
BAS_CURLINE         := $06               ; $06-$07 - Pointer to current line start
BAS_LINENUM         := $08               ; $08-$09 - Current line number (16-bit)
BAS_ACC             := $0A               ; $0A-$0B - Expression accumulator (16-bit)
BAS_AUX             := $0C               ; $0C-$0D - Auxiliary register (right operand)
BAS_TMP1            := $0E               ; $0E-$0F - General-purpose temp / pointer
BAS_TMP2            := $10               ; $10-$11 - General-purpose temp / pointer
BAS_PRGEND          := $12               ; $12-$13 - First byte past end of program
BAS_VARPTR          := $14               ; $14-$15 - Variable address pointer
BAS_TOKIDX          := $16               ; $16     - Tokenizer index / scratch
BAS_FLAGS           := $17               ; $17     - Runtime flags
BAS_RNDSEED         := $18               ; $18-$19 - PRNG state (16-bit)
BAS_GOSUBSP         := $1A               ; $1A     - GOSUB stack pointer (byte index)
BAS_FORSP           := $1B               ; $1B     - FOR stack pointer (byte index)
BAS_SCRATCH         := $1C               ; $1C-$1D - Scratch / division workspace
BAS_SCRATCH2        := $1E               ; $1E-$1F - Scratch / division workspace
BAS_SIGN            := $20               ; $20     - Sign tracking for mul/div
BAS_TEMP            := $21               ; $21     - General temp byte
BAS_NUMTMP          := $22               ; $22-$23 - Number parsing accumulator

; BAS_FLAGS bit definitions
BAS_FLAG_RUN        = %00000001          ; Bit 0: program is running
BAS_FLAG_NOSEP      = %00000010          ; Bit 1: suppress CRLF after PRINT

; ============================================================================
; RAM Layout — USER_VARS ($0400-$07FF)
; ============================================================================

BAS_VARS            := $0400             ; $0400-$0433 - 26 vars A-Z (2 bytes each)
BAS_LINBUF          := $0434             ; $0434-$04FF - Input line buffer (204 bytes)
BAS_GOSUBSTK        := $0500             ; $0500-$057F - GOSUB stack (128 bytes, 32 levels)
BAS_FORSTK          := $0580             ; $0580-$05FF - FOR/NEXT stack (128 bytes, 8 levels)
BAS_TOKBUF          := $0600             ; $0600-$06FF - Tokenized line buffer (256 bytes)
BAS_STRBUF          := $0700             ; $0700-$07FF - Scratch / number-to-string (256 bytes)

; Derived constants
BAS_LINBUF_SIZE     = 200                ; Max input line length
BAS_GOSUBSTK_SIZE   = 128               ; GOSUB stack capacity
BAS_FORSTK_SIZE     = 128               ; FOR stack capacity
BAS_GOSUB_ENTRY     = 2                  ; Bytes per GOSUB entry (CURLINE)
BAS_FOR_ENTRY       = 16                 ; Bytes per FOR entry
BAS_GOSUB_MAX       = BAS_GOSUBSTK_SIZE / BAS_GOSUB_ENTRY  ; 64 levels
BAS_FOR_MAX         = BAS_FORSTK_SIZE / BAS_FOR_ENTRY       ; 8 levels

; Program space
BAS_PRG_START       = PROGRAM_START      ; $0800 - Start of BASIC program storage
BAS_PRG_END         = $7FFF              ; Last usable byte for programs

; ============================================================================
; Program Line Format (in memory at $0800-$7FFF)
; ============================================================================
; Each stored line:
;   [2 bytes] Next-line pointer (little-endian; $0000 = end of program)
;   [2 bytes] Line number (little-endian; 0-65535)
;   [N bytes] Tokenized payload
;   [1 byte]  $00 terminator
;
; Offsets within a line:
LINE_NEXT           = 0                  ; Offset to next-line pointer
LINE_NUM            = 2                  ; Offset to line number
LINE_PAYLOAD        = 4                  ; Offset to tokenized data

; ============================================================================
; Token Definitions ($80+)
; ============================================================================
; Tokens >= $80 represent keywords; raw ASCII is stored as-is.

; Statement tokens
TOK_PRINT           = $80
TOK_INPUT           = $81
TOK_LET             = $82
TOK_GOTO            = $83
TOK_GOSUB           = $84
TOK_RETURN          = $85
TOK_IF              = $86
TOK_THEN            = $87
TOK_FOR             = $88
TOK_TO              = $89
TOK_STEP            = $8A
TOK_NEXT            = $8B
TOK_REM             = $8C
TOK_END             = $8D
TOK_LIST            = $8E
TOK_RUN             = $8F
TOK_NEW             = $90
TOK_CLR             = $91
TOK_PEEK            = $92
TOK_POKE            = $93
TOK_ABS             = $94
TOK_RND             = $95
TOK_NOT             = $96
TOK_AND             = $97
TOK_OR              = $98
TOK_MOD             = $99

TOK_BRK             = $9D
TOK_SYS             = $9E
TOK_LOAD            = $9F
TOK_SAVE            = $A0
TOK_DIR             = $A1
TOK_DEL             = $A2
TOK_CLS             = $A3
TOK_LOCATE          = $A4
TOK_COLOR           = $A5
TOK_JOY             = $A6
TOK_SOUND           = $A7
TOK_VOL             = $A8
TOK_TIME            = $A9
TOK_DATE            = $AA
TOK_WAIT            = $AB
TOK_PAUSE           = $AC
TOK_BANK            = $AD
TOK_SGN             = $AE
TOK_CHR             = $AF

; Multi-char operator tokens
TOK_GE              = $9A               ; >=
TOK_LE              = $9B               ; <=
TOK_NE              = $9C               ; <>

; ASCII characters used in parsing (for readability)
CH_CR               = $0D               ; Carriage return
CH_LF               = $0A               ; Line feed
CH_SPACE            = $20               ; Space
CH_QUOTE            = $22               ; Double-quote
CH_COMMA            = $2C               ; Comma
CH_MINUS            = $2D               ; Minus / dash
CH_COLON            = $3A               ; Colon (statement separator)
CH_SEMICOL          = $3B               ; Semicolon
CH_EQUALS           = $3D               ; Equals sign
CH_LPAREN           = $28               ; (
CH_RPAREN           = $29               ; )
CH_LESS             = $3C               ; <
CH_GREATER          = $3E               ; >
CH_PLUS             = $2B               ; +
CH_STAR             = $2A               ; *
CH_SLASH            = $2F               ; /
CH_BKSP             = $08               ; Backspace
CH_ESC              = $1B               ; Escape
CH_CTRLC            = $03               ; Ctrl+C (break)

; Error codes
ERR_SYNTAX          = 0
ERR_UNDEF_LINE      = 1
ERR_TYPE_MISMATCH   = 2
ERR_OUT_OF_MEM      = 3
ERR_RET_NO_GOSUB    = 4
ERR_NEXT_NO_FOR     = 5
ERR_DIV_ZERO        = 6
ERR_OVERFLOW        = 7
ERR_ILLEGAL_QTY     = 8
ERR_BREAK           = 9

; ============================================================================
; Entry Point
; ============================================================================

BasEntry:
  jmp BasColdStart               ; Jump to cold start initialization

; ============================================================================
; Cold Start — Initialize interpreter and enter REPL
; ============================================================================

BasColdStart:
  ; Initialize program end pointer to start (empty program)
  lda #<BAS_PRG_START
  sta BAS_PRGEND
  lda #>BAS_PRG_START
  sta BAS_PRGEND + 1

  ; Write end-of-program sentinel ($0000 next-line pointer)
  lda #$00
  sta BAS_PRG_START
  sta BAS_PRG_START + 1

  ; Clear variables and stacks
  jsr BasCmdClr

  ; Seed PRNG with a nonzero value
  lda #$A5
  sta BAS_RNDSEED
  lda #$37
  sta BAS_RNDSEED + 1

  ; Print welcome banner
  lda #<BasStrWelcome
  sta BAS_TMP1
  lda #>BasStrWelcome
  sta BAS_TMP1 + 1
  jsr BasPrintStr

  ; Print free memory
  jsr BasPrintFree

  ; Fall through to main REPL loop

; ============================================================================
; Main REPL Loop
; ============================================================================

BasMainLoop:
  ; Reset flags for immediate mode
  stz BAS_FLAGS

  ; Print OK prompt
  lda #<BasStrOK
  sta BAS_TMP1
  lda #>BasStrOK
  sta BAS_TMP1 + 1
  jsr BasPrintStr

  ; Read a line of input
  jsr BasReadLine

  ; Tokenize the input line
  jsr BasTokenize

  ; Check if line has a line number (first 2 bytes of TOKBUF)
  lda BAS_TOKBUF
  ora BAS_TOKBUF + 1
  beq @Immediate                 ; No line number — execute immediately

  ; Has line number — insert/replace in program
  jsr BasInsertLine
  jmp BasMainLoop

@Immediate:
  ; Set TXTPTR to the tokenized payload (skip 2-byte line number slot)
  lda #<(BAS_TOKBUF + 2)
  sta BAS_TXTPTR
  lda #>(BAS_TOKBUF + 2)
  sta BAS_TXTPTR + 1

  ; Execute the immediate line
  jsr BasExecLine
  jmp BasMainLoop

; ============================================================================
; CLR — Clear all variables and reset stacks
; ============================================================================

BasCmdClr:
  ; Zero 26 variables (52 bytes at BAS_VARS)
  ldx #51
  lda #$00
@ClrLoop:
  sta BAS_VARS,x
  dex
  bpl @ClrLoop

  ; Reset GOSUB and FOR stack pointers
  stz BAS_GOSUBSP
  stz BAS_FORSP
  rts

; ============================================================================
; Print Helpers
; ============================================================================

; Print null-terminated string at (BAS_TMP1)
; Modifies: A, Y, Flags
BasPrintStr:
  ldy #$00
@Loop:
  lda (BAS_TMP1),y
  beq @Done
  jsr Chrout
  iny
  bne @Loop
@Done:
  rts

; Print CR + LF
; Modifies: A, Flags
BasPrintCRLF:
  lda #CH_CR
  jsr Chrout
  lda #CH_LF
  jsr Chrout
  rts

; Print free bytes message: "XXXXX BYTES FREE" + CRLF
; Modifies: A, X, Y, Flags
BasPrintFree:
  ; Calculate free = BAS_PRG_END - BAS_PRGEND
  sec
  lda #<BAS_PRG_END
  sbc BAS_PRGEND
  sta BAS_ACC
  lda #>BAS_PRG_END
  sbc BAS_PRGEND + 1
  sta BAS_ACC + 1

  jsr BasPrintInt

  lda #<BasStrFree
  sta BAS_TMP1
  lda #>BasStrFree
  sta BAS_TMP1 + 1
  jsr BasPrintStr
  jmp BasPrintCRLF

; ============================================================================
; Print signed 16-bit integer in BAS_ACC
; Modifies: A, X, Y, Flags
; ============================================================================

BasPrintInt:
  ; Check if negative (bit 15 set)
  lda BAS_ACC + 1
  bpl @Positive

  ; Print minus sign
  lda #CH_MINUS
  jsr Chrout

  ; Negate: ACC = 0 - ACC
  sec
  lda #$00
  sbc BAS_ACC
  sta BAS_ACC
  lda #$00
  sbc BAS_ACC + 1
  sta BAS_ACC + 1

@Positive:
  ; Push digits onto CPU stack (divide by 10 repeatedly)
  ldx #$00                       ; Digit counter on stack

@DivLoop:
  ; Divide BAS_ACC by 10, remainder is next digit (least significant first)
  lda #$00
  sta BAS_SCRATCH               ; Remainder
  ldy #16                        ; 16-bit division

@DivBit:
  asl BAS_ACC
  rol BAS_ACC + 1
  rol BAS_SCRATCH
  sec
  lda BAS_SCRATCH
  sbc #10
  bcc @DivNoSub
  sta BAS_SCRATCH
  inc BAS_ACC                    ; Set quotient bit

@DivNoSub:
  dey
  bne @DivBit

  ; Push remainder digit (ASCII)
  lda BAS_SCRATCH
  ora #$30                       ; Convert to ASCII '0'-'9'
  pha
  inx                            ; Count digits

  ; Check if quotient is zero
  lda BAS_ACC
  ora BAS_ACC + 1
  bne @DivLoop

  ; Pop and print digits (most significant first)
@PrintDigits:
  pla
  jsr Chrout
  dex
  bne @PrintDigits
  rts

; ============================================================================
; Read a line of input into BAS_LINBUF
; Blocks until CR received. Handles backspace.
; Modifies: A, X, Y, Flags
; ============================================================================

BasReadLine:
  ldy #$00                       ; Index into BAS_LINBUF

@WaitChar:
  jsr Chrin                      ; Non-blocking read (carry=1 if char available)
  bcc @WaitChar                  ; Loop until character available

  ; Check for backspace
  cmp #CH_BKSP
  beq @Backspace

  ; Check for CR (end of line)
  cmp #CH_CR
  beq @Done

  ; Check for Ctrl+C (cancel line)
  cmp #CH_CTRLC
  beq @Cancel

  ; Skip non-printable control characters (LF, NUL, ESC, etc.)
  cmp #CH_SPACE
  bcc @WaitChar

  ; Ignore if buffer full
  cpy #BAS_LINBUF_SIZE
  bcs @WaitChar

  ; Convert lowercase to uppercase
  cmp #'a'
  bcc @Store
  cmp #'z' + 1
  bcs @Store
  and #$DF                       ; Clear bit 5 → uppercase
@Store:
  ; Store character and advance
  sta BAS_LINBUF,y
  iny
  bra @WaitChar

@Backspace:
  cpy #$00
  beq @WaitChar                  ; Nothing to delete
  dey
  bra @WaitChar

@Cancel:
  ldy #$00                       ; Reset buffer
  jsr BasPrintCRLF
  bra @WaitChar

@Done:
  lda #$00
  sta BAS_LINBUF,y               ; Null-terminate
  jsr BasPrintCRLF               ; Echo newline (Chrin echoed the CR)
  rts

; ============================================================================
; Tokenizer — Convert BAS_LINBUF ASCII text into BAS_TOKBUF tokenized form
; ============================================================================
; Input:  BAS_LINBUF contains null-terminated ASCII line
; Output: BAS_TOKBUF contains:
;           [2 bytes] line number (0 if no line number)
;           [N bytes] tokenized payload
;           [$00]     terminator
; Modifies: A, X, Y, Flags, BAS_TMP1, BAS_TMP2, BAS_TOKIDX, BAS_NUMTMP

BasTokenize:
  ldx #$00                       ; X = source index into BAS_LINBUF
  stz BAS_TOKIDX                 ; Output index into BAS_TOKBUF

  ; --- Parse optional line number ---
  stz BAS_NUMTMP                 ; Clear 16-bit accumulator
  stz BAS_NUMTMP + 1
  ldy #$00                       ; Flag: any digit found?

@TokNumLoop:
  lda BAS_LINBUF,x
  sec
  sbc #'0'
  bcc @TokNumDone                ; < '0'
  cmp #10
  bcs @TokNumDone                ; > '9'

  ; Accumulate: NUMTMP = NUMTMP * 10 + digit
  pha                            ; Save digit
  ; Multiply NUMTMP by 10: (val<<3) + (val<<1)
  lda BAS_NUMTMP
  sta BAS_SCRATCH
  lda BAS_NUMTMP + 1
  sta BAS_SCRATCH + 1
  ; Shift left 1 (×2)
  asl BAS_NUMTMP
  rol BAS_NUMTMP + 1
  ; Shift left 3 more (×8 total from original)
  lda BAS_SCRATCH
  asl
  sta BAS_SCRATCH
  lda BAS_SCRATCH + 1
  rol
  sta BAS_SCRATCH + 1
  asl BAS_SCRATCH
  rol BAS_SCRATCH + 1
  asl BAS_SCRATCH
  rol BAS_SCRATCH + 1
  ; Add ×2 + ×8 = ×10
  clc
  lda BAS_NUMTMP
  adc BAS_SCRATCH
  sta BAS_NUMTMP
  lda BAS_NUMTMP + 1
  adc BAS_SCRATCH + 1
  sta BAS_NUMTMP + 1
  ; Add the digit
  pla
  clc
  adc BAS_NUMTMP
  sta BAS_NUMTMP
  bcc @TokNumNoCarry
  inc BAS_NUMTMP + 1
@TokNumNoCarry:
  iny                            ; Mark digit found
  inx                            ; Advance source
  bra @TokNumLoop

@TokNumDone:
  ; Store line number (0 if none found)
  lda BAS_NUMTMP
  sta BAS_TOKBUF
  lda BAS_NUMTMP + 1
  sta BAS_TOKBUF + 1
  lda #2
  sta BAS_TOKIDX                 ; Output starts after 2-byte line number

  ; Skip spaces after line number
  jsr @TokSkipSpaces

  ; --- Main tokenize loop ---
@TokLoop:
  lda BAS_LINBUF,x
  beq @TokEnd                   ; Null terminator — done

  ; Check for string literal (copy verbatim including quotes)
  cmp #CH_QUOTE
  beq @TokString

  ; Check for multi-char operators: >=, <=, <>
  cmp #CH_GREATER
  beq @TokCheckGE
  cmp #CH_LESS
  beq @TokCheckLE

  ; Check if uppercase letter — possible keyword
  cmp #'A'
  bcc @TokCopyChar               ; Below 'A' — just copy
  cmp #'Z' + 1
  bcs @TokCopyChar               ; Above 'Z' — just copy

  ; Try to match a keyword
  pha                            ; Save char in case match fails
  jsr BasMatchKeyword
  bcs @TokGotKeywordPop         ; Carry set = matched
  pla                            ; Restore original character

  ; Not a keyword — copy single character as-is
@TokCopyChar:
  ldy BAS_TOKIDX
  sta BAS_TOKBUF,y
  inc BAS_TOKIDX
  inx                            ; Advance source
  bra @TokLoop

@TokEnd:
  ; Null-terminate tokenized output
  ldy BAS_TOKIDX
  lda #$00
  sta BAS_TOKBUF,y
  rts

@TokCheckGE:
  ; Current char is '>', check next for '='
  lda BAS_LINBUF+1,x
  cmp #CH_EQUALS
  bne @TokCopyGT
  lda #TOK_GE
  ldy BAS_TOKIDX
  sta BAS_TOKBUF,y
  inc BAS_TOKIDX
  inx                            ; Skip '>'
  inx                            ; Skip '='
  bra @TokLoop
@TokCopyGT:
  lda #CH_GREATER
  bra @TokCopyChar

@TokCheckLE:
  ; Current char is '<', check next
  lda BAS_LINBUF+1,x
  cmp #CH_EQUALS
  beq @TokEmitLE
  cmp #CH_GREATER
  beq @TokEmitNE
  lda #CH_LESS
  bra @TokCopyChar
@TokEmitLE:
  lda #TOK_LE
  ldy BAS_TOKIDX
  sta BAS_TOKBUF,y
  inc BAS_TOKIDX
  inx
  inx
  bra @TokLoop
@TokEmitNE:
  lda #TOK_NE
  ldy BAS_TOKIDX
  sta BAS_TOKBUF,y
  inc BAS_TOKIDX
  inx
  inx
  bra @TokLoop

@TokGotKeywordPop:
  ply                            ; Discard saved char (preserves A = token)
@TokGotKeyword:
  ; A = token byte, X already advanced past keyword
  ldy BAS_TOKIDX
  sta BAS_TOKBUF,y
  inc BAS_TOKIDX

  ; If REM token, copy rest of line verbatim
  cmp #TOK_REM
  beq @TokRem
  jmp @TokLoop

@TokString:
  ; Copy opening quote
  ldy BAS_TOKIDX
  sta BAS_TOKBUF,y
  inc BAS_TOKIDX
  inx
@TokStrLoop:
  lda BAS_LINBUF,x
  beq @TokEndJ                   ; Unterminated string — end of line
  ldy BAS_TOKIDX
  sta BAS_TOKBUF,y
  inc BAS_TOKIDX
  inx
  cmp #CH_QUOTE                  ; Closing quote?
  bne @TokStrLoop
  jmp @TokLoop                   ; Continue after closing quote
@TokEndJ:
  jmp @TokEnd

@TokRem:
  ; Copy everything remaining verbatim
@TokRemLoop:
  lda BAS_LINBUF,x
  beq @TokEndJ2
  ldy BAS_TOKIDX
  sta BAS_TOKBUF,y
  inc BAS_TOKIDX
  inx
  bra @TokRemLoop
@TokEndJ2:
  jmp @TokEnd

; Skip spaces in BAS_LINBUF at position X
@TokSkipSpaces:
  lda BAS_LINBUF,x
  cmp #CH_SPACE
  bne @TokSkipDone
  inx
  bra @TokSkipSpaces
@TokSkipDone:
  rts

; ============================================================================
; Keyword Matching — Try to match a keyword at BAS_LINBUF+X
; ============================================================================
; Input:  X = current source index in BAS_LINBUF
; Output: Carry set if matched, A = token, X advanced past keyword
;         Carry clear if no match, X unchanged
; Modifies: A, Y, BAS_TMP1, BAS_TMP2

BasMatchKeyword:
  phx                            ; Save source position for rollback

  ; Set BAS_TMP1 to start of keyword table
  lda #<BasKeywordTable
  sta BAS_TMP1
  lda #>BasKeywordTable
  sta BAS_TMP1 + 1

  ldy #$00                       ; Index into keyword table

@KwOuter:
  ; Load first byte of keyword entry — $00 = end of table
  lda (BAS_TMP1),y
  beq @KwNoMatch                 ; End of table — no match

  ; Save Y (table position) and try matching chars
  plx                            ; Restore original X (source position)
  phx                            ; Re-save it for next attempt
  sty BAS_TMP2                   ; Save table offset

@KwCompare:
  lda (BAS_TMP1),y
  beq @KwMatched                 ; Null terminator in keyword = full match
  cmp BAS_LINBUF,x
  bne @KwSkip                   ; Mismatch — skip to next keyword
  iny
  inx
  bra @KwCompare

@KwMatched:
  ; Keyword matched. The token byte follows the null terminator.
  iny                            ; Advance past the null
  lda (BAS_TMP1),y               ; Read token byte

  ; Check that the next source char is not a letter (prevent partial match)
  ; e.g. "TORE" should not match "TO"
  pha                            ; Save token
  lda BAS_LINBUF,x
  cmp #'A'
  bcc @KwConfirmed               ; Not a letter — confirmed
  cmp #'Z' + 1
  bcs @KwConfirmed               ; Not a letter — confirmed
  ; Next char is a letter — this is a partial match, skip it
  pla
  ldy BAS_TMP2
  bra @KwSkip

@KwConfirmed:
  pla                            ; Recover token
  ply                            ; Discard saved source position (PLY not PLX — X holds the advanced position)
  ; X is already advanced past the keyword
  sec
  rts

@KwSkip:
  ; Advance Y past current keyword string + null + token byte
  ldy BAS_TMP2                   ; Back to start of this keyword
@KwSkipStr:
  lda (BAS_TMP1),y
  iny
  cmp #$00                       ; Found null terminator?
  bne @KwSkipStr
  iny                            ; Skip token byte too
  bra @KwOuter                   ; Try next keyword

@KwNoMatch:
  plx                            ; Restore original source position
  clc
  rts

; ============================================================================
; Detokenizer — Convert tokenized line to printable ASCII
; ============================================================================
; Input:  BAS_TMP1 points to tokenized payload (past line number)
; Output: Characters sent to Chrout
; Input:  BAS_TXTPTR points to tokenized payload
; Output: Characters sent to Chrout
; Modifies: A, X, Y, Flags, BAS_TMP2

BasDetokenize:
  ldy #$00

@DetokLoop:
  lda (BAS_TXTPTR),y
  beq @DetokDone                 ; Null terminator — done

  ; Check if token (>= $80)
  bmi @DetokKeyword

  ; Regular ASCII character — output it
  jsr Chrout
  iny
  bra @DetokLoop

@DetokKeyword:
  ; Look up keyword string for this token
  phy                            ; Save source index
  sta BAS_TEMP                   ; Save target token

  ; Walk the keyword table looking for matching token
  lda #<BasKeywordTable
  sta BAS_TMP2
  lda #>BasKeywordTable
  sta BAS_TMP2 + 1

  ldy #$00                       ; Table index

@DetokSearch:
  lda (BAS_TMP2),y
  beq @DetokNotFound             ; End of table — token not found
  ; Save start of this keyword string
  sty BAS_TOKIDX                 ; Remember keyword start
@DetokScanStr:
  lda (BAS_TMP2),y
  iny
  cmp #$00                       ; End of keyword string?
  bne @DetokScanStr
  ; Y now points to the token byte
  lda (BAS_TMP2),y
  iny                            ; Advance past token byte

  ; Compare to our target token
  cmp BAS_TEMP
  beq @DetokFound
  ; Not this one — continue searching
  bra @DetokSearch

@DetokFound:
  ; Print the keyword string starting at BAS_TOKIDX
  ldy BAS_TOKIDX
@DetokPrintKw:
  lda (BAS_TMP2),y
  beq @DetokKwDone               ; Null = end of keyword string
  jsr Chrout
  iny
  bra @DetokPrintKw

@DetokKwDone:
  ply                            ; Restore source index
  iny                            ; Advance past the token byte in source
  bra @DetokLoop

@DetokNotFound:
  ; Token not in table (shouldn't happen) — print '?' and continue
  lda #'?'
  jsr Chrout
  ply
  iny
  bra @DetokLoop

@DetokDone:
  rts

; ============================================================================
; Line Editor — Program Storage Management
; ============================================================================

; ----------------------------------------------------------------------------
; BasInsertLine — Insert or replace a program line
; ----------------------------------------------------------------------------
; Input:  BAS_TOKBUF contains tokenized line:
;           [2 bytes] line number
;           [N bytes] tokenized payload
;           [$00]     terminator
; If payload is empty (just null after line number), deletes existing line.
; Modifies: A, X, Y, Flags, BAS_TMP1, BAS_TMP2, BAS_SCRATCH, BAS_SCRATCH2

BasInsertLine:
  ; Load line number from TOKBUF
  lda BAS_TOKBUF
  sta BAS_LINENUM
  lda BAS_TOKBUF + 1
  sta BAS_LINENUM + 1

  ; Calculate new line size: scan TOKBUF payload for null terminator
  ldx #2                         ; Start past line number in TOKBUF
@SizeLoop:
  lda BAS_TOKBUF,x
  beq @SizeDone
  inx
  bra @SizeLoop
@SizeDone:
  ; X = offset of null terminator (payload length = X - 2)
  ; Total line in memory: 2 (next ptr) + 2 (line num) + (X-2) payload + 1 (null) = X + 3
  inx                            ; Include the null terminator
  inx                            ; +2 for next-line pointer
  inx                            ; +2 for line number (but X already includes 2 from tokbuf offset)
  ; X now = new line byte count including header
  ; Actually: payload starts at TOKBUF+2, null at TOKBUF+X (original)
  ; Memory line = 4 header + (origX - 2) payload + 1 null = origX + 3
  ; But we already incremented X by 3, so X = origX + 3. Correct.
  stx BAS_SCRATCH2               ; Save new line size

  ; Check if payload is empty (just the null after line number = delete only)
  lda BAS_TOKBUF + 2
  sta BAS_TEMP                   ; $00 if empty, nonzero if has content

  ; --- Try to find existing line with this number ---
  jsr BasFindLine                ; Sets BAS_TMP1 if found, carry set/clear

  bcc @NoExisting

  ; --- Delete existing line ---
  ; BAS_TMP1 = address of existing line
  ; Calculate old line's size by scanning for null terminator
  ldy #LINE_PAYLOAD
@DelSizeLoop:
  lda (BAS_TMP1),y
  beq @DelSizeDone
  iny
  bra @DelSizeLoop
@DelSizeDone:
  iny                            ; Include null byte; Y = total line size
  sty BAS_AUX                   ; Old line size low
  stz BAS_AUX + 1               ; High byte = 0 (lines < 256 bytes)

  ; Compute source (next line address) = BAS_TMP1 + Y
  tya
  clc
  adc BAS_TMP1
  sta BAS_SCRATCH                ; Next-line address low
  lda #$00
  adc BAS_TMP1 + 1
  sta BAS_SCRATCH + 1            ; Next-line address high

  ; Shift bytes down: copy from BAS_SCRATCH to BAS_TMP1, up to BAS_PRGEND
  ; Source = BAS_SCRATCH (next line), Dest = BAS_TMP1 (current line)
  ; Count = BAS_PRGEND - BAS_SCRATCH
  ldy #$00
@DeleteLoop:
  lda BAS_SCRATCH
  cmp BAS_PRGEND
  lda BAS_SCRATCH + 1
  sbc BAS_PRGEND + 1
  bcs @DeleteDone                ; Source >= PRGEND, done copying

  lda (BAS_SCRATCH),y
  sta (BAS_TMP1),y

  ; Increment source pointer
  inc BAS_SCRATCH
  bne @DelSrcOk
  inc BAS_SCRATCH + 1
@DelSrcOk:
  ; Increment dest pointer
  inc BAS_TMP1
  bne @DelDstOk
  inc BAS_TMP1 + 1
@DelDstOk:
  bra @DeleteLoop

@DeleteDone:
  ; Update PRGEND: subtract old line size
  sec
  lda BAS_PRGEND
  sbc BAS_AUX
  sta BAS_PRGEND
  lda BAS_PRGEND + 1
  sbc BAS_AUX + 1
  sta BAS_PRGEND + 1

@NoExisting:
  ; If payload was empty, we're done (delete only)
  lda BAS_TEMP
  bne @DoInsert
  rts                            ; Empty payload — delete only, done

@DoInsert:

  ; --- Find insertion point (keep lines sorted by number) ---
  lda #<BAS_PRG_START
  sta BAS_TMP1
  lda #>BAS_PRG_START
  sta BAS_TMP1 + 1

@FindInsPos:
  ; Check if we've reached end of program (TMP1 == PRGEND)
  lda BAS_TMP1
  cmp BAS_PRGEND
  bne @FindNotEnd
  lda BAS_TMP1 + 1
  cmp BAS_PRGEND + 1
  beq @InsertHere                ; At PRGEND — insert here
@FindNotEnd:

  ; Compare this line's number with target
  ldy #LINE_NUM
  lda (BAS_TMP1),y
  sta BAS_AUX
  iny
  lda (BAS_TMP1),y
  sta BAS_AUX + 1

  ; If this line number >= target, insert before it
  lda BAS_LINENUM
  cmp BAS_AUX
  lda BAS_LINENUM + 1
  sbc BAS_AUX + 1
  bcc @InsertHere                ; Target < this line — insert here

  ; Advance to next line via next-ptr; if $0000, advance to PRGEND
  ldy #LINE_NEXT
  lda (BAS_TMP1),y
  tax
  iny
  lda (BAS_TMP1),y
  sta BAS_TMP1 + 1
  stx BAS_TMP1
  ; If next-ptr was $0000, use PRGEND instead
  ora BAS_TMP1
  bne @FindInsPos
  lda BAS_PRGEND
  sta BAS_TMP1
  lda BAS_PRGEND + 1
  sta BAS_TMP1 + 1
  bra @FindInsPos

@InsertHere:
  ; BAS_TMP1 = insertion point
  ; BAS_SCRATCH2 = new line size
  ; Check if there's room
  clc
  lda BAS_PRGEND
  adc BAS_SCRATCH2
  sta BAS_SCRATCH                ; Tentative new PRGEND low
  lda BAS_PRGEND + 1
  adc #$00
  sta BAS_SCRATCH + 1            ; Tentative new PRGEND high

  ; Check if new PRGEND > BAS_PRG_END ($7FFF)
  lda BAS_SCRATCH + 1
  cmp #>BAS_PRG_END
  bcc @HasRoom
  bne @OutOfMem
  lda BAS_SCRATCH
  cmp #<BAS_PRG_END
  bcc @HasRoom
  beq @HasRoom
@OutOfMem:
  lda #ERR_OUT_OF_MEM
  jmp BasError

@HasRoom:
  ; Shift bytes up: move from PRGEND-1 down to TMP1, shifting by SCRATCH2 bytes
  ; Work backwards from PRGEND to TMP1

  ; Source end = PRGEND - 1
  sec
  lda BAS_PRGEND
  sbc #$01
  sta BAS_SCRATCH
  lda BAS_PRGEND + 1
  sbc #$00
  sta BAS_SCRATCH + 1

  ; Dest end = source end + new line size
  clc
  lda BAS_SCRATCH
  adc BAS_SCRATCH2
  sta BAS_AUX
  lda BAS_SCRATCH + 1
  adc #$00
  sta BAS_AUX + 1

@ShiftUpLoop:
  ; Check if source < insertion point (done)
  lda BAS_SCRATCH
  cmp BAS_TMP1
  lda BAS_SCRATCH + 1
  sbc BAS_TMP1 + 1
  bcc @ShiftUpDone

  ; Copy byte from source to dest
  ldy #$00
  lda (BAS_SCRATCH),y
  sta (BAS_AUX),y

  ; Decrement source
  lda BAS_SCRATCH
  bne @ShiftSrcOk
  dec BAS_SCRATCH + 1
@ShiftSrcOk:
  dec BAS_SCRATCH

  ; Decrement dest
  lda BAS_AUX
  bne @ShiftDstOk
  dec BAS_AUX + 1
@ShiftDstOk:
  dec BAS_AUX
  bra @ShiftUpLoop

@ShiftUpDone:
  ; Update PRGEND
  clc
  lda BAS_PRGEND
  adc BAS_SCRATCH2
  sta BAS_PRGEND
  lda BAS_PRGEND + 1
  adc #$00
  sta BAS_PRGEND + 1

  ; Write the new line at BAS_TMP1
  ; Bytes 0-1: next-line pointer (filled by relink)
  ; Bytes 2-3: line number
  ldy #LINE_NUM
  lda BAS_LINENUM
  sta (BAS_TMP1),y
  iny
  lda BAS_LINENUM + 1
  sta (BAS_TMP1),y

  ; Copy tokenized payload from BAS_TOKBUF+2 to line+4
  ldx #$00                       ; Source index into TOKBUF+2
  ldy #LINE_PAYLOAD              ; Dest offset in line
@CopyPayload:
  lda BAS_TOKBUF + 2,x
  sta (BAS_TMP1),y
  beq @CopyDone                  ; Copied the null terminator — done
  inx
  iny
  bra @CopyPayload

@CopyDone:
  ; Relink all lines
  jsr BasRelink

@InsertDone:
  rts

; ----------------------------------------------------------------------------
; BasFindLine — Find a program line by line number
; ----------------------------------------------------------------------------
; Input:  BAS_LINENUM = target line number (16-bit)
; Output: Carry set if found, clear if not found
;         BAS_TMP1 = pointer to line (if found) or insertion point (if not)
; Modifies: A, Y, Flags, BAS_TMP1

BasFindLine:
  lda #<BAS_PRG_START
  sta BAS_TMP1
  lda #>BAS_PRG_START
  sta BAS_TMP1 + 1

@FindLoop:
  ; Check if at end of program (TMP1 == PRGEND)
  lda BAS_TMP1
  cmp BAS_PRGEND
  bne @FindNotEnd
  lda BAS_TMP1 + 1
  cmp BAS_PRGEND + 1
  beq @FindNotFound              ; End of program
@FindNotEnd:

  ; Compare this line's number with target
  ldy #LINE_NUM
  lda (BAS_TMP1),y
  cmp BAS_LINENUM
  bne @FindNotEqual
  iny
  lda (BAS_TMP1),y
  cmp BAS_LINENUM + 1
  beq @FindFound                 ; Exact match

@FindNotEqual:
  ; Check if this line number > target (past where it would be)
  ldy #LINE_NUM + 1
  lda BAS_LINENUM + 1
  cmp (BAS_TMP1),y
  bcc @FindNotFound              ; Target high < line high — not found
  bne @FindAdvance               ; Target high > line high — keep looking
  dey
  lda BAS_LINENUM
  cmp (BAS_TMP1),y
  bcc @FindNotFound              ; Target < line — not found

@FindAdvance:
  ; Move to next line by scanning for null terminator
  ldy #LINE_PAYLOAD
@FindScan:
  lda (BAS_TMP1),y
  beq @FindScanDone
  iny
  bra @FindScan
@FindScanDone:
  iny                            ; Past null
  tya
  clc
  adc BAS_TMP1
  sta BAS_TMP1
  lda #$00
  adc BAS_TMP1 + 1
  sta BAS_TMP1 + 1
  bra @FindLoop

@FindFound:
  sec
  rts

@FindNotFound:
  clc
  rts

; ----------------------------------------------------------------------------
; BasRelink — Rebuild all next-line pointers from PROGRAM_START
; ----------------------------------------------------------------------------
; Walks program lines, computes each line's length, sets next-pointer.
; Modifies: A, X, Y, Flags, BAS_TMP2

BasRelink:
  lda #<BAS_PRG_START
  sta BAS_TMP2
  lda #>BAS_PRG_START
  sta BAS_TMP2 + 1

@RelinkLoop:
  ; Check if at PRGEND
  lda BAS_TMP2
  cmp BAS_PRGEND
  bne @RelinkNotEnd
  lda BAS_TMP2 + 1
  cmp BAS_PRGEND + 1
  beq @RelinkDone

@RelinkNotEnd:
  ; Find length of this line by scanning for null terminator in payload
  ldy #LINE_PAYLOAD
@RelinkScan:
  lda (BAS_TMP2),y
  beq @RelinkFoundNull
  iny
  bra @RelinkScan

@RelinkFoundNull:
  ; Y = offset of null terminator. Line length = Y + 1.
  iny                            ; Include the null byte
  ; Next line address = BAS_TMP2 + Y
  tya
  clc
  adc BAS_TMP2
  sta BAS_SCRATCH
  lda #$00
  adc BAS_TMP2 + 1
  sta BAS_SCRATCH + 1

  ; Check if next line is at or past PRGEND — if so, write $0000
  lda BAS_SCRATCH
  cmp BAS_PRGEND
  bne @RelinkWrite
  lda BAS_SCRATCH + 1
  cmp BAS_PRGEND + 1
  bne @RelinkWrite
  ; At PRGEND — write end-of-program sentinel
  ldy #LINE_NEXT
  lda #$00
  sta (BAS_TMP2),y
  iny
  sta (BAS_TMP2),y
  bra @RelinkDone

@RelinkWrite:
  ; Write next-line pointer
  ldy #LINE_NEXT
  lda BAS_SCRATCH
  sta (BAS_TMP2),y
  iny
  lda BAS_SCRATCH + 1
  sta (BAS_TMP2),y

  ; Advance to next line
  lda BAS_SCRATCH
  sta BAS_TMP2
  lda BAS_SCRATCH + 1
  sta BAS_TMP2 + 1
  bra @RelinkLoop

@RelinkDone:
  ; Write end sentinel at PRGEND
  ldy #$00
  lda #$00
  sta (BAS_PRGEND),y
  iny
  sta (BAS_PRGEND),y
  rts

; ============================================================================
; BasParseInt — Parse decimal integer from tokenized text at TXTPTR
; ============================================================================
; Input:  BAS_TXTPTR points at text
; Output: BAS_ACC = parsed 16-bit value, BAS_TXTPTR advanced
;         Carry set on error (no digits found)
; Modifies: A, X, Y, Flags, BAS_NUMTMP, BAS_SCRATCH

BasParseInt:
  stz BAS_NUMTMP
  stz BAS_NUMTMP + 1
  ldx #$00                       ; Digit count

  ldy #$00

@ParseLoop:
  lda (BAS_TXTPTR),y
  sec
  sbc #'0'
  bcc @ParseDone                 ; Not a digit
  cmp #10
  bcs @ParseDone                 ; Not a digit

  ; Have a digit — multiply accumulator by 10 and add
  pha                            ; Save digit

  ; NUMTMP × 10 = (NUMTMP × 8) + (NUMTMP × 2)
  lda BAS_NUMTMP
  sta BAS_SCRATCH
  lda BAS_NUMTMP + 1
  sta BAS_SCRATCH + 1

  ; ×2
  asl BAS_NUMTMP
  rol BAS_NUMTMP + 1
  ; ×8 from original (3 shifts)
  asl BAS_SCRATCH
  rol BAS_SCRATCH + 1
  asl BAS_SCRATCH
  rol BAS_SCRATCH + 1
  asl BAS_SCRATCH
  rol BAS_SCRATCH + 1

  ; ×2 + ×8 = ×10
  clc
  lda BAS_NUMTMP
  adc BAS_SCRATCH
  sta BAS_NUMTMP
  lda BAS_NUMTMP + 1
  adc BAS_SCRATCH + 1
  sta BAS_NUMTMP + 1

  ; Add digit
  pla
  clc
  adc BAS_NUMTMP
  sta BAS_NUMTMP
  bcc @ParseNoCarry
  inc BAS_NUMTMP + 1
@ParseNoCarry:
  inx                            ; Count digit
  iny                            ; Advance past digit
  bra @ParseLoop

@ParseDone:
  ; Advance TXTPTR by Y
  tya
  clc
  adc BAS_TXTPTR
  sta BAS_TXTPTR
  lda #$00
  adc BAS_TXTPTR + 1
  sta BAS_TXTPTR + 1

  ; Copy result to ACC
  lda BAS_NUMTMP
  sta BAS_ACC
  lda BAS_NUMTMP + 1
  sta BAS_ACC + 1

  ; Set carry if no digits found
  cpx #$00
  beq @ParseError
  clc
  rts

@ParseError:
  sec
  rts

; BasNibble — Convert ASCII hex character in A to nibble value (0-15)
; Input:  A = ASCII character ('0'-'9', 'A'-'F')
; Output: A = nibble value 0-15, carry clear on success
;         Carry set if character is not a valid hex digit
; Modifies: Flags, A
BasNibble:
  cmp #'0'
  bcc @NibbleInvalid
  cmp #'9' + 1
  bcs @NibbleTryAlpha
  sec
  sbc #'0'
  clc
  rts
@NibbleTryAlpha:
  cmp #'A'
  bcc @NibbleInvalid
  cmp #'F' + 1
  bcs @NibbleInvalid
  sec
  sbc #'A' - 10
  clc
  rts
@NibbleInvalid:
  sec
  rts

; ============================================================================
; BasSkipSpaces — Advance TXTPTR past spaces
; ============================================================================
; Modifies: A, Y, Flags

BasSkipSpaces:
  ldy #$00
@SkipLoop:
  lda (BAS_TXTPTR),y
  cmp #CH_SPACE
  bne @SkipDone
  iny
  bra @SkipLoop
@SkipDone:
  ; Advance TXTPTR by Y
  tya
  clc
  adc BAS_TXTPTR
  sta BAS_TXTPTR
  lda #$00
  adc BAS_TXTPTR + 1
  sta BAS_TXTPTR + 1
  rts

; ============================================================================
; BasGetTokChar — Get current token byte at TXTPTR without advancing
; ============================================================================
; Output: A = byte at TXTPTR, Z flag set if null
; Modifies: A, Y, Flags

BasGetTokChar:
  ldy #$00
  lda (BAS_TXTPTR),y
  rts

; ============================================================================
; BasAdvTxtPtr — Advance TXTPTR by 1
; ============================================================================
; Modifies: Flags

BasAdvTxtPtr:
  inc BAS_TXTPTR
  bne @Done
  inc BAS_TXTPTR + 1
@Done:
  rts

; ============================================================================
; BasExpectChar — Expect a specific character at TXTPTR, error if not found
; ============================================================================
; Input: A = expected character
; Modifies: A, Y, Flags

BasExpectChar:
  ldy #$00
  cmp (BAS_TXTPTR),y             ; Compare expected (A) with actual
  bne @SyntaxErr
  jsr BasAdvTxtPtr               ; Skip the character
  rts
@SyntaxErr:
  lda #ERR_SYNTAX
  jmp BasError

; ============================================================================
; BasCheckBreak — Check for Ctrl+C during program execution
; ============================================================================
; Call at the top of each line in RUN mode.
; Modifies: A, Flags

BasCheckBreak:
  lda BAS_FLAGS
  and #BAS_FLAG_RUN
  beq @NoBrk                    ; Not running — skip check
  jsr Chrin                      ; Non-blocking read
  bcc @NoBrk                    ; No character available
  cmp #CH_CTRLC
  beq @Break
  cmp #CH_ESC
  beq @Break
@NoBrk:
  rts
@Break:
  lda #ERR_BREAK
  jmp BasError

; ============================================================================
; Error Handling
; ============================================================================

; BasError — Print error message and return to REPL
; Input: A = error code (ERR_* constant)
; Never returns — jumps to BasMainLoop

BasError:
  pha                            ; Save error code

  jsr BasPrintCRLF

  lda #'?'
  jsr Chrout

  ; Look up error message pointer
  pla
  asl                            ; ×2 for word-sized table index
  tax
  lda BasErrTable,x
  sta BAS_TMP1
  lda BasErrTable+1,x
  sta BAS_TMP1 + 1

  ; Print error message
  jsr BasPrintStr

  ; Print " ERROR" (skip for BREAK)
  cpx #(ERR_BREAK * 2)
  beq @SkipErrorWord
  lda #<BasStrError
  sta BAS_TMP1
  lda #>BasStrError
  sta BAS_TMP1 + 1
  jsr BasPrintStr
@SkipErrorWord:

  ; If running, print " IN " + line number
  lda BAS_FLAGS
  and #BAS_FLAG_RUN
  beq @ErrDone

  lda #<BasStrIn
  sta BAS_TMP1
  lda #>BasStrIn
  sta BAS_TMP1 + 1
  jsr BasPrintStr

  ; Print current line number
  lda BAS_LINENUM
  sta BAS_ACC
  lda BAS_LINENUM + 1
  sta BAS_ACC + 1
  jsr BasPrintInt

@ErrDone:
  jsr BasPrintCRLF

  ; Reset state and return to REPL
  stz BAS_FLAGS
  stz BAS_GOSUBSP
  stz BAS_FORSP

  ; Reset stack pointer to avoid stack corruption from nested calls
  ldx #$FF
  txs

  jmp BasMainLoop

; Error message pointer table
BasErrTable:
  .word BasErrSyntax             ; 0 - SYNTAX
  .word BasErrUndef              ; 1 - UNDEF'D LINE
  .word BasErrType               ; 2 - TYPE MISMATCH
  .word BasErrMem                ; 3 - OUT OF MEMORY
  .word BasErrRetGosub           ; 4 - RETURN W/O GOSUB
  .word BasErrNextFor            ; 5 - NEXT W/O FOR
  .word BasErrDivZero            ; 6 - DIVISION BY ZERO
  .word BasErrOverflow           ; 7 - OVERFLOW
  .word BasErrIllegal            ; 8 - ILLEGAL QUANTITY
  .word BasErrBreak              ; 9 - BREAK

; Error message strings
BasErrSyntax:    .byte "SYNTAX", $00
BasErrUndef:     .byte "UNDEF'D LINE", $00
BasErrType:      .byte "TYPE MISMATCH", $00
BasErrMem:       .byte "OUT OF MEMORY", $00
BasErrRetGosub:  .byte "RETURN W/O GOSUB", $00
BasErrNextFor:   .byte "NEXT W/O FOR", $00
BasErrDivZero:   .byte "DIVISION BY ZERO", $00
BasErrOverflow:  .byte "OVERFLOW", $00
BasErrIllegal:   .byte "ILLEGAL QUANTITY", $00
BasErrBreak:     .byte "BREAK", $00

; ============================================================================
; 16-Bit Math Routines
; ============================================================================

; BasMathAdd — ACC = AUX + ACC
BasMathAdd:
  clc
  lda BAS_AUX
  adc BAS_ACC
  sta BAS_ACC
  lda BAS_AUX + 1
  adc BAS_ACC + 1
  sta BAS_ACC + 1
  rts

; BasMathSub — ACC = AUX - ACC
BasMathSub:
  sec
  lda BAS_AUX
  sbc BAS_ACC
  sta BAS_ACC
  lda BAS_AUX + 1
  sbc BAS_ACC + 1
  sta BAS_ACC + 1
  rts

; BasMathNeg — ACC = -ACC (two's complement)
BasMathNeg:
  sec
  lda #$00
  sbc BAS_ACC
  sta BAS_ACC
  lda #$00
  sbc BAS_ACC + 1
  sta BAS_ACC + 1
  rts

; BasMathAbs — ACC = |ACC|
BasMathAbs:
  lda BAS_ACC + 1
  bpl @Done
  jmp BasMathNeg
@Done:
  rts

; BasMathMul — ACC = AUX * ACC (16-bit signed)
; Uses shift-and-add on magnitudes, applies sign separately
BasMathMul:
  ; Determine result sign
  lda BAS_AUX + 1
  eor BAS_ACC + 1
  sta BAS_SIGN                   ; Bit 7 = result sign

  ; Make both operands positive
  lda BAS_AUX + 1
  bpl @AuxPos
  sec
  lda #$00
  sbc BAS_AUX
  sta BAS_AUX
  lda #$00
  sbc BAS_AUX + 1
  sta BAS_AUX + 1
@AuxPos:
  lda BAS_ACC + 1
  bpl @AccPos
  jsr BasMathNeg
@AccPos:
  ; ACC = multiplier, AUX = multiplicand
  ; Result accumulates in SCRATCH:SCRATCH+1
  stz BAS_SCRATCH
  stz BAS_SCRATCH + 1
  ldx #16                        ; 16 bits

@MulLoop:
  ; Shift multiplier (ACC) right
  lsr BAS_ACC + 1
  ror BAS_ACC
  bcc @MulNoAdd

  ; Add multiplicand to result
  clc
  lda BAS_SCRATCH
  adc BAS_AUX
  sta BAS_SCRATCH
  lda BAS_SCRATCH + 1
  adc BAS_AUX + 1
  sta BAS_SCRATCH + 1

@MulNoAdd:
  ; Shift multiplicand left
  asl BAS_AUX
  rol BAS_AUX + 1
  dex
  bne @MulLoop

  ; Copy result
  lda BAS_SCRATCH
  sta BAS_ACC
  lda BAS_SCRATCH + 1
  sta BAS_ACC + 1

  ; Apply sign
  lda BAS_SIGN
  bpl @MulDone
  jmp BasMathNeg
@MulDone:
  rts

; BasMathDiv — ACC = AUX / ACC, remainder in BAS_SCRATCH2
; 16-bit signed division
BasMathDiv:
  ; Check for division by zero
  lda BAS_ACC
  ora BAS_ACC + 1
  bne @DivNotZero
  lda #ERR_DIV_ZERO
  jmp BasError

@DivNotZero:
  ; Determine result sign
  lda BAS_AUX + 1
  eor BAS_ACC + 1
  sta BAS_SIGN

  ; Save remainder sign (same as dividend) on CPU stack
  lda BAS_AUX + 1
  pha

  ; Make both positive
  lda BAS_AUX + 1
  bpl @DivAuxPos
  sec
  lda #$00
  sbc BAS_AUX
  sta BAS_AUX
  lda #$00
  sbc BAS_AUX + 1
  sta BAS_AUX + 1
@DivAuxPos:
  lda BAS_ACC + 1
  bpl @DivAccPos
  jsr BasMathNeg
@DivAccPos:
  ; AUX = dividend, ACC = divisor
  ; Remainder in SCRATCH2
  stz BAS_SCRATCH2
  stz BAS_SCRATCH2 + 1

  ldx #16

@DivLoop:
  ; Shift dividend left into remainder
  asl BAS_AUX
  rol BAS_AUX + 1
  rol BAS_SCRATCH2
  rol BAS_SCRATCH2 + 1

  ; Try subtract divisor from remainder
  sec
  lda BAS_SCRATCH2
  sbc BAS_ACC
  sta BAS_SCRATCH
  lda BAS_SCRATCH2 + 1
  sbc BAS_ACC + 1

  bcc @DivNoSub

  ; Subtraction succeeded — set quotient bit
  sta BAS_SCRATCH2 + 1
  lda BAS_SCRATCH
  sta BAS_SCRATCH2
  inc BAS_AUX                    ; Set low bit of quotient

@DivNoSub:
  dex
  bne @DivLoop

  ; Quotient is in AUX, remainder in SCRATCH2
  lda BAS_AUX
  sta BAS_ACC
  lda BAS_AUX + 1
  sta BAS_ACC + 1

  ; Apply sign to quotient
  lda BAS_SIGN
  bpl @DivQuotPos
  jsr BasMathNeg
@DivQuotPos:
  ; Apply sign to remainder (same sign as dividend)
  pla                            ; Remainder sign (was dividend's high byte)
  bpl @DivDone
  ; Negate remainder
  sec
  lda #$00
  sbc BAS_SCRATCH2
  sta BAS_SCRATCH2
  lda #$00
  sbc BAS_SCRATCH2 + 1
  sta BAS_SCRATCH2 + 1
@DivDone:
  rts

; ============================================================================
; Expression Evaluator — Recursive Descent
; ============================================================================
; Result always in BAS_ACC (16-bit signed).
; TXTPTR is advanced past consumed tokens.

; BasExpr — Top level: handle OR
BasExpr:
  jsr BasExprAnd
@OrLoop:
  jsr BasSkipSpaces
  jsr BasGetTokChar
  cmp #TOK_OR
  bne @OrDone
  jsr BasAdvTxtPtr
  lda BAS_ACC
  pha
  lda BAS_ACC + 1
  pha
  jsr BasExprAnd
  ; Pop left operand into AUX
  pla
  sta BAS_AUX + 1
  pla
  sta BAS_AUX
  ; OR: result = (AUX != 0) || (ACC != 0) ? 1 : 0
  lda BAS_AUX
  ora BAS_AUX + 1
  beq @OrRight
  lda #$01
  bra @OrStore
@OrRight:
  lda BAS_ACC
  ora BAS_ACC + 1
  beq @OrFalse
  lda #$01
  bra @OrStore
@OrFalse:
  lda #$00
@OrStore:
  sta BAS_ACC
  stz BAS_ACC + 1
  bra @OrLoop
@OrDone:
  rts

; BasExprAnd — Handle AND
BasExprAnd:
  jsr BasExprNot
@AndLoop:
  jsr BasSkipSpaces
  jsr BasGetTokChar
  cmp #TOK_AND
  bne @AndDone
  jsr BasAdvTxtPtr
  lda BAS_ACC
  pha
  lda BAS_ACC + 1
  pha
  jsr BasExprNot
  pla
  sta BAS_AUX + 1
  pla
  sta BAS_AUX
  ; AND: both nonzero = 1, else 0
  lda BAS_AUX
  ora BAS_AUX + 1
  beq @AndFalse
  lda BAS_ACC
  ora BAS_ACC + 1
  beq @AndFalse
  lda #$01
  stz BAS_ACC + 1
  sta BAS_ACC
  bra @AndLoop
@AndFalse:
  stz BAS_ACC
  stz BAS_ACC + 1
  bra @AndLoop
@AndDone:
  rts

; BasExprNot — Handle NOT (unary prefix)
BasExprNot:
  jsr BasSkipSpaces
  jsr BasGetTokChar
  cmp #TOK_NOT
  bne @NotSkip
  jsr BasAdvTxtPtr
  jsr BasExprCmp
  ; NOT: 0 -> 1, nonzero -> 0
  lda BAS_ACC
  ora BAS_ACC + 1
  beq @NotTrue
  stz BAS_ACC
  stz BAS_ACC + 1
  rts
@NotTrue:
  lda #$01
  sta BAS_ACC
  stz BAS_ACC + 1
  rts
@NotSkip:
  jmp BasExprCmp

; BasExprCmp — Handle comparison: =, <>, <, >, <=, >=
BasExprCmp:
  jsr BasExprAdd
  jsr BasSkipSpaces
  jsr BasGetTokChar

  ; Check each comparison operator
  cmp #CH_EQUALS
  beq @CmpEQ
  cmp #CH_LESS
  beq @CmpLT
  cmp #CH_GREATER
  beq @CmpGT
  cmp #TOK_NE
  beq @CmpNE
  cmp #TOK_LE
  beq @CmpLE
  cmp #TOK_GE
  beq @CmpGE
  rts                            ; No comparison operator

@CmpEQ:
  jsr BasAdvTxtPtr
  jsr @CmpPushEvalRight
  ; Equal: ACC == AUX
  lda BAS_ACC
  cmp BAS_AUX
  bne @CmpSetFalse
  lda BAS_ACC + 1
  cmp BAS_AUX + 1
  bne @CmpSetFalse
  bra @CmpSetTrue

@CmpNE:
  jsr BasAdvTxtPtr
  jsr @CmpPushEvalRight
  lda BAS_ACC
  cmp BAS_AUX
  bne @CmpSetTrue
  lda BAS_ACC + 1
  cmp BAS_AUX + 1
  bne @CmpSetTrue
  bra @CmpSetFalse

@CmpLT:
  jsr BasAdvTxtPtr
  jsr @CmpPushEvalRight
  jsr BasCmpAuxAcc
  bmi @CmpSetTrue
  bra @CmpSetFalse

@CmpGT:
  jsr BasAdvTxtPtr
  jsr @CmpPushEvalRight
  jsr BasCmpAuxAcc
  beq @CmpSetFalse
  bpl @CmpSetTrue
  bra @CmpSetFalse

@CmpLE:
  jsr BasAdvTxtPtr
  jsr @CmpPushEvalRight
  jsr BasCmpAuxAcc
  bmi @CmpSetTrue
  beq @CmpSetTrue
  bra @CmpSetFalse

@CmpGE:
  jsr BasAdvTxtPtr
  jsr @CmpPushEvalRight
  jsr BasCmpAuxAcc
  bpl @CmpSetTrue
  bra @CmpSetFalse

@CmpSetTrue:
  lda #$01
  sta BAS_ACC
  stz BAS_ACC + 1
  rts
@CmpSetFalse:
  stz BAS_ACC
  stz BAS_ACC + 1
  rts

; Helper: push left, evaluate right into ACC, pop left into AUX
@CmpPushEvalRight:
  lda BAS_ACC
  pha
  lda BAS_ACC + 1
  pha
  jsr BasExprAdd
  pla
  sta BAS_AUX + 1
  pla
  sta BAS_AUX
  rts

; BasCmpAuxAcc — Signed compare AUX vs ACC
; Returns: N flag set if AUX < ACC, Z if equal, N clear & Z clear if AUX > ACC
BasCmpAuxAcc:
  ; Compare high bytes first (signed)
  lda BAS_AUX + 1
  sec
  sbc BAS_ACC + 1
  bvc @CmpNoOvf
  eor #$80                       ; Fix sign on overflow
@CmpNoOvf:
  bmi @CmpLess
  bne @CmpGreater
  ; High bytes equal — compare low bytes (unsigned)
  lda BAS_AUX
  cmp BAS_ACC
  beq @CmpEqual
  bcc @CmpLess
@CmpGreater:
  lda #$01                       ; Positive, non-zero
  rts
@CmpLess:
  lda #$FF                       ; Negative
  rts
@CmpEqual:
  lda #$00                       ; Zero
  rts

; BasExprAdd — Handle + and -
BasExprAdd:
  jsr BasExprMul
@AddLoop:
  jsr BasSkipSpaces
  jsr BasGetTokChar
  cmp #CH_PLUS
  beq @DoAdd
  cmp #CH_MINUS
  beq @DoSub
  rts

@DoAdd:
  jsr BasAdvTxtPtr
  lda BAS_ACC
  pha
  lda BAS_ACC + 1
  pha
  jsr BasExprMul
  pla
  sta BAS_AUX + 1
  pla
  sta BAS_AUX
  jsr BasMathAdd
  jmp @AddLoop

@DoSub:
  jsr BasAdvTxtPtr
  lda BAS_ACC
  pha
  lda BAS_ACC + 1
  pha
  jsr BasExprMul
  pla
  sta BAS_AUX + 1
  pla
  sta BAS_AUX
  jsr BasMathSub
  jmp @AddLoop

; BasExprMul — Handle *, /, MOD
BasExprMul:
  jsr BasExprUnary
@MulLoop:
  jsr BasSkipSpaces
  jsr BasGetTokChar
  cmp #CH_STAR
  beq @DoMul
  cmp #CH_SLASH
  beq @DoDiv
  cmp #TOK_MOD
  beq @DoMod
  rts

@DoMul:
  jsr BasAdvTxtPtr
  lda BAS_ACC
  pha
  lda BAS_ACC + 1
  pha
  jsr BasExprUnary
  pla
  sta BAS_AUX + 1
  pla
  sta BAS_AUX
  jsr BasMathMul
  jmp @MulLoop

@DoDiv:
  jsr BasAdvTxtPtr
  lda BAS_ACC
  pha
  lda BAS_ACC + 1
  pha
  jsr BasExprUnary
  pla
  sta BAS_AUX + 1
  pla
  sta BAS_AUX
  jsr BasMathDiv
  jmp @MulLoop

@DoMod:
  jsr BasAdvTxtPtr
  lda BAS_ACC
  pha
  lda BAS_ACC + 1
  pha
  jsr BasExprUnary
  pla
  sta BAS_AUX + 1
  pla
  sta BAS_AUX
  jsr BasMathDiv
  ; MOD result is the remainder
  lda BAS_SCRATCH2
  sta BAS_ACC
  lda BAS_SCRATCH2 + 1
  sta BAS_ACC + 1
  jmp @MulLoop

; BasExprUnary — Handle unary minus
BasExprUnary:
  jsr BasSkipSpaces
  jsr BasGetTokChar
  cmp #CH_MINUS
  bne @UnaryPos
  jsr BasAdvTxtPtr
  jsr BasExprPrimary
  jmp BasMathNeg
@UnaryPos:
  jmp BasExprPrimary

; BasExprPrimary — Numbers, variables, parens, functions
BasExprPrimary:
  jsr BasSkipSpaces
  jsr BasGetTokChar

  ; Number literal?
  cmp #'0'
  bcc @NotNum
  cmp #'9' + 1
  bcs @NotNum
  jmp @IsNum                     ; Digit found — parse number
@NotNum:

  ; Variable A-Z?
  cmp #'A'
  bcc @NotVar
  cmp #'Z' + 1
  bcs @NotVar
  ; Variable — compute address: BAS_VARS + (ch - 'A') * 2
  sec
  sbc #'A'
  asl                            ; ×2 for 16-bit
  tax
  lda BAS_VARS,x
  sta BAS_ACC
  lda BAS_VARS + 1,x
  sta BAS_ACC + 1
  jmp BasAdvTxtPtr               ; Skip variable letter
@NotVar:

  ; Parenthesized expression?
  cmp #CH_LPAREN
  bne @NotParen
  jsr BasAdvTxtPtr               ; Skip '('
  jsr BasExpr
  lda #CH_RPAREN
  jmp BasExpectChar              ; Expect and skip ')'
@NotParen:

  ; PEEK(expr)?
  cmp #TOK_PEEK
  bne @NotPeek
  jsr BasAdvTxtPtr               ; Skip PEEK token
  lda #CH_LPAREN
  jsr BasExpectChar
  jsr BasExpr
  lda #CH_RPAREN
  jsr BasExpectChar
  ; Load byte from address in ACC
  lda BAS_ACC
  sta BAS_TMP2
  lda BAS_ACC + 1
  sta BAS_TMP2 + 1
  ldy #$00
  lda (BAS_TMP2),y
  sta BAS_ACC
  stz BAS_ACC + 1
  rts
@NotPeek:

  ; ABS(expr)?
  cmp #TOK_ABS
  bne @NotAbs
  jsr BasAdvTxtPtr
  lda #CH_LPAREN
  jsr BasExpectChar
  jsr BasExpr
  lda #CH_RPAREN
  jsr BasExpectChar
  jmp BasMathAbs
@NotAbs:

  ; RND(expr)?
  cmp #TOK_RND
  bne @NotRnd
  jsr BasAdvTxtPtr
  lda #CH_LPAREN
  jsr BasExpectChar
  jsr BasExpr
  lda #CH_RPAREN
  jsr BasExpectChar
  ; Save modulus (ACC) and generate random number
  lda BAS_ACC
  pha
  lda BAS_ACC + 1
  pha
  ; Galois LFSR step
  lda BAS_RNDSEED
  asl
  rol BAS_RNDSEED + 1
  bcc @RndNoTap
  eor #$2D                      ; Tap polynomial
@RndNoTap:
  sta BAS_RNDSEED
  ; Use seed as raw random value
  lda BAS_RNDSEED
  sta BAS_AUX
  lda BAS_RNDSEED + 1
  ; Make positive
  and #$7F
  sta BAS_AUX + 1
  ; Restore modulus
  pla
  sta BAS_ACC + 1
  pla
  sta BAS_ACC
  ; If modulus <= 0, just return raw number
  lda BAS_ACC
  ora BAS_ACC + 1
  beq @RndRaw
  lda BAS_ACC + 1
  bmi @RndRaw
  ; ACC = AUX MOD ACC
  jsr BasMathDiv
  lda BAS_SCRATCH2
  sta BAS_ACC
  lda BAS_SCRATCH2 + 1
  sta BAS_ACC + 1
  rts
@RndRaw:
  lda BAS_AUX
  sta BAS_ACC
  lda BAS_AUX + 1
  sta BAS_ACC + 1
  rts
@NotRnd:

  ; JOY(n) — read joystick port
  cmp #TOK_JOY
  bne @NotJoy
  jsr BasAdvTxtPtr               ; skip TOK_JOY
  lda #CH_LPAREN
  jsr BasExpectChar
  jsr BasExpr                    ; n -> BAS_ACC
  lda #CH_RPAREN
  jsr BasExpectChar
  lda BAS_ACC
  cmp #2
  bne @JoyPort1
  jsr ReadJoystick2
  bra @JoyDone
@JoyPort1:
  jsr ReadJoystick1
@JoyDone:
  sta BAS_ACC
  stz BAS_ACC + 1
  rts
@NotJoy:

  ; SGN(x) — return sign of value
  cmp #TOK_SGN
  bne @NotSgn
  jsr BasAdvTxtPtr               ; skip TOK_SGN
  lda #CH_LPAREN
  jsr BasExpectChar
  jsr BasExpr                    ; x -> BAS_ACC
  lda #CH_RPAREN
  jsr BasExpectChar
  lda BAS_ACC
  ora BAS_ACC + 1
  beq @SgnZero
  lda BAS_ACC + 1
  bmi @SgnNeg
  lda #$01
  sta BAS_ACC
  stz BAS_ACC + 1
  rts
@SgnNeg:
  lda #$FF
  sta BAS_ACC
  sta BAS_ACC + 1                ; $FFFF = -1 (signed)
  rts
@SgnZero:
  stz BAS_ACC
  stz BAS_ACC + 1
  rts
@NotSgn:

  ; CHR(n) — return value (identity in expression context)
  cmp #TOK_CHR
  bne @NotChr
  jsr BasAdvTxtPtr               ; skip TOK_CHR
  lda #CH_LPAREN
  jsr BasExpectChar
  jsr BasExpr                    ; n -> BAS_ACC
  lda #CH_RPAREN
  jsr BasExpectChar
  rts                            ; BAS_ACC already holds n
@NotChr:

  ; Hex literal $xxxx
  cmp #'$'
  bne @NotHex
  jsr BasAdvTxtPtr               ; skip '$'
  stz BAS_NUMTMP
  stz BAS_NUMTMP + 1
@HexLoop:
  jsr BasGetTokChar
  jsr BasNibble                  ; A -> nibble (0-15), carry set if not a hex char
  bcs @HexDone
  ; Shift NUMTMP left 4 bits
  ldy #4
@HexShift:
  asl BAS_NUMTMP
  rol BAS_NUMTMP + 1
  dey
  bne @HexShift
  ora BAS_NUMTMP
  sta BAS_NUMTMP
  jsr BasAdvTxtPtr
  bra @HexLoop
@HexDone:
  lda BAS_NUMTMP
  sta BAS_ACC
  lda BAS_NUMTMP + 1
  sta BAS_ACC + 1
  rts
@NotHex:

  ; Try parsing as a number
@IsNum:
  jmp BasParseInt                ; Parse decimal, result in ACC

; ============================================================================
; Command Dispatch and Execution
; ============================================================================

; BasExecLine — Execute one tokenized line starting at TXTPTR
BasExecLine:
  jsr BasSkipSpaces
  jsr BasGetTokChar
  bne @ExecNotNull
  rts                            ; Null = end of line
@ExecNotNull:

  ; Dispatch based on token/character
  cmp #TOK_PRINT
  bne :+
  jmp @JmpPrint
: cmp #TOK_INPUT
  bne :+
  jmp @JmpInput
: cmp #TOK_GOTO
  bne :+
  jmp @JmpGoto
: cmp #TOK_GOSUB
  bne :+
  jmp @JmpGosub
: cmp #TOK_RETURN
  bne :+
  jmp @JmpReturn
: cmp #TOK_IF
  bne :+
  jmp @JmpIf
: cmp #TOK_FOR
  bne :+
  jmp @JmpFor
: cmp #TOK_NEXT
  bne :+
  jmp @JmpNext
: cmp #TOK_REM
  bne @NotRem
  rts                            ; REM — skip rest of line
@NotRem:
  cmp #TOK_END
  bne @NotEnd
  jmp @JmpEnd
@NotEnd:
  cmp #TOK_LIST
  bne @NotList
  jmp @JmpList
@NotList:
  cmp #TOK_RUN
  bne @NotRun
  jmp @JmpRun
@NotRun:
  cmp #TOK_NEW
  bne @NotNew
  jmp @JmpNew
@NotNew:
  cmp #TOK_CLR
  bne @NotClr
  jmp @JmpClrCmd
@NotClr:
  cmp #TOK_POKE
  bne @NotPoke
  jmp @JmpPoke
@NotPoke:
  cmp #TOK_LET
  bne @NotLet
  jmp @JmpLet
@NotLet:
  cmp #TOK_BRK
  bne @NotBrk
  jmp @JmpBrk
@NotBrk:
  cmp #TOK_SYS
  bne @NotSys
  jmp @JmpSys
@NotSys:
  cmp #TOK_LOAD
  bne @NotLoad
  jmp @JmpLoad
@NotLoad:
  cmp #TOK_SAVE
  bne @NotSave
  jmp @JmpSave
@NotSave:
  cmp #TOK_DIR
  bne @NotDir
  jmp @JmpDir
@NotDir:
  cmp #TOK_DEL
  bne @NotDel
  jmp @JmpDel
@NotDel:
  cmp #TOK_CLS
  bne :+
  jmp @JmpCls
: cmp #TOK_LOCATE
  bne :+
  jmp @JmpLocate
: cmp #TOK_COLOR
  bne :+
  jmp @JmpColor
: cmp #TOK_SOUND
  bne :+
  jmp @JmpSound
: cmp #TOK_VOL
  bne :+
  jmp @JmpVol
: cmp #TOK_TIME
  bne :+
  jmp @JmpTime
: cmp #TOK_DATE
  bne :+
  jmp @JmpDate
: cmp #TOK_WAIT
  bne :+
  jmp @JmpWait
: cmp #TOK_PAUSE
  bne :+
  jmp @JmpPause
: cmp #TOK_BANK
  bne :+
  jmp @JmpBank
:
  ; Check for implicit LET: A-Z followed by =
  cmp #'A'
  bcc @ExecSyntaxErr
  cmp #'Z' + 1
  bcs @ExecSyntaxErr
  ; Don't consume the variable letter — BasCmdLet will read it
  jmp BasCmdLet

@ExecSyntaxErr:
  lda #ERR_SYNTAX
  jmp BasError

@JmpPrint:
  jsr BasAdvTxtPtr
  jsr BasCmdPrint
  jmp @ExecCheckMore
@JmpInput:
  jsr BasAdvTxtPtr
  jsr BasCmdInput
  jmp @ExecCheckMore
@JmpGoto:
  jsr BasAdvTxtPtr
  jmp BasCmdGoto                 ; Goto changes TXTPTR, don't check for ':'
@JmpGosub:
  jsr BasAdvTxtPtr
  jmp BasCmdGosub
@JmpReturn:
  jsr BasAdvTxtPtr
  jmp BasCmdReturn
@JmpIf:
  jsr BasAdvTxtPtr
  jmp BasCmdIf
@JmpFor:
  jsr BasAdvTxtPtr
  jmp BasCmdFor
@JmpNext:
  jsr BasAdvTxtPtr
  jmp BasCmdNext
@JmpEnd:
  jmp BasCmdEnd
@JmpList:
  jsr BasAdvTxtPtr
  jsr BasCmdList
  jmp @ExecCheckMore
@JmpRun:
  jmp BasCmdRun
@JmpNew:
  jmp BasCmdNew
@JmpClrCmd:
  jsr BasAdvTxtPtr
  jsr BasCmdClr
  jmp @ExecCheckMore
@JmpPoke:
  jsr BasAdvTxtPtr
  jsr BasCmdPoke
  jmp @ExecCheckMore
@JmpLet:
  jsr BasAdvTxtPtr
  jsr BasCmdLet
  jmp @ExecCheckMore
@JmpBrk:
  jmp BasCmdBrk
@JmpSys:
  jsr BasAdvTxtPtr
  jsr BasCmdSys
  jmp @ExecCheckMore
@JmpLoad:
  jsr BasAdvTxtPtr
  jsr BasCmdLoad
  jmp @ExecCheckMore
@JmpSave:
  jsr BasAdvTxtPtr
  jsr BasCmdSave
  jmp @ExecCheckMore
@JmpDir:
  jsr BasAdvTxtPtr
  jsr BasCmdDir
  jmp @ExecCheckMore
@JmpDel:
  jsr BasAdvTxtPtr
  jsr BasCmdDel
  jmp @ExecCheckMore
@JmpCls:
  jsr BasAdvTxtPtr
  jsr BasCmdCls
  bra @ExecCheckMore
@JmpLocate:
  jsr BasAdvTxtPtr
  jsr BasCmdLocate
  bra @ExecCheckMore
@JmpColor:
  jsr BasAdvTxtPtr
  jsr BasCmdColor
  bra @ExecCheckMore
@JmpSound:
  jsr BasAdvTxtPtr
  jsr BasCmdSound
  bra @ExecCheckMore
@JmpVol:
  jsr BasAdvTxtPtr
  jsr BasCmdVol
  bra @ExecCheckMore
@JmpTime:
  jsr BasAdvTxtPtr
  jsr BasCmdTime
  bra @ExecCheckMore
@JmpDate:
  jsr BasAdvTxtPtr
  jsr BasCmdDate
  bra @ExecCheckMore
@JmpWait:
  jsr BasAdvTxtPtr
  jsr BasCmdWait
  bra @ExecCheckMore
@JmpPause:
  jsr BasAdvTxtPtr
  jsr BasCmdPause
  bra @ExecCheckMore
@JmpBank:
  jsr BasAdvTxtPtr
  jsr BasCmdBank
  bra @ExecCheckMore

@ExecCheckMore:
  ; Check for ':' statement separator
  jsr BasSkipSpaces
  jsr BasGetTokChar
  cmp #CH_COLON
  bne @ExecDone
  jsr BasAdvTxtPtr               ; Skip ':'
  jmp BasExecLine                ; Execute next statement
@ExecDone:
  rts

; ============================================================================
; RUN — Execute program from first line
; ============================================================================

BasCmdRun:
  jsr BasCmdClr
  lda #BAS_FLAG_RUN
  sta BAS_FLAGS

  ; Start at first program line
  lda #<BAS_PRG_START
  sta BAS_CURLINE
  lda #>BAS_PRG_START
  sta BAS_CURLINE + 1

BasRunLoop:
  ; Check if at end of program (CURLINE == PRGEND)
  lda BAS_CURLINE
  cmp BAS_PRGEND
  bne @RunNotEnd
  lda BAS_CURLINE + 1
  cmp BAS_PRGEND + 1
  beq BasRunDone
@RunNotEnd:

  ; Check for Ctrl+C break
  jsr BasCheckBreak

  ; Get line number
  ldy #LINE_NUM
  lda (BAS_CURLINE),y
  sta BAS_LINENUM
  iny
  lda (BAS_CURLINE),y
  sta BAS_LINENUM + 1

  ; Save CURLINE before execution for GOTO/GOSUB detection
  lda BAS_CURLINE
  sta BAS_VARPTR
  lda BAS_CURLINE + 1
  sta BAS_VARPTR + 1

  ; Set TXTPTR to payload
  clc
  lda BAS_CURLINE
  adc #LINE_PAYLOAD
  sta BAS_TXTPTR
  lda BAS_CURLINE + 1
  adc #$00
  sta BAS_TXTPTR + 1

  ; Execute the line
  jsr BasExecLine

  ; Check if END was executed (flags cleared)
  lda BAS_FLAGS
  and #BAS_FLAG_RUN
  beq BasRunDone

  ; Check if GOTO/GOSUB changed CURLINE
  lda BAS_CURLINE
  cmp BAS_VARPTR
  bne BasRunLoop                 ; Changed — re-execute from new CURLINE
  lda BAS_CURLINE + 1
  cmp BAS_VARPTR + 1
  bne BasRunLoop                 ; Changed — re-execute from new CURLINE

  ; Advance to next line by scanning for end of current line
  ldy #LINE_PAYLOAD
@RunScanNull:
  lda (BAS_CURLINE),y
  beq @RunFoundNull
  iny
  bra @RunScanNull
@RunFoundNull:
  iny                            ; Past null terminator
  tya
  clc
  adc BAS_CURLINE
  sta BAS_CURLINE
  lda #$00
  adc BAS_CURLINE + 1
  sta BAS_CURLINE + 1
  jmp BasRunLoop

BasRunDone:
  stz BAS_FLAGS
  rts

; ============================================================================
; Statement Handlers
; ============================================================================

; --- PRINT ---
BasCmdPrint:
  jsr BasSkipSpaces
  jsr BasGetTokChar
  beq @PrintNewline              ; Empty PRINT — just newline
  cmp #CH_COLON
  beq @PrintNewline              ; PRINT: — newline then next statement

@PrintLoop:
  jsr BasSkipSpaces
  jsr BasGetTokChar
  beq @PrintEnd                  ; End of line
  cmp #CH_COLON
  beq @PrintEnd

  ; String literal?
  cmp #CH_QUOTE
  beq @PrintString

  ; CHR(n) — output character directly
  cmp #TOK_CHR
  beq @PrintChr

  ; Otherwise evaluate expression and print number
  jsr BasExpr
  jsr BasPrintInt
  bra @PrintSep

@PrintString:
  jsr BasAdvTxtPtr               ; Skip opening quote
@PrintStrCh:
  jsr BasGetTokChar
  beq @PrintEnd                  ; Unterminated string
  cmp #CH_QUOTE
  beq @PrintStrEnd
  jsr Chrout
  jsr BasAdvTxtPtr
  bra @PrintStrCh
@PrintStrEnd:
  jsr BasAdvTxtPtr               ; Skip closing quote
  bra @PrintSep

@PrintChr:
  jsr BasAdvTxtPtr               ; Skip TOK_CHR
  lda #CH_LPAREN
  jsr BasExpectChar
  jsr BasExpr                    ; n -> BAS_ACC
  lda #CH_RPAREN
  jsr BasExpectChar
  lda BAS_ACC                    ; Output low byte as character
  jsr VideoChroutRaw             ; Raw output — no control-code interception

@PrintSep:
  jsr BasSkipSpaces
  jsr BasGetTokChar
  cmp #CH_SEMICOL
  beq @PrintSemicolon
  cmp #CH_COMMA
  beq @PrintComma
  ; No separator — done, print newline
  bra @PrintNewline

@PrintSemicolon:
  jsr BasAdvTxtPtr               ; Skip ';'
  ; Check if end of statement (suppress newline)
  jsr BasSkipSpaces
  jsr BasGetTokChar
  beq @PrintDone                 ; End of line — suppress newline
  cmp #CH_COLON
  beq @PrintDone                 ; Colon — suppress newline
  bra @PrintLoop

@PrintComma:
  jsr BasAdvTxtPtr               ; Skip ','
  ; Print separator spaces
  lda #CH_SPACE
  jsr Chrout
  jsr Chrout
  bra @PrintLoop

@PrintNewline:
  jsr BasPrintCRLF
@PrintDone:
@PrintEnd:
  rts

; --- INPUT ---
BasCmdInput:
  jsr BasSkipSpaces
  jsr BasGetTokChar

  ; Check for optional prompt string
  cmp #CH_QUOTE
  bne @InputNoPrompt

  ; Print prompt string
  jsr BasAdvTxtPtr
@InputPromptCh:
  jsr BasGetTokChar
  beq @InputPromptDone
  cmp #CH_QUOTE
  beq @InputPromptEnd
  jsr Chrout
  jsr BasAdvTxtPtr
  bra @InputPromptCh
@InputPromptEnd:
  jsr BasAdvTxtPtr               ; Skip closing quote
@InputPromptDone:
  ; Expect semicolon or comma after prompt
  jsr BasSkipSpaces
  jsr BasGetTokChar
  cmp #CH_SEMICOL
  beq @InputSemiSep
  cmp #CH_COMMA
  beq @InputCommaSep
  bra @InputGetVar

@InputSemiSep:
  jsr BasAdvTxtPtr
  ; Print "? " after semicolon-style prompt
  lda #'?'
  jsr Chrout
  lda #CH_SPACE
  jsr Chrout
  bra @InputGetVar

@InputCommaSep:
  jsr BasAdvTxtPtr
  ; No "? " with comma separator
  bra @InputGetVar

@InputNoPrompt:
  ; Print default "? " prompt
  lda #'?'
  jsr Chrout
  lda #CH_SPACE
  jsr Chrout

@InputGetVar:
  jsr BasSkipSpaces
  jsr BasGetTokChar

  ; Must be a variable A-Z
  cmp #'A'
  bcc @InputErr
  cmp #'Z' + 1
  bcs @InputErr

  ; Save variable index
  sec
  sbc #'A'
  asl
  sta BAS_TEMP                   ; Variable offset
  jsr BasAdvTxtPtr               ; Skip variable letter

  ; Save TXTPTR (points into tokenized program line)
  lda BAS_TXTPTR
  pha
  lda BAS_TXTPTR + 1
  pha

@InputRetry:
  ; Read a line of input
  jsr BasReadLine

  ; Point TXTPTR at input buffer for parsing
  lda #<BAS_LINBUF
  sta BAS_TXTPTR
  lda #>BAS_LINBUF
  sta BAS_TXTPTR + 1

  ; Handle optional negative sign
  stz BAS_SIGN
  jsr BasSkipSpaces
  jsr BasGetTokChar
  cmp #CH_MINUS
  bne @InputParse
  lda #$FF
  sta BAS_SIGN
  jsr BasAdvTxtPtr

@InputParse:
  jsr BasParseInt
  bcs @InputBadNum               ; No digits found

  ; Negate if minus was present
  lda BAS_SIGN
  beq @InputStore
  jsr BasMathNeg

@InputStore:
  ; Store in variable
  ldx BAS_TEMP
  lda BAS_ACC
  sta BAS_VARS,x
  lda BAS_ACC + 1
  sta BAS_VARS + 1,x

  ; Restore TXTPTR to tokenized program line
  pla
  sta BAS_TXTPTR + 1
  pla
  sta BAS_TXTPTR
  rts

@InputBadNum:
  lda #<BasStrRedo
  sta BAS_TMP1
  lda #>BasStrRedo
  sta BAS_TMP1 + 1
  jsr BasPrintStr
  bra @InputRetry

@InputErr:
  lda #ERR_SYNTAX
  jmp BasError

; --- LET (also implicit assignment) ---
BasCmdLet:
  jsr BasSkipSpaces
  jsr BasGetTokChar

  ; Must be a variable A-Z
  cmp #'A'
  bcc @LetErr
  cmp #'Z' + 1
  bcs @LetErr

  sec
  sbc #'A'
  asl
  sta BAS_TEMP                   ; Variable offset
  jsr BasAdvTxtPtr               ; Skip variable letter

  jsr BasSkipSpaces
  lda #CH_EQUALS
  jsr BasExpectChar              ; Expect '='

  jsr BasExpr                    ; Evaluate RHS

  ; Store result in variable
  ldx BAS_TEMP
  lda BAS_ACC
  sta BAS_VARS,x
  lda BAS_ACC + 1
  sta BAS_VARS + 1,x
  rts

@LetErr:
  lda #ERR_SYNTAX
  jmp BasError

; --- GOTO ---
BasCmdGoto:
  jsr BasExpr                    ; Evaluate target line number
  lda BAS_ACC
  sta BAS_LINENUM
  lda BAS_ACC + 1
  sta BAS_LINENUM + 1
  jsr BasFindLine
  bcc @GotoErr

  ; Set CURLINE to the found line — run loop will detect the change
  lda BAS_TMP1
  sta BAS_CURLINE
  lda BAS_TMP1 + 1
  sta BAS_CURLINE + 1
  rts

@GotoErr:
  lda #ERR_UNDEF_LINE
  jmp BasError

; --- GOSUB ---
BasCmdGosub:
  ; Push current CURLINE onto GOSUB stack (2 bytes per entry)
  ldx BAS_GOSUBSP
  txa
  clc
  adc #BAS_GOSUB_ENTRY
  cmp #BAS_GOSUBSTK_SIZE + 1
  bcs @GosubFull

  lda BAS_CURLINE
  sta BAS_GOSUBSTK,x
  lda BAS_CURLINE + 1
  sta BAS_GOSUBSTK + 1,x
  txa
  clc
  adc #BAS_GOSUB_ENTRY
  sta BAS_GOSUBSP

  ; Now do GOTO (sets CURLINE to target)
  jmp BasCmdGoto

@GosubFull:
  lda #ERR_OUT_OF_MEM
  jmp BasError

; --- RETURN ---
BasCmdReturn:
  ldx BAS_GOSUBSP
  beq @RetErr

  ; Pop CURLINE from GOSUB stack
  dex
  dex
  lda BAS_GOSUBSTK,x
  sta BAS_CURLINE
  lda BAS_GOSUBSTK + 1,x
  sta BAS_CURLINE + 1
  stx BAS_GOSUBSP

  ; Advance CURLINE to the line AFTER the GOSUB line
  ; so the run loop continues from there
  ldy #LINE_PAYLOAD
@RetScan:
  lda (BAS_CURLINE),y
  beq @RetScanDone
  iny
  bra @RetScan
@RetScanDone:
  iny                            ; Past null
  tya
  clc
  adc BAS_CURLINE
  sta BAS_CURLINE
  lda #$00
  adc BAS_CURLINE + 1
  sta BAS_CURLINE + 1
  ; CURLINE now differs from saved VARPTR, so run loop re-executes
  rts

@RetErr:
  lda #ERR_RET_NO_GOSUB
  jmp BasError

; --- IF...THEN ---
BasCmdIf:
  jsr BasExpr                    ; Evaluate condition
  jsr BasSkipSpaces

  ; Expect THEN
  jsr BasGetTokChar
  cmp #TOK_THEN
  bne @IfSyntax
  jsr BasAdvTxtPtr

  ; Check condition: 0 = false, nonzero = true
  lda BAS_ACC
  ora BAS_ACC + 1
  beq @IfFalse

  ; True — check if THEN is followed by a line number (implicit GOTO)
  jsr BasSkipSpaces
  jsr BasGetTokChar
  cmp #'0'
  bcc @IfExecRest
  cmp #'9' + 1
  bcs @IfExecRest
  ; It's a digit — treat as GOTO line number
  jmp BasCmdGoto

@IfExecRest:
  ; Execute rest of line as statement(s)
  jmp BasExecLine

@IfFalse:
  ; Skip rest of line (don't execute THEN clause)
  rts

@IfSyntax:
  lda #ERR_SYNTAX
  jmp BasError

; --- FOR ---
BasCmdFor:
  jsr BasSkipSpaces
  jsr BasGetTokChar

  ; Must be a variable
  cmp #'A'
  bcs @ForVarOk1
  jmp @ForErr
@ForVarOk1:
  cmp #'Z' + 1
  bcc @ForVarOk2
  jmp @ForErr
@ForVarOk2:

  sec
  sbc #'A'
  asl
  sta BAS_TEMP                   ; Variable offset
  jsr BasAdvTxtPtr

  ; Expect '='
  jsr BasSkipSpaces
  lda #CH_EQUALS
  jsr BasExpectChar

  ; Evaluate initial value and store in variable
  jsr BasExpr
  ldx BAS_TEMP
  lda BAS_ACC
  sta BAS_VARS,x
  lda BAS_ACC + 1
  sta BAS_VARS + 1,x

  ; Expect TO
  jsr BasSkipSpaces
  jsr BasGetTokChar
  cmp #TOK_TO
  bne @ForErr
  jsr BasAdvTxtPtr

  ; Evaluate limit — store temporarily in SCRATCH
  jsr BasExpr
  lda BAS_ACC
  sta BAS_SCRATCH
  lda BAS_ACC + 1
  sta BAS_SCRATCH + 1

  ; Check for optional STEP — default is 1
  lda #$01
  sta BAS_SCRATCH2
  stz BAS_SCRATCH2 + 1

  jsr BasSkipSpaces
  jsr BasGetTokChar
  cmp #TOK_STEP
  bne @ForNoStep
  jsr BasAdvTxtPtr
  jsr BasExpr
  lda BAS_ACC
  sta BAS_SCRATCH2
  lda BAS_ACC + 1
  sta BAS_SCRATCH2 + 1
@ForNoStep:

  ; Check room on FOR stack
  ldx BAS_FORSP
  txa
  clc
  adc #BAS_FOR_ENTRY
  cmp #BAS_FORSTK_SIZE + 1
  bcs @ForStackFull

  ; Build FOR stack entry (16 bytes per entry):
  ;  +0: var_offset (1)
  ;  +1: limit_lo (1)
  ;  +2: limit_hi (1)
  ;  +3: step_lo (1)
  ;  +4: step_hi (1)
  ;  +5: body_start_lo (1) — first line of loop body (next line after FOR)
  ;  +6: body_start_hi (1)
  ; +7..+15: unused padding

  lda BAS_TEMP
  sta BAS_FORSTK,x               ; +0: var offset
  lda BAS_SCRATCH
  sta BAS_FORSTK + 1,x           ; +1: limit lo
  lda BAS_SCRATCH + 1
  sta BAS_FORSTK + 2,x           ; +2: limit hi
  lda BAS_SCRATCH2
  sta BAS_FORSTK + 3,x           ; +3: step lo
  lda BAS_SCRATCH2 + 1
  sta BAS_FORSTK + 4,x           ; +4: step hi
  ; body_start = next line after the FOR line (scan for null)
  ldy #LINE_PAYLOAD
@ForScanBody:
  lda (BAS_CURLINE),y
  beq @ForScanDone
  iny
  bra @ForScanBody
@ForScanDone:
  iny                            ; Past null terminator
  tya
  clc
  adc BAS_CURLINE
  pha
  lda #$00
  adc BAS_CURLINE + 1
  sta BAS_FORSTK + 6,x           ; +6: body_start hi
  pla
  sta BAS_FORSTK + 5,x           ; +5: body_start lo

  txa
  clc
  adc #BAS_FOR_ENTRY
  sta BAS_FORSP
  rts

@ForStackFull:
  lda #ERR_OUT_OF_MEM
  jmp BasError

@ForErr:
  lda #ERR_SYNTAX
  jmp BasError

; --- NEXT ---
BasCmdNext:
  jsr BasSkipSpaces
  jsr BasGetTokChar

  ; Must be a variable
  cmp #'A'
  bcs @NextVarOk1
  jmp @NextErr
@NextVarOk1:
  cmp #'Z' + 1
  bcc @NextVarOk2
  jmp @NextErr
@NextVarOk2:

  sec
  sbc #'A'
  asl
  sta BAS_TEMP                   ; Variable offset
  jsr BasAdvTxtPtr

  ; Search FOR stack from top for matching variable
  ldx BAS_FORSP
  beq @NextNoFor

@NextSearch:
  dex                            ; Back up past padding and entries
  txa
  sec
  sbc #BAS_FOR_ENTRY - 1         ; Point to start of this entry
  tax
  bmi @NextNoFor
  lda BAS_FORSTK,x               ; var_offset
  cmp BAS_TEMP
  beq @NextFound
  ; Not this entry — keep searching
  bra @NextSearch

@NextFound:
  ; Add step to variable
  lda BAS_FORSTK + 3,x           ; step lo
  sta BAS_AUX
  lda BAS_FORSTK + 4,x           ; step hi
  sta BAS_AUX + 1

  ldy BAS_TEMP                   ; var offset
  clc
  lda BAS_VARS,y
  adc BAS_AUX
  sta BAS_VARS,y
  sta BAS_ACC
  lda BAS_VARS + 1,y
  adc BAS_AUX + 1
  sta BAS_VARS + 1,y
  sta BAS_ACC + 1

  ; Load limit into AUX for comparison
  lda BAS_FORSTK + 1,x           ; limit lo
  sta BAS_AUX
  lda BAS_FORSTK + 2,x           ; limit hi
  sta BAS_AUX + 1

  ; Check if loop is done:
  ; If step > 0: done when var > limit (AUX)
  ; If step < 0: done when var < limit (AUX)
  lda BAS_FORSTK + 4,x           ; step hi
  bmi @NextStepNeg

  ; Step positive: compare var (ACC) vs limit (AUX)
  ; Done if ACC > AUX (i.e., AUX < ACC)
  jsr BasCmpAuxAcc
  bmi @NextDone                  ; AUX < ACC means var > limit
  bra @NextLoop                  ; Continue loop

@NextStepNeg:
  ; Step negative: done if var < limit
  ; Done if ACC < AUX (i.e., AUX > ACC)
  jsr BasCmpAuxAcc
  beq @NextLoop
  bpl @NextDone                  ; AUX > ACC means var < limit

@NextLoop:
  ; Continue loop — set CURLINE to body start
  ; Keep the FOR entry on the stack (FORSP stays where it is)
  lda BAS_FORSTK + 5,x           ; body_start lo
  sta BAS_CURLINE
  lda BAS_FORSTK + 6,x           ; body_start hi
  sta BAS_CURLINE + 1
  ; Invalidate saved CURLINE so run loop always detects the change,
  ; even when body_start == current line (empty loop body / NEXT on next line)
  lda #$FF
  sta BAS_VARPTR
  sta BAS_VARPTR + 1
  rts

@NextDone:
  ; Loop complete — remove this FOR entry from stack
  stx BAS_FORSP                  ; Pop down to this entry (removes it)
  rts

@NextNoFor:
@NextErr:
  lda #ERR_NEXT_NO_FOR
  jmp BasError

; --- END ---
BasCmdEnd:
  stz BAS_FLAGS                  ; Clear run flag
  rts                            ; Returns to BasRunLoop which checks flags

; --- SYS ---
; SYS <address> — Call machine code at 16-bit address, RTS returns to BASIC
BasCmdSys:
  jsr BasExpr                    ; Evaluate address expression → BAS_ACC
  ; Use BAS_TMP2 as the indirect jump target
  lda BAS_ACC
  sta BAS_TMP2
  lda BAS_ACC + 1
  sta BAS_TMP2 + 1
  jmp (BAS_TMP2)                 ; JSR-like: callee RTSes back to caller

; --- LOAD ---
; LOAD "filename" — Load from CF filesystem
; LOAD (no arg)   — Load via serial ASCII transfer
BasCmdLoad:
  jsr BasSkipSpaces
  jsr BasGetTokChar
  cmp #CH_QUOTE
  beq @LoadCF

  ; No filename — serial ASCII load
  lda HW_PRESENT
  and #HW_SC
  beq @LoadNoDev
  jsr AsciiLoad
  bcs @LoadErr
  ; Update BAS_PRGEND from XFER_PTR (points past last byte written)
  lda XFER_PTR
  sta BAS_PRGEND
  lda XFER_PTR + 1
  sta BAS_PRGEND + 1
  rts

@LoadNoDev:
  jmp BasPrintNoDevice

@LoadCF:
  lda HW_PRESENT
  and #HW_CF
  beq @LoadNoDev
  ; Parse quoted filename into STR_PTR for FsLoadFile
  jsr BasAdvTxtPtr               ; Skip opening quote
  ; Point STR_PTR at current position in tokenized text
  lda BAS_TXTPTR
  sta STR_PTR
  lda BAS_TXTPTR + 1
  sta STR_PTR + 1
  ; Advance TXTPTR past the filename to closing quote
@LoadScanName:
  jsr BasGetTokChar
  beq @LoadNameDone              ; End of line (unterminated — use what we have)
  cmp #CH_QUOTE
  beq @LoadNameEnd
  jsr BasAdvTxtPtr
  bra @LoadScanName
@LoadNameEnd:
  ; Null-terminate the filename in the token buffer (overwrite closing quote)
  ldy #$00
  lda #$00
  sta (BAS_TXTPTR),y
  jsr BasAdvTxtPtr               ; Skip past the closing quote
@LoadNameDone:
  ; Call filesystem load
  jsr FsLoadFile
  bcs @LoadErr
  ; Update BAS_PRGEND: PROGRAM_START + FS_FILE_SIZE
  lda #<PROGRAM_START
  clc
  adc FS_FILE_SIZE
  sta BAS_PRGEND
  lda #>PROGRAM_START
  adc FS_FILE_SIZE + 1
  sta BAS_PRGEND + 1
  rts

@LoadErr:
  lda #<BasStrLoadErr
  sta BAS_TMP1
  lda #>BasStrLoadErr
  sta BAS_TMP1 + 1
  jsr BasPrintStr
  rts

; --- SAVE ---
; SAVE "filename" — Save to CF filesystem
; SAVE (no arg)   — Save via serial ASCII transfer
BasCmdSave:
  jsr BasSkipSpaces
  jsr BasGetTokChar
  cmp #CH_QUOTE
  beq @SaveCF

  ; No filename — serial ASCII save
  lda HW_PRESENT
  and #HW_SC
  beq @SaveNoDev
  jsr AsciiSave
  rts

@SaveNoDev:
  jmp BasPrintNoDevice

@SaveCF:
  lda HW_PRESENT
  and #HW_CF
  beq @SaveNoDev
  ; Parse quoted filename into STR_PTR for FsSaveFile
  jsr BasAdvTxtPtr               ; Skip opening quote
  lda BAS_TXTPTR
  sta STR_PTR
  lda BAS_TXTPTR + 1
  sta STR_PTR + 1
  ; Advance TXTPTR past the filename to closing quote
@SaveScanName:
  jsr BasGetTokChar
  beq @SaveNameDone
  cmp #CH_QUOTE
  beq @SaveNameEnd
  jsr BasAdvTxtPtr
  bra @SaveScanName
@SaveNameEnd:
  ldy #$00
  lda #$00
  sta (BAS_TXTPTR),y
  jsr BasAdvTxtPtr               ; Skip past the closing quote
@SaveNameDone:
  ; Calculate file size = BAS_PRGEND - PROGRAM_START
  lda BAS_PRGEND
  sec
  sbc #<PROGRAM_START
  sta FS_FILE_SIZE
  lda BAS_PRGEND + 1
  sbc #>PROGRAM_START
  sta FS_FILE_SIZE + 1
  ; Call filesystem save
  jsr FsSaveFile
  bcs @SaveErr
  rts

@SaveErr:
  lda #<BasStrSaveErr
  sta BAS_TMP1
  lda #>BasStrSaveErr
  sta BAS_TMP1 + 1
  jsr BasPrintStr
  rts

; --- DIR ---
; DIR — Print directory listing from CF
BasCmdDir:
  lda HW_PRESENT
  and #HW_CF
  bne @DirHasCF
  jmp BasPrintNoDevice
@DirHasCF:
  jsr FsDirectory
  rts

; --- DEL ---
; DEL "filename" — Delete a file from CF
BasCmdDel:
  lda HW_PRESENT
  and #HW_CF
  bne @DelHasCF
  jmp BasPrintNoDevice
@DelHasCF:
  jsr BasSkipSpaces
  jsr BasGetTokChar
  cmp #CH_QUOTE
  bne @DelErr

  ; Parse quoted filename into STR_PTR for FsDeleteFile
  jsr BasAdvTxtPtr               ; Skip opening quote
  lda BAS_TXTPTR
  sta STR_PTR
  lda BAS_TXTPTR + 1
  sta STR_PTR + 1
  ; Advance TXTPTR past the filename to closing quote
@DelScanName:
  jsr BasGetTokChar
  beq @DelNameDone
  cmp #CH_QUOTE
  beq @DelNameEnd
  jsr BasAdvTxtPtr
  bra @DelScanName
@DelNameEnd:
  ldy #$00
  lda #$00
  sta (BAS_TXTPTR),y
  jsr BasAdvTxtPtr               ; Skip past the closing quote
@DelNameDone:
  ; Call filesystem delete
  jsr FsDeleteFile
  bcs @DelErr
  rts

@DelErr:
  lda #<BasStrDelErr
  sta BAS_TMP1
  lda #>BasStrDelErr
  sta BAS_TMP1 + 1
  jsr BasPrintStr
  rts

; --- CLS ---
BasCmdCls:
  jsr VideoClear
  rts

; --- LOCATE row, col ---
BasCmdLocate:
  jsr BasExpr                    ; row -> BAS_ACC
  lda BAS_ACC
  sta BAS_TEMP                   ; save row
  jsr BasSkipSpaces
  lda #CH_COMMA
  jsr BasExpectChar
  jsr BasExpr                    ; col -> BAS_ACC
  lda BAS_ACC
  tax                            ; X = col
  ldy BAS_TEMP                   ; Y = row
  jsr VideoSetCursor
  rts

; --- COLOR fg, bg ---
BasCmdColor:
  jsr BasExpr                    ; fg -> BAS_ACC (0-15)
  lda BAS_ACC
  and #$0F
  asl a
  asl a
  asl a
  asl a                          ; shift to high nibble
  sta BAS_TEMP
  jsr BasSkipSpaces
  lda #CH_COMMA
  jsr BasExpectChar
  jsr BasExpr                    ; bg -> BAS_ACC (0-15)
  lda BAS_ACC
  and #$0F
  ora BAS_TEMP                   ; combine fg|bg
  jsr VideoSetColor
  rts

; --- SOUND voice, freq, dur ---
; freq is in Hz; converted to SID register via: reg = Hz*16 + Hz - Hz/4
; Approximation of Hz * 2^24 / 1000000 ≈ Hz * 16.75 (0.16% error)
BasCmdSound:
  lda HW_PRESENT
  and #HW_SID
  bne @SoundStart
  rts
@SoundStart:
  jsr BasExpr                    ; voice (1-3) -> BAS_ACC
  lda BAS_ACC
  dec a                          ; convert to 0-indexed
  sta BAS_TEMP                   ; save voice
  jsr BasSkipSpaces
  lda #CH_COMMA
  jsr BasExpectChar
  jsr BasExpr                    ; freq (Hz) -> BAS_ACC
  ; --- Convert Hz to SID register value ---
  lda BAS_ACC                    ; save Hz in BAS_SCRATCH
  sta BAS_SCRATCH
  lda BAS_ACC + 1
  sta BAS_SCRATCH + 1
  asl BAS_ACC                    ; BAS_ACC = Hz << 4 (multiply by 16)
  rol BAS_ACC + 1
  asl BAS_ACC
  rol BAS_ACC + 1
  asl BAS_ACC
  rol BAS_ACC + 1
  asl BAS_ACC
  rol BAS_ACC + 1
  clc                            ; BAS_ACC += Hz (now Hz * 17)
  lda BAS_ACC
  adc BAS_SCRATCH
  sta BAS_ACC
  lda BAS_ACC + 1
  adc BAS_SCRATCH + 1
  sta BAS_ACC + 1
  lsr BAS_SCRATCH + 1            ; BAS_SCRATCH = Hz / 4
  ror BAS_SCRATCH
  lsr BAS_SCRATCH + 1
  ror BAS_SCRATCH
  sec                            ; BAS_ACC -= Hz/4 (now Hz * 16.75)
  lda BAS_ACC
  sbc BAS_SCRATCH
  sta BAS_ACC
  lda BAS_ACC + 1
  sbc BAS_SCRATCH + 1
  sta BAS_ACC + 1
  ; --- SID register value now in BAS_ACC ---
  lda BAS_ACC + 1
  pha                            ; save regHi on stack
  lda BAS_ACC
  pha                            ; save regLo on stack
  jsr BasSkipSpaces
  lda #CH_COMMA
  jsr BasExpectChar
  jsr BasExpr                    ; dur (centiseconds) -> BAS_ACC
  ; BAS_ACC holds dur; stack holds freq; BAS_TEMP holds voice
  pla                            ; freqLo
  tax                            ; X = freqLo
  pla                            ; freqHi
  tay                            ; Y = freqHi
  lda BAS_TEMP                   ; A = voice (0-indexed)
  jsr SidPlayNote
  lda BAS_ACC                    ; A = dur_lo (BAS_ACC not changed by SidPlayNote)
  ldx BAS_ACC + 1                ; X = dur_hi
  jsr SysDelay
  jsr SidSilence
  rts

; --- VOL n ---
BasCmdVol:
  lda HW_PRESENT
  and #HW_SID
  bne @VolStart
  rts
@VolStart:
  jsr BasExpr
  lda BAS_ACC
  jsr SidSetVolume
  rts

; BasPrint2Digit — Print A as a 2-digit decimal with leading zero
; Input: A = value 0-99
; Modifies: A, X, Flags
BasPrint2Digit:
  ldx #0
@P2DLoop:
  cmp #10
  bcc @P2DDone
  sbc #10                        ; carry already set from cmp
  inx
  bra @P2DLoop
@P2DDone:
  pha                            ; save units digit
  txa
  ora #'0'                       ; tens digit as ASCII
  jsr Chrout
  pla
  ora #'0'                       ; units digit as ASCII
  jsr Chrout
  rts

; --- TIME ---
BasCmdTime:
  lda HW_PRESENT
  and #HW_RTC
  bne @TimeHasRTC
  jmp BasPrintNoDevice
@TimeHasRTC:
  jsr RtcReadTime                ; A=hours, X=minutes, Y=seconds
  phy                            ; save seconds
  phx                            ; save minutes
  jsr BasPrint2Digit             ; print hours
  lda #':'
  jsr Chrout
  pla                            ; restore minutes
  jsr BasPrint2Digit
  lda #':'
  jsr Chrout
  pla                            ; restore seconds
  jsr BasPrint2Digit
  jsr BasPrintCRLF
  rts

; --- DATE ---
BasCmdDate:
  lda HW_PRESENT
  and #HW_RTC
  bne @DateHasRTC
  jmp BasPrintNoDevice
@DateHasRTC:
  jsr RtcReadDate                ; A=day, X=month, Y=year; RTC_BUF_CENT=century
  pha                            ; save day
  phx                            ; save month
  phy                            ; save year (pushed last, popped first)
  lda RTC_BUF_CENT
  jsr BasPrint2Digit             ; print century
  pla                            ; restore year
  jsr BasPrint2Digit             ; print year (CCYY together)
  lda #'-'
  jsr Chrout
  pla                            ; restore month
  jsr BasPrint2Digit
  lda #'-'
  jsr Chrout
  pla                            ; restore day
  jsr BasPrint2Digit
  jsr BasPrintCRLF
  rts

; --- WAIT addr, mask ---
BasCmdWait:
  jsr BasExpr                    ; addr -> BAS_ACC
  lda BAS_ACC
  sta BAS_TMP2
  lda BAS_ACC + 1
  sta BAS_TMP2 + 1
  jsr BasSkipSpaces
  lda #CH_COMMA
  jsr BasExpectChar
  jsr BasExpr                    ; mask -> BAS_ACC
  lda BAS_ACC
  sta BAS_TEMP
@WaitPoll:
  jsr BasCheckBreak              ; allow Ctrl+C to abort
  ldy #0
  lda (BAS_TMP2),y
  and BAS_TEMP
  beq @WaitPoll
  rts

; --- PAUSE n ---
BasCmdPause:
  jsr BasExpr
  lda BAS_ACC
  ldx BAS_ACC + 1
  jsr SysDelay
  rts

; --- BANK n ---
BasCmdBank:
  lda HW_PRESENT
  and #HW_RAM_L
  bne @BankHasRAM
  jmp BasPrintNoDevice
@BankHasRAM:
  jsr BasExpr
  lda BAS_ACC
  sta RAM_BANK_L
  rts

; --- BRK ---
BasCmdBrk:
  stz BAS_FLAGS                  ; Clear run flag
  brk                            ; Trigger BRK → IRQ vector → Wozmon

; --- NEW ---
BasCmdNew:
  ; Set program end to program start (empty program)
  lda #<BAS_PRG_START
  sta BAS_PRGEND
  lda #>BAS_PRG_START
  sta BAS_PRGEND + 1
  ; Write end marker
  ldy #LINE_NEXT
  lda #$00
  sta (BAS_PRGEND),y
  iny
  sta (BAS_PRGEND),y
  ; Clear variables
  jsr BasCmdClr
  stz BAS_FLAGS
  jmp BasMainLoop

; --- LIST ---
BasCmdList:
  ; Start at beginning of program
  lda #<BAS_PRG_START
  sta BAS_TMP1
  lda #>BAS_PRG_START
  sta BAS_TMP1 + 1

@ListLoop:
  ; Check if at end of program (TMP1 == PRGEND)
  lda BAS_TMP1
  cmp BAS_PRGEND
  bne @ListNotEnd
  lda BAS_TMP1 + 1
  cmp BAS_PRGEND + 1
  beq @ListDone
@ListNotEnd:

  ; Check for Ctrl+C break
  jsr BasCheckBreak

  ; Print line number
  ldy #LINE_NUM
  lda (BAS_TMP1),y
  sta BAS_ACC
  iny
  lda (BAS_TMP1),y
  sta BAS_ACC + 1
  jsr BasPrintInt

  ; Print space
  lda #CH_SPACE
  jsr Chrout

  ; Detokenize and print the payload
  ; Set TXTPTR to payload
  clc
  lda BAS_TMP1
  adc #LINE_PAYLOAD
  sta BAS_TXTPTR
  lda BAS_TMP1 + 1
  adc #$00
  sta BAS_TXTPTR + 1

  jsr BasDetokenize

  ; Print CRLF
  jsr BasPrintCRLF

  ; Advance to next line by scanning for null terminator
  ldy #LINE_PAYLOAD
@ListScan:
  lda (BAS_TMP1),y
  beq @ListScanDone
  iny
  bra @ListScan
@ListScanDone:
  iny                            ; Past null
  tya
  clc
  adc BAS_TMP1
  sta BAS_TMP1
  lda #$00
  adc BAS_TMP1 + 1
  sta BAS_TMP1 + 1
  jmp @ListLoop

@ListDone:
  rts

; --- POKE addr, value ---
BasCmdPoke:
  jsr BasExpr                    ; Evaluate address
  lda BAS_ACC
  sta BAS_TMP2
  lda BAS_ACC + 1
  sta BAS_TMP2 + 1

  ; Expect comma
  jsr BasSkipSpaces
  jsr BasGetTokChar
  cmp #CH_COMMA
  bne @PokeErr
  jsr BasAdvTxtPtr

  jsr BasExpr                    ; Evaluate value (low byte used)
  lda BAS_ACC
  ldy #$00
  sta (BAS_TMP2),y
  rts

@PokeErr:
  lda #ERR_SYNTAX
  jmp BasError

; ============================================================================
; Keyword Table
; ============================================================================
; Format: null-terminated keyword string, then token byte.
; Longer keywords first to prevent partial matches (e.g. GOSUB before GOTO).
; Table terminated by a lone $00.

BasKeywordTable:
  .byte "RETURN", $00, TOK_RETURN
  .byte "LOCATE", $00, TOK_LOCATE
  .byte "PRINT",  $00, TOK_PRINT
  .byte "INPUT",  $00, TOK_INPUT
  .byte "GOSUB",  $00, TOK_GOSUB
  .byte "SOUND",  $00, TOK_SOUND
  .byte "PAUSE",  $00, TOK_PAUSE
  .byte "COLOR",  $00, TOK_COLOR
  .byte "GOTO",   $00, TOK_GOTO
  .byte "THEN",   $00, TOK_THEN
  .byte "STEP",   $00, TOK_STEP
  .byte "NEXT",   $00, TOK_NEXT
  .byte "PEEK",   $00, TOK_PEEK
  .byte "POKE",   $00, TOK_POKE
  .byte "SAVE",   $00, TOK_SAVE
  .byte "LOAD",   $00, TOK_LOAD
  .byte "LIST",   $00, TOK_LIST
  .byte "BANK",   $00, TOK_BANK
  .byte "WAIT",   $00, TOK_WAIT
  .byte "TIME",   $00, TOK_TIME
  .byte "DATE",   $00, TOK_DATE
  .byte "LET",    $00, TOK_LET
  .byte "FOR",    $00, TOK_FOR
  .byte "REM",    $00, TOK_REM
  .byte "END",    $00, TOK_END
  .byte "RUN",    $00, TOK_RUN
  .byte "NEW",    $00, TOK_NEW
  .byte "CLR",    $00, TOK_CLR
  .byte "ABS",    $00, TOK_ABS
  .byte "RND",    $00, TOK_RND
  .byte "NOT",    $00, TOK_NOT
  .byte "AND",    $00, TOK_AND
  .byte "MOD",    $00, TOK_MOD
  .byte "SYS",    $00, TOK_SYS
  .byte "DIR",    $00, TOK_DIR
  .byte "DEL",    $00, TOK_DEL
  .byte "BRK",    $00, TOK_BRK
  .byte "CLS",    $00, TOK_CLS
  .byte "VOL",    $00, TOK_VOL
  .byte "JOY",    $00, TOK_JOY
  .byte "SGN",    $00, TOK_SGN
  .byte "CHR",    $00, TOK_CHR
  .byte "IF",     $00, TOK_IF
  .byte "TO",     $00, TOK_TO
  .byte "OR",     $00, TOK_OR
  .byte $00                       ; End of table sentinel

; ============================================================================
; BasPrintNoDevice — Print "?NO DEVICE" and return
; Used by hardware-guarded commands when device is absent
; ============================================================================
BasPrintNoDevice:
  lda #<BasStrNoDevice
  sta BAS_TMP1
  lda #>BasStrNoDevice
  sta BAS_TMP1 + 1
  jsr BasPrintStr
  rts

; ============================================================================
; String Data
; ============================================================================

BasStrWelcome:  .byte CH_CR, CH_LF, "COB BASIC v1.0", CH_CR, CH_LF, $00
BasStrOK:       .byte CH_CR, CH_LF, "OK", CH_CR, CH_LF, $00
BasStrFree:     .byte " BYTES FREE", $00
BasStrError:    .byte " ERROR", $00
BasStrIn:       .byte " IN ", $00
BasStrRedo:     .byte "?REDO", CH_CR, CH_LF, $00
BasStrPrompt:   .byte "? ", $00
BasStrLoadErr:  .byte CH_CR, CH_LF, "?LOAD ERROR", CH_CR, CH_LF, $00
BasStrSaveErr:  .byte CH_CR, CH_LF, "?SAVE ERROR", CH_CR, CH_LF, $00
BasStrDelErr:   .byte CH_CR, CH_LF, "?DEL ERROR", CH_CR, CH_LF, $00
BasStrNoDevice: .byte CH_CR, CH_LF, "?NO DEVICE", CH_CR, CH_LF, $00

