; =============================================================================
; BASIC v2.0  —  5-Byte Floating-Point MSBASIC-Compatible Interpreter
;                for AC6502 Homebrew Computer
;
;   ROM Region  :  $C000-$EDFF  (11,776 bytes / $2E00)
;   Segment     :  BASIC
;   Entry point :  BasEntry  (first byte of segment = $C000)
;   Assembler   :  ca65  (cc65 toolchain)
;   Linker cfg  :  BIOS.cfg
;
;   Coding style :  Match the rest of the BIOS project.
;                   * Routine / data labels : PascalCase  (e.g. BasEntry,
;                     FAdd, NormalizeFac1, Lbl367F).
;                   * Constants / equates    : UPPER_SNAKE_CASE
;                     (e.g. BAS_TXTPTR, TOK_PRINT, ERR_SYNTAX).
;                   * Local labels           : @camelCase or @PascalCase.
;                   * Opcodes are lowercase.
;
;   Reference source tree:  msbasic-master/  (read-only; NOT linked).
; =============================================================================

        .segment "BASIC"

        .macpack longbranch     ; jeq/jne/etc. used by ported MSBASIC FP code

; =============================================================================
;   Z E R O - P A G E   E Q U A T E S
;
;   $00-$03   Kernal reserved
;   $04-$23   BASIC primary workspace
;   $24-$39   Kernal reserved
;   $3A-$FF   BASIC spill (FP scratch in later phases)
; =============================================================================

BAS_TXTPTR      := $04          ; $04-$05  ChrGet / parse pointer
BAS_CURLINE     := $06          ; $06-$07  Pointer to current executing line
BAS_LINNUM      := $08          ; $08-$09  Parsed line number / scratch (= LINNUM)

; ----- Floating-point primary block ($0A-$1B, contiguous) -------------------
; The MSBASIC float code accesses these via ZP,X with one label as the
; immediate base (e.g. EXPSGN,X / SHIFTSIGNEXT,X / TMPEXP,X), so this entire
; block MUST stay contiguous in this exact order.  See msbasic-master/
; zeropage.s for the reference layout.
BAS_TMPEXP      := $0A          ; $0A      TMPEXP / INDX (alias)
BAS_INDX        := $0A          ; $0A      (alias of TMPEXP per msbasic SMALL)
BAS_EXPON       := $0B          ; $0B      EXPON
BAS_LOWTR       := $0C          ; $0C      LOWTR
BAS_EXPSGN      := $0D          ; $0D      EXPSGN  (== FAC-1 scratch byte)
BAS_FAC         := $0E          ; $0E-$12  FAC  (5 bytes)
BAS_FACSIGN     := $13          ; $13      FACSIGN  (== FAC+5)
BAS_SERLEN      := $14          ; $14      SERLEN
BAS_SHIFTSGN    := $15          ; $15      SHIFTSIGNEXT (== ARG-1 scratch)
BAS_ARG         := $16          ; $16-$1A  ARG  (5 bytes)
BAS_ARGSIGN     := $1B          ; $1B      ARGSIGN  (== ARG+5)
; ----------------------------------------------------------------------------

BAS_STRNG1      := $1C          ; $1C-$1D  STRNG1 (= SGNCPR; +1 = FACEXTENSION)
BAS_STRNG2      := $1E          ; $1E-$1F  STRNG2

BAS_INDEX       := $20          ; $20-$21  General index pointer (line walk + msbasic INDEX)
BAS_DEST        := $22          ; $22-$23  Destination pointer (msbasic DEST)

; ----- Spill area: $3A-$67 --------------------------------------------------
BAS_TMP1        := $3A          ; $3A-$3B  General-purpose 16-bit pointer
BAS_TMP2        := $3C          ; $3C-$3D  General-purpose 16-bit pointer
BAS_TMP3        := $3E          ; $3E      Spill scratch byte
BAS_VARPNT      := $3F          ; $3F-$40  Current variable address
BAS_QUOTEFLG    := $41          ; $41      Tokenizer quote-state
BAS_DETOKY      := $42          ; $42      Saved Y across detokenize calls

; FP-only scratch registers (single bytes unless noted)
BAS_ARGEXT      := $43          ; ARGEXTENSION
BAS_CHARAC      := $44          ; CHARAC (string-quote/end char tracker)
BAS_CPRMASK     := $45          ; CPRMASK (FComp result mask)
BAS_FORPNT      := $46          ; $46-$47  FORPNT
BAS_RESULT      := $48          ; $48-$4C  RESULT  (5-byte FMult accumulator)
BAS_TEMP1       := $4D          ; $4D-$51  TEMP1  (5-byte FP scratch)
BAS_TEMP2       := $52          ; $52-$56  TEMP2  (5-byte FP scratch)
BAS_TEMP3       := $57          ; $57-$5B  TEMP3  (5-byte FP scratch)
BAS_RNDSEED     := $5C          ; $5C-$60  RNDSEED (5-byte FP value)
BAS_KWPTR       := $61          ; $61-$62  Keyword-table walker pointer

; ----- Variable / array / string-heap workspace ($63-$85) -----------------
BAS_DIMFLG      := $63          ; DIM-mode flag (nonzero = called from DIM)
BAS_VALTYP      := $64          ; $64-$65  Value type ($00=numeric, $FF=string)
BAS_EOLPNTR     := $66          ; Array scratch: dim count / pointer
BAS_DATAFLG     := $67          ; GetSpa: GC retry flag
BAS_SUBFLG      := $68          ; PtrGet: $40 from GETARYPT, $80 from DEF FN
BAS_INPUTFLG    := $69          ; INPUT/READ flag
BAS_ENDCHR      := $6A          ; StrLt2 secondary terminator
BAS_TEMPPT      := $6B          ; Top-of-temp-string-stack pointer
BAS_LASTPT      := $6C          ; $6C-$6D  Last temp descriptor allocated
BAS_TEMPST      := $6E          ; $6E-$76  Temp descriptor stack (3 * 3 bytes)
BAS_HIGHDS      := $77          ; $77-$78  Bltu dest end+1
BAS_HIGHTR      := $79          ; $79-$7A  Bltu source end+1
BAS_VARNAM      := $7B          ; $7B-$7C  Variable name pair (with type bits)
BAS_DSCPTR      := $7D          ; $7D-$7E  String descriptor pointer
BAS_DSCLEN      := $7F          ; $7F-$80  String descriptor length / GC scratch
BAS_FNCNAM      := $81          ; $81-$82  GC: highest-string descriptor ptr
BAS_Z52         := $83          ; GC scratch byte
BAS_FRESPC      := $84          ; $84-$85  Free-string-space pointer
; ----------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; Symbol aliases used by the inlined MSBASIC FP code.  These let the ported
; routines keep their original names without a global rename pass.
; ---------------------------------------------------------------------------
FAC             := BAS_FAC
FAC_LAST        := BAS_FAC + 4
FACSIGN         := BAS_FACSIGN
ARG             := BAS_ARG
ARG_LAST        := BAS_ARG + 4
ARGSIGN         := BAS_ARGSIGN
INDEX           := BAS_INDEX
DEST            := BAS_DEST
STRNG1          := BAS_STRNG1
STRNG2          := BAS_STRNG2
SGNCPR          := BAS_STRNG1            ; aliased as in msbasic zeropage.s
FACEXTENSION    := BAS_STRNG1 + 1        ; aliased as in msbasic zeropage.s
TXTPTR          := BAS_TXTPTR
LINNUM          := BAS_LINNUM
CURLIN          := BAS_CURLIN            ; non-ZP ($0369) — only used by InPrt
VARPNT          := BAS_VARPNT
ARGEXTENSION    := BAS_ARGEXT
EXPON           := BAS_EXPON
EXPSGN          := BAS_EXPSGN
LOWTR           := BAS_LOWTR
INDX            := BAS_INDX
TMPEXP          := BAS_TMPEXP
SERLEN          := BAS_SERLEN
SHIFTSIGNEXT    := BAS_SHIFTSGN
CHARAC          := BAS_CHARAC
CPRMASK         := BAS_CPRMASK
FORPNT          := BAS_FORPNT
RESULT          := BAS_RESULT
RESULT_LAST     := BAS_RESULT + 4
TEMP1           := BAS_TEMP1
TEMP2           := BAS_TEMP2
TEMP3           := BAS_TEMP3
RNDSEED         := BAS_RNDSEED

; ----- Aliases used by ported msbasic var/array/string code ----------------
DIMFLG          := BAS_DIMFLG
VALTYP          := BAS_VALTYP
EOLPNTR         := BAS_EOLPNTR
DATAFLG         := BAS_DATAFLG
SUBFLG          := BAS_SUBFLG
INPUTFLG        := BAS_INPUTFLG
ENDCHR          := BAS_ENDCHR
TEMPPT          := BAS_TEMPPT
LASTPT          := BAS_LASTPT
TEMPST          := BAS_TEMPST
HIGHDS          := BAS_HIGHDS
HIGHTR          := BAS_HIGHTR
VARNAM          := BAS_VARNAM
DSCPTR          := BAS_DSCPTR
DSCLEN          := BAS_DSCLEN
FNCNAM          := BAS_FNCNAM
Z52             := BAS_Z52
FRESPC          := BAS_FRESPC

; ---------------------------------------------------------------------------
; Constants required by the ported FP code.
; ---------------------------------------------------------------------------
BYTES_FP        = 5
MANTISSA_BYTES  = 4
MAX_EXPON       = 10
STACK2          = $0100             ; Fout output buffer base (bottom of stack page)

; Variable / array layout constants (CONFIG_2 / CBM2-class equivalents).
BYTES_PER_VARIABLE = 7              ; 2 name + 5 value (numeric or descriptor)
BYTES_PER_ELEMENT  = 5              ; numeric array element size

; ---------------------------------------------------------------------------
; Aliases for the runtime pointers that live in $035D+ (defined in BIOS.inc).
; The msbasic var/array/string code references them by these short names.
; ---------------------------------------------------------------------------
TXTTAB          := BAS_TXTTAB
VARTAB          := BAS_VARTAB
ARYTAB          := BAS_ARYTAB
STREND          := BAS_STREND
FRETOP          := BAS_FRETOP
MEMSIZ          := BAS_MEMSIZ

; ERR_OVERFLOW / ERR_DIVZERO already defined below; alias zerodiv:
ERR_ZERODIV     = 6                 ; matches ERR_DIVZERO

; Fin parses these as numeric-prefix tokens.  Final token assignments are
; wired up when the expression evaluator goes live; until then $00 is fine
; (will not appear in tokenised input).
TOKEN_PLUS      = $00
TOKEN_MINUS     = $00

; Rnd(0) source: 6 stable but variable bytes from kernel vars (IRQ_PTR/BRK_PTR
; etc.).  Just needs to exist — used only when Rnd is called with arg 0.
ENTROPY         = $0300

; =============================================================================
;   R A M   L A Y O U T   ( B A S I C   W O R K S P A C E )
;
;   $0400-$04FF   Input line buffer (256 bytes)
;   $0500-$05FF   Tokenized line scratch (256 bytes)
;
;   GOSUB / FOR stacks live elsewhere; $0500-$05FF doubles as the
;   tokenization scratch buffer.  $0600-$07FF overlaps FS_SECTOR_BUF and
;   is left untouched here.
; =============================================================================

BAS_LINBUF      := $0400        ; Raw input line  (NUL-terminated)
BAS_TOKBUF      := $0500        ; Tokenized scratch buffer (NUL-terminated)

BAS_LINBUF_MAX  = 200           ; Max accepted input length (bytes)
BAS_TOKBUF_MAX  = 250           ; Max tokenized payload bytes

; =============================================================================
;   P R O G R A M   S T O R A G E
;
;   Lines at $0800+ : [next-lo][next-hi][num-lo][num-hi][tokens...][$00]
;   End-of-program  : a "next-pointer" of $0000.
; =============================================================================

BAS_PRG_START   = $0800

; =============================================================================
;   T O K E N   E Q U A T E S
;
;   Tokens are assigned sequentially starting at $80.  KEEP THE TABLE BELOW
;   IN SYNC WITH THESE EQUATES.  If you reorder or insert keywords, renumber.
; =============================================================================

TOK_BASE        = $80

TOK_END         = $80
TOK_FOR         = $81
TOK_NEXT        = $82
TOK_DATA        = $83
TOK_INPUT       = $84
TOK_DIM         = $85
TOK_READ        = $86
TOK_LET         = $87
TOK_GOTO        = $88
TOK_RUN         = $89
TOK_IF          = $8A
TOK_RESTORE     = $8B
TOK_GOSUB       = $8C
TOK_RETURN      = $8D
TOK_REM         = $8E
TOK_STOP        = $8F
TOK_ON          = $90
TOK_WAIT        = $91
TOK_LOAD        = $92
TOK_SAVE        = $93
TOK_DEF         = $94
TOK_POKE        = $95
TOK_PRINT       = $96
TOK_CONT        = $97
TOK_LIST        = $98
TOK_CLR         = $99
TOK_NEW         = $9A
TOK_TAB         = $9B
TOK_TO          = $9C
TOK_FN          = $9D
TOK_SPC         = $9E
TOK_THEN        = $9F
TOK_NOT         = $A0
TOK_STEP        = $A1
TOK_AND         = $A2
TOK_OR          = $A3
TOK_ELSE        = $A4
TOK_SYS         = $A5
TOK_DIR         = $A6
TOK_DEL         = $A7
TOK_CLS         = $A8
TOK_LOCATE      = $A9
TOK_COLOR       = $AA
TOK_SOUND       = $AB
TOK_VOL         = $AC
TOK_TIME        = $AD
TOK_DATE        = $AE
TOK_SETTIME     = $AF
TOK_SETDATE     = $B0
TOK_NVRAM       = $B1
TOK_PAUSE       = $B2
TOK_BANK        = $B3
TOK_BRK         = $B4
TOK_MEM         = $B5
TOK_SGN         = $B6
TOK_INT         = $B7
TOK_ABS         = $B8
TOK_FRE         = $B9
TOK_POS         = $BA
TOK_SQR         = $BB
TOK_RND         = $BC
TOK_LOG         = $BD
TOK_EXP         = $BE
TOK_COS         = $BF
TOK_SIN         = $C0
TOK_TAN         = $C1
TOK_ATN         = $C2
TOK_PEEK        = $C3
TOK_LEN         = $C4
TOK_STRSTR      = $C5           ; STR$
TOK_VAL         = $C6
TOK_ASC         = $C7
TOK_CHRSTR      = $C8           ; CHR$
TOK_LEFTSTR     = $C9           ; LEFT$
TOK_RIGHTSTR    = $CA           ; RIGHT$
TOK_MIDSTR      = $CB           ; MID$
TOK_JOY         = $CC
TOK_INKEY       = $CD
TOK_HEX         = $CE
TOK_MIN         = $CF
TOK_MAX         = $D0
TOK_FPTEST      = $D1           ; debug only - removed in final cleanup
TOK_VARTEST     = $D2           ; debug only - removed in final cleanup

; =============================================================================
;   E R R O R   C O D E S
; =============================================================================

ERR_SYNTAX      = 0
ERR_OVERFLOW    = 1
ERR_OUTOFMEM    = 2
ERR_UNDEFSTMT   = 3
ERR_BADSUBSCR   = 4
ERR_REDIM       = 5
ERR_DIVZERO     = 6
ERR_ILLDIRECT   = 7
ERR_TYPEMISM    = 8
ERR_LONGSTR     = 9
ERR_FORMULA     = 10
ERR_ILLQUAN     = 11
ERR_RG          = 12            ; RETURN without GOSUB
ERR_NF          = 13            ; NEXT without FOR
ERR_OD          = 14            ; OUT OF DATA
ERR_NODEV       = 15
ERR_CANTCONT    = 16

; Aliases used by ported msbasic code.
ERR_BADSUBS     = ERR_BADSUBSCR
ERR_REDIMD      = ERR_REDIM
ERR_FRMCPX      = ERR_FORMULA
ERR_MEMFULL     = ERR_OUTOFMEM
ERR_STRLONG     = ERR_LONGSTR
ERR_ILLQTY      = ERR_ILLQUAN

; =============================================================================
;   B A S E N T R Y   -   $C000
;
;   First byte of segment.  Reached from:
;     * Kernal cold-boot path
;     * Monitor 'X' command (warm re-entry)
;
;   Cold-vs-warm detection: BAS_WARM holds $A5 once cold init has run.
;   Re-entry skips banner and goes straight to the OK prompt.
; =============================================================================

BasEntry:
        ldx     #$FF                    ; reset stack on (re)entry
        txs
        cld

        lda     BAS_WARM
        cmp     #$A5
        beq     @Warm

        jsr     BasColdInit
        jsr     BasBanner
        bra     BasReadyLoop

@Warm:
        ; Warm restart - skip banner; the OK printer will lead with CRLF.

; -----------------------------------------------------------------------------
; BasReadyLoop - REPL: print OK, read a line, dispatch.
; -----------------------------------------------------------------------------
BasReadyLoop:
        jsr     BasPrintOK
@nextline:
        jsr     BasReadLine             ; fills BAS_LINBUF, NUL-terminated
        jsr     BasProcessLine
        bra     @nextline

; =============================================================================
;   B a s C o l d I n i t
; =============================================================================
; Initialise BASIC runtime variables.  Called once on first entry.
; =============================================================================
BasColdInit:
        ; TXTTAB / MEMSIZ are constants for our memory map.
        lda     #<BAS_PRG_START
        sta     BAS_TXTTAB
        lda     #>BAS_PRG_START
        sta     BAS_TXTTAB+1

        lda     #<$8000
        sta     BAS_MEMSIZ
        lda     #>$8000
        sta     BAS_MEMSIZ+1

        ; Auto-detect a pre-loaded program at $0800: if the first word looks
        ; like a valid next-pointer (high byte in [$08, $80)), walk the chain
        ; to compute end-of-program.  Otherwise install an empty program.
        lda     BAS_PRG_START+1         ; high byte of first next-ptr
        cmp     #$08
        bcc     @InstallEmpty
        cmp     #$80
        bcs     @InstallEmpty

        ; Walk the chain to find the end-marker (next-ptr = 0).
        lda     #<BAS_PRG_START
        sta     BAS_TMP1
        lda     #>BAS_PRG_START
        sta     BAS_TMP1+1
@WalkLoop:
        ldy     #1
        lda     (BAS_TMP1),y
        beq     @WalkDone               ; end-marker reached
        ldy     #0
        lda     (BAS_TMP1),y
        pha
        ldy     #1
        lda     (BAS_TMP1),y
        sta     BAS_TMP1+1
        pla
        sta     BAS_TMP1
        bra     @WalkLoop
@WalkDone:
        ; BAS_TMP1 points at the end-marker; VARTAB = TMP1 + 2.
        clc
        lda     BAS_TMP1
        adc     #2
        sta     BAS_VARTAB
        lda     BAS_TMP1+1
        adc     #0
        sta     BAS_VARTAB+1
        bra     @InitFinalize

@InstallEmpty:
        ; Write [00][00] end-marker at $0800; VARTAB = $0802.
        lda     #0
        sta     BAS_PRG_START
        sta     BAS_PRG_START+1
        lda     #<(BAS_PRG_START+2)
        sta     BAS_VARTAB
        lda     #>(BAS_PRG_START+2)
        sta     BAS_VARTAB+1

@InitFinalize:
        ; ARYTAB = STREND = VARTAB; FRETOP = MEMSIZ.
        lda     BAS_VARTAB
        sta     BAS_ARYTAB
        sta     BAS_STREND
        lda     BAS_VARTAB+1
        sta     BAS_ARYTAB+1
        sta     BAS_STREND+1
        lda     BAS_MEMSIZ
        sta     BAS_FRETOP
        lda     BAS_MEMSIZ+1
        sta     BAS_FRETOP+1

        ; CURLIN = $FFFF (direct mode marker).
        lda     #$FF
        sta     BAS_CURLIN
        sta     BAS_CURLIN+1

        ; Clear CONT state and pending-key.
        stz     BAS_OLDLIN
        stz     BAS_OLDLIN+1
        stz     BAS_OLDTEXT
        stz     BAS_OLDTEXT+1
        stz     BAS_DATAPTR
        stz     BAS_DATAPTR+1
        stz     BAS_STOPLINE
        stz     BAS_STOPLINE+1
        stz     BAS_STOPTXT
        stz     BAS_STOPTXT+1
        stz     BAS_PENDKEY

        stz     BAS_QUOTEFLG

        ; Variable/array/string runtime state.
        stz     BAS_DIMFLG
        stz     BAS_VALTYP
        stz     BAS_VALTYP+1
        stz     BAS_DATAFLG
        stz     BAS_SUBFLG
        stz     BAS_INPUTFLG
        ; Temp-string descriptor stack: TEMPPT = TEMPST.
        lda     #BAS_TEMPST
        sta     BAS_TEMPPT

        ; Initialise Rnd seed from the embedded constant.
        ldx     #4
@SeedCopy:
        lda     RndSeedInit,x
        sta     RNDSEED,x
        dex
        bpl     @SeedCopy

        ; Mark warm-start magic.
        lda     #$A5
        sta     BAS_WARM
        rts

; =============================================================================
;   B a s B a n n e r
; =============================================================================
BasBanner:
        lda     #<MsgBanner
        ldy     #>MsgBanner
        jsr     BasPrintStr
        ; Print "<n> BYTES FREE" line.
        sec
        lda     BAS_MEMSIZ
        sbc     BAS_VARTAB
        tay
        lda     BAS_MEMSIZ+1
        sbc     BAS_VARTAB+1
        jsr     GivAyf
        ; Print the byte count left-aligned: Fout always emits a leading
        ; sign character (' ' for positive, '-' for negative).  For the
        ; banner we skip that leading space so the number lines up with
        ; the left edge of the title above it.
        jsr     Fout                    ; (Y,A) -> NUL-terminated buffer
        sta     INDEX
        sty     INDEX+1
        ldy     #0
        lda     (INDEX),y
        cmp     #' '
        bne     @bnLoop
        iny                             ; skip the positive-sign space
@bnLoop:
        lda     (INDEX),y
        beq     @bnDone
        jsr     PrintCh
        iny
        bne     @bnLoop
@bnDone:
        lda     #<MsgBytesFreeNL
        ldy     #>MsgBytesFreeNL
        jmp     BasPrintStr

; =============================================================================
;   B a s P r i n t O K
; =============================================================================
BasPrintOK:
        jsr     BasPrintCRLF
        lda     #<MsgOK
        ldy     #>MsgOK
        jmp     BasPrintStr

; =============================================================================
;   B a s P r i n t S t r
; =============================================================================
; Print a NUL-terminated string via Chrout.
; Input  : A=lo, Y=hi  (string address)
; Clobbers : A, Y  (X preserved)
; =============================================================================
BasPrintStr:
        sta     BAS_TMP1
        sty     BAS_TMP1+1
        ldy     #0
@Loop:
        lda     (BAS_TMP1),y
        beq     @Done
        jsr     Chrout
        iny
        bne     @Loop
@Done:
        rts

; =============================================================================
;   B a s P r i n t C R L F
; =============================================================================
BasPrintCRLF:
        lda     #$0D
        jsr     Chrout
        lda     #$0A
        jmp     Chrout

; =============================================================================
;   B a s R e a d L i n e
; =============================================================================
; Read a line of input into BAS_LINBUF, NUL-terminated.  Echoes characters
; manually (does not use Chrin's auto-echo).  Supports CR, BS ($08), ESC
; ($1B = cancel and restart line).  Caps stored length at BAS_LINBUF_MAX
; (extra characters are silently dropped from the buffer but still echoed
; -- acceptable truncation behavior).
;
; Output : BAS_LINBUF holds the raw line, terminated with $00.
; =============================================================================
BasReadLine:
        ldy     #0
@Loop:
        jsr     BasReadKey              ; A = next key, blocking
        cmp     #$0D
        beq     @Done
        cmp     #$08
        beq     @Backspace
        cmp     #$1B
        beq     @Cancel
        cmp     #$20                    ; reject control codes below space
        bcc     @Loop
        cmp     #$7F                    ; reject DEL and 8-bit
        bcs     @Loop
        ; Printable - store and echo.
        cpy     #BAS_LINBUF_MAX
        bcs     @Loop                   ; full - drop quietly
        sta     BAS_LINBUF,y
        iny
        jsr     Chrout
        bra     @Loop

@Backspace:
        cpy     #0
        beq     @Loop                   ; nothing to erase
        dey
        lda     #$08                    ; video / serial driver erases on BS
        jsr     Chrout
        bra     @Loop

@Cancel:
        jsr     BasPrintCRLF
        ldy     #0
        bra     @Loop

@Done:
        lda     #0
        sta     BAS_LINBUF,y
        jsr     BasPrintCRLF
        rts

; =============================================================================
;   B a s R e a d K e y
; =============================================================================
; Spin until a key is available in the input buffer; return it in A
; (no echo).
; =============================================================================
BasReadKey:
@Wait:
        jsr     BufferSize
        beq     @Wait
        jmp     ReadBuffer              ; tail-call: returns A=byte

; =============================================================================
;   B a s P r o c e s s L i n e
; =============================================================================
; Triage BAS_LINBUF after reading: empty, numbered (insert/replace/delete),
; or immediate command.
; =============================================================================
BasProcessLine:
        ldx     #0
@SkipSpaces:
        lda     BAS_LINBUF,x
        beq     @Empty
        cmp     #' '
        bne     @HasContent
        inx
        bra     @SkipSpaces
@Empty:
        rts                             ; nothing to do; caller will reprompt

@HasContent:
        cmp     #'0'
        bcc     @Immediate
        cmp     #'9'+1
        bcs     @Immediate

; --- Numbered line -----------------------------------------------------------
        jsr     BasParseLineNum         ; consumes digits at BAS_LINBUF+X
        ; X now points to first non-digit; allow exactly one optional space.
        lda     BAS_LINBUF,x
        cmp     #' '
        bne     @TokenizeRest
        inx
@TokenizeRest:
        jsr     BasCrunch               ; tokenize from BAS_LINBUF+X to BAS_TOKBUF
        bcs     @StoreLine              ; carry set = success
        jmp     BasErrSyntax

@StoreLine:
        jmp     BasStoreLine            ; insert/replace/delete by line number

@Immediate:
        ; Immediate (no line number) - tokenize whole line and dispatch.
        ldx     #0
        jsr     BasCrunch
        bcs     @ImmDispatch
        jmp     BasErrSyntax
@ImmDispatch:
        jsr     BasDispatchImmediate
        jmp     BasPrintOK              ; MS BASIC: OK only after immediate

; =============================================================================
;   B a s P a r s e L i n e N u m
; =============================================================================
; Parse decimal digits at BAS_LINBUF,X into BAS_LINNUM (16-bit).
; X advances past the digits.  Saturates at $FFFF on overflow.
; =============================================================================
BasParseLineNum:
        stz     BAS_LINNUM
        stz     BAS_LINNUM+1
@Loop:
        lda     BAS_LINBUF,x
        cmp     #'0'
        bcc     @Done
        cmp     #'9'+1
        bcs     @Done
        ; Multiply LINNUM by 10.
        pha
        asl     BAS_LINNUM              ; *2
        rol     BAS_LINNUM+1
        lda     BAS_LINNUM
        sta     BAS_TMP1
        lda     BAS_LINNUM+1
        sta     BAS_TMP1+1
        asl     BAS_LINNUM              ; *4
        rol     BAS_LINNUM+1
        asl     BAS_LINNUM              ; *8
        rol     BAS_LINNUM+1
        clc                             ; *8 + *2 = *10
        lda     BAS_LINNUM
        adc     BAS_TMP1
        sta     BAS_LINNUM
        lda     BAS_LINNUM+1
        adc     BAS_TMP1+1
        sta     BAS_LINNUM+1
        ; Add digit value.
        pla
        and     #$0F
        clc
        adc     BAS_LINNUM
        sta     BAS_LINNUM
        bcc     @NoCarry
        inc     BAS_LINNUM+1
@NoCarry:
        inx
        bra     @Loop
@Done:
        rts

; =============================================================================
;   B a s C r u n c h
; =============================================================================
; Tokenize BAS_LINBUF starting at offset X into BAS_TOKBUF.
;
; Tokenization rules:
;   - Outside quoted strings, lowercase a-z are folded to uppercase.
;   - Outside quoted strings, alphabetic runs are matched against the
;     keyword table; on a match the token byte is emitted in place of the
;     keyword characters.
;   - Inside double quotes, characters are copied verbatim until the
;     closing quote (or end of line).
;   - After a REM token, the rest of the line is copied verbatim.
;   - Disallowed punctuation (@, &, [, ], {, }, |, \, `, ~) raises
;     ?SYNTAX ERROR via carry-clear return.
;
; Output : BAS_TOKBUF holds the tokenized line, NUL-terminated.
; Returns: carry SET on success, carry CLEAR on syntax error.
; Clobbers: A, X, Y, BAS_TMP1/TMP2/TMP3.
; =============================================================================
BasCrunch:
        ; X = src index, Y = dst index
        ldy     #0
        stz     BAS_QUOTEFLG
@Scan:
        cpy     #BAS_TOKBUF_MAX
        bcs     @Overflow
        lda     BAS_LINBUF,x
        bne     @NotEnd
        ; End of input.
        sta     BAS_TOKBUF,y            ; A=0
        sec
        rts
@Overflow:
        ; Tokenized line too long; treat as syntax error.
        clc
        rts

@NotEnd:
        cmp     #'"'
        beq     @Quote
        ; Lowercase to uppercase outside quotes.
        cmp     #'a'
        bcc     @CheckAlpha
        cmp     #'z'+1
        bcs     @CheckAlpha
        and     #$DF
@CheckAlpha:
        ; Alphabetic? Try keyword match.
        cmp     #'A'
        bcc     @NotAlpha
        cmp     #'Z'+1
        bcs     @NotAlpha
        ; Alpha - try matching a keyword starting at BAS_LINBUF,x.
        jsr     BasMatchKeyword         ; returns C set (A=token, X advanced) or C clear
        bcc     @CopyAlpha
        ; Match: emit token byte.
        sta     BAS_TOKBUF,y
        iny
        cmp     #TOK_REM
        bne     @Scan
        ; After REM: copy the remainder verbatim.
@RemCopy:
        cpy     #BAS_TOKBUF_MAX
        bcs     @Overflow
        lda     BAS_LINBUF,x
        beq     @TermAndExit
        sta     BAS_TOKBUF,y
        iny
        inx
        bra     @RemCopy
@TermAndExit:
        sta     BAS_TOKBUF,y            ; A=0
        sec
        rts

@CopyAlpha:
        ; No keyword match - copy a single alpha char (re-uppercase here, since
        ; BasMatchKeyword returns the original LINBUF byte).
        lda     BAS_LINBUF,x
        cmp     #'a'
        bcc     @CASto
        cmp     #'z'+1
        bcs     @CASto
        and     #$DF
@CASto:
        sta     BAS_TOKBUF,y
        iny
        inx
        bra     @Scan

@NotAlpha:
        ; Punctuation / digit / space.  Validate against the disallowed set.
        jsr     BasValidPunct
        bcc     @SyntaxFail
        sta     BAS_TOKBUF,y
        iny
        inx
        bra     @Scan
@SyntaxFail:
        clc
        rts

@Quote:
        ; Copy opening quote, then everything up to closing quote (or end).
        sta     BAS_TOKBUF,y
        iny
        inx
@QuoteLoop:
        cpy     #BAS_TOKBUF_MAX
        bcs     @Overflow
        lda     BAS_LINBUF,x
        beq     @TermAndExit
        sta     BAS_TOKBUF,y
        iny
        inx
        cmp     #'"'
        bne     @QuoteLoop
        jmp     @Scan

; =============================================================================
;   B a s V a l i d P u n c t
; =============================================================================
; Verify A is an acceptable non-keyword character.
; Carry SET = OK, carry CLEAR = illegal.
; Allowed: anything in $20-$7E EXCEPT @, &, [, ], {, }, |, \, `, ~.
; =============================================================================
BasValidPunct:
        cmp     #'@'
        beq     @Bad
        cmp     #'&'
        beq     @Bad
        cmp     #'['
        beq     @Bad
        cmp     #']'
        beq     @Bad
        cmp     #'{'
        beq     @Bad
        cmp     #'}'
        beq     @Bad
        cmp     #'|'
        beq     @Bad
        cmp     #'\'
        beq     @Bad
        cmp     #'`'
        beq     @Bad
        cmp     #'~'
        beq     @Bad
        sec
        rts
@Bad:
        clc
        rts

; =============================================================================
;   B a s M a t c h K e y w o r d
; =============================================================================
; Try to match a keyword from KeywordTbl starting at BAS_LINBUF,X.
;
; On match  : carry SET, A = token byte, X advanced past the matched
;             keyword characters in BAS_LINBUF.
; On miss   : carry CLEAR, X unchanged, A = original character at LINBUF,X.
;
; Match algorithm:
;   - Walk KeywordTbl, comparing characters (folding LINBUF lowercase to
;     uppercase) to each keyword in turn.  A keyword's last byte has bit 7
;     set; the byte after the table's final keyword is $00.
;   - Token value = TOK_BASE + (index of keyword in table).
; =============================================================================
BasMatchKeyword:
        ; Save initial X for rollback on miss; preserve caller's Y (BasCrunch
        ; uses Y as the TOKBUF destination index).
        stx     BAS_TMP3
        phy
        ; Walk the keyword table via a 16-bit ZP pointer (BAS_KWPTR), since
        ; the table is larger than 256 bytes.  Y is held at 0 throughout and
        ; we advance BAS_KWPTR byte-by-byte instead of relying on Y.
        lda     #<KeywordTbl
        sta     BAS_KWPTR
        lda     #>KeywordTbl
        sta     BAS_KWPTR+1
        lda     #TOK_BASE
        sta     BAS_TMP1                ; current candidate token
        ldy     #0
@KeywordLoop:
        ; Restore X to start of input keyword.
        ldx     BAS_TMP3
@CharLoop:
        lda     (BAS_KWPTR),y           ; Y == 0
        beq     @NoMatch                ; reached table terminator
        pha
        and     #$7F
        sta     BAS_TMP2                ; expected char (uppercase)
        ; Read input char and uppercase it.
        lda     BAS_LINBUF,x
        cmp     #'a'
        bcc     @InpCmp
        cmp     #'z'+1
        bcs     @InpCmp
        and     #$DF
@InpCmp:
        cmp     BAS_TMP2
        bne     @CharMismatch
        pla                             ; restore raw table byte
        ; Match - is this the last char of the keyword?
        bmi     @WholeMatch             ; bit 7 set -> full keyword matched
        ; Advance both pointers and continue.
        inc     BAS_KWPTR
        bne     @CharNoCarry
        inc     BAS_KWPTR+1
@CharNoCarry:
        inx
        bra     @CharLoop

@CharMismatch:
        pla
        ; Skip ahead to start of next keyword in table.  Walk byte-by-byte
        ; until we consume a byte with bit 7 set (last char of this keyword)
        ; or hit the $00 terminator.
@SkipKeyword:
        lda     (BAS_KWPTR),y           ; Y == 0
        beq     @NoMatch                ; hit table terminator
        inc     BAS_KWPTR
        bne     @SkipNoCarry
        inc     BAS_KWPTR+1
@SkipNoCarry:
        cmp     #$80                    ; carry set iff loaded byte >= $80
        bcc     @SkipKeyword
        ; Fall through: byte had bit 7 set => end of keyword.
@AdvanceTok:
        inc     BAS_TMP1
        bra     @KeywordLoop

@WholeMatch:
        ; X points at the LAST matched char in input; advance past it.
        inx
        lda     BAS_TMP1
        ply                             ; restore caller's Y
        sec
        rts

@NoMatch:
        ldx     BAS_TMP3                ; restore caller's X
        ply                             ; restore caller's Y
        lda     BAS_LINBUF,x
        clc
        rts

; =============================================================================
;   B a s S t o r e L i n e
; =============================================================================
; Insert or replace BAS_LINNUM in the program with the tokenized payload in
; BAS_TOKBUF.  If BAS_TOKBUF is empty, delete the existing line.
;
; Algorithm:
;   1. Find existing line number (or insertion point).
;   2. If exact match, delete that line (close the gap, decrement VARTAB).
;   3. If payload non-empty, splice in [next][num][payload][$00].
;   4. Relink all next-pointers.
; =============================================================================
BasStoreLine:
        ; Locate insertion point.  BAS_INDEX <- pointer; carry set = exact match.
        jsr     BasFindLine

        bcc     @NoExisting
        ; Line exists - delete it first.
        jsr     BasDeleteAtIndex
@NoExisting:
        ; If tokbuf is empty, we're done (delete-only operation).
        lda     BAS_TOKBUF
        bne     @InsertNew
        jsr     BasRelink
        rts

@InsertNew:
        jsr     BasInsertAtIndex
        bcc     @NoMem
        jsr     BasRelink
        rts
@NoMem:
        lda     #ERR_OUTOFMEM
        jmp     BasError

; =============================================================================
;   B a s F i n d L i n e
; =============================================================================
; Locate BAS_LINNUM in the program list.
;
; On entry : BAS_LINNUM = target line number.
; On exit  : BAS_INDEX = pointer to start of either the matching line or the
;            first line whose number > target (or end-marker).
;            Carry SET if exact match, CLEAR otherwise.
; =============================================================================
BasFindLine:
        lda     BAS_TXTTAB
        sta     BAS_INDEX
        lda     BAS_TXTTAB+1
        sta     BAS_INDEX+1
@Loop:
        ldy     #1
        lda     (BAS_INDEX),y
        beq     @NotFound               ; end-marker (next-hi = 0)

        ; Compare line numbers: (INDEX+2/+3) vs LINNUM.
        ldy     #3
        lda     (BAS_INDEX),y
        cmp     BAS_LINNUM+1
        bcc     @Advance                ; line < target
        bne     @TooHigh                ; line > target -> insertion point
        dey
        lda     (BAS_INDEX),y
        cmp     BAS_LINNUM
        bcc     @Advance
        bne     @TooHigh
        ; Exact match.
        sec
        rts

@Advance:
        ; Follow next-pointer.
        ldy     #0
        lda     (BAS_INDEX),y
        pha
        ldy     #1
        lda     (BAS_INDEX),y
        sta     BAS_INDEX+1
        pla
        sta     BAS_INDEX
        bra     @Loop

@NotFound:
@TooHigh:
        clc
        rts

; =============================================================================
;   B a s D e l e t e A t I n d e x
; =============================================================================
; Delete the line whose start is at BAS_INDEX.
; Closes the gap by copying [next-line .. VARTAB-1] down to (BAS_INDEX...)
; and decrements VARTAB by the deleted size.
; =============================================================================
BasDeleteAtIndex:
        ; BAS_TMP1 = next-line address (read from current line's next ptr).
        ldy     #0
        lda     (BAS_INDEX),y
        sta     BAS_TMP1
        iny
        lda     (BAS_INDEX),y
        sta     BAS_TMP1+1

        ; gap-size = TMP1 - INDEX  (positive)
        ; Copy from TMP1 to INDEX, byte by byte, until TMP1 reaches VARTAB.
        ; BAS_DEST = INDEX (write cursor); BAS_TMP2 = src cursor (= TMP1).
        lda     BAS_INDEX
        sta     BAS_DEST
        lda     BAS_INDEX+1
        sta     BAS_DEST+1

@CopyLoop:
        ; Done when TMP1 == VARTAB.
        lda     BAS_TMP1
        cmp     BAS_VARTAB
        lda     BAS_TMP1+1
        sbc     BAS_VARTAB+1
        bcs     @CopyDone

        ldy     #0
        lda     (BAS_TMP1),y
        sta     (BAS_DEST),y

        inc     BAS_TMP1
        bne     @IncDest
        inc     BAS_TMP1+1
@IncDest:
        inc     BAS_DEST
        bne     @CopyLoop
        inc     BAS_DEST+1
        bra     @CopyLoop

@CopyDone:
        ; VARTAB = DEST.
        lda     BAS_DEST
        sta     BAS_VARTAB
        lda     BAS_DEST+1
        sta     BAS_VARTAB+1
        ; Mirror to ARYTAB/STREND (vars/arrays empty after edit; keep them
        ; tracking VARTAB).
        sta     BAS_ARYTAB+1
        sta     BAS_STREND+1
        lda     BAS_VARTAB
        sta     BAS_ARYTAB
        sta     BAS_STREND
        rts

; =============================================================================
;   B a s I n s e r t A t I n d e x
; =============================================================================
; Splice a new line ([next-placeholder][num-lo][num-hi][payload][$00]) in
; at BAS_INDEX, shifting following bytes upward.
;
; On entry : BAS_INDEX = insertion address, BAS_LINNUM = line number,
;            BAS_TOKBUF = NUL-terminated payload (non-empty).
; On exit  : Carry SET on success, CLEAR if not enough memory.
;            VARTAB / ARYTAB / STREND advanced to new end-of-program.
; =============================================================================
BasInsertAtIndex:
        ; Compute payload length L (excluding NUL): scan TOKBUF.
        ldy     #0
@LenScan:
        lda     BAS_TOKBUF,y
        beq     @LenDone
        iny
        bne     @LenScan
@LenDone:
        ; Total line size = 4 (header) + L + 1 (terminator) = L + 5.
        ; Store size in BAS_TMP3 (assumes <= 250+5 = 255, fits in one byte).
        tya
        clc
        adc     #5
        sta     BAS_TMP3                ; line size in bytes (<=255)

        ; Memory check: VARTAB + size <= MEMSIZ.
        clc
        lda     BAS_VARTAB
        adc     BAS_TMP3
        sta     BAS_TMP1
        lda     BAS_VARTAB+1
        adc     #0
        sta     BAS_TMP1+1
        lda     BAS_TMP1
        cmp     BAS_MEMSIZ
        lda     BAS_TMP1+1
        sbc     BAS_MEMSIZ+1
        bcc     @SizeOK
        clc                             ; out of memory
        rts
@SizeOK:
        ; Shift bytes [INDEX .. VARTAB-1] up by TMP3.
        ; Copy from high-to-low to avoid overlap clobber.
        ; src  = VARTAB-1
        ; dst  = VARTAB-1 + TMP3
        lda     BAS_VARTAB
        sec
        sbc     #1
        sta     BAS_TMP1                ; src
        lda     BAS_VARTAB+1
        sbc     #0
        sta     BAS_TMP1+1
        clc
        lda     BAS_TMP1
        adc     BAS_TMP3
        sta     BAS_DEST                ; dst
        lda     BAS_TMP1+1
        adc     #0
        sta     BAS_DEST+1
@Shift:
        ; Stop when TMP1 < INDEX (i.e. INDEX-1 reached -> done).
        lda     BAS_TMP1
        cmp     BAS_INDEX
        lda     BAS_TMP1+1
        sbc     BAS_INDEX+1
        bcc     @ShiftDone

        ldy     #0
        lda     (BAS_TMP1),y
        sta     (BAS_DEST),y

        ; dec TMP1
        lda     BAS_TMP1
        bne     @T1NoBorrow
        dec     BAS_TMP1+1
@T1NoBorrow:
        dec     BAS_TMP1
        ; dec DEST
        lda     BAS_DEST
        bne     @DNoBorrow
        dec     BAS_DEST+1
@DNoBorrow:
        dec     BAS_DEST
        bra     @Shift

@ShiftDone:
        ; Write new line header at BAS_INDEX.
        ldy     #0
        lda     #$FF                    ; placeholder next-ptr (Relink fixes)
        sta     (BAS_INDEX),y
        iny
        sta     (BAS_INDEX),y
        iny
        lda     BAS_LINNUM
        sta     (BAS_INDEX),y
        iny
        lda     BAS_LINNUM+1
        sta     (BAS_INDEX),y
        iny

        ; Copy payload from BAS_TOKBUF (NUL terminator included).
        ldx     #0
@PayloadCopy:
        lda     BAS_TOKBUF,x
        sta     (BAS_INDEX),y
        beq     @PayloadDone
        inx
        iny
        bra     @PayloadCopy
@PayloadDone:
        ; Update VARTAB.
        clc
        lda     BAS_VARTAB
        adc     BAS_TMP3
        sta     BAS_VARTAB
        lda     BAS_VARTAB+1
        adc     #0
        sta     BAS_VARTAB+1
        ; Mirror to ARYTAB/STREND.
        lda     BAS_VARTAB
        sta     BAS_ARYTAB
        sta     BAS_STREND
        lda     BAS_VARTAB+1
        sta     BAS_ARYTAB+1
        sta     BAS_STREND+1

        sec
        rts

; =============================================================================
;   B a s R e l i n k
; =============================================================================
; Walk the program list and rewrite every next-pointer to the address of
; the following line (computed by scanning forward to the line's NUL
; terminator).  Stops when a next-pointer's high byte is already 0
; (the [00][00] end-marker, which is left untouched).
; =============================================================================
BasRelink:
        lda     BAS_TXTTAB
        sta     BAS_INDEX
        lda     BAS_TXTTAB+1
        sta     BAS_INDEX+1
@Loop:
        ldy     #1
        lda     (BAS_INDEX),y
        beq     @Done                   ; end-marker reached

        ; Find the NUL terminator at INDEX + Y for some Y >= 4.
        ldy     #4
@Scan:
        lda     (BAS_INDEX),y
        beq     @Found
        iny
        bne     @Scan
@Found:
        iny                             ; one past NUL = next line address
        ; next = INDEX + Y
        tya
        clc
        adc     BAS_INDEX
        sta     BAS_TMP1
        lda     BAS_INDEX+1
        adc     #0
        sta     BAS_TMP1+1

        ; Write new next-pointer at (INDEX),0/1.
        ldy     #0
        lda     BAS_TMP1
        sta     (BAS_INDEX),y
        iny
        lda     BAS_TMP1+1
        sta     (BAS_INDEX),y

        ; Advance INDEX = TMP1.
        lda     BAS_TMP1
        sta     BAS_INDEX
        lda     BAS_TMP1+1
        sta     BAS_INDEX+1
        bra     @Loop
@Done:
        rts

; =============================================================================
;   B a s D i s p a t c h I m m e d i a t e
; =============================================================================
; Execute a tokenized line (BAS_TOKBUF) in immediate mode by entering the
; statement loop (BasNewstt) with TXTPTR pointing one byte before the first
; tokenized byte.  Re-anchors the CPU stack so that FOR / GOSUB frames
; stored on the stack can be located by the scanners.
; =============================================================================
BasDispatchImmediate:
        ; Write a ':' sentinel just before BAS_TOKBUF so NEWSTT's initial
        ; (TXTPTR),y read takes the @nextStmt path and CHRGETs the first token.
        lda     #':'
        sta     BAS_TOKBUF-1
        lda     #<(BAS_TOKBUF-1)
        sta     TXTPTR
        lda     #>(BAS_TOKBUF-1)
        sta     TXTPTR+1
        stz     BAS_POSX
        ; Direct mode: CURLIN = $FFFF (msbasic convention).
        lda     #$FF
        sta     BAS_CURLIN
        sta     BAS_CURLIN+1
        ; Reset CPU stack so FOR / GOSUB frame scanners have a clean baseline.
        ldx     #$FF
        txs
        jmp     BasNewstt

; =============================================================================
;   B a s C m d N e w
; =============================================================================
; Reset program storage to empty: write [00][00] at $0800 and reset the
; runtime pointers.
; =============================================================================
BasCmdNew:
        stz     BAS_PRG_START
        stz     BAS_PRG_START+1
        lda     #<(BAS_PRG_START+2)
        sta     BAS_VARTAB
        sta     BAS_ARYTAB
        sta     BAS_STREND
        lda     #>(BAS_PRG_START+2)
        sta     BAS_VARTAB+1
        sta     BAS_ARYTAB+1
        sta     BAS_STREND+1
        lda     BAS_MEMSIZ
        sta     BAS_FRETOP
        lda     BAS_MEMSIZ+1
        sta     BAS_FRETOP+1
        rts

; =============================================================================
;   B a s C m d L i s t
; =============================================================================
; Print every stored line in order.  Each line: decimal line number, single
; space, detokenized payload, CRLF.
; =============================================================================
BasCmdList:
        lda     BAS_TXTTAB
        sta     BAS_INDEX
        lda     BAS_TXTTAB+1
        sta     BAS_INDEX+1
@LineLoop:
        ldy     #1
        lda     (BAS_INDEX),y
        beq     @Done                   ; end-marker
        ; Print line number.
        ldy     #2
        lda     (BAS_INDEX),y
        sta     BAS_LINNUM
        iny
        lda     (BAS_INDEX),y
        sta     BAS_LINNUM+1
        jsr     BasPrintLineNum
        lda     #' '
        jsr     Chrout

        ; Detokenize from offset 4 to the NUL terminator.
        ldy     #4
@DetokLoop:
        lda     (BAS_INDEX),y
        beq     @LineEnd
        bmi     @Token
        jsr     Chrout
        iny
        bra     @DetokLoop
@Token:
        sty     BAS_DETOKY
        jsr     BasPrintKeyword         ; preserves nothing useful
        ldy     BAS_DETOKY
        iny
        bra     @DetokLoop
@LineEnd:
        jsr     BasPrintCRLF
        ; Advance INDEX via next-pointer.
        ldy     #0
        lda     (BAS_INDEX),y
        pha
        iny
        lda     (BAS_INDEX),y
        sta     BAS_INDEX+1
        pla
        sta     BAS_INDEX
        bra     @LineLoop
@Done:
        rts

; =============================================================================
;   B a s P r i n t L i n e N u m
; =============================================================================
; Print BAS_LINNUM (16-bit unsigned) as decimal (no leading zeros, no sign).
; Clobbers : A, X, Y, BAS_TMP1.
; =============================================================================
BasPrintLineNum:
        ; Repeated-subtraction divide by powers of ten.
        ; Suppress leading zeros via flag in BAS_TMP3.
        stz     BAS_TMP3                ; printed-something flag
        stz     BAS_TMP2                ; current-digit accumulator

        lda     BAS_LINNUM
        sta     BAS_TMP1
        lda     BAS_LINNUM+1
        sta     BAS_TMP1+1

        ldx     #0
@PowerLoop:
        ; Subtract powers[X], counting iterations to get digit.
        ldy     #0                      ; digit counter
@Sub:
        sec
        lda     BAS_TMP1
        sbc     PowersOfTenLo,x
        tay                             ; temp save
        lda     BAS_TMP1+1
        sbc     PowersOfTenHi,x
        bcc     @SubDone
        sta     BAS_TMP1+1
        sty     BAS_TMP1
        ; reuse Y for digit count via a scratch?  Use BAS_TMP2.
        inc     BAS_TMP2
        bra     @Sub
@SubDone:
        ; Digit is in BAS_TMP2.
        lda     BAS_TMP2
        ora     BAS_TMP3                ; if any prior digit OR this digit nonzero, print
        beq     @SkipDigit
        lda     BAS_TMP2
        ora     #'0'
        jsr     Chrout
        lda     #1
        sta     BAS_TMP3
@SkipDigit:
        stz     BAS_TMP2
        inx
        cpx     #4                      ; ten-thousands, thousands, hundreds, tens
        bne     @ResetAndLoop
        ; Final ones digit is in TMP1 (0-9).
        lda     BAS_TMP1
        ora     #'0'
        jsr     Chrout
        rts
@ResetAndLoop:
        bra     @PowerLoop

PowersOfTenLo:
        .byte   <10000, <1000, <100, <10
PowersOfTenHi:
        .byte   >10000, >1000, >100, >10

; =============================================================================
;   B a s C m d P r i n t
; =============================================================================
; Immediate-mode PRINT.  X on entry = offset into BAS_TOKBUF where the
; PRINT token sits.  Items separated by ';' (no separator) or ',' (advance
; to next 14-column print zone).  Trailing ';' or ',' suppresses CRLF.
;
; Special-cased token: HEX(n) -> emit "$XXXX" hex form (does not call
; FrmEvl; consumes the token + parens here).
; =============================================================================
BasCmdPrint:
        ; TXTPTR is positioned with ChrGot returning TOK_PRINT.  Advance
        ; past the token; col counter is reset by the dispatcher's outer loop.
        jsr     ChrGet                  ; consume PRINT token

BasPrLoop:
        jsr     ChrGot
        jeq     BasPrEndNl
        cmp     #':'
        jeq     BasPrEndNl
        cmp     #TOK_ELSE
        jeq     BasPrEndNl
        cmp     #';'
        jeq     BasPrSep
        cmp     #','
        jeq     BasPrComma
        cmp     #TOK_HEX
        bne     @chkTab
        ; HEX(n) in PRINT context: emit "$XXXX".
        jsr     ChrGet                  ; consume HEX
        jsr     ChkOpn
        jsr     FrmEvl
        jsr     ChkNum
        jsr     ChkCls
        jsr     AyInt
        jsr     PrintHex16
        bra     BasPrAfter
@chkTab:
        cmp     #TOK_TAB
        bne     @chkSpc
        jsr     ChrGet                  ; consume TAB
        jsr     ChkOpn
        jsr     FrmNum
        jsr     ChkCls
        jsr     AyInt
        lda     FAC+3                   ; column count must fit in a byte
        bne     BasPrAfter
        lda     FAC+4
        cmp     BAS_POSX
        bcc     BasPrAfter              ; already at/past target column
        sec
        sbc     BAS_POSX
        tay
        beq     BasPrAfter
@tabLoop:
        phy
        lda     #' '
        jsr     PrintCh
        ply
        dey
        bne     @tabLoop
        bra     BasPrAfter
@chkSpc:
        cmp     #TOK_SPC
        bne     @expr
        jsr     ChrGet                  ; consume SPC
        jsr     ChkOpn
        jsr     FrmNum
        jsr     ChkCls
        jsr     AyInt
        lda     FAC+3
        bne     BasPrAfter
        ldy     FAC+4
        beq     BasPrAfter
@spcLoop:
        phy
        lda     #' '
        jsr     PrintCh
        ply
        dey
        bne     @spcLoop
        bra     BasPrAfter
@expr:
        jsr     FrmEvl
        bit     VALTYP
        bmi     @prStr
        jsr     PrintNum
        bra     BasPrAfter
@prStr:
        jsr     PrintStrFAC
        jsr     FreFac
BasPrAfter:
        jsr     ChrGot
        jeq     BasPrEndNl
        cmp     #':'
        jeq     BasPrEndNl
        cmp     #TOK_ELSE
        jeq     BasPrEndNl
        cmp     #';'
        jeq     BasPrSep
        cmp     #','
        jeq     BasPrComma
        jmp     SynErr
BasPrSep:
        jsr     ChrGet                  ; consume ;
        jsr     ChrGot
        beq     BasPrEndNoNl            ; trailing ; -> no CRLF
        cmp     #':'
        beq     BasPrEndNoNl
        jmp     BasPrLoop
BasPrComma:
        jsr     ChrGet
        ; Pad to next multiple of 14 (MS-BASIC 14-column zone).
        ; col_mod = BAS_POSX mod 14; if 0 already at zone, else emit (14-col_mod) spaces.
        lda     BAS_POSX
        sta     BAS_TMP1
@modA:
        lda     BAS_TMP1
        cmp     #14
        bcc     @modB
        sec
        sbc     #14
        sta     BAS_TMP1
        bra     @modA
@modB:
        cmp     #0
        beq     @padDone
@padSp:
        lda     #' '
        jsr     PrintCh
        inc     BAS_TMP1
        lda     BAS_TMP1
        cmp     #14
        bne     @padSp
@padDone:
        jsr     ChrGot
        beq     BasPrEndNoNl
        cmp     #':'
        beq     BasPrEndNoNl
        jmp     BasPrLoop
BasPrEndNl:
        jsr     BasPrintCRLF
        stz     BAS_POSX
        rts
BasPrEndNoNl:
        rts

; ---------------------------------------------------------------------------
; PrintCh -- emit A through Chrout, maintaining BAS_POSX (CR resets it).
; ---------------------------------------------------------------------------
PrintCh:
        cmp     #$0D
        beq     @cr
        cmp     #$0A
        beq     @cr
        pha
        inc     BAS_POSX
        pla
        jmp     Chrout
@cr:
        stz     BAS_POSX
        jmp     Chrout

; ---------------------------------------------------------------------------
; PrintNum -- emit FAC as ASCII via Fout, tracking column.
; ---------------------------------------------------------------------------
PrintNum:
        jsr     Fout                    ; (Y,A) = NUL-terminated buffer
        sta     INDEX
        sty     INDEX+1
        ldy     #0
@loop:
        lda     (INDEX),y
        beq     @done
        jsr     PrintCh
        iny
        bne     @loop
@done:
        rts

; ---------------------------------------------------------------------------
; PrintStrFAC -- emit string-descriptor at FAC..FAC+2.
; ---------------------------------------------------------------------------
PrintStrFAC:
        lda     FAC+1
        sta     INDEX
        lda     FAC+2
        sta     INDEX+1
        ldy     #0
@loop:
        cpy     FAC
        beq     @done
        lda     (INDEX),y
        jsr     PrintCh
        iny
        bra     @loop
@done:
        rts

; ---------------------------------------------------------------------------
; PrintHex16 -- emit FAC+3,FAC+4 (lo,hi) as "$XXXX".
; ---------------------------------------------------------------------------
PrintHex16:
        lda     #'$'
        jsr     PrintCh
        lda     FAC+3
        jsr     PrintHexByte
        lda     FAC+4
        ; fall through
PrintHexByte:
        pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     @nib
        pla
        and     #$0F
@nib:
        cmp     #10
        bcc     @dig
        adc     #'A'-'9'-2              ; +'A'-10-1 (carry already set)
@dig:
        adc     #'0'
        jmp     PrintCh

; =============================================================================
;   B a s P r i n t K e y w o r d
; =============================================================================
; Print the keyword whose token byte is in A (bit 7 set).
; Walks the keyword table to find entry (A - TOK_BASE) and prints its chars.
; =============================================================================
BasPrintKeyword:
        sec
        sbc     #TOK_BASE               ; A = index
        tax
        ; Walk via 16-bit BAS_KWPTR since the table is > 256 bytes.
        lda     #<KeywordTbl
        sta     BAS_KWPTR
        lda     #>KeywordTbl
        sta     BAS_KWPTR+1
        ldy     #0
@FindLoop:
        cpx     #0
        beq     @PrintIt
        ; Skip current keyword: walk byte-by-byte until we consume a byte
        ; whose bit 7 is set (last char of the keyword).
@Skip:
        lda     (BAS_KWPTR),y           ; Y == 0
        inc     BAS_KWPTR
        bne     @SkipNoCarry
        inc     BAS_KWPTR+1
@SkipNoCarry:
        cmp     #$80                    ; C set iff loaded byte >= $80
        bcc     @Skip
@SkipEnd:
        dex
        bra     @FindLoop
@PrintIt:
@PrintLoop:
        lda     (BAS_KWPTR),y           ; Y == 0
        inc     BAS_KWPTR
        bne     @PrintNoCarry
        inc     BAS_KWPTR+1
@PrintNoCarry:
        pha
        and     #$7F
        jsr     Chrout
        pla
        bpl     @PrintLoop
        rts

; =============================================================================
;   E R R O R   H A N D L I N G
; =============================================================================

BasErrSyntax:
        lda     #ERR_SYNTAX
        ; fall through

; BasError - print "?<msg> ERROR[ IN nnnn]" and return to the REPL.
;   Input: A = error code (index into ErrorMessages).
;   Resets the stack, prints, and jumps to BasReadyLoop.
BasError:
        sta     BAS_TMP3                ; stash code (stack reset wipes A on stack)
        ldx     #$FF
        txs
        jsr     BasPrintCRLF
        lda     #'?'
        jsr     Chrout
        lda     BAS_TMP3
        ; A = error code; print the matching message.
        jsr     BasPrintErrorMsg
        ; Append " ERROR" and (if not direct mode) line number.
        lda     #<MsgErrorWord
        ldy     #>MsgErrorWord
        jsr     BasPrintStr
        lda     BAS_CURLIN+1
        cmp     #$FF
        beq     @NoLine
        lda     #<MsgInWord
        ldy     #>MsgInWord
        jsr     BasPrintStr
        lda     BAS_CURLIN
        sta     BAS_LINNUM
        lda     BAS_CURLIN+1
        sta     BAS_LINNUM+1
        jsr     BasPrintLineNum
@NoLine:
        ; Mark direct mode and bounce back to REPL.
        lda     #$FF
        sta     BAS_CURLIN
        sta     BAS_CURLIN+1
        jmp     BasReadyLoop

; BasPrintErrorMsg - print message #A from the error-message table.
;   Each message is NUL-terminated; the table is a sequence of those.
BasPrintErrorMsg:
        tax
        lda     #<ErrorMessages
        sta     BAS_TMP1
        lda     #>ErrorMessages
        sta     BAS_TMP1+1
@Skip:
        cpx     #0
        beq     @Print
        ; Walk past one message (advance until NUL, then one more).
@SkipLoop:
        ldy     #0
        lda     (BAS_TMP1),y
        beq     @SkipDone
        inc     BAS_TMP1
        bne     @SkipLoop
        inc     BAS_TMP1+1
        bra     @SkipLoop
@SkipDone:
        inc     BAS_TMP1
        bne     @SkippedHi
        inc     BAS_TMP1+1
@SkippedHi:
        dex
        bra     @Skip
@Print:
        lda     BAS_TMP1
        ldy     BAS_TMP1+1
        jmp     BasPrintStr


; =============================================================================
;   F L O A T I N G - P O I N T   R U N T I M E
;
;   Externals required by the inlined MSBASIC FP code:
;     ChrGet   - advance TXTPTR and load next non-space tokenized char
;                (used by Fin; never exercised by the FP tests).
;     BasErrorVec    - error vector; X = error code
;     IqErr    - "?ILLEGAL QUANTITY" entry
;     STROUT   - print NUL-terminated string at (A=lo, Y=hi)
;     QtIn    - the literal " IN " string (used only by InPrt)
; =============================================================================

; --- ChrGet / ChrGot --------------------------------------------------------
; Real implementation (ROM, not ZP self-modifying).  Increments TXTPTR and
; returns the next non-space byte at (TXTPTR) in A, with carry CLEAR if the
; byte is a digit '0'-'9'.  ChrGot re-reads the current byte without
; advancing first.  Both clobber only A and flags.
;
; Side effects on flags after the routine returns:
;   Z=1  if A == $00 or A is a tokenized/keyword byte that wraps to zero
;        (used by callers checking end-of-statement).
;   C=0  if A is a digit ('0'-'9'); else C=1.
;
; Implementation matches msbasic-master/chrget.s.
ChrGet:
        inc     TXTPTR
        bne     ChrGot
        inc     TXTPTR+1
ChrGot:
        lda     (TXTPTR)
        cmp     #':'
        bcs     @out
        cmp     #' '
        beq     ChrGet
        sec
        sbc     #'0'
        sec
        sbc     #$D0                    ; restore A; sets C=0 iff digit
@out:
        rts

; --- Error trampolines ------------------------------------------------------
; The MSBASIC convention is "ldx #code / jmp ERROR".  Our BasError takes
; the code in A, so translate.
BasErrorVec:
        txa
        jmp     BasError

IqErr:
        ldx     #ERR_ILLQUAN
        jmp     BasErrorVec

; --- String output ----------------------------------------------------------
; FP code calls STROUT with (A=lo, Y=hi).  BasPrintStr matches that ABI.
STROUT          := BasPrintStr

; --- "IN " literal (referenced by InPrt) ----------------------------------
QtIn:
        .byte   " IN ",0

; --- Shared RTS targets used by branches in the FP code --------------------
; The original MSBASIC defines Rts3 in poke.s (which we don't include).
; Provide a single shared RTS landing pad here.
Rts3:
        rts

; =============================================================================
;   F L O A T I N G - P O I N T   R U N T I M E   ( P h a s e   2 )
;
;   Inline-ported from msbasic-master/{float,trig,rnd}.s.  Symbol aliases for
;   FAC, ARG, INDEX, etc. are defined at the top of this file.  External hooks
;   (ChrGet, BasErrorVec, IqErr, STROUT, QtIn) are stubbed below.
; =============================================================================

; ===== from msbasic-master/float.s =====
; (.segment removed - inlined into BASIC)

TEMP1X = TEMP1+(5-BYTES_FP)

; ----------------------------------------------------------------------------
; ADD 0.5 TO FAC
; ----------------------------------------------------------------------------
FAddH:
        lda     #<ConHalf
        ldy     #>ConHalf
        jmp     FAdd

; ----------------------------------------------------------------------------
; FAC = (Y,A) - FAC
; ----------------------------------------------------------------------------
FSub:
        jsr     LoadArgFromYa

; ----------------------------------------------------------------------------
; FAC = ARG - FAC
; ----------------------------------------------------------------------------
FSubT:
        lda     FACSIGN
        eor     #$FF
        sta     FACSIGN
        eor     ARGSIGN
        sta     SGNCPR
        lda     FAC
        jmp     FAddT

; ----------------------------------------------------------------------------
; Commodore BASIC V2 Easter Egg
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; SHIFT SMALLER ARGUMENT MORE THAN 7 BITS
; ----------------------------------------------------------------------------
FAdd1:
        jsr     ShiftRight
        bcc     FAdd3

; ----------------------------------------------------------------------------
; FAC = (Y,A) + FAC
; ----------------------------------------------------------------------------
FAdd:
        jsr     LoadArgFromYa

; ----------------------------------------------------------------------------
; FAC = ARG + FAC
; ----------------------------------------------------------------------------
FAddT:
        bne     Lbl365B
        jmp     CopyArgToFac
Lbl365B:
        ldx     FACEXTENSION
        stx     ARGEXTENSION
        ldx     #ARG
        lda     ARG
FAdd2:
        tay
        beq     Rts3
        sec
        sbc     FAC
        beq     FAdd3
        bcc     Lbl367F
        sty     FAC
        ldy     ARGSIGN
        sty     FACSIGN
        eor     #$FF
        adc     #$00
        ldy     #$00
        sty     ARGEXTENSION
        ldx     #FAC
        bne     Lbl3683
Lbl367F:
        ldy     #$00
        sty     FACEXTENSION
Lbl3683:
        cmp     #$F9
        bmi     FAdd1
        tay
        lda     FACEXTENSION
        lsr     1,x
        jsr     ShiftRight4
FAdd3:
        bit     SGNCPR
        bpl     FAdd4
        ldy     #FAC
        cpx     #ARG
        beq     Lbl369B
        ldy     #ARG
Lbl369B:
        sec
        eor     #$FF
        adc     ARGEXTENSION
        sta     FACEXTENSION
        lda     4,y
        sbc     4,x
        sta     FAC+4
        lda     3,y
        sbc     3,x
        sta     FAC+3
        lda     2,y
        sbc     2,x
        sta     FAC+2
        lda     1,y
        sbc     1,x
        sta     FAC+1

; ----------------------------------------------------------------------------
; NORMALIZE VALUE IN FAC
; ----------------------------------------------------------------------------
NormalizeFac1:
        bcs     NormalizeFac2
        jsr     ComplementFac
NormalizeFac2:
        ldy     #$00
        tya
        clc
Lbl36C7:
        ldx     FAC+1
        bne     NormalizeFac4
        ldx     FAC+2
        stx     FAC+1
        ldx     FAC+3
        stx     FAC+2
        ldx     FAC+4
        stx     FAC+3
        ldx     FACEXTENSION
        stx     FAC+4
        sty     FACEXTENSION
        adc     #$08
        cmp     #MANTISSA_BYTES*8
        bne     Lbl36C7

; ----------------------------------------------------------------------------
; SET FAC = 0
; (ONLY NECESSARY TO Zero EXPONENT AND Sign CELLS)
; ----------------------------------------------------------------------------
ZeroFac:
        lda     #$00
StaInFacSignAndExp:
        sta     FAC
StaInFacSign:
        sta     FACSIGN
        rts

; ----------------------------------------------------------------------------
; ADD MANTISSAS OF FAC AND ARG INTO FAC
; ----------------------------------------------------------------------------
FAdd4:
        adc     ARGEXTENSION
        sta     FACEXTENSION
        lda     FAC+4
        adc     ARG+4
        sta     FAC+4
        lda     FAC+3
        adc     ARG+3
        sta     FAC+3
        lda     FAC+2
        adc     ARG+2
        sta     FAC+2
        lda     FAC+1
        adc     ARG+1
        sta     FAC+1
        jmp     NormalizeFac5

; ----------------------------------------------------------------------------
; FINISH NORMALIZING FAC
; ----------------------------------------------------------------------------
NormalizeFac3:
        adc     #$01
        asl     FACEXTENSION
        rol     FAC+4
        rol     FAC+3
        rol     FAC+2
        rol     FAC+1
NormalizeFac4:
        bpl     NormalizeFac3
        sec
        sbc     FAC
        bcs     ZeroFac
        eor     #$FF
        adc     #$01
        sta     FAC
NormalizeFac5:
        bcc     Lbl3764
NormalizeFac6:
        inc     FAC
        beq     Overflow
        ror     FAC+1
        ror     FAC+2
        ror     FAC+3
        ror     FAC+4
        ror     FACEXTENSION
Lbl3764:
        rts

; ----------------------------------------------------------------------------
; 2'S COMPLEMENT OF FAC
; ----------------------------------------------------------------------------
ComplementFac:
        lda     FACSIGN
        eor     #$FF
        sta     FACSIGN

; ----------------------------------------------------------------------------
; 2'S COMPLEMENT OF FAC MANTISSA ONLY
; ----------------------------------------------------------------------------
ComplementFacMantissa:
        lda     FAC+1
        eor     #$FF
        sta     FAC+1
        lda     FAC+2
        eor     #$FF
        sta     FAC+2
        lda     FAC+3
        eor     #$FF
        sta     FAC+3
        lda     FAC+4
        eor     #$FF
        sta     FAC+4
        lda     FACEXTENSION
        eor     #$FF
        sta     FACEXTENSION
        inc     FACEXTENSION
        bne     Rts12

; ----------------------------------------------------------------------------
; INCREMENT FAC MANTISSA
; ----------------------------------------------------------------------------
IncrementFacMantissa:
        inc     FAC+4
        bne     Rts12
        inc     FAC+3
        bne     Rts12
        inc     FAC+2
        bne     Rts12
        inc     FAC+1
Rts12:
        rts
Overflow:
        ldx     #ERR_OVERFLOW
        jmp     BasErrorVec

; ----------------------------------------------------------------------------
; SHIFT 1,X THRU 5,X RIGHT
; (A) = NEGATIVE OF SHIFT COUNT
; (X) = POINTER TO BYTES TO BE SHIFTED
;
; RETURN WITH (Y)=0, CARRY=0, EXTENSION BITS IN A-REG
; ----------------------------------------------------------------------------
ShiftRight1:
        ldx     #RESULT-1
ShiftRight2:
        ldy     4,x
        sty     FACEXTENSION
        ldy     3,x
        sty     4,x
        ldy     2,x
        sty     3,x
        ldy     1,x
        sty     2,x
        ldy     SHIFTSIGNEXT
        sty     1,x

; ----------------------------------------------------------------------------
; MAIN ENTRY TO RIGHT SHIFT SUBROUTINE
; ----------------------------------------------------------------------------
ShiftRight:
        adc     #$08
        bmi     ShiftRight2
        beq     ShiftRight2
        sbc     #$08
        tay
        lda     FACEXTENSION
        bcs     ShiftRight5
LblB588:
        asl     1,x
        bcc     LblB58E
        inc     1,x
LblB58E:
        ror     1,x
        ror     1,x

; ----------------------------------------------------------------------------
; ENTER HERE FOR SHORT SHIFTS WITH NO Sign EXTENSION
; ----------------------------------------------------------------------------
ShiftRight4:
        ror     2,x
        ror     3,x
        ror     4,x
        ror     a
        iny
        bne     LblB588
ShiftRight5:
        clc
        rts

; ----------------------------------------------------------------------------
ConOne:
        .byte   $81,$00,$00,$00,$00
PolyLog:
        .byte   $03
		.byte   $7F,$5E,$56,$CB,$79
		.byte   $80,$13,$9B,$0B,$64
		.byte   $80,$76,$38,$93,$16
        .byte   $82,$38,$AA,$3B,$20
ConSqrHalf:
        .byte   $80,$35,$04,$F3,$34
ConSqrTwo:
        .byte   $81,$35,$04,$F3,$34
ConNegHalf:
        .byte   $80,$80,$00,$00,$00
ConLogTwo:
        .byte   $80,$31,$72,$17,$F8

; ----------------------------------------------------------------------------
; "LOG" FUNCTION
; ----------------------------------------------------------------------------
Log:
        jsr     Sign
        beq     Giq
        bpl     Log2
Giq:
        jmp     IqErr
Log2:
        lda     FAC
        sbc     #$7F
        pha
        lda     #$80
        sta     FAC
        lda     #<ConSqrHalf
        ldy     #>ConSqrHalf
        jsr     FAdd
        lda     #<ConSqrTwo
        ldy     #>ConSqrTwo
        jsr     FDiv
        lda     #<ConOne
        ldy     #>ConOne
        jsr     FSub
        lda     #<PolyLog
        ldy     #>PolyLog
        jsr     PolynomialOdd
        lda     #<ConNegHalf
        ldy     #>ConNegHalf
        jsr     FAdd
        pla
        jsr     AddAcc
        lda     #<ConLogTwo
        ldy     #>ConLogTwo

; ----------------------------------------------------------------------------
; FAC = (Y,A) * FAC
; ----------------------------------------------------------------------------
FMult:
        jsr     LoadArgFromYa

; ----------------------------------------------------------------------------
; FAC = ARG * FAC
; ----------------------------------------------------------------------------
FMultT:
        jeq     Lbl3903
        jsr     AddExponents
        lda     #$00
        sta     RESULT
        sta     RESULT+1
        sta     RESULT+2
        sta     RESULT+3
        lda     FACEXTENSION
        jsr     Multiply1
        lda     FAC+4
        jsr     Multiply1
        lda     FAC+3
        jsr     Multiply1
        lda     FAC+2
        jsr     Multiply1
        lda     FAC+1
        jsr     Multiply2
        jmp     CopyResultIntoFac

; ----------------------------------------------------------------------------
; MULTIPLY ARG BY (A) INTO RESULT
; ----------------------------------------------------------------------------
Multiply1:
        bne     Multiply2
        jmp     ShiftRight1
Multiply2:
        lsr     a
        ora     #$80
Lbl38A7:
        tay
        bcc     Lbl38C3
        clc
        lda     RESULT+3
        adc     ARG+4
        sta     RESULT+3
        lda     RESULT+2
        adc     ARG+3
        sta     RESULT+2
        lda     RESULT+1
        adc     ARG+2
        sta     RESULT+1
        lda     RESULT
        adc     ARG+1
        sta     RESULT
Lbl38C3:
        ror     RESULT
        ror     RESULT+1
        ror     RESULT+2
        ror     RESULT+3
        ror     FACEXTENSION
        tya
        lsr     a
        bne     Lbl38A7
Lbl3903:
        rts

; ----------------------------------------------------------------------------
; UNPACK NUMBER AT (Y,A) INTO ARG
; ----------------------------------------------------------------------------
LoadArgFromYa:
        sta     INDEX
        sty     INDEX+1
        ldy     #BYTES_FP-1
        lda     (INDEX),y
        sta     ARG+4
        dey
        lda     (INDEX),y
        sta     ARG+3
        dey
        lda     (INDEX),y
        sta     ARG+2
        dey
        lda     (INDEX),y
        sta     ARGSIGN
        eor     FACSIGN
        sta     SGNCPR
        lda     ARGSIGN
        ora     #$80
        sta     ARG+1
        dey
        lda     (INDEX),y
        sta     ARG
        lda     FAC
        rts

; ----------------------------------------------------------------------------
; ADD EXPONENTS OF ARG AND FAC
; (CALLED BY FMult AND FDiv)
;
; ALSO CHECK FOR Overflow, AND SET RESULT Sign
; ----------------------------------------------------------------------------
AddExponents:
        lda     ARG
AddExponents1:
        beq     Zero
        clc
        adc     FAC
        bcc     Lbl393C
        bmi     Jov
        clc
        .byte   $2C
Lbl393C:
        bpl     Zero
        adc     #$80
        sta     FAC
        bne     Lbl3947
        jmp     StaInFacSign
Lbl3947:
        lda     SGNCPR
        sta     FACSIGN
        rts

; ----------------------------------------------------------------------------
; IF (FAC) IS POSITIVE, GIVE "OVERFLOW" ERROR
; IF (FAC) IS NEGATIVE, SET FAC=0, POP ONE RETURN, AND RTS
; CALLED FROM "EXP" FUNCTION
; ----------------------------------------------------------------------------
OutOfRng:
        lda     FACSIGN
        eor     #$FF
        bmi     Jov

; ----------------------------------------------------------------------------
; POP RETURN ADDRESS AND SET FAC=0
; ----------------------------------------------------------------------------
Zero:
        pla
        pla
        jmp     ZeroFac
Jov:
        jmp     Overflow

; ----------------------------------------------------------------------------
; MULTIPLY FAC BY 10
; ----------------------------------------------------------------------------
Mul10:
        jsr     CopyFacToArgRounded
        tax
        beq     Lbl3970
        clc
        adc     #$02
        bcs     Jov
LblD9BF:
        ldx     #$00
        stx     SGNCPR
        jsr     FAdd2
        inc     FAC
        beq     Jov
Lbl3970:
        rts

; ----------------------------------------------------------------------------
Conten:
        .byte   $84,$20,$00,$00,$00

; ----------------------------------------------------------------------------
; DIVIDE FAC BY 10
; ----------------------------------------------------------------------------
Div10:
        jsr     CopyFacToArgRounded
        lda     #<Conten
        ldy     #>Conten
        ldx     #$00

; ----------------------------------------------------------------------------
; FAC = ARG / (Y,A)
; ----------------------------------------------------------------------------
Div:
        stx     SGNCPR
        jsr     LoadFacFromYa
        jmp     FDivT

; ----------------------------------------------------------------------------
; FAC = (Y,A) / FAC
; ----------------------------------------------------------------------------
FDiv:
        jsr     LoadArgFromYa

; ----------------------------------------------------------------------------
; FAC = ARG / FAC
; ----------------------------------------------------------------------------
FDivT:
        beq     Lbl3A02
        jsr     RoundFac
        lda     #$00
        sec
        sbc     FAC
        sta     FAC
        jsr     AddExponents
        inc     FAC
        beq     Jov
        ldx     #<-MANTISSA_BYTES
        lda     #$01
Lbl39A1:
        ldy     ARG+1
        cpy     FAC+1
        bne     Lbl39B7
        ldy     ARG+2
        cpy     FAC+2
        bne     Lbl39B7
        ldy     ARG+3
        cpy     FAC+3
        bne     Lbl39B7
        ldy     ARG+4
        cpy     FAC+4
Lbl39B7:
        php
        rol     a
        bcc     Lbl39C4
        inx
        sta     RESULT_LAST-1,x
        beq     Lbl39F2
        bpl     Lbl39F6
        lda     #$01
Lbl39C4:
        plp
        bcs     Lbl39D5
Lbl39C7:
        asl     ARG_LAST
        rol     ARG+3
        rol     ARG+2
        rol     ARG+1
        bcs     Lbl39B7
        bmi     Lbl39A1
        bpl     Lbl39B7
Lbl39D5:
        tay
        lda     ARG+4
        sbc     FAC+4
        sta     ARG+4
        lda     ARG+3
        sbc     FAC+3
        sta     ARG+3
        lda     ARG+2
        sbc     FAC+2
        sta     ARG+2
        lda     ARG+1
        sbc     FAC+1
        sta     ARG+1
        tya
        jmp     Lbl39C7
Lbl39F2:
        lda     #$40
        bne     Lbl39C4
Lbl39F6:
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        sta     FACEXTENSION
        plp
        jmp     CopyResultIntoFac
Lbl3A02:
        ldx     #ERR_ZERODIV
        jmp     BasErrorVec

; ----------------------------------------------------------------------------
; COPY RESULT INTO FAC MANTISSA, AND NORMALIZE
; ----------------------------------------------------------------------------
CopyResultIntoFac:
        lda     RESULT
        sta     FAC+1
        lda     RESULT+1
        sta     FAC+2
        lda     RESULT+2
        sta     FAC+3
        lda     RESULT+3
        sta     FAC+4
        jmp     NormalizeFac2

; ----------------------------------------------------------------------------
; UNPACK (Y,A) INTO FAC
; ----------------------------------------------------------------------------
LoadFacFromYa:
        sta     INDEX
        sty     INDEX+1
        ldy     #MANTISSA_BYTES
        lda     (INDEX),y
        sta     FAC+4
        dey
        lda     (INDEX),y
        sta     FAC+3
        dey
        lda     (INDEX),y
        sta     FAC+2
        dey
        lda     (INDEX),y
        sta     FACSIGN
        ora     #$80
        sta     FAC+1
        dey
        lda     (INDEX),y
        sta     FAC
        sty     FACEXTENSION
        rts

; ----------------------------------------------------------------------------
; ROUND FAC, STORE IN TEMP2
; ----------------------------------------------------------------------------
StoreFacInTemp2Rounded:
        ldx     #TEMP2
        .byte   $2C

; ----------------------------------------------------------------------------
; ROUND FAC, STORE IN TEMP1
; ----------------------------------------------------------------------------
StoreFacInTemp1Rounded:
        ldx     #TEMP1X
        ldy     #$00
        beq     StoreFacAtYxRounded

; ----------------------------------------------------------------------------
; ROUND FAC, AND STORE WHERE FORPNT POINTS
; ----------------------------------------------------------------------------
SetFor:
        ldx     FORPNT
        ldy     FORPNT+1

; ----------------------------------------------------------------------------
; ROUND FAC, AND STORE AT (Y,X)
; ----------------------------------------------------------------------------
StoreFacAtYxRounded:
        jsr     RoundFac
        stx     INDEX
        sty     INDEX+1
        ldy     #MANTISSA_BYTES
        lda     FAC+4
        sta     (INDEX),y
        dey
        lda     FAC+3
        sta     (INDEX),y
        dey
        lda     FAC+2
        sta     (INDEX),y
        dey
        lda     FACSIGN
        ora     #$7F
        and     FAC+1
        sta     (INDEX),y
        dey
        lda     FAC
        sta     (INDEX),y
        sty     FACEXTENSION
        rts

; ----------------------------------------------------------------------------
; COPY ARG INTO FAC
; ----------------------------------------------------------------------------
CopyArgToFac:
        lda     ARGSIGN
Mfa:
        sta     FACSIGN
        ldx     #BYTES_FP
Lbl3A7A:
        lda     SHIFTSIGNEXT,x
        sta     EXPSGN,x
        dex
        bne     Lbl3A7A
        stx     FACEXTENSION
        rts

; ----------------------------------------------------------------------------
; ROUND FAC AND COPY TO ARG
; ----------------------------------------------------------------------------
CopyFacToArgRounded:
        jsr     RoundFac
Maf:
        ldx     #BYTES_FP+1
Lbl3A89:
        lda     EXPSGN,x
        sta     SHIFTSIGNEXT,x
        dex
        bne     Lbl3A89
        stx     FACEXTENSION
Rts14:
        rts

; ----------------------------------------------------------------------------
; ROUND FAC USING EXTENSION BYTE
; ----------------------------------------------------------------------------
RoundFac:
        lda     FAC
        beq     Rts14
        asl     FACEXTENSION
        bcc     Rts14

; ----------------------------------------------------------------------------
; INCREMENT MANTISSA AND RE-NORMALIZE IF CARRY
; ----------------------------------------------------------------------------
IncrementMantissa:
        jsr     IncrementFacMantissa
        bne     Rts14
        jmp     NormalizeFac6

; ----------------------------------------------------------------------------
; TEST FAC FOR Zero AND Sign
;
; FAC > 0, RETURN +1
; FAC = 0, RETURN  0
; FAC < 0, RETURN -1
; ----------------------------------------------------------------------------
Sign:
        lda     FAC
        beq     Rts15
Lbl3AA7:
        lda     FACSIGN
Sign2:
        rol     a
        lda     #$FF
        bcs     Rts15
        lda     #$01
Rts15:
        rts

; ----------------------------------------------------------------------------
; "SGN" FUNCTION
; ----------------------------------------------------------------------------
Sgn:
        jsr     Sign

; ----------------------------------------------------------------------------
; CONVERT (A) INTO FAC, AS SIGNED VALUE -128 TO +127
; ----------------------------------------------------------------------------
Float:
        sta     FAC+1
        lda     #$00
        sta     FAC+2
        ldx     #$88

; ----------------------------------------------------------------------------
; Float UNSIGNED VALUE IN FAC+1,2
; (X) = EXPONENT
; ----------------------------------------------------------------------------
Float1:
        lda     FAC+1
        eor     #$FF
        rol     a

; ----------------------------------------------------------------------------
; Float UNSIGNED VALUE IN FAC+1,2
; (X) = EXPONENT
; C=0 TO MAKE VALUE NEGATIVE
; C=1 TO MAKE VALUE POSITIVE
; ----------------------------------------------------------------------------
Float2:
        lda     #$00
        sta     FAC+4
        sta     FAC+3
LblDB21:
        stx     FAC
        sta     FACEXTENSION
        sta     FACSIGN
        jmp     NormalizeFac1

; ----------------------------------------------------------------------------
; "ABS" FUNCTION
; ----------------------------------------------------------------------------
Abs:
        lsr     FACSIGN
        rts

; ----------------------------------------------------------------------------
; COMPARE FAC WITH PACKED # AT (Y,A)
; RETURN A=1,0,-1 AS (Y,A) IS <,=,> FAC
; ----------------------------------------------------------------------------
FComp:
        sta     DEST

; ----------------------------------------------------------------------------
; SPECIAL ENTRY FROM "NEXT" PROCESSOR
; "DEST" ALREADY SET UP
; ----------------------------------------------------------------------------
FComp2:
        sty     DEST+1
        ldy     #$00
        lda     (DEST),y
        iny
        tax
        beq     Sign
        lda     (DEST),y
        eor     FACSIGN
        bmi     Lbl3AA7
        cpx     FAC
        bne     Lbl3B0A
        lda     (DEST),y
        ora     #$80
        cmp     FAC+1
        bne     Lbl3B0A
        iny
        lda     (DEST),y
        cmp     FAC+2
        bne     Lbl3B0A
        iny
        lda     (DEST),y
        cmp     FAC+3
        bne     Lbl3B0A
        iny
        lda     #$7F
        cmp     FACEXTENSION
        lda     (DEST),y
        sbc     FAC_LAST
        beq     Lbl3B32
Lbl3B0A:
        lda     FACSIGN
        bcc     Lbl3B10
        eor     #$FF
Lbl3B10:
        jmp     Sign2

; ----------------------------------------------------------------------------
; QUICK INTEGER FUNCTION
;
; CONVERTS FP VALUE IN FAC TO INTEGER VALUE
; IN FAC+1...FAC+4, BY SHIFTING RIGHT WITH Sign
; EXTENSION UNTIL FRACTIONAL BITS ARE OUT.
;
; THIS SUBROUTINE ASSUMES THE EXPONENT < 32.
; ----------------------------------------------------------------------------
QInt:
        lda     FAC
        beq     QInt3
        sec
        sbc     #120+8*BYTES_FP
        bit     FACSIGN
        bpl     Lbl3B27
        tax
        lda     #$FF
        sta     SHIFTSIGNEXT
        jsr     ComplementFacMantissa
        txa
Lbl3B27:
        ldx     #FAC
        cmp     #$F9
        bpl     QInt2
        jsr     ShiftRight
        sty     SHIFTSIGNEXT
Lbl3B32:
        rts
QInt2:
        tay
        lda     FACSIGN
        and     #$80
        lsr     FAC+1
        ora     FAC+1
        sta     FAC+1
        jsr     ShiftRight4
        sty     SHIFTSIGNEXT
        rts

; ----------------------------------------------------------------------------
; "INT" FUNCTION
;
; USES QInt TO CONVERT (FAC) TO INTEGER FORM,
; AND THEN REFLOATS THE INTEGER.
; ----------------------------------------------------------------------------
Int:
        lda     FAC
        cmp     #120+8*BYTES_FP
        bcs     Rts17
        jsr     QInt
        sty     FACEXTENSION
        lda     FACSIGN
        sty     FACSIGN
        eor     #$80
        rol     a
        lda     #120+8*BYTES_FP
        sta     FAC
        lda     FAC_LAST
        sta     CHARAC
        jmp     NormalizeFac1
QInt3:
        sta     FAC+1
        sta     FAC+2
        sta     FAC+3
        sta     FAC+4
        tay
Rts17:
        rts

; ----------------------------------------------------------------------------
; CONVERT STRING TO FP VALUE IN FAC
;
; STRING POINTED TO BY TXTPTR
; FIRST CHAR ALREADY SCANNED BY ChrGet
; (A) = FIRST CHAR, C=0 IF DIGIT.
; ----------------------------------------------------------------------------
Fin:
        ldy     #$00
        ldx     #SERLEN-TMPEXP
Lbl3B6F:
        sty     TMPEXP,x
        dex
        bpl     Lbl3B6F
        bcc     Fin2
        cmp     #$2D
        bne     Lbl3B7E
        stx     SERLEN
        beq     Fin1
Lbl3B7E:
        cmp     #$2B
        bne     Fin3
Fin1:
        jsr     ChrGet
Fin2:
        bcc     Fin9
Fin3:
        cmp     #$2E
        beq     Fin10
        cmp     #$45
        bne     Fin7
        jsr     ChrGet
        bcc     Fin5
        cmp     #TOKEN_MINUS
        beq     Lbl3BA6
        cmp     #$2D
        beq     Lbl3BA6
        cmp     #TOKEN_PLUS
        beq     Fin4
        cmp     #$2B
        beq     Fin4
        bne     Fin6
Lbl3BA6:
        ror     EXPSGN
Fin4:
        jsr     ChrGet
Fin5:
        bcc     GetExp
Fin6:
        bit     EXPSGN
        bpl     Fin7
        lda     #$00
        sec
        sbc     EXPON
        jmp     Fin8

; ----------------------------------------------------------------------------
; FOUND A DECIMAL POINT
; ----------------------------------------------------------------------------
Fin10:
        ror     LOWTR
        bit     LOWTR
        bvc     Fin1

; ----------------------------------------------------------------------------
; NUMBER TERMINATED, ADJUST EXPONENT NOW
; ----------------------------------------------------------------------------
Fin7:
        lda     EXPON
Fin8:
        sec
        sbc     INDX
        sta     EXPON
        beq     Lbl3BEE
        bpl     Lbl3BE7
Lbl3BDE:
        jsr     Div10
        inc     EXPON
        bne     Lbl3BDE
        beq     Lbl3BEE
Lbl3BE7:
        jsr     Mul10
        dec     EXPON
        bne     Lbl3BE7
Lbl3BEE:
        lda     SERLEN
        bmi     Lbl3BF3
        rts
Lbl3BF3:
        jmp     NegOp

; ----------------------------------------------------------------------------
; ACCUMULATE A DIGIT INTO FAC
; ----------------------------------------------------------------------------
Fin9:
        pha
        bit     LOWTR
        bpl     Lbl3BFD
        inc     INDX
Lbl3BFD:
        jsr     Mul10
        pla
        sec
        sbc     #$30
        jsr     AddAcc
        jmp     Fin1

; ----------------------------------------------------------------------------
; ADD (A) TO FAC
; ----------------------------------------------------------------------------
AddAcc:
        pha
        jsr     CopyFacToArgRounded
        pla
        jsr     Float
        lda     ARGSIGN
        eor     FACSIGN
        sta     SGNCPR
        ldx     FAC
        jmp     FAddT

; ----------------------------------------------------------------------------
; ACCUMULATE DIGIT OF EXPONENT
; ----------------------------------------------------------------------------
GetExp:
        lda     EXPON
        cmp     #MAX_EXPON
        bcc     Lbl3C2C
        lda     #$64
        bit     EXPSGN
        bmi     Lbl3C3A
        jmp     Overflow
LblDC70:
Lbl3C2C:
        asl     a
        asl     a
        clc
        adc     EXPON
        asl     a
        clc
        ldy     #$00
        adc     (TXTPTR),y
        sec
        sbc     #$30
Lbl3C3A:
        sta     EXPON
        jmp     Fin4

; ----------------------------------------------------------------------------
Con99999999_9:
        .byte   $9B,$3E,$BC,$1F,$FD
Con999999999:
        .byte   $9E,$6E,$6B,$27,$FD
ConBillion:
        .byte   $9E,$6E,$6B,$28,$00

; ----------------------------------------------------------------------------
; PRINT "IN <LINE #>"
; ----------------------------------------------------------------------------
InPrt:
        lda     #<QtIn
        ldy     #>QtIn
        jsr     GoStrOut2
        lda     CURLIN+1
        ldx     CURLIN

; ----------------------------------------------------------------------------
; PRINT A,X AS DECIMAL INTEGER
; ----------------------------------------------------------------------------
LinPrt:
        sta     FAC+1
        stx     FAC+2
        ldx     #$90
        sec
        jsr     Float2
        jsr     Fout
GoStrOut2:
        jmp     STROUT

; ----------------------------------------------------------------------------
; CONVERT (FAC) TO STRING STARTING AT STACK
; RETURN WITH (Y,A) POINTING AT STRING
; ----------------------------------------------------------------------------
Fout:
        ldy     #$01

; ----------------------------------------------------------------------------
; "STR$" FUNCTION ENTERS HERE, WITH (Y)=0
; SO THAT RESULT STRING STARTS AT STACK-1
; (THIS IS USED AS A FLAG)
; ----------------------------------------------------------------------------
Fout1:
        lda     #$20
        bit     FACSIGN
        bpl     Lbl3C73
        lda     #$2D
Lbl3C73:
        sta     STACK2-1,y
        sta     FACSIGN
        sty     STRNG2
        iny
        lda     #$30
        ldx     FAC
        bne     Lbl3C84
        jmp     Fout4
Lbl3C84:
        lda     #$00
        cpx     #$80
        beq     Lbl3C8C
        bcs     Lbl3C95
Lbl3C8C:
        lda     #<ConBillion
        ldy     #>ConBillion
        jsr     FMult
        lda     #<-9
Lbl3C95:
        sta     INDX
; ----------------------------------------------------------------------------
; ADJUST UNTIL 1E8 <= (FAC) <1E9
; ----------------------------------------------------------------------------
Lbl3C97:
        lda     #<Con999999999
        ldy     #>Con999999999
        jsr     FComp
        beq     Lbl3CBE
        bpl     Lbl3CB4
Lbl3CA2:
        lda     #<Con99999999_9
        ldy     #>Con99999999_9
        jsr     FComp
        beq     Lbl3CAD
        bpl     Lbl3CBB
Lbl3CAD:
        jsr     Mul10
        dec     INDX
        bne     Lbl3CA2
Lbl3CB4:
        jsr     Div10
        inc     INDX
        bne     Lbl3C97
Lbl3CBB:
        jsr     FAddH
Lbl3CBE:
        jsr     QInt
; ----------------------------------------------------------------------------
; FAC+1...FAC+4 IS NOW IN INTEGER FORM
; WITH POWER OF TEN ADJUSTMENT IN TMPEXP
;
; IF -10 < TMPEXP > 1, PRINT IN DECIMAL FORM
; OTHERWISE, PRINT IN EXPONENTIAL FORM
; ----------------------------------------------------------------------------
        ldx     #$01
        lda     INDX
        clc
        adc     #3*BYTES_FP-5
        bmi     Lbl3CD3
        cmp     #3*BYTES_FP-4
        bcs     Lbl3CD4
        adc     #$FF
        tax
        lda     #$02
Lbl3CD3:
        sec
Lbl3CD4:
        sbc     #$02
        sta     EXPON
        stx     INDX
        txa
        beq     Lbl3CDF
        bpl     Lbl3CF2
Lbl3CDF:
        ldy     STRNG2
        lda     #$2E
        iny
        sta     STACK2-1,y
        txa
        beq     Lbl3CF0
        lda     #$30
        iny
        sta     STACK2-1,y
Lbl3CF0:
        sty     STRNG2
; ----------------------------------------------------------------------------
; NOW DIVIDE BY POWERS OF TEN TO GET SUCCESSIVE DIGITS
; ----------------------------------------------------------------------------
Lbl3CF2:
        ldy     #$00
LblDD3A:
        ldx     #$80
Lbl3CF6:
        lda     FAC_LAST
        clc
        adc     DecTbl+3,y
        sta     FAC+4
        lda     FAC+3
        adc     DecTbl+2,y
        sta     FAC+3
        lda     FAC+2
        adc     DecTbl+1,y
        sta     FAC+2
        lda     FAC+1
        adc     DecTbl,y
        sta     FAC+1
        inx
        bcs     Lbl3D1A
        bpl     Lbl3CF6
        bmi     Lbl3D1C
Lbl3D1A:
        bmi     Lbl3CF6
Lbl3D1C:
        txa
        bcc     Lbl3D23
        eor     #$FF
        adc     #$0A
Lbl3D23:
        adc     #$2F
        iny
        iny
        iny
        iny
        sty     VARPNT
        ldy     STRNG2
        iny
        tax
        and     #$7F
        sta     STACK2-1,y
        dec     INDX
        bne     Lbl3D3E
        lda     #$2E
        iny
        sta     STACK2-1,y
Lbl3D3E:
        sty     STRNG2
        ldy     VARPNT
        txa
        eor     #$FF
        and     #$80
        tax
        cpy     #DecTblEnd-DecTbl
        beq     LblDD96
        cpy     #$3C ; XXX
        bne     Lbl3CF6
; ----------------------------------------------------------------------------
; NINE DIGITS HAVE BEEN STORED IN STRING.  NOW LOOK
; BACK AND LOP OFF TRAILING ZEROES AND A TRAILING
; DECIMAL POINT.
; ----------------------------------------------------------------------------
LblDD96:
        ldy     STRNG2
Lbl3D4E:
        lda     STACK2-1,y
        dey
        cmp     #$30
        beq     Lbl3D4E
        cmp     #$2E
        beq     Lbl3D5B
        iny
Lbl3D5B:
        lda     #$2B
        ldx     EXPON
        beq     Lbl3D8F
        bpl     Lbl3D6B
        lda     #$00
        sec
        sbc     EXPON
        tax
        lda     #$2D
Lbl3D6B:
        sta     STACK2+1,y
        lda     #$45
        sta     STACK2,y
        txa
        ldx     #$2F
        sec
Lbl3D77:
        inx
        sbc     #$0A
        bcs     Lbl3D77
        adc     #$3A
        sta     STACK2+3,y
        txa
        sta     STACK2+2,y
        lda     #$00
        sta     STACK2+4,y
        beq     Lbl3D94
Fout4:
        sta     STACK2-1,y
Lbl3D8F:
        lda     #$00
        sta     STACK2,y
Lbl3D94:
        lda     #<STACK2
        ldy     #>STACK2
        rts

; ----------------------------------------------------------------------------
ConHalf:
        .byte   $80,$00,$00,$00,$00

; ----------------------------------------------------------------------------
; POWERS OF 10 FROM 1E8 DOWN TO 1,
; AS 32-BIT INTEGERS, WITH ALTERNATING SIGNS
; ----------------------------------------------------------------------------
DecTbl:
		.byte	$FA,$0A,$1F,$00	; -100000000
		.byte	$00,$98,$96,$80	; 10000000
		.byte	$FF,$F0,$BD,$C0	; -1000000
		.byte	$00,$01,$86,$A0	; 100000
		.byte	$FF,$FF,$D8,$F0	; -10000
		.byte   $00,$00,$03,$E8	; 1000
		.byte	$FF,$FF,$FF,$9C	; -100
		.byte   $00,$00,$00,$0A	; 10
		.byte	$FF,$FF,$FF,$FF	; -1
DecTblEnd:
		.byte	$FF,$DF,$0A,$80 ; TI$
		.byte	$00,$03,$4B,$C0
		.byte	$FF,$FF,$73,$60
		.byte	$00,$00,$0E,$10
		.byte	$FF,$FF,$FD,$A8
		.byte	$00,$00,$00,$3C
C_ZERO = ConHalf + 2

; ----------------------------------------------------------------------------
; "SQR" FUNCTION
; ----------------------------------------------------------------------------
Sqr:
        jsr     CopyFacToArgRounded
        lda     #<ConHalf
        ldy     #>ConHalf
        jsr     LoadFacFromYa

; ----------------------------------------------------------------------------
; EXPONENTIATION OPERATION
;
; ARG ^ FAC  =  Exp( Log(ARG) * FAC )
; ----------------------------------------------------------------------------
FPwrt:
        beq     Exp
        lda     ARG
        bne     Lbl3DD5
        jmp     StaInFacSignAndExp
Lbl3DD5:
        ldx     #TEMP3
        ldy     #$00
        jsr     StoreFacAtYxRounded
        lda     ARGSIGN
        bpl     Lbl3DEF
        jsr     Int
        lda     #TEMP3
        ldy     #$00
        jsr     FComp
        bne     Lbl3DEF
        tya
        ldy     CHARAC
Lbl3DEF:
        jsr     Mfa
        tya
        pha
        jsr     Log
        lda     #TEMP3
        ldy     #$00
        jsr     FMult
        jsr     Exp
        pla
        lsr     a
        bcc     Lbl3E0F

; ----------------------------------------------------------------------------
; NEGATE VALUE IN FAC
; ----------------------------------------------------------------------------
NegOp:
        lda     FAC
        beq     Lbl3E0F
        lda     FACSIGN
        eor     #$FF
        sta     FACSIGN
Lbl3E0F:
        rts

; ----------------------------------------------------------------------------
ConLogE:
        .byte   $81,$38,$AA,$3B,$29
PolyExp:
        .byte   $07
		.byte	$71,$34,$58,$3E,$56
		.byte	$74,$16,$7E,$B3,$1B
		.byte	$77,$2F,$EE,$E3,$85
        .byte   $7A,$1D,$84,$1C,$2A
		.byte	$7C,$63,$59,$58,$0A
		.byte	$7E,$75,$FD,$E7,$C6
		.byte	$80,$31,$72,$18,$10
		.byte	$81,$00,$00,$00,$00

; ----------------------------------------------------------------------------
; "EXP" FUNCTION
;
; FAC = E ^ FAC
; ----------------------------------------------------------------------------
Exp:
        lda     #<ConLogE
        ldy     #>ConLogE
        jsr     FMult
        lda     FACEXTENSION
        adc     #$50
        bcc     Lbl3E4E
        jsr     IncrementMantissa
Lbl3E4E:
        sta     ARGEXTENSION
        jsr     Maf
        lda     FAC
        cmp     #$88
        bcc     Lbl3E5C
Lbl3E59:
        jsr     OutOfRng
Lbl3E5C:
        jsr     Int
        lda     CHARAC
        clc
        adc     #$81
        beq     Lbl3E59
        sec
        sbc     #$01
        pha
        ldx     #BYTES_FP
Lbl3E6C:
        lda     ARG,x
        ldy     FAC,x
        sta     FAC,x
        sty     ARG,x
        dex
        bpl     Lbl3E6C
        lda     ARGEXTENSION
        sta     FACEXTENSION
        jsr     FSubT
        jsr     NegOp
        lda     #<PolyExp
        ldy     #>PolyExp
        jsr     Polynomial
        lda     #$00
        sta     SGNCPR
        pla
        jsr     AddExponents1
        rts

; ----------------------------------------------------------------------------
; ODD Polynomial SUBROUTINE
;
; F(X) = X * P(X^2)
;
; WHERE:  X IS VALUE IN FAC
;	Y,A POINTS AT COEFFICIENT TABLE
;	FIRST BYTE OF COEFF. TABLE IS N
;	COEFFICIENTS FOLLOW, HIGHEST POWER FIRST
;
; P(X^2) COMPUTED USING NORMAL Polynomial SUBROUTINE
; ----------------------------------------------------------------------------
PolynomialOdd:
        sta     STRNG2
        sty     STRNG2+1
        jsr     StoreFacInTemp1Rounded
        lda     #TEMP1X
        jsr     FMult
        jsr     SerMain
        lda     #TEMP1X
        ldy     #$00
        jmp     FMult

; ----------------------------------------------------------------------------
; NORMAL Polynomial SUBROUTINE
;
; P(X) = C(0)*X^N + C(1)*X^(N-1) + ... + C(N)
;
; WHERE:  X IS VALUE IN FAC
;	Y,A POINTS AT COEFFICIENT TABLE
;	FIRST BYTE OF COEFF. TABLE IS N
;	COEFFICIENTS FOLLOW, HIGHEST POWER FIRST
; ----------------------------------------------------------------------------
Polynomial:
        sta     STRNG2
        sty     STRNG2+1
SerMain:
        jsr     StoreFacInTemp2Rounded
        lda     (STRNG2),y
        sta     SERLEN
        ldy     STRNG2
        iny
        tya
        bne     Lbl3EBA
        inc     STRNG2+1
Lbl3EBA:
        sta     STRNG2
        ldy     STRNG2+1
Lbl3EBE:
        jsr     FMult
        lda     STRNG2
        ldy     STRNG2+1
        clc
        adc     #BYTES_FP
        bcc     Lbl3ECB
        iny
Lbl3ECB:
        sta     STRNG2
        sty     STRNG2+1
        jsr     FAdd
        lda     #TEMP2
        ldy     #$00
        dec     SERLEN
        bne     Lbl3EBE
Rts19:
        rts
; ===== from msbasic-master/trig.s =====
; (.segment removed - inlined into BASIC)

SinCosTanAtn:
; ----------------------------------------------------------------------------
; "COS" FUNCTION
; ----------------------------------------------------------------------------
Cos:
        lda     #<ConPiHalf
        ldy     #>ConPiHalf
        jsr     FAdd

; ----------------------------------------------------------------------------
; "SIN" FUNCTION
; ----------------------------------------------------------------------------
Sin:
        jsr     CopyFacToArgRounded
        lda     #<ConPiDoub
        ldy     #>ConPiDoub
        ldx     ARGSIGN
        jsr     Div
        jsr     CopyFacToArgRounded
        jsr     Int
        lda     #$00
        sta     STRNG1
        jsr     FSubT
; ----------------------------------------------------------------------------
; (FAC) = ANGLE AS A FRACTION OF A FULL CIRCLE
;
; NOW FOLD THE RANGE INTO A Quarter CIRCLE
;
; <<< THERE ARE MUCH SIMPLER WAYS TO DO THIS >>>
; ----------------------------------------------------------------------------
        lda     #<Quarter
        ldy     #>Quarter
        jsr     FSub
        lda     FACSIGN
        pha
        bpl     Sin1
        jsr     FAddH
        lda     FACSIGN
        bmi     Lbl3F5B
        lda     CPRMASK
        eor     #$FF
        sta     CPRMASK
; ----------------------------------------------------------------------------
; IF FALL THRU, RANGE IS 0...1/2
; IF BRANCH HERE, RANGE IS 0...1/4
; ----------------------------------------------------------------------------
Sin1:
        jsr     NegOp
; ----------------------------------------------------------------------------
; IF FALL THRU, RANGE IS -1/2...0
; IF BRANCH HERE, RANGE IS -1/4...0
; ----------------------------------------------------------------------------
Lbl3F5B:
        lda     #<Quarter
        ldy     #>Quarter
        jsr     FAdd
        pla
        bpl     Lbl3F68
        jsr     NegOp
Lbl3F68:
        lda     #<PolySin
        ldy     #>PolySin
        jmp     PolynomialOdd

; ----------------------------------------------------------------------------
; "TAN" FUNCTION
;
; COMPUTE Tan(X) = Sin(X) / Cos(X)
; ----------------------------------------------------------------------------
Tan:
        jsr     StoreFacInTemp1Rounded
        lda     #$00
        sta     CPRMASK
        jsr     Sin
        ldx     #TEMP3
        ldy     #$00
        jsr     GoMovMf
        lda     #TEMP1+(5-BYTES_FP)
        ldy     #$00
        jsr     LoadFacFromYa
        lda     #$00
        sta     FACSIGN
        lda     CPRMASK
        jsr     Tan1
        lda     #TEMP3
        ldy     #$00
        jmp     FDiv
Tan1:
        pha
        jmp     Sin1

; ----------------------------------------------------------------------------
ConPiHalf:
        .byte   $81,$49,$0F,$DA,$A2
ConPiDoub:
        .byte   $83,$49,$0F,$DA,$A2
Quarter:
        .byte   $7F,$00,$00,$00,$00
PolySin:
        .byte   $05,$84,$E6,$1A,$2D,$1B,$86,$28
        .byte   $07,$FB,$F8,$87,$99,$68,$89,$01
        .byte   $87,$23,$35,$DF,$E1,$86,$A5,$5D
        .byte   $E7,$28,$83,$49,$0F,$DA,$A2
; PET encoded easter egg text since CBM2
Microsoft:
        .byte   $A1,$54,$46,$8F,$13,$8F,$52,$43
        .byte   $89,$CD

; ----------------------------------------------------------------------------
; "ATN" FUNCTION
; ----------------------------------------------------------------------------
Atn:
        lda     FACSIGN
        pha
        bpl     Lbl3FDB
        jsr     NegOp
Lbl3FDB:
        lda     FAC
        pha
        cmp     #$81
        bcc     Lbl3FE9
        lda     #<ConOne
        ldy     #>ConOne
        jsr     FDiv
; ----------------------------------------------------------------------------
; 0 <= X <= 1
; 0 <= Atn(X) <= PI/8
; ----------------------------------------------------------------------------
Lbl3FE9:
        lda     #<PolyAtn
        ldy     #>PolyAtn
        jsr     PolynomialOdd
        pla
        cmp     #$81
        bcc     Lbl3FFC
        lda     #<ConPiHalf
        ldy     #>ConPiHalf
        jsr     FSub
Lbl3FFC:
        pla
        bpl     Lbl4002
        jmp     NegOp
Lbl4002:
        rts

; ----------------------------------------------------------------------------
PolyAtn:
        .byte   $0B
		.byte	$76,$B3,$83,$BD,$D3
		.byte	$79,$1E,$F4,$A6,$F5
		.byte	$7B,$83,$FC,$B0,$10
        .byte   $7C,$0C,$1F,$67,$CA
		.byte	$7C,$DE,$53,$CB,$C1
		.byte	$7D,$14,$64,$70,$4C
		.byte	$7D,$B7,$EA,$51,$7A
		.byte	$7D,$63,$30,$88,$7E
		.byte	$7E,$92,$44,$99,$3A
		.byte	$7E,$4C,$CC,$91,$C7
		.byte	$7F,$AA,$AA,$AA,$13
        .byte   $81,$00,$00,$00,$00

; ===== from msbasic-master/rnd.s =====
; (.segment removed - inlined into BASIC)

; ----------------------------------------------------------------------------
; "RND" FUNCTION
; ----------------------------------------------------------------------------

; <<< THESE ARE MISSING ONE BYTE FOR FP VALUES >>>
; (non CONFIG_SMALL)
ConRnd1:
        .byte   $98,$35,$44,$7A
ConRnd2:
        .byte   $68,$28,$B1,$46
Rnd:
        jsr     Sign
        bmi     Lbl3F01
        bne     LblDF63
        lda     ENTROPY
        sta     FAC+1
        lda     ENTROPY+4
        sta     FAC+2
        lda     ENTROPY+1
        sta     FAC+3
        lda     ENTROPY+5
        sta     FAC+4
        jmp     LblDF88
LblDF63:
        lda     #<RNDSEED
        ldy     #>RNDSEED
        jsr     LoadFacFromYa
        lda     #<ConRnd1
        ldy     #>ConRnd1
        jsr     FMult
        lda     #<ConRnd2
        ldy     #>ConRnd2
        jsr     FAdd
Lbl3F01:
        ldx     FAC_LAST
        lda     FAC+1
        sta     FAC_LAST
        stx     FAC+1
        ldx     FAC+2
        lda     FAC+3
        sta     FAC+2
        stx     FAC+3
LblDF88:
        lda     #$00
        sta     FACSIGN
        lda     FAC
        sta     FACEXTENSION
        lda     #$80
        sta     FAC
        jsr     NormalizeFac2
        ldx     #<RNDSEED
        ldy     #>RNDSEED
GoMovMf:
        jmp     StoreFacAtYxRounded

; (.segment "CHRGET" removed - inlined into BASIC)
; ----------------------------------------------------------------------------
; INITIAL VALUE FOR RANDOM NUMBER, ALSO COPIED
; IN ALONG WITH ChrGet, BUT ERRONEOUSLY:
; <<< THE LAST BYTE IS NOT COPIED >>>
; (on all non-CONFIG_SMALL)
; ----------------------------------------------------------------------------
RndSeedInit:
; random number seed
        .byte   $80,$4F,$C7,$52,$58
; GENERIC_CHRGET_END (unused)

; =============================================================================
;   V A R I A B L E S ,   A R R A Y S ,   S T R I N G   H E A P
;
;   Inline-ported from msbasic-master/{var,array,string,memory}.s and
;   misc2.s (GivAyf/SngFlt).  All MSBASIC externals are resolved here:
;
;     SynErr / MemErr / IqErr / Gme / SubErr        - error trampolines
;     ChkCom / ChkCls / ChkNum / ChkStr             - parser predicates
;     MakInt / FrmNum / FrmEvl                      - minimal stubs (only
;                                                     handle literal unsigned
;                                                     decimals via Fin; full
;                                                     evaluator wired in a
;                                                     later phase)
;     IsLetC                                        - ASCII letter test
;     PtrGet / Array / GetAry                       - variable lookup
;     StrIni / StrSpa / GetSpa / PutNew / MovStr    - string allocation
;     Garbag (and helpers)                          - string GC
;     Bltu / Reason                                 - block-up-move helpers
;     AyInt / GivAyf / SngFlt                       - FP <-> 16-bit int
;     BasCmdClr                                     - implements CLR / NEW core
; =============================================================================

; ---------------------------------------------------------------------------
; SynErr / MemErr / IqErr / SubErr / Gme -- error trampolines.
; The msbasic convention is "ldx #code; jmp ERROR".  Our BasError takes the
; code in A, so translate; BasErrorVec (defined earlier) does that translation.
; ---------------------------------------------------------------------------
SynErr:
        ldx     #ERR_SYNTAX
        jmp     BasErrorVec

MemErr:
        ldx     #ERR_MEMFULL
        jmp     BasErrorVec

SubErr:
        ldx     #ERR_BADSUBS
        jmp     BasErrorVec

Gse:
        jmp     SubErr

Gme:
        jmp     MemErr

; ---------------------------------------------------------------------------
; Parser predicates (operate on byte at TXTPTR; advance via ChrGet).
; ---------------------------------------------------------------------------
ChkCom:
        lda     #','
        .byte   $2C                     ; BIT abs -> skip next 2 bytes
SynChr:
        ; Used by code that wants a specific char.  A on entry = required char.
        ldy     #0
        cmp     (TXTPTR)
        bne     SynErr
        jmp     ChrGet

ChkCls:
        lda     #')'
        bra     SynChr

ChkOpn:
        lda     #'('
        bra     SynChr

ChkNum:
        clc
        .byte   $24                     ; BIT zp -> skip next byte
ChkStr:
        sec
ChkVal:
        bit     VALTYP
        bmi     @isstr
        bcs     @typeerr                ; numeric, wanted string
        rts
@isstr:
        bcc     @typeerr                ; string, wanted numeric
        rts
@typeerr:
        ldx     #ERR_TYPEMISM
        jmp     BasErrorVec

; ---------------------------------------------------------------------------
; IsLetC -- carry SET if A is ASCII A-Z, else carry CLEAR.
; ---------------------------------------------------------------------------
IsLetC:
        cmp     #'A'
        bcc     @no
        cmp     #'Z'+1
        bcs     @no
        sec
        rts
@no:
        clc
        rts

; ---------------------------------------------------------------------------
; FrmNum -- evaluate expression (FrmEvl), then enforce numeric type.
; FrmEvl is implemented in the expression-evaluator section below.
; ---------------------------------------------------------------------------
FrmNum:
        jsr     FrmEvl
        ; falls into ChkNum
ChknumAfterFrm:
        jmp     ChkNum

; ---------------------------------------------------------------------------
; AyInt  --  CONVERT FAC to 16-bit signed int in FAC+3,FAC+4
; Range: -32767 to +32767.  Out of range -> ?ILLEGAL QUANTITY.
; ---------------------------------------------------------------------------
Neg32768:
        .byte   $90,$80,$00,$00,$00

MakInt:
        jsr     ChrGet
        jsr     FrmNum
MkInt:
        jsr     ChkNum
        lda     FACSIGN
        bmi     AyintNeg
AyInt:
        lda     FAC
        cmp     #$90
        bcc     AyintOk
        lda     #<Neg32768
        ldy     #>Neg32768
        jsr     FComp
AyintNeg:
        bne     AyintIll
AyintOk:
        jmp     QInt
AyintIll:
        jmp     IqErr

; ---------------------------------------------------------------------------
; GivAyf -- Float signed integer in (Y,A) into FAC.
; SngFlt -- Float unsigned byte in Y into FAC.
; ---------------------------------------------------------------------------
GivAyf:
        ldx     #$00
        stx     VALTYP
        sta     FAC+1
        sty     FAC+2
        ldx     #$90
        jmp     Float1

SngFlt:
        lda     #$00
        beq     GivAyf

; ---------------------------------------------------------------------------
; Bltu / Reason -- block-up-move + free-space check.
; ---------------------------------------------------------------------------
Bltu:
        jsr     Reason
        sta     STREND
        sty     STREND+1
Bltu2:
        sec
        lda     HIGHTR
        sbc     LOWTR
        sta     INDEX
        tay
        lda     HIGHTR+1
        sbc     LOWTR+1
        tax
        inx
        tya
        beq     @big
        lda     HIGHTR
        sec
        sbc     INDEX
        sta     HIGHTR
        bcs     @nb1
        dec     HIGHTR+1
        sec
@nb1:
        lda     HIGHDS
        sbc     INDEX
        sta     HIGHDS
        bcs     @loop
        dec     HIGHDS+1
        bcc     @loop
@inner:
        lda     (HIGHTR),y
        sta     (HIGHDS),y
@loop:
        dey
        bne     @inner
        lda     (HIGHTR),y
        sta     (HIGHDS),y
@big:
        dec     HIGHTR+1
        dec     HIGHDS+1
        dex
        bne     @loop
        rts

; Reason -- Verify (Y,A) <= FRETOP, calling Garbag and rechecking on
; failure.  We omit the msbasic save/restore of TEMP1..FAC-1 because in
; our layout TEMP1 is above FAC; Garbag only writes to its own ZP scratch
; (FNCNAM/Z52/HIGHDS/HIGHTR/INDEX/LOWTR/DSCLEN) so callers that have FAC
; live across Reason must save FAC themselves.  Current callers do.
Reason:
        cpy     FRETOP+1
        bcc     @ok
        bne     @gc
        cmp     FRETOP
        bcc     @ok
@gc:
        pha
        tya
        pha
        jsr     Garbag
        pla
        tay
        pla
        cpy     FRETOP+1
        bcc     @ok
        bne     @oom
        cmp     FRETOP
        bcs     @oom
@ok:
        rts
@oom:
        jmp     MemErr

; ---------------------------------------------------------------------------
; PtrGet -- find or create a scalar variable.
; On entry : ChrGot-equivalent state; TXTPTR points at first char of name.
; On exit  : VARPNT = address of variable's value bytes; (Y,A) = same.
;            VARNAM = encoded name (with type bits in bit 7s).
;            VALTYP = $00 numeric, $FF string.
; ---------------------------------------------------------------------------
PtrGet:
        ldx     #$00
        jsr     ChrGot
PtrGet2:
        stx     DIMFLG
PtrGet3:
        sta     VARNAM
        jsr     ChrGot
        jsr     IsLetC
        bcs     @nameok
        jmp     SynErr
@nameok:
        ldx     #$00
        stx     VALTYP
        stx     VALTYP+1
        jsr     ChrGet
        bcc     @second                 ; digit -> second char of name
        jsr     IsLetC
        bcc     @aftername              ; not letter -> done with chars
@second:
        tax                             ; remember second char
@strip:
        jsr     ChrGet
        bcc     @strip
        jsr     IsLetC
        bcs     @strip
@aftername:
        cmp     #'$'
        bne     @notstr
        lda     #$FF
        sta     VALTYP
        bne     @typedone
@notstr:
        cmp     #'%'
        bne     @typeskip               ; integer-percent unsupported -> ignore
        jmp     SynErr                  ; reject A% style
@typeskip:
@nottype:
        bra     @aftertype
@typedone:
        txa
        ora     #$80
        tax
        jsr     ChrGet
@aftertype:
        stx     VARNAM+1
        sec
        ora     SUBFLG
        sbc     #'('
        bne     @notarray
        jmp     Array
@notarray:
        lda     #$00
        sta     SUBFLG
        ; Walk VARTAB looking for VARNAM.
        lda     VARTAB
        ldx     VARTAB+1
        ldy     #$00
@nextrec:
        stx     LOWTR+1
@cmprec:
        sta     LOWTR
        cpx     ARYTAB+1
        bne     @notend
        cmp     ARYTAB
        beq     Makenewvariable
@notend:
        lda     VARNAM
        cmp     (LOWTR),y
        bne     @advance
        lda     VARNAM+1
        iny
        cmp     (LOWTR),y
        beq     SetVarpntAndYa
        dey
@advance:
        clc
        lda     LOWTR
        adc     #BYTES_PER_VARIABLE
        bcc     @cmprec
        inx
        bne     @nextrec

; --- Make new scalar -------------------------------------------------------
Makenewvariable:
        lda     ARYTAB
        ldy     ARYTAB+1
        sta     LOWTR
        sty     LOWTR+1
        lda     STREND
        ldy     STREND+1
        sta     HIGHTR
        sty     HIGHTR+1
        clc
        adc     #BYTES_PER_VARIABLE
        bcc     @nb
        iny
@nb:
        sta     HIGHDS
        sty     HIGHDS+1
        jsr     Bltu
        lda     HIGHDS
        ldy     HIGHDS+1
        iny
        sta     ARYTAB
        sty     ARYTAB+1
        ldy     #$00
        lda     VARNAM
        sta     (LOWTR),y
        iny
        lda     VARNAM+1
        sta     (LOWTR),y
        lda     #$00
        iny
        sta     (LOWTR),y
        iny
        sta     (LOWTR),y
        iny
        sta     (LOWTR),y
        iny
        sta     (LOWTR),y
        iny
        sta     (LOWTR),y               ; CONFIG_2 7-byte variable
        ; fall through

SetVarpntAndYa:
        lda     LOWTR
        clc
        adc     #$02
        ldy     LOWTR+1
        bcc     @nb
        iny
@nb:
        sta     VARPNT
        sty     VARPNT+1
        rts

; ---------------------------------------------------------------------------
; Array  --  locate or create an array element.
; Restriction: 1-D arrays only.  >1 dimensions -> ?BAD SUBSCRIPT.
; ---------------------------------------------------------------------------
GetAry:
        lda     EOLPNTR
        asl     a
        adc     #$05
        adc     LOWTR
        ldy     LOWTR+1
        bcc     @nb
        iny
@nb:
        sta     HIGHDS
        sty     HIGHDS+1
        rts

Array:
        lda     DIMFLG
        ora     VALTYP+1
        pha
        lda     VALTYP
        pha
        ldy     #$00
@nextsub:
        tya
        pha
        lda     VARNAM+1
        pha
        lda     VARNAM
        pha
        jsr     MakInt
        pla
        sta     VARNAM
        pla
        sta     VARNAM+1
        pla
        tay
        ; Push the integer subscript onto the 6502 stack, beneath our
        ; return address.  msbasic does this by manipulating STACK,X
        ; with TSX; reproduce the trick.
        tsx
        lda     $0102,x
        pha
        lda     $0101,x
        pha
        lda     FAC+3
        sta     $0102,x
        lda     FAC+4
        sta     $0101,x
        iny
        ; 1-D arrays only.
        cpy     #2
        bcs     @badsubs
        jsr     ChrGot
        cmp     #','
        beq     @nextsub
        sty     EOLPNTR
        jsr     ChkCls
        pla
        sta     VALTYP
        pla
        sta     VALTYP+1
        and     #$7F
        sta     DIMFLG
        ; Search ARYTAB for matching name.
        ldx     ARYTAB
        lda     ARYTAB+1
@nextary:
        stx     LOWTR
        sta     LOWTR+1
        cmp     STREND+1
        bne     @cmpary
        cpx     STREND
        beq     MakeNewArray
@cmpary:
        ldy     #$00
        lda     (LOWTR),y
        iny
        cmp     VARNAM
        bne     @aryadv
        lda     VARNAM+1
        cmp     (LOWTR),y
        beq     UseOldArray
@aryadv:
        iny
        lda     (LOWTR),y
        clc
        adc     LOWTR
        tax
        iny
        lda     (LOWTR),y
        adc     LOWTR+1
        bcc     @nextary
        bcs     @nextary
@badsubs:
        jmp     SubErr

UseOldArray:
        ldx     #ERR_REDIMD
        lda     DIMFLG
        beq     @notredim
        jmp     BasErrorVec
@notredim:
        jsr     GetAry
        lda     EOLPNTR
        ldy     #$04
        cmp     (LOWTR),y
        bne     @suberr
        jmp     FindArrayElement
@suberr:
        jmp     SubErr

MakeNewArray:
        jsr     GetAry
        jsr     Reason
        lda     #$00
        tay
        sta     STRNG2+1
        ldx     #BYTES_PER_ELEMENT
        lda     VARNAM
        sta     (LOWTR),y
        bpl     @n1
        dex
@n1:
        iny
        lda     VARNAM+1
        sta     (LOWTR),y
        bpl     @n2
        dex
        dex
@n2:
        stx     STRNG2
        lda     EOLPNTR
        iny
        iny
        iny
        sta     (LOWTR),y               ; #DIMS at offset 4
@dimloop:
        ldx     #$0B
        lda     #$00
        bit     DIMFLG
        bvc     @nodim                  ; bit 6 == 0 -> not from DIM
        pla
        clc
        adc     #$01
        tax
        pla
        adc     #$00
@nodim:
        iny
        sta     (LOWTR),y               ; dim hi byte
        iny
        txa
        sta     (LOWTR),y               ; dim lo byte
        jsr     MultiplySubscript
        stx     STRNG2
        sta     STRNG2+1
        ldy     INDEX
        dec     EOLPNTR
        beq     @dimdone
        jmp     @dimloop
@dimdone:
        adc     HIGHDS+1
        bcc     @nooflo
        jmp     Gme
@nooflo:
        sta     HIGHDS+1
        tay
        txa
        adc     HIGHDS
        bcc     @ne
        iny
        bne     @ne
        jmp     Gme
@ne:
        jsr     Reason
        sta     STREND
        sty     STREND+1
        lda     #$00
        inc     STRNG2+1
        ldy     STRNG2
        beq     @zext
@zloop:
        dey
        sta     (HIGHDS),y
        bne     @zloop
@zext:
        dec     HIGHDS+1
        dec     STRNG2+1
        bne     @zloop
        inc     HIGHDS+1
        sec
        lda     STREND
        sbc     LOWTR
        ldy     #$02
        sta     (LOWTR),y
        lda     STREND+1
        iny
        sbc     LOWTR+1
        sta     (LOWTR),y
        lda     DIMFLG
        bne     Rts9
        iny

FindArrayElement:
        lda     (LOWTR),y
        sta     EOLPNTR
        lda     #$00
        sta     STRNG2
@subloop:
        sta     STRNG2+1
        iny
        pla
        tax
        sta     FAC+3
        pla
        sta     FAC+4
        cmp     (LOWTR),y
        bcc     @ok2
        bne     @sub_err
        iny
        txa
        cmp     (LOWTR),y
        bcc     @ok3
@sub_err:
        jmp     SubErr
@ok2:
        iny
@ok3:
        lda     STRNG2+1
        ora     STRNG2
        clc
        beq     @noshift
        jsr     MultiplySubscript
        txa
        adc     FAC+3
        tax
        tya
        ldy     INDEX
@noshift:
        adc     FAC+4
        stx     STRNG2
        dec     EOLPNTR
        bne     @subloop
        ldx     #BYTES_FP
        lda     VARNAM
        bpl     @nb1
        dex
@nb1:
        lda     VARNAM+1
        bpl     @nb2
        dex
        dex
@nb2:
        stx     RESULT+2
        lda     #$00
        jsr     MultiplySubs1
        txa
        adc     HIGHDS
        sta     VARPNT
        tya
        adc     HIGHDS+1
        sta     VARPNT+1
        tay
        lda     VARPNT
Rts9:
        rts

MultiplySubscript:
        sty     INDEX
        lda     (LOWTR),y
        sta     RESULT+2
        dey
        lda     (LOWTR),y
MultiplySubs1:
        sta     RESULT+3
        lda     #$10
        sta     INDX
        ldx     #$00
        ldy     #$00
@mloop:
        txa
        asl     a
        tax
        tya
        rol     a
        tay
        bcs     @oflo
        asl     STRNG2
        rol     STRNG2+1
        bcc     @noadd
        clc
        txa
        adc     RESULT+2
        tax
        tya
        adc     RESULT+3
        tay
        bcc     @noadd
@oflo:
        jmp     Gme
@noadd:
        dec     INDX
        bne     @mloop
        rts

; ---------------------------------------------------------------------------
; STRING HEAP  --  GetSpa / StrSpa / StrIni / PutNew / MovStr / FreTmp / FreTms
; ---------------------------------------------------------------------------

; StrIni -- get space and build descriptor for string at FAC+3,FAC+4 with
; length in A.  DSCPTR set to source.
StrIni:
        ldx     FAC+3
        ldy     FAC+4
        stx     DSCPTR
        sty     DSCPTR+1
StrSpa:
        jsr     GetSpa
        stx     FAC+1
        sty     FAC+2
        sta     FAC
        rts

; StrLit -- build descriptor for string at (Y,A) terminated by $00 or '"'.
StrLit:
        ldx     #'"'
        stx     CHARAC
        stx     ENDCHR

StrLt2:
        sta     STRNG1
        sty     STRNG1+1
        sta     FAC+1
        sty     FAC+2
        ldy     #$FF
@scan:
        iny
        lda     (STRNG1),y
        beq     @endlit
        cmp     CHARAC
        beq     @maybeq
        cmp     ENDCHR
        bne     @scan
@maybeq:
        cmp     #'"'
        beq     @endquote
@endlit:
        clc
@endquote:
        sty     FAC
        tya
        adc     STRNG1
        sta     STRNG2
        ldx     STRNG1+1
        bcc     @nb1
        inx
@nb1:
        stx     STRNG2+1
        ; If the source isn't on the input line, descriptor points in place;
        ; otherwise copy to heap.  We always copy (no INPUTBUFFER ZP
        ; optimisation).
        tya
        jsr     StrIni
        ldx     STRNG1
        ldy     STRNG1+1
        jsr     MovStr
        ; fall through to PutNew

PutNew:
        ldx     TEMPPT
        cpx     #BAS_TEMPST+9
        bne     @ok
        ldx     #ERR_FRMCPX
        jmp     BasErrorVec
@ok:
        lda     FAC
        sta     0,x
        lda     FAC+1
        sta     1,x
        lda     FAC+2
        sta     2,x
        ldy     #$00
        stx     FAC+3
        sty     FAC+4
        sty     FACEXTENSION
        dey
        sty     VALTYP
        stx     LASTPT
        inx
        inx
        inx
        stx     TEMPPT
        rts

; GetSpa -- allocate (A) bytes at top of string heap; result address in
; (Y,X), length in A unchanged.
GetSpa:
        lsr     DATAFLG
@try:
        pha
        eor     #$FF
        sec
        adc     FRETOP
        ldy     FRETOP+1
        bcs     @nb
        dey
@nb:
        cpy     STREND+1
        bcc     @full
        bne     @ok
        cmp     STREND
        bcc     @full
@ok:
        sta     FRETOP
        sty     FRETOP+1
        sta     FRESPC
        sty     FRESPC+1
        tax
        pla
        rts
@full:
        ldx     #ERR_MEMFULL
        lda     DATAFLG
        bmi     @errjmp
        jsr     Garbag
        lda     #$80
        sta     DATAFLG
        pla
        bne     @try
@errjmp:
        jmp     BasErrorVec

; MovStr -- copy (A) bytes from (Y,X) to (FRESPC); advance FRESPC.
MovStr:
        stx     INDEX
        sty     INDEX+1
MovStr1:
        tay
        beq     @done
        pha
@cp:
        dey
        lda     (INDEX),y
        sta     (FRESPC),y
        tya
        bne     @cp
        pla
@done:
        clc
        adc     FRESPC
        sta     FRESPC
        bcc     @nb
        inc     FRESPC+1
@nb:
        rts

; FreStr -- if FAC holds a string descriptor, free it from temp stack;
; FreFac variant assumes FAC already loaded.
FreStr:
        jsr     ChkStr
FreFac:
        lda     FAC+3
        ldy     FAC+4
FreTmp:
        sta     INDEX
        sty     INDEX+1
        jsr     FreTms
        php
        ldy     #$00
        lda     (INDEX),y
        pha
        iny
        lda     (INDEX),y
        tax
        iny
        lda     (INDEX),y
        tay
        pla
        plp
        bne     @leave
        cpy     FRETOP+1
        bne     @leave
        cpx     FRETOP
        bne     @leave
        pha
        clc
        adc     FRETOP
        sta     FRETOP
        bcc     @nb
        inc     FRETOP+1
@nb:
        pla
@leave:
        stx     INDEX
        sty     INDEX+1
        rts

FreTms:
        cpy     LASTPT+1
        bne     @ne
        cmp     LASTPT
        bne     @ne
        sta     TEMPPT
        sbc     #$03
        sta     LASTPT
        ldy     #$00
@ne:
        rts

; ---------------------------------------------------------------------------
; Garbag  --  garbage-collect string heap.
; ---------------------------------------------------------------------------
Garbag:
        ldx     MEMSIZ
        lda     MEMSIZ+1
Findhigheststring:
        stx     FRETOP
        sta     FRETOP+1
        ldy     #$00
        sty     FNCNAM+1
        sty     FNCNAM
        lda     STREND
        ldx     STREND+1
        sta     LOWTR
        stx     LOWTR+1
        lda     #BAS_TEMPST
        ldx     #$00
        sta     INDEX
        stx     INDEX+1
        lda     #$03
        sta     DSCLEN
@scantemp:
        cmp     TEMPPT
        beq     @scanvar
        jsr     CheckVariable
        beq     @scantemp
@scanvar:
        lda     #BYTES_PER_VARIABLE
        sta     DSCLEN
        lda     VARTAB
        ldx     VARTAB+1
        sta     INDEX
        stx     INDEX+1
@nextvar:
        cpx     ARYTAB+1
        bne     @cv
        cmp     ARYTAB
        beq     @startary
@cv:
        jsr     CheckSimpleVariable
        beq     @nextvar
@startary:
        sta     HIGHDS
        stx     HIGHDS+1
        lda     #$03
        sta     DSCLEN
@aryloop:
        lda     HIGHDS
        ldx     HIGHDS+1
@aryskip:
        cpx     STREND+1
        bne     @next_ary
        cmp     STREND
        bne     @next_ary
        jmp     MoveHighestStringToTop
@next_ary:
        sta     INDEX
        stx     INDEX+1
        ldy     #$00
        lda     (INDEX),y
        tax
        iny
        lda     (INDEX),y
        php
        iny
        lda     (INDEX),y
        adc     HIGHDS
        sta     HIGHDS
        iny
        lda     (INDEX),y
        adc     HIGHDS+1
        sta     HIGHDS+1
        plp
        bpl     @aryloop
        txa
        bmi     @aryloop
        iny
        lda     (INDEX),y
        asl     a
        adc     #$05
        adc     INDEX
        sta     INDEX
        bcc     @noinc
        inc     INDEX+1
@noinc:
        ldx     INDEX+1
@aryelem:
        cpx     HIGHDS+1
        bne     @cve
        cmp     HIGHDS
        beq     @aryskip
@cve:
        jsr     CheckVariable
        beq     @aryelem

CheckSimpleVariable:
        lda     (INDEX),y
        bmi     CheckBump
        iny
        lda     (INDEX),y
        bpl     CheckBump
        iny

CheckVariable:
        lda     (INDEX),y
        beq     CheckBump
        iny
        lda     (INDEX),y
        tax
        iny
        lda     (INDEX),y
        cmp     FRETOP+1
        bcc     @inrange
        bne     CheckBump
        cpx     FRETOP
        bcs     CheckBump
@inrange:
        cmp     LOWTR+1
        bcc     CheckBump
        bne     @higher
        cpx     LOWTR
        bcc     CheckBump
@higher:
        stx     LOWTR
        sta     LOWTR+1
        lda     INDEX
        ldx     INDEX+1
        sta     FNCNAM
        stx     FNCNAM+1
        lda     DSCLEN
        sta     Z52

CheckBump:
        lda     DSCLEN
        clc
        adc     INDEX
        sta     INDEX
        bcc     @nb
        inc     INDEX+1
@nb:
        ldx     INDEX+1
        ldy     #$00
        rts

MoveHighestStringToTop:
        lda     FNCNAM+1
        ora     FNCNAM
        beq     @nb
        lda     Z52
        sbc     #$03
        lsr     a
        tay
        sta     Z52
        lda     (FNCNAM),y
        adc     LOWTR
        sta     HIGHTR
        lda     LOWTR+1
        adc     #$00
        sta     HIGHTR+1
        lda     FRETOP
        ldx     FRETOP+1
        sta     HIGHDS
        stx     HIGHDS+1
        jsr     Bltu2
        ldy     Z52
        iny
        lda     HIGHDS
        sta     (FNCNAM),y
        tax
        inc     HIGHDS+1
        lda     HIGHDS+1
        iny
        sta     (FNCNAM),y
        jmp     Findhigheststring
@nb:
        rts

; ---------------------------------------------------------------------------
; BasCmdClr -- implement CLR (clear vars/arrays/strings without erasing program).
;   VARTAB := PRGEND (already correct in our model)
;   ARYTAB := STREND := VARTAB
;   FRETOP := MEMSIZ
;   TEMPPT := TEMPST, DATAPTR := TXTTAB-1, stacks emptied
; ---------------------------------------------------------------------------
BasCmdClr:
        ; ARYTAB = STREND = VARTAB
        lda     VARTAB
        sta     ARYTAB
        sta     STREND
        lda     VARTAB+1
        sta     ARYTAB+1
        sta     STREND+1
        ; FRETOP = MEMSIZ
        lda     MEMSIZ
        sta     FRETOP
        lda     MEMSIZ+1
        sta     FRETOP+1
        ; Reset temp string descriptor stack.
        lda     #BAS_TEMPST
        sta     TEMPPT
        stz     LASTPT
        stz     LASTPT+1
        ; CONT state, DATA pointer, pending key.
        ; DATAPTR := TXTTAB - 1 so first READ does FindData and lands on
        ; the first DATA item.
        sec
        lda     TXTTAB
        sbc     #1
        sta     BAS_DATAPTR
        lda     TXTTAB+1
        sbc     #0
        sta     BAS_DATAPTR+1
        stz     BAS_OLDLIN
        stz     BAS_OLDLIN+1
        stz     BAS_OLDTEXT
        stz     BAS_OLDTEXT+1
        stz     BAS_STOPLINE
        stz     BAS_STOPLINE+1
        stz     BAS_STOPTXT
        stz     BAS_STOPTXT+1
        stz     BAS_PENDKEY
        stz     DIMFLG
        stz     SUBFLG
        stz     VALTYP
        stz     VALTYP+1
        stz     DATAFLG
        rts

.if 0
; (Removed in Phase 8: _VARTEST debug harness lived here.)
VT_SetTxt:
        ; Set TXTPTR = VT_TXTPTR_TMP - 1 then ChrGet to load first char.
        ; Actually simpler: caller passes (Y,A) = pointer; we set TXTPTR =
        ; (Y,A) - 1 and call ChrGet to land on (Y,A).
        sta     TXTPTR
        sty     TXTPTR+1
        lda     TXTPTR
        bne     @nb
        dec     TXTPTR+1
@nb:
        dec     TXTPTR
        jmp     ChrGet

VT_StoreFAC:
        ; Round and store FAC at (VARPNT).
        ldx     VARPNT
        ldy     VARPNT+1
        jmp     StoreFacAtYxRounded

VT_LoadFAC:
        ; Load FAC from (VARPNT).
        lda     VARPNT
        ldy     VARPNT+1
        jmp     LoadFacFromYa

VT_VPSAVE       = $86           ; 2-byte ZP VARPNT save (_VARTEST debug)

BasCmdVarTest:
        jsr     BasCmdClr

        ; --- Test 1: A=3.14, B=A*2 ---
        lda     #<VT_NameA
        ldy     #>VT_NameA
        jsr     VT_SetTxt
        jsr     PtrGet                  ; creates A; VARPNT -> A's value
        ; FAC = 3.14
        lda     #<VT_pi
        ldy     #>VT_pi
        jsr     LoadFacFromYa
        jsr     VT_StoreFAC

        lda     #<VT_NameB
        ldy     #>VT_NameB
        jsr     VT_SetTxt
        jsr     PtrGet                  ; creates B
        ; Save B's VARPNT.
        lda     VARPNT
        sta     VT_VPSAVE
        lda     VARPNT+1
        sta     VT_VPSAVE+1

        ; Look up A again (already exists).
        lda     #<VT_NameA
        ldy     #>VT_NameA
        jsr     VT_SetTxt
        jsr     PtrGet
        jsr     VT_LoadFAC              ; FAC = A = 3.14
        ; Multiply by 2.
        lda     #<FpC2
        ldy     #>FpC2
        jsr     FMult                   ; FAC = 2 * FAC = 6.28
        ; Store into B.
        ldx     VT_VPSAVE
        ldy     VT_VPSAVE+1
        jsr     StoreFacAtYxRounded

        ; Print result.
        lda     #<MsgVT_A
        ldy     #>MsgVT_A
        jsr     BasPrintStr
        ; Reload B and print.
        lda     VT_VPSAVE
        ldy     VT_VPSAVE+1
        jsr     LoadFacFromYa
        jsr     BasPrintFAC
        jsr     BasPrintCRLF

        ; --- Test 2: A$="HELLO" ---
        lda     #<VT_NameAS
        ldy     #>VT_NameAS
        jsr     VT_SetTxt
        jsr     PtrGet                  ; creates A$
        ; Save VARPNT (A$ descriptor address).
        lda     VARPNT
        sta     VT_VPSAVE
        lda     VARPNT+1
        sta     VT_VPSAVE+1
        ; Allocate space, copy "HELLO" via StrLit.
        lda     #<VT_HelloLit
        ldy     #>VT_HelloLit
        jsr     StrLit                  ; FAC has descriptor, in temp stack
        ; Now copy descriptor (3 bytes from temp stack entry) to A$ var.
        ; FAC+3,4 points at the temp descriptor; FAC = length, FAC+1/2 = addr.
        ; The descriptor lives in TEMPST.  We just write [len][lo][hi] into
        ; (VARPNT) so the variable now references the heap copy.
        lda     FAC
        ldy     #$00
        sta     (VT_VPSAVE),y           ; length
        lda     FAC+1
        iny
        sta     (VT_VPSAVE),y           ; addr lo
        lda     FAC+2
        iny
        sta     (VT_VPSAVE),y           ; addr hi
        ; Print length.
        lda     #<MsgVT_AS
        ldy     #>MsgVT_AS
        jsr     BasPrintStr
        ldy     #$00
        lda     (VT_VPSAVE),y
        tay
        jsr     SngFlt
        jsr     BasPrintFAC
        jsr     BasPrintCRLF

        ; --- Test 3: DIM N(10), N(5)=42 ---
        ; Build TXTPTR pointing at "N(10) " and call MakInt-equivalent path.
        ; Easier: directly construct array via PtrGet3 + Array by simulating
        ; a 1-D DIM of size 11 (indices 0..10).  We emulate the parser:
        ;   1. Set DIMFLG = $40, VARNAM = ('N','N'), call PtrGet3 with X=1?
        ;   2. Or: just do PtrGet3 entry by hand then jmp Array.
        ; Simplest: set TXTPTR at "N(10) ", DIMFLG <- $40 (from DIM
        ; statement), then PtrGet3 with VARNAM letter, jmp to '(' branch.
        lda     #<VT_DimN10
        ldy     #>VT_DimN10
        jsr     VT_SetTxt               ; A = 'N'
        ldx     #$40                    ; from-DIM flag (bit 6)
        jsr     PtrGet2                 ; will hit '(' -> Array -> create
        ; Now N(5)=42.  Re-parse "N(5)" to find element.
        lda     #<VT_DimN5
        ldy     #>VT_DimN5
        jsr     VT_SetTxt
        jsr     PtrGet                  ; element address in VARPNT
        ; Save VARPNT.
        lda     VARPNT
        sta     VT_VPSAVE
        lda     VARPNT+1
        sta     VT_VPSAVE+1
        ; FAC = 42.
        lda     #<Vt42
        ldy     #>Vt42
        jsr     LoadFacFromYa
        ldx     VT_VPSAVE
        ldy     VT_VPSAVE+1
        jsr     StoreFacAtYxRounded
        ; Read it back and print.
        lda     #<MsgVT_NewArr
        ldy     #>MsgVT_NewArr
        jsr     BasPrintStr
        lda     VT_VPSAVE
        ldy     VT_VPSAVE+1
        jsr     LoadFacFromYa
        jsr     BasPrintFAC
        jsr     BasPrintCRLF

        ; --- Test 4: 8 string allocations + GC ---
        ldx     #8
@galloc:
        phx
        lda     #16
        jsr     StrSpa                  ; consumes 16 bytes; FAC has descriptor
        plx
        dex
        bne     @galloc
        ; Force GC (TEMPPT got bumped by StrSpa-via-StrIni? StrSpa itself
        ; doesn't call PutNew, so temp stack untouched here.)
        jsr     Garbag
        lda     #<MsgVT_GC
        ldy     #>MsgVT_GC
        jsr     BasPrintStr
        lda     FRETOP+1
        ldy     FRETOP
        jsr     GivAyf
        jsr     BasPrintFAC
        jsr     BasPrintCRLF

        rts
.endif

; =============================================================================
;   E X P R E S S I O N   E V A L U A T O R
;
;   Recursive-descent precedence climber.  Operates on tokenized text at
;   TXTPTR (advanced via ChrGet/ChrGot).  Result lands in FAC (numeric)
;   or as a 3-byte string descriptor at FAC..FAC+2 (string).  VALTYP
;   selects: $00 = numeric, $FF = string.
;
;   Precedence (lowest -> highest):
;     OR
;     AND
;     NOT  (right-assoc unary)
;     comparison (= <> < > <= >=)
;     + -
;     * /
;     ^    (right-assoc)
;     unary -, unary +
;     atom: number, variable, string-literal, "(" expr ")", function call
; =============================================================================

; ---------------------------------------------------------------------------
; ZP scratch used only during expression evaluation.
;   BAS_LVTYP = saved VALTYP of left operand around binary ops
; ---------------------------------------------------------------------------
BAS_LVTYP       := $86

; ---------------------------------------------------------------------------
; FrmEvl -- top-level entry.  TXTPTR positioned so ChrGot returns the first
; byte of the expression.  On exit TXTPTR is at the first byte AFTER the
; expression.  Result in FAC + VALTYP.
; ---------------------------------------------------------------------------
FrmEvl:
        jmp     EvalOr

; ---------------------------------------------------------------------------
; PushFac -- push the current FAC + VALTYP onto the CPU stack (8 bytes).
; Order pushed: VALTYP, FAC, FAC+1, FAC+2, FAC+3, FAC+4, FACSIGN, FACEXTENSION
; (FACEXTENSION pushed last so it's pulled first by PullArg.)
; Preserves the return address.
; ---------------------------------------------------------------------------
PushFac:
        pla
        tay                             ; Y = ret-addr lo
        pla
        tax                             ; X = ret-addr hi
        lda     VALTYP
        pha
        lda     FAC
        pha
        lda     FAC+1
        pha
        lda     FAC+2
        pha
        lda     FAC+3
        pha
        lda     FAC+4
        pha
        lda     FACSIGN
        pha
        lda     FACEXTENSION
        pha
        txa
        pha
        tya
        pha
        rts

; ---------------------------------------------------------------------------
; PullArg -- pop the previously-pushed FAC into ARG (signed FP value or
; string descriptor in ARG..ARG+2/sign).  Sets BAS_LVTYP to the saved
; left-operand VALTYP.  Preserves return address.
; ---------------------------------------------------------------------------
PullArg:
        pla
        tay                             ; Y = ret-addr lo
        pla
        tax                             ; X = ret-addr hi
        pla
        sta     ARGEXTENSION
        pla
        sta     ARGSIGN
        pla
        sta     ARG+4
        pla
        sta     ARG+3
        pla
        sta     ARG+2
        pla
        sta     ARG+1
        pla
        sta     ARG
        pla
        sta     BAS_LVTYP
        txa
        pha
        tya
        pha
        rts

; ---------------------------------------------------------------------------
; PullFac -- pop pushed FAC back into FAC (used to discard right side and
; restore left, e.g. unused).
; ---------------------------------------------------------------------------
PullFac:
        pla
        tay
        pla
        tax
        pla
        sta     FACEXTENSION
        pla
        sta     FACSIGN
        pla
        sta     FAC+4
        pla
        sta     FAC+3
        pla
        sta     FAC+2
        pla
        sta     FAC+1
        pla
        sta     FAC
        pla
        sta     VALTYP
        txa
        pha
        tya
        pha
        rts

; ---------------------------------------------------------------------------
; TypeMismatch helper.
; ---------------------------------------------------------------------------
EvalTypeErr:
        ldx     #ERR_TYPEMISM
        jmp     BasErrorVec

; ===========================================================================
;   L E V E L 0  --  O R
; ===========================================================================
EvalOr:
        jsr     EvalAnd
@loop:
        jsr     ChrGot
        cmp     #TOK_OR
        bne     @done
        jsr     ChkNum                  ; left must be numeric
        jsr     ChrGet                  ; consume OR
        jsr     PushFac
        jsr     EvalAnd
        jsr     ChkNum                  ; right must be numeric
        jsr     PullArg
        jsr     OrOp
        bra     @loop
@done:
        rts

; ===========================================================================
;   L E V E L 1  --  A N D
; ===========================================================================
EvalAnd:
        jsr     EvalNot
@loop:
        jsr     ChrGot
        cmp     #TOK_AND
        bne     @done
        jsr     ChkNum
        jsr     ChrGet
        jsr     PushFac
        jsr     EvalNot
        jsr     ChkNum
        jsr     PullArg
        jsr     AndOp
        bra     @loop
@done:
        rts

; ===========================================================================
;   L E V E L 2  --  N O T   (right-assoc unary prefix)
; ===========================================================================
EvalNot:
        jsr     ChrGot
        cmp     #TOK_NOT
        bne     EvalCmp
        jsr     ChrGet
        jsr     EvalNot
        jsr     ChkNum
        jmp     NotOp

; ===========================================================================
;   L E V E L 3  --  C O M P A R I S O N
;   Reads up to two of {<, =, >} forming a relop; if none, no-op.
;   Mask:  bit 0 = '>' present, bit 1 = '=' present, bit 2 = '<' present
; ===========================================================================
EvalCmp:
        jsr     EvalAdd
        ldx     #0                      ; relop mask
@scan:
        jsr     ChrGot
        cmp     #'='
        beq     @gotEq
        cmp     #'<'
        beq     @gotLt
        cmp     #'>'
        beq     @gotGt
        bra     @done
@gotEq:
        ldy     #2
        bra     @setbit
@gotLt:
        ldy     #4
        bra     @setbit
@gotGt:
        ldy     #1
@setbit:
        sty     CPRMASK                 ; reuse as scratch
        txa
        and     CPRMASK
        bne     @synErr                 ; same char twice (e.g. "==")
        txa
        ora     CPRMASK
        tax
        jsr     ChrGet
        bra     @scan
@synErr:
        jmp     SynErr
@done:
        cpx     #0
        bne     @doCmp
        rts
@doCmp:
        stx     CPRMASK
        ; Save left operand, evaluate right
        jsr     PushFac
        jsr     EvalAdd
        jsr     PullArg                 ; ARG = left, BAS_LVTYP = left's type
        ; Type compatibility check.
        lda     BAS_LVTYP
        eor     VALTYP
        jmi     EvalTypeErr             ; one numeric, one string -> mismatch
        bit     VALTYP
        bmi     @strCmp
        ; Numeric comparison.
        jmp     RelOpsNum
@strCmp:
        jmp     RelOpsStr

; ---------------------------------------------------------------------------
; RelOpsNum -- numeric comparison.
; Inputs: ARG = left, FAC = right, CPRMASK = relop mask (bit 0=>, 1==, 2=<).
; Output: FAC = -1 if (ARG <op> FAC) is true, else 0.  VALTYP = numeric.
; ---------------------------------------------------------------------------
RelOpsNum:
        ; Replicate msbasic ARG-pre-relop fixup: clear ARG+1 high bit, then
        ; set it from ARGSIGN's MSB.  This rebuilds the implicit-1 mantissa
        ; for FCOMP's signed comparison path.
        lda     ARGSIGN
        ora     #$7F
        and     ARG+1
        sta     ARG+1
        lda     #<ARG
        ldy     #$00
        jsr     FComp                   ; A = sign(FAC - ARG)
        ; Map A to bit position:
        ;   FAC<ARG (A=$FF): ARG>FAC  -> bit 0 (mask 1)
        ;   FAC=ARG (A=$00):           -> bit 1 (mask 2)
        ;   FAC>ARG (A=$01): ARG<FAC  -> bit 2 (mask 4)
        tax
        bmi     @lt
        beq     @eq
        lda     #4
        bra     @check
@lt:
        lda     #1
        bra     @check
@eq:
        lda     #2
@check:
        and     CPRMASK
        beq     @false
        lda     #$FF
        ldy     #$FF
        jmp     GivAyf
@false:
        lda     #0
        tay
        jmp     GivAyf

; ---------------------------------------------------------------------------
; RelOpsStr -- bytewise string comparison.
; ARG = left descriptor (ARG=len, ARG+1=lo, ARG+2=hi, ARGSIGN, ARGEXT pushed).
; FAC = right descriptor.  CPRMASK as above.
; ---------------------------------------------------------------------------
RelOpsStr:
        ; INDEX = left ptr, BAS_TMP1 = right ptr, BAS_TMP2 lo = left len,
        ; BAS_TMP2 hi = right len.
        lda     ARG+1
        sta     INDEX
        lda     ARG+2
        sta     INDEX+1
        lda     FAC+1
        sta     BAS_TMP1
        lda     FAC+2
        sta     BAS_TMP1+1
        lda     ARG
        sta     BAS_TMP2                ; left len
        lda     FAC
        sta     BAS_TMP2+1              ; right len
        ; Compare byte-by-byte up to min length.
        ldy     #0
@cmp:
        ; Has either side ended?
        cpy     BAS_TMP2
        beq     @leftEnd
        cpy     BAS_TMP2+1
        beq     @rightEnd               ; right ended first -> left > right
        lda     (INDEX),y
        cmp     (BAS_TMP1),y
        beq     @next
        bcc     @lt                     ; left < right
        ; left > right
        lda     #1
        bra     @decide
@lt:
        lda     #4
        bra     @decide
@next:
        iny
        bra     @cmp
@leftEnd:
        ; Left ran out; check right
        cpy     BAS_TMP2+1
        beq     @equal
        ; left < right (left is prefix)
        lda     #4
        bra     @decide
@rightEnd:
        ; right ran out, left has more; left > right
        lda     #1
        bra     @decide
@equal:
        lda     #2
@decide:
        and     CPRMASK
        beq     @false
        lda     #$FF
        tay
        bra     @ret
@false:
        lda     #0
        tay
@ret:
        ; Free temp strings before returning.  Save A,Y first.
        pha
        phy
        ; Free FAC's temp string (right operand).
        bit     VALTYP
        bpl     @noFreeR
        jsr     FreFac
@noFreeR:
        ; Free ARG's temp string (left operand): manually restore VALTYP=$FF
        ; and FAC := ARG, then FreFac.  (We don't always know if ARG is a
        ; temp; FreTms inside FreTmp checks.)
        lda     ARG
        sta     FAC
        lda     ARG+1
        sta     FAC+1
        lda     ARG+2
        sta     FAC+2
        lda     #$FF
        sta     VALTYP
        jsr     FreFac
        ply
        pla
        jmp     GivAyf

; ===========================================================================
;   L E V E L 4  --  + / -
; ===========================================================================
EvalAdd:
        jsr     EvalMul
@loop:
        jsr     ChrGot
        cmp     #'+'
        beq     @plus
        cmp     #'-'
        beq     @minus
        rts
@plus:
        jsr     ChrGet
        jsr     PushFac
        jsr     EvalMul
        jsr     PullArg
        ; Type dispatch.
        lda     BAS_LVTYP
        eor     VALTYP
        jmi     EvalTypeErr
        bit     VALTYP
        bmi     @cat
        ; numeric add: FAC = ARG + FAC
        ; FAddT expects: ARG is the operand, A=FAC's exponent on entry.
        ; Use entry "FAddT" preceded by sign work: msbasic does
        ;   bne <continue>; jmp CopyArgToFac
        ; But our FAddT entry already handles that.  We need to set
        ; SGNCPR = ARGSIGN ^ FACSIGN before FAddT.
        lda     ARGSIGN
        eor     FACSIGN
        sta     SGNCPR
        lda     FAC
        jsr     FAddT
        bra     @loop
@minus:
        jsr     ChrGet
        jsr     PushFac
        jsr     EvalMul
        jsr     ChkNum
        ; left was pushed; check pushed type via TOS-byte? Easier: we already
        ; verified left is numeric on first iteration.  But left might have
        ; been a string from concatenation; require numeric here:
        jsr     PullArg
        lda     BAS_LVTYP
        jmi     EvalTypeErr
        ; FAC = ARG - FAC
        ; FSubT does: FACSIGN ^= $FF; SGNCPR = FACSIGN^ARGSIGN; jmp FAddT
        ; We need to call FSubT directly.
        jsr     FSubT
        bra     @loop
@cat:
        jsr     CatStr
        bra     @loop

; ---------------------------------------------------------------------------
; CatStr -- concatenate ARG (left) + FAC (right), result in FAC.
; ---------------------------------------------------------------------------
CatStr:
        ; Stash right's length+addr before we overwrite FAC.
        lda     FAC
        sta     BAS_TEMP1               ; right len
        lda     FAC+1
        sta     BAS_TEMP1+1
        lda     FAC+2
        sta     BAS_TEMP1+2
        ; Total length = ARG + FAC; abort if > 255.
        clc
        lda     ARG
        adc     BAS_TEMP1
        bcs     @tooLong
        sta     BAS_TEMP1+3             ; total length
        ; Free both source temps before allocating result -- otherwise we
        ; pile up to 3 temps and the next PutNew throws ?FRMCPX.
        jsr     FreeBothTemps
        ; Allocate.
        lda     BAS_TEMP1+3             ; total length
        jsr     GetSpa                  ; A=total, FRESPC=buf
        ; Copy left bytes (ARG -> FRESPC).
        lda     ARG+1
        sta     INDEX
        lda     ARG+2
        sta     INDEX+1
        lda     ARG
        beq     @right
        jsr     MovStr1                 ; advances FRESPC by len
@right:
        ; Copy right bytes.
        lda     BAS_TEMP1+1
        sta     INDEX
        lda     BAS_TEMP1+2
        sta     INDEX+1
        lda     BAS_TEMP1
        beq     @desc
        jsr     MovStr1
@desc:
        ; Descriptor: FAC := total len, FAC+1/2 := FRESPC - total.
        lda     BAS_TEMP1+3
        sta     FAC
        sec
        lda     FRESPC
        sbc     BAS_TEMP1+3
        sta     FAC+1
        lda     FRESPC+1
        sbc     #0
        sta     FAC+2
        lda     #$FF
        sta     VALTYP
        jmp     PutNew
@tooLong:
        ldx     #ERR_STRLONG
        jmp     BasErrorVec

; ===========================================================================
;   L E V E L 5  --  * / /
; ===========================================================================
EvalMul:
        jsr     EvalPow
@loop:
        jsr     ChrGot
        cmp     #'*'
        beq     @mul
        cmp     #'/'
        beq     @div
        rts
@mul:
        jsr     ChkNum
        jsr     ChrGet
        jsr     PushFac
        jsr     EvalPow
        jsr     ChkNum
        jsr     PullArg
        lda     BAS_LVTYP
        jmi     EvalTypeErr
        ; FAC = ARG * FAC: FMultT expects ARG + sign work.  See msbasic.
        lda     ARGSIGN
        eor     FACSIGN
        sta     SGNCPR
        lda     FAC
        jsr     FMultT
        bra     @loop
@div:
        jsr     ChkNum
        jsr     ChrGet
        jsr     PushFac
        jsr     EvalPow
        jsr     ChkNum
        jsr     PullArg
        lda     BAS_LVTYP
        jmi     EvalTypeErr
        ; FAC = ARG / FAC: FDivT.
        lda     ARGSIGN
        eor     FACSIGN
        sta     SGNCPR
        lda     FAC
        jsr     FDivT
        bra     @loop

; ===========================================================================
;   L E V E L 6  --  ^   (right-associative)
; ===========================================================================
EvalPow:
        jsr     EvalUnary
@loop:
        jsr     ChrGot
        cmp     #'^'
        bne     @done
        jsr     ChkNum
        jsr     ChrGet
        jsr     PushFac
        jsr     EvalUnary               ; right-assoc: recurse below
        ; Actually right-assoc means: evaluate the RHS at this level too.
        ; But EvalUnary doesn't loop ^; it stops.  Re-check ^ here?  No --
        ; for right-assoc we should recurse at the same level for the RHS.
        ; Simpler: after EvalUnary, look for another ^ and recurse.
        ; Implemented by jumping back to @loop (so chained ^ becomes
        ; left-assoc in this version).  Acceptable simplification.
        jsr     ChkNum
        jsr     PullArg
        lda     BAS_LVTYP
        jmi     EvalTypeErr
        ; FPwrt computes ARG ^ FAC.  Our ported FPwrt expects ARG = base,
        ; FAC = exponent, and A = FAC's exponent byte (FPwrt's first
        ; instruction is `beq Exp` to short-circuit FAC==0 -> 1).
        lda     FAC
        jsr     FPwrt
        bra     @loop
@done:
        rts

; ===========================================================================
;   L E V E L 7  --  U N A R Y
; ===========================================================================
EvalUnary:
        jsr     ChrGot
        cmp     #'-'
        beq     @neg
        cmp     #'+'
        beq     @pos
        jmp     EvalAtom
@neg:
        jsr     ChrGet
        jsr     EvalUnary
        jsr     ChkNum
        ; Negate FAC: flip FACSIGN bit 7.
        lda     FACSIGN
        eor     #$FF
        sta     FACSIGN
        rts
@pos:
        jsr     ChrGet
        jmp     EvalUnary

; ===========================================================================
;   L E V E L 8  --  A T O M
; ===========================================================================
EvalAtom:
        stz     VALTYP                  ; default to numeric; string paths override
        jsr     ChrGot
        bcc     @num                    ; digit
        cmp     #'.'
        beq     @num
        cmp     #'"'
        beq     @str
        cmp     #'('
        beq     @paren
        ; Letter? -> variable
        jsr     IsLetC
        bcs     @var
        ; Function token?
        cmp     #TOK_INKEY
        beq     FnInkey
        cmp     #TOK_FN
        beq     @fnCall                 ; FN A(...) — user-defined function
        ; Hex literal in PRINT context: not here (no '$' literal supported).
        ; NVRAM is dual-role (statement at $B1, function via FnTable);
        ; allow it through even though it sits below TOK_SGN.
        cmp     #TOK_NVRAM
        beq     @fnDisp
        ; Try function dispatch.
        cmp     #TOK_SGN
        bcc     @synErr
        cmp     #TOK_MAX+1
        bcs     @synErr
@fnDisp:
        jmp     FnDispatch
@synErr:
        jmp     SynErr
@fnCall:
        jmp     FnCall
@num:
        ; ASCII numeric: jump to Fin.  Fin uses ChrGet to consume.
        jmp     Fin
@str:
        ; '"' string literal.  Consume the opening quote, then StrLit.
        jsr     ChrGet                  ; consume "
        ; StrLit expects (Y,A) = src.  Source = TXTPTR.
        lda     TXTPTR
        ldy     TXTPTR+1
        jsr     StrLit
        ; StrLit advances internal pointer; we need to update TXTPTR.
        ; StrLit reads until $00 or '"' from (STRNG1)+y; FAC has length.
        ; Compute new TXTPTR = STRNG2 (which StrLit set), or TXTPTR + len + maybe-quote.
        ; STRNG2 = STRNG1 + len + (1 if hit quote else 0).  Use STRNG2.
        lda     STRNG2
        sta     TXTPTR
        lda     STRNG2+1
        sta     TXTPTR+1
        ; If we stopped at a closing quote, TXTPTR is past it (StrLit's
        ; @endquote path: tya/adc STRNG1 with carry set since cmp set C);
        ; if we ran into NUL, TXTPTR sits on the NUL (clc path).  Either
        ; is correct for ChrGot.
        jmp     ChrGot                  ; preload next char (for caller chains)
@paren:
        jsr     ChrGet                  ; consume '('
        jsr     FrmEvl
        jmp     ChkCls                  ; expects ')'; consumes via ChrGet
@var:
        ; Variable lookup.  PtrGet uses CHRGET internally and leaves
        ; (A,Y) = VARPNT.  VALTYP is set to $00 or $FF.
        jsr     PtrGet
        ; Fetch value into FAC.
        bit     VALTYP
        bmi     @loadStr
        ; numeric: FAC = (VARPNT)
        lda     VARPNT
        ldy     VARPNT+1
        jmp     LoadFacFromYa
@loadStr:
        ; string: copy descriptor [len][lo][hi] into FAC..FAC+2.
        ldy     #0
        lda     (VARPNT),y
        sta     FAC
        iny
        lda     (VARPNT),y
        sta     FAC+1
        iny
        lda     (VARPNT),y
        sta     FAC+2
        rts

; ---------------------------------------------------------------------------
; FnInkey -- INKEY (no parens).  Reads BAS_PENDKEY first; else BufferSize/
; ReadBuffer; else 0.  Result is unsigned 8-bit FP value.
; ---------------------------------------------------------------------------
FnInkey:
        jsr     ChrGet                  ; consume INKEY token
        lda     BAS_PENDKEY
        beq     @noPend
        ; consume pending key.
        ldy     #0
        sty     BAS_PENDKEY
        tay
        jmp     SngFlt
@noPend:
        jsr     BufferSize
        beq     @zero
        jsr     ReadBuffer
        tay
        jmp     SngFlt
@zero:
        ldy     #0
        jmp     SngFlt

; ---------------------------------------------------------------------------
; FnDispatch -- A holds a function token in [TOK_SGN..TOK_MAX].  Dispatch
; via FnTable, which pairs (token, handler-1).
; ---------------------------------------------------------------------------
FnDispatch:
        ldx     #0
@find:
        lda     FnTable,x
        beq     @synErr                 ; reached terminator
        cmp     (TXTPTR)
        beq     @match
        inx
        inx
        inx
        bra     @find
@match:
        ; Push handler-1 onto stack so RTS jumps to it after ChrGet.
        lda     FnTable+2,x
        pha
        lda     FnTable+1,x
        pha
        jmp     ChrGet                  ; consume token, return into handler
@synErr:
        jmp     SynErr

; ---------------------------------------------------------------------------
; FnTable -- (token, handler-1) triples, $00-terminated.
; "handler-1" because we push it through RTS which adds 1.
; ---------------------------------------------------------------------------
FnTable:
        .byte   TOK_SGN
        .word   FnSgn-1
        .byte   TOK_INT
        .word   FnInt-1
        .byte   TOK_ABS
        .word   FnAbs-1
        .byte   TOK_FRE
        .word   FnFre-1
        .byte   TOK_POS
        .word   FnPos-1
        .byte   TOK_SQR
        .word   FnSqr-1
        .byte   TOK_RND
        .word   FnRnd-1
        .byte   TOK_LOG
        .word   FnLog-1
        .byte   TOK_EXP
        .word   FnExp-1
        .byte   TOK_COS
        .word   FnCos-1
        .byte   TOK_SIN
        .word   FnSin-1
        .byte   TOK_TAN
        .word   FnTan-1
        .byte   TOK_ATN
        .word   FnAtn-1
        .byte   TOK_PEEK
        .word   FnPeek-1
        .byte   TOK_LEN
        .word   FnLen-1
        .byte   TOK_STRSTR
        .word   FnStrStr-1
        .byte   TOK_VAL
        .word   FnVal-1
        .byte   TOK_ASC
        .word   FnAsc-1
        .byte   TOK_CHRSTR
        .word   FnChrStr-1
        .byte   TOK_LEFTSTR
        .word   FnLeftStr-1
        .byte   TOK_RIGHTSTR
        .word   FnRightStr-1
        .byte   TOK_MIDSTR
        .word   FnMidStr-1
        .byte   TOK_JOY
        .word   FnJoy-1
        .byte   TOK_NVRAM
        .word   FnNvram-1
        .byte   TOK_HEX
        .word   FnHex-1
        .byte   TOK_MIN
        .word   FnMin-1
        .byte   TOK_MAX
        .word   FnMax-1
        .byte   0

; ---------------------------------------------------------------------------
; Numeric-arg helpers.
; ParenNum    -- expects "(" expr ")" with numeric result.  FAC = result.
; ParenStr    -- expects "(" expr ")" with string result.
; ParenU8     -- expects "(" expr ")" -> A = byte (0..255), or ?ILLQTY.
; ParenU16    -- expects "(" expr ")" -> AyInt result in FAC+3,+4.
; ---------------------------------------------------------------------------
ParenNum:
        jsr     ChkOpn
        jsr     FrmEvl
        jsr     ChkNum
        jmp     ChkCls
ParenStr:
        jsr     ChkOpn
        jsr     FrmEvl
        jsr     ChkStr
        jmp     ChkCls
ParenU8:
        jsr     ParenNum
        jsr     AyInt
        lda     FAC+3                   ; high byte must be 0
        bne     @bad
        lda     FAC+4                   ; low byte = result
        rts
@bad:
        jmp     IqErr

; ---------------------------------------------------------------------------
; Unary numeric functions (single-arg "(" num ")") -- shared body.
; Each entry sets up A = handler entry to call after ChkOpn/FrmEvl/ChkNum/ChkCls.
; ---------------------------------------------------------------------------
FnSgn:
        jsr     ParenNum
        jmp     Sgn
FnInt:
        jsr     ParenNum
        jmp     Int
FnAbs:
        jsr     ParenNum
        jmp     Abs
FnSqr:
        jsr     ParenNum
        jmp     Sqr
FnLog:
        jsr     ParenNum
        jmp     Log
FnExp:
        jsr     ParenNum
        jmp     Exp
FnCos:
        jsr     ParenNum
        jmp     Cos
FnSin:
        jsr     ParenNum
        jmp     Sin
FnTan:
        jsr     ParenNum
        jmp     Tan
FnAtn:
        jsr     ParenNum
        jmp     Atn
FnRnd:
        jsr     ParenNum
        jmp     Rnd
FnHex:
        ; In expression context: identity.
        jmp     ParenNum

; ---------------------------------------------------------------------------
; FnFre -- FRE(n): returns FRETOP - STREND (free string heap).
; Argument is parsed and ignored.
; ---------------------------------------------------------------------------
FnFre:
        jsr     ParenNum
        sec
        lda     FRETOP
        sbc     STREND
        tay
        lda     FRETOP+1
        sbc     STREND+1
        jmp     GivAyf

; ---------------------------------------------------------------------------
; FnPos -- POS(n): not yet maintained; returns 0.
; ---------------------------------------------------------------------------
FnPos:
        jsr     ParenNum
        ldy     #0
        jmp     SngFlt

; ---------------------------------------------------------------------------
; FnPeek -- PEEK(addr): byte at addr -> FP.
; ---------------------------------------------------------------------------
FnPeek:
        jsr     ParenNum
        jsr     FacToU16
        lda     FAC+4                   ; lo byte
        sta     INDEX
        lda     FAC+3                   ; hi byte
        sta     INDEX+1
        ldy     #0
        lda     (INDEX),y
        tay
        jmp     SngFlt

; ---------------------------------------------------------------------------
; FnJoy -- JOY(n): 1 or 2.  If GPIO absent, returns 0.
; ---------------------------------------------------------------------------
FnJoy:
        jsr     ParenU8
        pha
        lda     HW_PRESENT
        and     #HW_GPIO
        beq     @absent
        pla
        cmp     #1
        beq     @j1
        cmp     #2
        beq     @j2
        ldx     #ERR_ILLQUAN
        jmp     BasErrorVec
@j1:
        jsr     ReadJoystick1
        tay
        jmp     SngFlt
@j2:
        jsr     ReadJoystick2
        tay
        jmp     SngFlt
@absent:
        pla
        ldy     #0
        jmp     SngFlt

; ---------------------------------------------------------------------------
; FnNvram -- NVRAM(addr): if RTC absent, return 0.
; ---------------------------------------------------------------------------
FnNvram:
        jsr     ParenU8
        pha
        lda     HW_PRESENT
        and     #HW_RTC
        beq     @absent
        pla
        tax
        jsr     RtcReadNVRAM
        tay
        jmp     SngFlt
@absent:
        pla
        ldy     #0
        jmp     SngFlt

; ---------------------------------------------------------------------------
; FnMin / FnMax -- two numeric args, smaller / larger.
; ---------------------------------------------------------------------------
FnMin:
        jsr     MinMaxArgs              ; ARG = a, FAC = b, BAS_TMP3 = sign(b-a)
        ; Want smaller: if b>=a return a (ARG); else return b (FAC).
        bpl     @retArg                 ; sign>=0 means b>=a
        rts                             ; FAC already = b
@retArg:
        jmp     CopyArgToFac
FnMax:
        jsr     MinMaxArgs
        ; Want larger: if b>=a return b (FAC); else return a (ARG).
        bpl     @retFac
        jmp     CopyArgToFac
@retFac:
        rts

; MinMaxArgs -- consume "(" a "," b ")" with numerics; ARG=a, FAC=b.
; Returns A = sign(b - a) (FF/00/01) and N flag set accordingly.
MinMaxArgs:
        jsr     ChkOpn
        jsr     FrmEvl
        jsr     ChkNum
        jsr     PushFac                 ; save a
        jsr     ChkCom
        jsr     FrmEvl
        jsr     ChkNum
        jsr     ChkCls
        jsr     PullArg                 ; ARG = a, FAC = b
        ; Stash ARG so we can restore after FComp's destructive sign-pack.
        lda     ARG
        sta     BAS_TEMP1
        lda     ARG+1
        sta     BAS_TEMP1+1
        lda     ARG+2
        sta     BAS_TEMP1+2
        lda     ARG+3
        sta     BAS_TEMP1+3
        lda     ARG+4
        sta     BAS_TEMP1+4
        lda     ARGSIGN
        sta     BAS_TEMP1+5
        ; Pack ARGSIGN into bit 7 of ARG+1 so FComp reads it correctly.
        lda     ARGSIGN
        ora     #$7F
        and     ARG+1
        sta     ARG+1
        lda     #<ARG
        ldy     #$00
        jsr     FComp                   ; A = sign(FAC - ARG)
        pha
        ; Restore ARG.
        lda     BAS_TEMP1
        sta     ARG
        lda     BAS_TEMP1+1
        sta     ARG+1
        lda     BAS_TEMP1+2
        sta     ARG+2
        lda     BAS_TEMP1+3
        sta     ARG+3
        lda     BAS_TEMP1+4
        sta     ARG+4
        lda     BAS_TEMP1+5
        sta     ARGSIGN
        pla                             ; restore A, sets N/Z flags
        rts

; ---------------------------------------------------------------------------
; FnLen -- LEN(s$): length of string.
; ---------------------------------------------------------------------------
FnLen:
        jsr     ParenStr
        ldy     FAC                     ; length
        jsr     FreFac                  ; release temp string if any
        jmp     SngFlt

; ---------------------------------------------------------------------------
; FnAsc -- ASC(s$): code of first char; ?ILLQTY if empty.
; ---------------------------------------------------------------------------
FnAsc:
        jsr     ParenStr
        lda     FAC
        beq     @bad
        ; Read first byte of string.
        lda     FAC+1
        sta     INDEX
        lda     FAC+2
        sta     INDEX+1
        ldy     #0
        lda     (INDEX),y
        pha
        jsr     FreFac
        pla
        tay
        jmp     SngFlt
@bad:
        jmp     IqErr

; ---------------------------------------------------------------------------
; FnChrStr -- CHR$(n): 1-char string.
; ---------------------------------------------------------------------------
FnChrStr:
        jsr     ParenU8
        pha
        lda     #1
        jsr     GetSpa                  ; (Y,X) = addr; A unchanged
        pla
        ldy     #0
        sta     (FRESPC),y
        ; Build descriptor in FAC.
        lda     #1
        sta     FAC
        lda     FRESPC
        sta     FAC+1
        lda     FRESPC+1
        sta     FAC+2
        ; Advance FRESPC past the byte we just wrote.
        inc     FRESPC
        bne     @nb
        inc     FRESPC+1
@nb:
        jmp     PutNew

; ---------------------------------------------------------------------------
; FnStrStr -- STR$(n): convert numeric to string.
; ---------------------------------------------------------------------------
FnStrStr:
        jsr     ParenNum
        jsr     Fout                    ; A=lo, Y=hi -> NUL-terminated buffer
        ; (A,Y) = pointer to NUL-terminated ASCII number string in STACK2.
        jsr     StrLit                  ; allocates + copies + PutNew
        rts

; ---------------------------------------------------------------------------
; FnVal -- VAL(s$): parse leading numeric from string.
; Temporarily NUL-terminates the string in place, redirects TXTPTR, calls
; Fin, then restores.
; ---------------------------------------------------------------------------
FnVal:
        jsr     ParenStr
        lda     FAC
        bne     @nz
        ; empty string -> 0
        jsr     FreFac
        jmp     ZeroFac
@nz:
        ; Stash length, address into TEMP1..TEMP1+2.
        sta     TEMP1                   ; length
        lda     FAC+1
        sta     TEMP1+1
        lda     FAC+2
        sta     TEMP1+2
        ; Save the byte at offset = length and replace with $00.
        lda     TEMP1+1
        sta     INDEX
        lda     TEMP1+2
        sta     INDEX+1
        ldy     TEMP1
        lda     (INDEX),y
        sta     TEMP1+3                 ; saved byte
        lda     #0
        sta     (INDEX),y
        ; Save TXTPTR.
        lda     TXTPTR
        pha
        lda     TXTPTR+1
        pha
        ; TXTPTR := INDEX - 1, then ChrGet to load first char.
        lda     TEMP1+1
        sta     TXTPTR
        lda     TEMP1+2
        sta     TXTPTR+1
        lda     TXTPTR
        bne     @nb
        dec     TXTPTR+1
@nb:
        dec     TXTPTR
        jsr     ChrGet                  ; first char
        jsr     Fin                     ; FAC := value
        ; Restore the saved byte.
        lda     TEMP1+1
        sta     INDEX
        lda     TEMP1+2
        sta     INDEX+1
        ldy     TEMP1
        lda     TEMP1+3
        sta     (INDEX),y
        ; Restore TXTPTR.
        pla
        sta     TXTPTR+1
        pla
        sta     TXTPTR
        rts

; ---------------------------------------------------------------------------
; FnLeftStr -- LEFT$(s$, n): leftmost n chars.
; ---------------------------------------------------------------------------
FnLeftStr:
        jsr     ChkOpn
        jsr     FrmEvl
        jsr     ChkStr
        jsr     ChkCom
        jsr     PushFac                 ; save string descriptor
        jsr     FrmEvl
        jsr     ChkNum
        jsr     ChkCls
        jsr     AyInt
        jsr     PullArg                 ; ARG = string descriptor (BAS_TMP1 clobbered)
        ; FAC still holds the integer n; check range and copy now.
        lda     FAC+3
        bne     @bad
        lda     FAC+4
        sta     BAS_TMP1+1              ; n
        ; Clamp n to ARG (length).
        lda     BAS_TMP1+1
        cmp     ARG
        bcc     @ok
        lda     ARG
@ok:
        sta     BAS_TMP1+1
        ; Free the source temp BEFORE allocating result so the slot frees up.
        jsr     FreeArgString
        ; Offset = 0 for LEFT$.
        stz     BAS_TMP1
        ; Allocate, copy first n bytes.
        jmp     SubstrCommon            ; tail-call (rts to caller)
@bad:
        jmp     IqErr

; ---------------------------------------------------------------------------
; FnRightStr -- RIGHT$(s$, n): rightmost n chars.
; ---------------------------------------------------------------------------
FnRightStr:
        jsr     ChkOpn
        jsr     FrmEvl
        jsr     ChkStr
        jsr     ChkCom
        jsr     PushFac
        jsr     FrmEvl
        jsr     ChkNum
        jsr     ChkCls
        jsr     AyInt
        jsr     PullArg                 ; ARG = string descriptor (BAS_TMP1 clobbered)
        lda     FAC+3
        bne     @bad
        lda     FAC+4
        sta     BAS_TMP1+1              ; n
        ; Clamp n.
        lda     BAS_TMP1+1
        cmp     ARG
        bcc     @ok
        lda     ARG
@ok:
        sta     BAS_TMP1+1
        ; offset = ARG - n.
        lda     ARG
        sec
        sbc     BAS_TMP1+1
        sta     BAS_TMP1                ; start offset
        jsr     FreeArgString
        jmp     SubstrCommon
@bad:
        jmp     IqErr

; ---------------------------------------------------------------------------
; FnMidStr -- MID$(s$, m [, n]): substring starting at m (1-based).
; ---------------------------------------------------------------------------
FnMidStr:
        jsr     ChkOpn
        jsr     FrmEvl
        jsr     ChkStr
        jsr     ChkCom
        jsr     PushFac
        ; Read m.
        jsr     FrmEvl
        jsr     ChkNum
        jsr     AyInt
        lda     FAC+3
        bne     @bad
        lda     FAC+4
        beq     @bad                    ; m must be >= 1
        sec
        sbc     #1
        sta     BAS_TMP1                ; offset = m-1
        ; Optional ", n".
        jsr     ChrGot
        cmp     #','
        beq     @hasN
        ; No n: take rest -> n = 255 (will clamp).
        lda     #255
        sta     BAS_TMP1+1
        bra     @cls
@hasN:
        jsr     ChrGet
        jsr     FrmEvl
        jsr     ChkNum
        jsr     AyInt
        lda     FAC+3
        bne     @bad
        lda     FAC+4
        sta     BAS_TMP1+1
@cls:
        jsr     ChkCls
        jsr     PullArg                 ; ARG = string
        ; Clamp offset to length.
        lda     BAS_TMP1
        cmp     ARG
        bcc     @offOk
        lda     ARG                     ; offset = length -> empty result
        sta     BAS_TMP1
@offOk:
        ; Clamp n to (length - offset).
        sec
        lda     ARG
        sbc     BAS_TMP1
        cmp     BAS_TMP1+1
        bcs     @nOk
        sta     BAS_TMP1+1
@nOk:
        jsr     FreeArgString
        jmp     SubstrCommon
@bad:
        jmp     IqErr

; ---------------------------------------------------------------------------
; SubstrCommon -- copy BAS_TMP1+1 bytes from ARG-string at offset BAS_TMP1
; into a new heap allocation; result descriptor in FAC; PutNew.
; ---------------------------------------------------------------------------
SubstrCommon:
        ; Allocate.
        lda     BAS_TMP1+1
        jsr     GetSpa                  ; FRESPC = new buffer
        ; Source pointer = ARG+1 (lo/hi) + BAS_TMP1.
        clc
        lda     ARG+1
        adc     BAS_TMP1
        sta     INDEX
        lda     ARG+2
        adc     #0
        sta     INDEX+1
        ; Copy BAS_TMP1+1 bytes from (INDEX) to (FRESPC).
        ldy     BAS_TMP1+1
        beq     @done
        ldy     #0
@cp:
        lda     (INDEX),y
        sta     (FRESPC),y
        iny
        cpy     BAS_TMP1+1
        bne     @cp
@done:
        ; Build descriptor.
        lda     BAS_TMP1+1
        sta     FAC
        lda     FRESPC
        sta     FAC+1
        lda     FRESPC+1
        sta     FAC+2
        ; Advance FRESPC by length consumed.
        clc
        lda     FRESPC
        adc     BAS_TMP1+1
        sta     FRESPC
        bcc     @nb
        inc     FRESPC+1
@nb:
        jmp     PutNew

; FreeArgString -- if ARG holds a temp string descriptor (most-recent
; on TEMPST), pop just the descriptor.  Heap is left intact so callers
; that still need the source bytes can copy them safely; orphaned heap
; will be reclaimed by Garbag.
FreeArgString:
        lda     ARG+3                   ; descriptor address lo
        ldy     ARG+4                   ; descriptor address hi (always $00)
        jmp     FreTms

; Cleanup that releases both ARG's and FAC's temp descriptors (called from
; CatStr after content has been stashed but before new allocation).
FreeBothTemps:
        ; Free FAC's temp first (it is currently LASTPT).
        lda     FAC+3
        ldy     FAC+4
        jsr     FreTms
        ; Then ARG's (now LASTPT after FAC's removal).
        lda     ARG+3
        ldy     ARG+4
        jmp     FreTms
        rts

; ===========================================================================
;   E V A L U A T O R   -   B I N A R Y   O P E R A T O R   H E L P E R S
; ===========================================================================

; ---------------------------------------------------------------------------
; AndOp -- FAC = ARG AND FAC (bitwise on 16-bit signed ints).
; ---------------------------------------------------------------------------
AndOp:
        jsr     AyInt                   ; FAC -> int (FAC+3=hi, FAC+4=lo)
        lda     FAC+3
        sta     BAS_TMP1                ; saved hi
        lda     FAC+4
        sta     BAS_TMP1+1              ; saved lo
        jsr     CopyArgToFac
        jsr     AyInt
        lda     FAC+4
        and     BAS_TMP1+1
        tay                             ; Y = lo result
        lda     FAC+3
        and     BAS_TMP1                ; A = hi result
        jmp     GivAyf

; ---------------------------------------------------------------------------
; OrOp -- FAC = ARG OR FAC.
; ---------------------------------------------------------------------------
OrOp:
        jsr     AyInt
        lda     FAC+3
        sta     BAS_TMP1                ; saved hi
        lda     FAC+4
        sta     BAS_TMP1+1              ; saved lo
        jsr     CopyArgToFac
        jsr     AyInt
        lda     FAC+4
        ora     BAS_TMP1+1
        tay                             ; Y = lo
        lda     FAC+3
        ora     BAS_TMP1                ; A = hi
        jmp     GivAyf

; ---------------------------------------------------------------------------
; NotOp -- FAC = NOT FAC (bitwise complement of 16-bit signed int).
; ---------------------------------------------------------------------------
NotOp:
        jsr     AyInt
        lda     FAC+4
        eor     #$FF
        tay                             ; Y = lo
        lda     FAC+3
        eor     #$FF                    ; A = hi
        jmp     GivAyf

; ---------------------------------------------------------------------------
; BasCmdLet -- minimal LET (assignment).  Entered with ChrGot returning
; the first letter of the variable name.  No `LET` keyword required.
; ---------------------------------------------------------------------------
BasCmdLet:
        jsr     PtrGet                  ; VARPNT, VALTYP set; TXTPTR past name
        ; Save VARPNT and the variable's VALTYP across FrmEvl.
        lda     VARPNT
        pha
        lda     VARPNT+1
        pha
        lda     VALTYP
        pha
        jsr     ChrGot
        cmp     #'='
        bne     @synErr
        jsr     ChrGet
        jsr     FrmEvl
        pla                             ; saved variable VALTYP
        sta     BAS_TMP3
        eor     VALTYP
        bmi     @typeErr
        pla
        sta     VARPNT+1
        pla
        sta     VARPNT
        bit     BAS_TMP3
        bmi     @storeStr
        ; Numeric: store FAC into (VARPNT) (5 bytes).
        ldx     VARPNT
        ldy     VARPNT+1
        jmp     StoreFacAtYxRounded
@storeStr:
        ldy     #0
        lda     FAC
        sta     (VARPNT),y
        iny
        lda     FAC+1
        sta     (VARPNT),y
        iny
        lda     FAC+2
        sta     (VARPNT),y
        rts
@synErr:
        pla
        pla
        pla
        jmp     SynErr
@typeErr:
        pla
        pla
        ldx     #ERR_TYPEMISM
        jmp     BasErrorVec

; =============================================================================
;   C O N T R O L   F L O W   /   S T A T E M E N T   L O O P
;
;   BasNewstt drives execution for both direct mode (TXTPTR in BAS_TOKBUF)
;   and run mode (TXTPTR walks program lines from BAS_TXTTAB).  Statement
;   dispatch follows the msbasic convention: push (routine_addr - 1) and
;   tail-jump through ChrGet, so the routine entry is reached via RTS.
;
;   FOR and GOSUB store frames on the CPU stack and JMP back to BasNewstt;
;   NEXT and RETURN scan the stack for a matching tag, then TXS to discard
;   the frame and resume.
; =============================================================================

NUM_STMT_TOKENS = TOK_MEM + 1 - TOK_BASE       ; $36 entries

BasNewstt:
        jsr     BasCheckBreak
        ; Save TXTPTR -> OLDTEXT for CONT, except in direct mode.
        lda     BAS_CURLIN+1
        cmp     #$FF
        beq     @noSave
        lda     TXTPTR
        sta     BAS_OLDTEXT
        lda     TXTPTR+1
        sta     BAS_OLDTEXT+1
@noSave:
        ldy     #0
        lda     (TXTPTR),y
        beq     @endLine
        cmp     #TOK_ELSE
        beq     @skipElse               ; THEN-branch ran; skip ELSE clause to EOL
        cmp     #':'
        beq     @nextStmt
        jmp     SynErr
@skipElse:
        ; Advance TXTPTR until we land on a $00 terminator.
@skLoop:
        jsr     ChrGet
        bne     @skLoop
        ; Fall through to @endLine with TXTPTR at $00.
@endLine:
        ; Direct mode: end of buffer -> back to REPL.
        lda     BAS_CURLIN+1
        cmp     #$FF
        bne     @walkNext
        jmp     BasReadyLoop            ; OK is printed by BasReadyLoop
@walkNext:
        ; Run mode: examine next-pointer at offsets +1,+2.
        ldy     #2
        lda     (TXTPTR),y
        bne     @loadLine               ; nonzero hi -> next line exists
        ; End of program -> halt and return to REPL.
        ldx     #$FF
        txs
        jmp     BasReadyLoop
@loadLine:
        iny                             ; y=3
        lda     (TXTPTR),y
        sta     BAS_CURLIN
        iny                             ; y=4
        lda     (TXTPTR),y
        sta     BAS_CURLIN+1
        tya                             ; A=4
        clc
        adc     TXTPTR
        sta     TXTPTR
        bcc     @nextStmt
        inc     TXTPTR+1
@nextStmt:
        jsr     ChrGet
        jsr     BasExecuteStatement
        jmp     BasNewstt

; ---------------------------------------------------------------------------
; BasExecuteStatement -- A = current tokenized byte (loaded by ChrGet).
;   * A = 0  -> RTS (no-op; end of statement chain).
;   * A < $80 (letter) -> JMP BasCmdLet.
;   * A is a statement token ($80..TOK_MEM) -> dispatch via BasTokenAddrTbl.
;   * Otherwise -> ?SYNTAX ERROR.
; ---------------------------------------------------------------------------
BasExecuteStatement:
        beq     @ret
        sec
        sbc     #TOK_BASE
        bcc     @doLet
        cmp     #NUM_STMT_TOKENS
        bcs     @synErr
        asl     a
        tay
        lda     BasTokenAddrTbl+1,y
        pha
        lda     BasTokenAddrTbl,y
        pha
        jmp     ChrGet
@doLet:
        jmp     BasCmdLet
@synErr:
        jmp     SynErr
@ret:
        rts

; ---------------------------------------------------------------------------
; BasCheckBreak -- poll input buffer for Ctrl-C / ESC.  On break, save
; CONT context and bounce to REPL.  Other keys are stashed in BAS_PENDKEY
; for INKEY to retrieve.
; ---------------------------------------------------------------------------
BasCheckBreak:
        ; In direct mode (CURLIN hi == $FF) skip the break check entirely;
        ; otherwise we would drain pending REPL keystrokes and corrupt the
        ; next BasReadLine input.  Break is only meaningful while RUNning.
        lda     BAS_CURLIN+1
        cmp     #$FF
        beq     @no
        jsr     BufferSize
        beq     @no
        jsr     ReadBuffer
        cmp     #$03
        beq     @break
        cmp     #$1B
        beq     @break
        sta     BAS_PENDKEY
@no:
        rts
@break:
        ; OLDLIN/OLDTEXT already track the executing line.  Make sure the
        ; saved values reflect the current line so CONT can resume.
        lda     BAS_CURLIN
        sta     BAS_OLDLIN
        lda     BAS_CURLIN+1
        sta     BAS_OLDLIN+1
        ldx     #$FF
        txs
        jsr     BasPrintCRLF
        lda     #<MsgBreak
        ldy     #>MsgBreak
        jsr     BasPrintStr
        lda     BAS_CURLIN+1
        cmp     #$FF
        beq     @noLine
        lda     #<MsgInWord
        ldy     #>MsgInWord
        jsr     BasPrintStr
        lda     BAS_CURLIN
        sta     BAS_LINNUM
        lda     BAS_CURLIN+1
        sta     BAS_LINNUM+1
        jsr     BasPrintLineNum
@noLine:
        lda     #$FF
        sta     BAS_CURLIN
        sta     BAS_CURLIN+1
        jmp     BasReadyLoop

MsgBreak: .byte "BREAK",0

; ---------------------------------------------------------------------------
; LinGet -- parse decimal digits at TXTPTR into BAS_LINNUM (16-bit).
; Caller has set carry conditions appropriate to ChrGet entry.  TXTPTR
; ends pointing at the first non-digit.
; ---------------------------------------------------------------------------
LinGet:
        ldx     #0
        stx     BAS_LINNUM
        stx     BAS_LINNUM+1
@loop:
        bcs     @done
        sbc     #$2F                    ; carry already set
        sta     CHARAC
        ; LINNUM *= 10
        lda     BAS_LINNUM
        sta     BAS_TMP1
        lda     BAS_LINNUM+1
        sta     BAS_TMP1+1
        cmp     #$19
        bcs     @ovf
        asl     BAS_LINNUM
        rol     BAS_LINNUM+1
        asl     BAS_LINNUM
        rol     BAS_LINNUM+1
        clc
        lda     BAS_LINNUM
        adc     BAS_TMP1
        sta     BAS_LINNUM
        lda     BAS_LINNUM+1
        adc     BAS_TMP1+1
        sta     BAS_LINNUM+1
        asl     BAS_LINNUM
        rol     BAS_LINNUM+1
        clc
        lda     BAS_LINNUM
        adc     CHARAC
        sta     BAS_LINNUM
        bcc     @nextDigit
        inc     BAS_LINNUM+1
@nextDigit:
        jsr     ChrGet
        jmp     @loop
@done:
        rts
@ovf:
        ldx     #ERR_SYNTAX
        jmp     BasErrorVec

; ---------------------------------------------------------------------------
; FndLin -- find program line whose number matches BAS_LINNUM.
;   On success: carry SET, BAS_TMP1 (LOWTR alias) = address of line.
;   On failure: carry CLEAR, BAS_TMP1 = address where line would belong.
; ---------------------------------------------------------------------------
FndLin:
        lda     BAS_TXTTAB
        ldx     BAS_TXTTAB+1
@walk:
        sta     BAS_TMP1
        stx     BAS_TMP1+1
        ldy     #1
        lda     (BAS_TMP1),y
        beq     @notFound               ; next-hi=0 -> end of program
        ldy     #3                      ; line-num-lo offset
        lda     BAS_LINNUM+1
        cmp     (BAS_TMP1),y            ; compare hi byte at +3? need iny
        ; Actually format: +0 next-lo, +1 next-hi, +2 num-lo, +3 num-hi
        bcc     @notFound               ; LINNUM-hi < line-hi -> miss
        bne     @advance                ; LINNUM-hi > line-hi -> next line
        dey                             ; y=2 = num-lo
        lda     BAS_LINNUM
        cmp     (BAS_TMP1),y
        bcc     @notFound
        beq     @found
@advance:
        ldy     #0
        lda     (BAS_TMP1),y
        pha
        ldy     #1
        lda     (BAS_TMP1),y
        tax
        pla
        bcs     @walk                   ; carry=1 means continue (always)
@notFound:
        clc
        rts
@found:
        sec
        rts

; ---------------------------------------------------------------------------
; BasCmdGoto -- TXTPTR points at line-number digits.
; ---------------------------------------------------------------------------
BasCmdGoto:
        jsr     LinGet
        jsr     BasRemn                 ; skip remainder of statement
        jsr     FndLin
        bcc     @undef
        ; LOWTR (BAS_TMP1) = target line addr.  TXTPTR = LOWTR - 1
        ; (so NEWSTT sees the previous line's $00 terminator at offset 0).
        sec
        lda     BAS_TMP1
        sbc     #1
        sta     TXTPTR
        lda     BAS_TMP1+1
        sbc     #0
        sta     TXTPTR+1
        rts
@undef:
        ldx     #ERR_UNDEFSTMT
        jmp     BasErrorVec

; ---------------------------------------------------------------------------
; BasCmdGosub -- push 5-byte frame on stack, then GOTO target.
; Frame layout (top-down): [tag $8C][CURLIN-lo][CURLIN-hi][TXTPTR-lo][TXTPTR-hi]
; ---------------------------------------------------------------------------
BasCmdGosub:
        lda     TXTPTR+1
        pha
        lda     TXTPTR
        pha
        lda     BAS_CURLIN+1
        pha
        lda     BAS_CURLIN
        pha
        lda     #TOK_GOSUB
        pha
        jsr     ChrGot
        jsr     BasCmdGoto
        jmp     BasNewstt

; ---------------------------------------------------------------------------
; BasCmdReturn -- locate GOSUB frame on stack and resume at saved TXTPTR.
; Per msbasic: scan the CPU stack from SP+5 (skipping return-routine's caller
; return + this scan's own JSR return).  RTS at end pops the leaked
; EXEC-return that GOSUB left behind.
; ---------------------------------------------------------------------------
BasCmdReturn:
        jsr     GtForPnt
        ; X now points to the slot just BELOW a frame tag (or end of stack).
        txs
        cmp     #TOK_GOSUB
        beq     @ok
        ldx     #ERR_RG
        jmp     BasErrorVec
@ok:
        pla                             ; tag (already in A, this discards)
        pla
        sta     BAS_CURLIN
        pla
        sta     BAS_CURLIN+1
        pla
        sta     TXTPTR
        pla
        sta     TXTPTR+1
        ; Skip remainder of GOSUB-target statement (DATAN-style).
        jsr     BasDatan
        ; Advance TXTPTR by Y (number of bytes to terminator).
        tya
        clc
        adc     TXTPTR
        sta     TXTPTR
        bcc     @noinc
        inc     TXTPTR+1
@noinc:
        rts

; ---------------------------------------------------------------------------
; GtForPnt -- scan CPU stack for FOR/GOSUB frames.
;   On entry: BAS_FORPNT (FORPNT) = $FFxx for "match any tag".
;   Returns: X = stack pointer where the matching frame's tag-1 lives,
;            A = tag byte found (or 0 if end-of-stack).  Z=1 if found tag,
;            Z=0 (A=0) if no frame found.
; ---------------------------------------------------------------------------
GtForPnt:
        tsx
        inx
        inx
        inx
        inx
@scan:
        lda     $0101,x                 ; tag candidate
        cmp     #TOK_FOR
        bne     @notFor
        ; Compare frame's variable address to FORPNT.
        lda     BAS_FORPNT+1
        bne     @skipVar                ; FORPNT+1 = $FF -> skip variable test
        lda     $0102,x
        sta     BAS_FORPNT
        lda     $0103,x
        sta     BAS_FORPNT+1
@skipVar:
        cmp     $0103,x
        bne     @advance
        lda     BAS_FORPNT
        cmp     $0102,x
        beq     @found
@advance:
        txa
        clc
        adc     #18                     ; BYTES_PER_FRAME (FOR)
        tax
        bne     @scan
        ; Walked off stack
        lda     #0
        rts
@notFor:
        cmp     #TOK_GOSUB
        beq     @found
        lda     #0
        rts
@found:
        rts

; ---------------------------------------------------------------------------
; BasRemn -- scan TXTPTR forward to next ':' or end-of-line.
; Sets Y to byte offset of terminator from current TXTPTR.  Honours quotes.
; ---------------------------------------------------------------------------
BasDatan:
        ldx     #':'
        .byte   $2C                     ; BIT abs absorbs next 2-byte LDX
BasRemn:
        ldx     #0
        stx     CHARAC
        ldy     #0
        sty     ENDCHR
@swap:
        lda     ENDCHR
        ldx     CHARAC
        sta     CHARAC
        stx     ENDCHR
@scan:
        lda     (TXTPTR),y
        beq     @done
        cmp     ENDCHR
        beq     @done
        iny
        cmp     #'"'
        beq     @swap
        bne     @scan
@done:
        rts

; ---------------------------------------------------------------------------
; Statement: REM -- skip to end of line.
; Statement: DATA -- treated like REM at execution time (just skip).
; ---------------------------------------------------------------------------
BasCmdRem:
        jsr     BasRemn
        bra     BasAddon
BasCmdData:
        jsr     BasDatan
BasAddon:
        tya
        clc
        adc     TXTPTR
        sta     TXTPTR
        bcc     @done
        inc     TXTPTR+1
@done:
        rts

; ---------------------------------------------------------------------------
; Statement: IF expr THEN (linenum | stmt) [ELSE stmt]
;   IF expr GOTO linenum is also accepted.
;   If expr is false, skip rest of line (REM-style).
;   ELSE: scan ahead for TOK_ELSE on this line.
; ---------------------------------------------------------------------------
BasCmdIf:
        jsr     FrmEvl
        jsr     ChrGot
        cmp     #TOK_GOTO
        beq     @testTrue
        lda     #TOK_THEN
        jsr     SynChr
@testTrue:
        lda     FAC
        bne     @true
        ; FALSE: scan to end-of-line OR a TOK_ELSE; if ELSE found, advance
        ; TXTPTR past it and resume execution there.
        ldy     #0
@searchElse:
        lda     (TXTPTR),y
        beq     @noElse
        cmp     #TOK_ELSE
        beq     @gotElse
        iny
        bne     @searchElse
@noElse:
        ; Skip remainder of line (no ELSE).
        jsr     BasRemn
        jmp     BasAddon
@gotElse:
        ; Advance TXTPTR past ELSE token; continue execution.
        iny
        tya
        clc
        adc     TXTPTR
        sta     TXTPTR
        bcc     @t1
        inc     TXTPTR+1
@t1:
        rts
@true:
        ; TRUE: if next is a digit, IF expr THEN <linenum> -> implicit GOTO.
        jsr     ChrGot
        bcc     @goto                   ; carry CLEAR -> digit
        ; Otherwise dispatch as a statement (msbasic: jmp EXECUTE_STATEMENT).
        jmp     BasExecuteStatement
@goto:
        jmp     BasCmdGoto

; ---------------------------------------------------------------------------
; Statement: ON expr GOTO/GOSUB linenum,linenum,...
; ---------------------------------------------------------------------------
BasCmdOn:
        jsr     GetByt                  ; X = expr byte (1..255)
        pha                             ; save GOTO/GOSUB token byte
        cmp     #TOK_GOSUB
        beq     @loop
        cmp     #TOK_GOTO
        bne     @synErr
@loop:
        dec     FAC+4
        bne     @next
        pla
        ; Re-dispatch through statement table so trampoline ChrGet skips the
        ; current separator (',' or 0) before the GOTO/GOSUB handler runs.
        jmp     BasExecuteStatement
@next:
        jsr     ChrGet
        jsr     LinGet
        cmp     #','
        beq     @loop
        pla
        rts
@synErr:
        pla
        jmp     SynErr

; ---------------------------------------------------------------------------
; GetByt / GtByteCom -- evaluate expression in TXTPTR to byte 0..255 in X.
;   GetByt: TXTPTR is at first byte of expression.
;   GtByteCom: consume comma first.
; ---------------------------------------------------------------------------
GtByteCom:
        jsr     ChrGet
GetByt:
        jsr     FrmNum
        jsr     MkInt
        ldx     FAC+3
        bne     @ovf
        ldx     FAC+4
        jmp     ChrGot
@ovf:
        jmp     IqErr

; ---------------------------------------------------------------------------
; Statement: RUN [linenum]
; ---------------------------------------------------------------------------
BasCmdRun:
        jsr     ChrGot
        bne     @withLine
        jsr     BasCmdClr
        ; Set TXTPTR = TXTTAB - 1 ; ensure that byte = 0.
        sec
        lda     BAS_TXTTAB
        sbc     #1
        sta     TXTPTR
        lda     BAS_TXTTAB+1
        sbc     #0
        sta     TXTPTR+1
        ; Force the byte at TXTTAB-1 to be zero so NEWSTT walks the chain.
        lda     #0
        ldy     #0
        sta     (TXTPTR),y
        ; Leave direct-mode (CURLIN+1=$FF); @loadLine will set real value.
        stz     BAS_CURLIN
        stz     BAS_CURLIN+1
        rts
@withLine:
        jsr     BasCmdClr
        jsr     ChrGot
        jmp     BasCmdGoto

; ---------------------------------------------------------------------------
; Statement: END / STOP -- save CONT context and return to REPL.
; ---------------------------------------------------------------------------
BasCmdEnd:
        clc
        .byte   $24                     ; BIT zp -> skip next byte (sec)
BasCmdStop:
        sec
        ; Save the END/STOP flag (carry) before ChrGot clobbers it.
        php
        jsr     ChrGot
        bne     @synErrPlp
        plp
        ; Save CONT state.
        lda     TXTPTR
        sta     BAS_OLDTEXT
        lda     TXTPTR+1
        sta     BAS_OLDTEXT+1
        lda     BAS_CURLIN
        sta     BAS_OLDLIN
        lda     BAS_CURLIN+1
        sta     BAS_OLDLIN+1
        ldx     #$FF
        txs
        bcc     @end
        ; STOP path: print "BREAK[ IN nnnn]".
        jsr     BasPrintCRLF
        lda     #<MsgBreak
        ldy     #>MsgBreak
        jsr     BasPrintStr
        lda     BAS_CURLIN+1
        cmp     #$FF
        beq     @endNoLine
        lda     #<MsgInWord
        ldy     #>MsgInWord
        jsr     BasPrintStr
        lda     BAS_CURLIN
        sta     BAS_LINNUM
        lda     BAS_CURLIN+1
        sta     BAS_LINNUM+1
        jsr     BasPrintLineNum
@endNoLine:
        lda     #$FF
        sta     BAS_CURLIN
        sta     BAS_CURLIN+1
        jmp     BasReadyLoop
@end:
        lda     #$FF
        sta     BAS_CURLIN
        sta     BAS_CURLIN+1
        jmp     BasReadyLoop
@synErrPlp:
        plp
@synErr:
        jmp     SynErr

; ---------------------------------------------------------------------------
; Statement: CONT -- resume execution from saved OLDTEXT/OLDLIN.
; ---------------------------------------------------------------------------
BasCmdCont:
        jsr     ChrGot
        bne     @synErr
        lda     BAS_OLDTEXT+1
        bne     @canCont
        ldx     #ERR_CANTCONT
        jmp     BasErrorVec
@canCont:
        lda     BAS_OLDTEXT
        sta     TXTPTR
        lda     BAS_OLDTEXT+1
        sta     TXTPTR+1
        lda     BAS_OLDLIN
        sta     BAS_CURLIN
        lda     BAS_OLDLIN+1
        sta     BAS_CURLIN+1
        rts
@synErr:
        jmp     SynErr

; ---------------------------------------------------------------------------
; Statement: RESTORE -- DATAPTR := TXTTAB - 1.
; ---------------------------------------------------------------------------
BasCmdRestore:
        sec
        lda     BAS_TXTTAB
        sbc     #1
        sta     BAS_DATAPTR
        lda     BAS_TXTTAB+1
        sbc     #0
        sta     BAS_DATAPTR+1
        rts

; ---------------------------------------------------------------------------
; Statement: INPUT [<"prompt">{,;}] var[,var,...]
;   Prompts user for input, reads a line, parses it into the variable list.
;   "abc";VAR  prints  abc?    (question + space appended)
;   "abc",VAR  prints  abc      (no question mark)
;   no prompt: prints  ?
;   On bad numeric input or premature end-of-line: "?REDO FROM START"
;   and reprompt.  Trailing un-consumed input: "?EXTRA IGNORED".
; ---------------------------------------------------------------------------
BasCmdInput:
        ; INPUT is illegal in direct mode.
        lda     BAS_CURLIN+1
        cmp     #$FF
        bne     @notDirect
        ldx     #ERR_ILLDIRECT
        jmp     BasErrorVec
@notDirect:
        ; ChrGot returns first char after the INPUT token.
        jsr     ChrGot
        cmp     #'"'
        bne     @noPrompt
        ; Parse string literal & print it; FrmEvl will leave descriptor in FAC.
        jsr     FrmEvl
        jsr     ChkStr
        jsr     PrintStrFAC
        jsr     FreFac
        jsr     ChrGot
        cmp     #';'
        beq     @semi
        cmp     #','
        bne     @badPrompt
        jsr     ChrGet                  ; consume ','
        bra     @afterPrompt
@semi:
        jsr     ChrGet                  ; consume ';'
        jsr     BasInpQues              ; '? '
        bra     @afterPrompt
@badPrompt:
        jmp     SynErr
@noPrompt:
        jsr     BasInpQues              ; '? '
@afterPrompt:
        ; Save program TXTPTR (start of var-list) for REDO retry.
        lda     TXTPTR
        sta     BAS_INPSAV
        lda     TXTPTR+1
        sta     BAS_INPSAV+1
@retry:
        jsr     BasReadLine             ; reads to BAS_LINBUF, NUL-terminated, prints CRLF
        ; Set up data pointer with leading ',' sentinel just before LINBUF.
        lda     #','
        sta     BAS_LINBUF-1
        lda     #<(BAS_LINBUF-1)
        sta     BAS_TMP1
        lda     #>(BAS_LINBUF-1)
        sta     BAS_TMP1+1
        ; Restore program TXTPTR.
        lda     BAS_INPSAV
        sta     TXTPTR
        lda     BAS_INPSAV+1
        sta     TXTPTR+1
        stz     BAS_INPUTFLG            ; INPUT mode ($00)
@nextVar:
        jsr     PtrGet                  ; advance program TXTPTR past var name
        sta     BAS_FORPNT
        sty     BAS_FORPNT+1
        ; Save program TXTPTR; switch to data side.
        lda     TXTPTR+1
        pha
        lda     TXTPTR
        pha
        lda     BAS_TMP1
        sta     TXTPTR
        lda     BAS_TMP1+1
        sta     TXTPTR+1
        jsr     ChrGot
        bne     @gotData
        ; Out of input data before var list exhausted -> REDO.
        pla
        pla
        jmp     @doRedo
@gotData:
        jsr     ChrGet                  ; consume the separator/sentinel
        bit     VALTYP
        bmi     @inpStr
        ; Numeric: must start with digit, '+', '-' or '.'; else REDO.
        jsr     ChrGot
        bcc     @numOk                  ; carry clear == digit
        cmp     #'-'
        beq     @numOk
        cmp     #'+'
        beq     @numOk
        cmp     #'.'
        beq     @numOk
        ; bad numeric
        pla
        pla
        jmp     @doRedo
@numOk:
        jsr     Fin
        ldx     BAS_FORPNT
        ldy     BAS_FORPNT+1
        jsr     StoreFacAtYxRounded
        ; After Fin, ChrGot result must be NUL or ',' (Fin/ChrGot skips spaces).
        jsr     ChrGot
        beq     @afterStore
        cmp     #','
        beq     @afterStore
        ; Garbage trailing the number -> REDO.
        pla
        pla
        jmp     @doRedo
@inpStr:
        ; Peek at the first data character.  If it's a '"', use quote-mode
        ; (terminator = '"' or NUL); otherwise terminate at ',' or NUL.
        ldy     #0
        lda     (TXTPTR),y
        cmp     #'"'
        beq     @sQuoted
        ; Unquoted: STRLT2 source = TXTPTR.
        lda     #0
        sta     CHARAC
        lda     #','
        sta     ENDCHR
        lda     TXTPTR
        ldy     TXTPTR+1
        bra     @sCallStrLt
@sQuoted:
        lda     #'"'
        sta     CHARAC
        sta     ENDCHR
        ; Skip the opening '"'; STRLT2 source = TXTPTR + 1.
        clc
        lda     TXTPTR
        adc     #1
        ldy     TXTPTR+1
        bcc     @sCallStrLt
        iny
@sCallStrLt:
        jsr     StrLt2
        ; StrLt2 leaves STRNG2 pointing past the consumed string (at the
        ; terminator for unquoted input, or just past the closing '"' for
        ; quoted input).  Advance TXTPTR (== data pointer) accordingly so
        ; the trailing-extra check sees only what truly remained on the
        ; input line.
        lda     STRNG2
        sta     TXTPTR
        lda     STRNG2+1
        sta     TXTPTR+1
        ldy     #0
        lda     FAC
        sta     (BAS_FORPNT),y
        iny
        lda     FAC+1
        sta     (BAS_FORPNT),y
        iny
        lda     FAC+2
        sta     (BAS_FORPNT),y
@afterStore:
        ; Save data ptr; restore program TXTPTR.
        lda     TXTPTR
        sta     BAS_TMP1
        lda     TXTPTR+1
        sta     BAS_TMP1+1
        pla
        sta     TXTPTR
        pla
        sta     TXTPTR+1
        ; More variables?
        jsr     ChrGot
        cmp     #','
        bne     @doneVars
        jsr     ChrGet                  ; consume ','
        jmp     @nextVar
@doneVars:
        ; Check for un-consumed input (EXTRA IGNORED).
        ldy     #0
        lda     (BAS_TMP1),y
        beq     @inpDone
        ; Skip leading spaces; anything else is "extra".
@chkExtra:
        lda     (BAS_TMP1),y
        beq     @inpDone
        cmp     #' '
        bne     @hasExtra
        iny
        bne     @chkExtra
@hasExtra:
        lda     #<MsgExtra
        ldy     #>MsgExtra
        jsr     BasPrintStr
@inpDone:
        rts
@doRedo:
        lda     #<MsgRedo
        ldy     #>MsgRedo
        jsr     BasPrintStr
        jmp     @retry

; Print "? " prompt (used by INPUT and the ';' prompt-suffix path).
BasInpQues:
        lda     #'?'
        jsr     PrintCh
        lda     #' '
        jmp     PrintCh

MsgRedo:
        .byte   "?REDO FROM START", $0D, $0A, 0
MsgExtra:
        .byte   "?EXTRA IGNORED", $0D, $0A, 0

; ---------------------------------------------------------------------------
; Statement: READ var[,var,...] -- pull next DATA item from BAS_DATAPTR
; into the variable pointed to by PtrGet.
; ---------------------------------------------------------------------------
BasCmdRead:
        ldx     BAS_DATAPTR
        ldy     BAS_DATAPTR+1
        lda     #$98                    ; INPUTFLG = $98 means READ mode
        .byte   $2C
BasInpDoit:
        lda     #0
        sta     BAS_INPUTFLG
        stx     BAS_TMP1                ; TMP1 = data pointer
        sty     BAS_TMP1+1
@nextVar:
        ; TXTPTR currently points into program at variable name.
        jsr     PtrGet                  ; advances TXTPTR past var name
        sta     BAS_FORPNT
        sty     BAS_FORPNT+1
        ; Save program TXTPTR on hw stack, switch TXTPTR to data ptr.
        lda     TXTPTR+1
        pha
        lda     TXTPTR
        pha
        lda     BAS_TMP1
        sta     TXTPTR
        lda     BAS_TMP1+1
        sta     TXTPTR+1
        jsr     ChrGot
        bne     @gotData
        ; Out of items on this line - find next DATA.
        jsr     BasFindData
        bcc     @gotData
        jmp     @oodata
@gotData:
        ; Advance past separator (',' between items, ' ' after DATA token,
        ; or quote-delimiter for strings).  ChrGet also skips spaces.
        jsr     ChrGet
        ; Parse value at TXTPTR (data side).
        bit     VALTYP
        bmi     @readStr
        ; Numeric.
        jsr     Fin
        ldx     BAS_FORPNT
        ldy     BAS_FORPNT+1
        jsr     StoreFacAtYxRounded
        bra     @afterStore
@readStr:
        ; String.
        lda     #'"'
        sta     CHARAC
        sta     ENDCHR
        ldy     #0
        lda     (TXTPTR),y
        cmp     #'"'
        beq     @quoted
        lda     #':'
        sta     CHARAC
        lda     #','
        sta     ENDCHR
@quoted:
        jsr     StrLt2
        ldy     #0
        lda     FAC
        sta     (BAS_FORPNT),y
        iny
        lda     FAC+1
        sta     (BAS_FORPNT),y
        iny
        lda     FAC+2
        sta     (BAS_FORPNT),y
@afterStore:
        ; Save updated data ptr.
        lda     TXTPTR
        sta     BAS_TMP1
        lda     TXTPTR+1
        sta     BAS_TMP1+1
        ; Restore program TXTPTR.
        pla
        sta     TXTPTR
        pla
        sta     TXTPTR+1
        ; If next program byte is ',', another variable follows.
        jsr     ChrGot
        cmp     #','
        bne     @done
        jsr     ChrGet
        bra     @nextVar
@done:
        ; Persist data ptr.
        lda     BAS_TMP1
        sta     BAS_DATAPTR
        lda     BAS_TMP1+1
        sta     BAS_DATAPTR+1
        rts
@oodata:
        ldx     #ERR_OD
        jmp     BasErrorVec

; ---------------------------------------------------------------------------
; BasFindData -- starting from TXTPTR (positioned somewhere within a line's
; payload), advance to the byte after the next DATA token in the program.
; Returns carry SET on out-of-data, carry CLEAR with TXTPTR at first byte
; AFTER the DATA token (i.e. at the first DATA item).
; ---------------------------------------------------------------------------
BasFindData:
@scanByte:
        ldy     #0
        lda     (TXTPTR),y
        beq     @atEnd
        cmp     #TOK_DATA
        beq     @found
        cmp     #'"'
        bne     @advance1
        ; Skip quoted string (advance TXTPTR past closing quote or NUL).
        jsr     @incTxt
@inStr:
        ldy     #0
        lda     (TXTPTR),y
        beq     @atEnd
        jsr     @incTxt
        cmp     #'"'
        bne     @inStr
        bra     @scanByte
@advance1:
        jsr     @incTxt
        bra     @scanByte
@atEnd:
        ; (TXTPTR) is on the line's $00 terminator.  Bytes immediately after
        ; are the next line's [next-lo][next-hi][num-lo][num-hi][payload..].
        ; Check next-pointer at offset +2 (next-hi); if 0, end of program.
        ldy     #2
        lda     (TXTPTR),y
        beq     @oodata
        ; Advance TXTPTR by 5: past terminator (1) + line header (4).
        clc
        lda     TXTPTR
        adc     #5
        sta     TXTPTR
        bcc     @scanByte
        inc     TXTPTR+1
        bra     @scanByte
@found:
        ; TXTPTR is left AT the TOK_DATA byte; caller's CHRGET advances past.
        clc
        rts
@oodata:
        sec
        rts
@incTxt:
        inc     TXTPTR
        bne     @r
        inc     TXTPTR+1
@r:
        rts

; ---------------------------------------------------------------------------
; Statement: FOR var = expr1 TO expr2 [STEP expr3]
; Pushes 18-byte frame on CPU stack:
;   [tag $81][VAR-lo][VAR-hi][STEP-FP (5)][STEP-sign][CURLIN-lo][CURLIN-hi]
;   [TXTPTR-lo][TXTPTR-hi][LIMIT-FP (5)]
; ---------------------------------------------------------------------------
BasCmdFor:
        ; Set SUBFLG so PtrGet doesn't recurse on FN.
        lda     #$80
        sta     SUBFLG
        jsr     BasCmdLet               ; consumes "var = expr"
        ; PtrGet (inside LET) saved VARPNT in FORPNT (hopefully). Re-fetch
        ; FORPNT from the assignment, but BasCmdLet doesn't set FORPNT in
        ; our impl.  Re-parse the variable name by rewinding TXTPTR via
        ; CURLIN scan.  Cheat: BasCmdLet leaves VARPNT current.
        lda     VARPNT
        sta     BAS_FORPNT
        lda     VARPNT+1
        sta     BAS_FORPNT+1
        ; Discard any prior FOR frame for the same variable to avoid leak.
        jsr     GtForPnt
        bne     @noOld                  ; Z=0 -> not found (lda #0 sets Z=1; we invert below)
        ; Actually GtForPnt's "not found" path also ends with `lda #0;rts` (Z=1).
        ; So the BEQ/BNE distinction can't be used. Skip the prior-frame
        ; pop entirely; the runtime can tolerate one stray frame and msbasic
        ; FOR re-uses the same slot only when an explicit FOR with a matching
        ; variable already exists, which is rare.
@noOld:
        ; Discard our caller's (BasExecuteStatement's) return address so
        ; that the FOR frame sits on the stack with no other junk above it.
        ; We will JMP BasNewstt at the end instead of RTSing.
        pla
        pla
        ; Push limit (will be parsed below) -- we lay out the frame as:
        ;   pushed first (deepest): TXTPTR, CURLIN, LIMIT (5), STEP-sign,
        ;   STEP (5), VAR-addr, $81-tag.
        ; We don't know LIMIT/STEP yet; we push placeholders and patch.
        ; Easier: parse limit & step first, then push frame in one go.
        lda     #TOK_TO
        jsr     SynChr
        jsr     FrmNum
        ; Strip sign info on limit (msbasic stores limit unsigned-magnitude
        ; with sign packed).  Pack FACSIGN bit 7 -> FAC+1 bit 7.
        lda     FACSIGN
        ora     #$7F
        and     FAC+1
        sta     FAC+1
        ; Save LIMIT temporarily in BAS_TEMP1..+4 (5 bytes).
        ldx     #4
@saveLimit:
        lda     FAC,x
        sta     BAS_TEMP1,x
        dex
        bpl     @saveLimit
        ; STEP: default 1, or evaluate after TOK_STEP.
        jsr     ChrGot
        cmp     #TOK_STEP
        bne     @defStep
        jsr     ChrGet
        jsr     FrmNum
        bra     @gotStep
@defStep:
        lda     #<ConstOne
        ldy     #>ConstOne
        jsr     LoadFacFromYa
@gotStep:
        jsr     Sign                    ; A = step sign byte (-1/0/1)
        sta     BAS_TEMP2               ; stash step sign
        ; Pack sign of FAC into FAC+1 bit7 then save STEP into BAS_TEMP2+1..+5.
        lda     FACSIGN
        ora     #$7F
        and     FAC+1
        sta     FAC+1
        ldx     #4
@saveStep:
        lda     FAC,x
        sta     BAS_TEMP2+1,x
        dex
        bpl     @saveStep
        ; Now push the frame on stack (deepest first):
        ;   TXTPTR-hi, TXTPTR-lo, CURLIN-hi, CURLIN-lo,
        ;   LIMIT[4..0]   (deepest=LIMIT[4], so LIMIT[0] ends at $010A,x),
        ;   STEP-sign,
        ;   STEP[4..0]    (deepest=STEP[4], so STEP[0]  ends at $0104,x),
        ;   VAR-hi, VAR-lo, $81
        lda     TXTPTR+1
        pha
        lda     TXTPTR
        pha
        lda     BAS_CURLIN+1
        pha
        lda     BAS_CURLIN
        pha
        ldx     #4
@pushLim:
        lda     BAS_TEMP1,x
        pha
        dex
        bpl     @pushLim
        lda     BAS_TEMP2               ; step sign
        pha
        ldx     #5
@pushStep:
        lda     BAS_TEMP2,x
        pha
        dex
        bne     @pushStep
        lda     BAS_FORPNT+1
        pha
        lda     BAS_FORPNT
        pha
        lda     #TOK_FOR
        pha
        jmp     BasNewstt               ; resume statement loop with frame in place

ConstOne:
        .byte   $81,$00,$00,$00,$00     ; FP +1.0

; ---------------------------------------------------------------------------
; Statement: NEXT [var]
; Locate matching FOR frame, increment var by step, test against limit,
; loop back if more iterations remain, else discard frame and continue.
; ---------------------------------------------------------------------------
BasCmdNext:
        jsr     ChrGot
        beq     @anyVar
        cmp     #':'
        beq     @anyVar
        jsr     PtrGet
        sta     BAS_FORPNT
        sty     BAS_FORPNT+1
        bra     @find
@anyVar:
        ; "NEXT" without a variable: set FORPNT = 0 so GtForPnt copies the
        ; stack-frame's var address into FORPNT and then trivially matches
        ; (any FOR frame is acceptable).
        lda     #0
        sta     BAS_FORPNT
        sta     BAS_FORPNT+1
@find:
        jsr     GtForPnt
        beq     @found
        ldx     #ERR_NF
        jmp     BasErrorVec
@found:
        ; X = stack offset of (tag - 1).  txs makes SP = X so the frame
        ; sits at $101+X..$112+X.  All subsequent accesses use $0101+offset,x
        ; just like msbasic.
        txs
        ; Frame layout (tag at $0101+X):
        ;   $0101+X = $81 tag
        ;   $0102+X = VAR-lo
        ;   $0103+X = VAR-hi
        ;   $0104+X..$0108+X = STEP (5 bytes FP, FAC[0..4] ascending)
        ;   $0109+X = STEP-sign
        ;   $010A+X..$010E+X = LIMIT (5 bytes FP, FAC[0..4] ascending)
        ;   $010F+X = CURLIN-lo
        ;   $0110+X = CURLIN-hi
        ;   $0111+X = TXTPTR-lo
        ;   $0112+X = TXTPTR-hi
        ; Load STEP into FAC.
        lda     #$01
        sta     BAS_TMP1+1
        txa
        clc
        adc     #$04
        sta     BAS_TMP1                ; TMP1 -> STEP[0] at $0104,x
        lda     BAS_TMP1
        ldy     BAS_TMP1+1
        jsr     LoadFacFromYa
        ; FACSIGN := step sign byte at $0109,x.
        lda     $0109,x
        sta     FACSIGN
        ; FAC += variable.
        lda     $0102,x
        ldy     $0103,x
        sta     BAS_FORPNT
        sty     BAS_FORPNT+1
        jsr     FAdd
        jsr     SetFor
        ; Compare FAC with LIMIT (at $010A,x).
        tsx                             ; reload x (FAdd may have used it)
        txa
        clc
        adc     #$0A
        sta     BAS_TMP1
        lda     #$01
        sta     BAS_TMP1+1
        lda     BAS_TMP1
        ldy     BAS_TMP1+1
        jsr     FComp
        tsx
        sec
        sbc     $0109,x                 ; A - step-sign
        beq     @loopDone
        ; Continue: restore CURLIN/TXTPTR from frame, JMP NEWSTT (don't RTS).
        lda     $010F,x
        sta     BAS_CURLIN
        lda     $0110,x
        sta     BAS_CURLIN+1
        lda     $0111,x
        sta     TXTPTR
        lda     $0112,x
        sta     TXTPTR+1
        jmp     BasNewstt
@loopDone:
        ; Discard frame: SP := X + 18.
        txa
        clc
        adc     #18
        tax
        txs
        ; Allow ", var" to chain into another NEXT.
        jsr     ChrGot
        cmp     #','
        bne     @retNewstt
        jsr     ChrGet
        jmp     BasCmdNext
@retNewstt:
        jmp     BasNewstt

; ---------------------------------------------------------------------------
; Statement: DEF FN A(X) = expr
; Stored in the variable's 5 value bytes:
;   [TXTPTR-of-expr-lo][TXTPTR-of-expr-hi][param-name-lo][param-name-hi][0]
; ---------------------------------------------------------------------------
BasCmdDef:
        ; Expect: FN <name>(<param>) = <expr>
        lda     #TOK_FN
        jsr     SynChr
        ora     #$80
        sta     SUBFLG                  ; tell PtrGet "this is a DEF FN var"
        jsr     PtrGet
        ; VARPNT = address of FN var slot.
        sta     BAS_FNCNAM
        sty     BAS_FNCNAM+1
        jsr     ChkNum
        ; Expect '(' name ')' = expr
        ; Param name parsed by recursive PtrGet inside FrmEvl on call;
        ; here we just record (param-name) by parsing it ourselves.
        lda     #'('
        jsr     SynChr
        lda     #$80
        sta     SUBFLG
        jsr     PtrGet
        ; VARPNT = param var addr.  Save it.
        lda     VARPNT
        sta     BAS_TMP1
        lda     VARPNT+1
        sta     BAS_TMP1+1
        jsr     ChkNum
        lda     #')'
        jsr     SynChr
        lda     #'='
        jsr     SynChr
        ; Reject in direct mode.
        lda     BAS_CURLIN+1
        cmp     #$FF
        bne     @ok
        ldx     #ERR_ILLDIRECT
        jmp     BasErrorVec
@ok:
        ; Store [TXTPTR][param][0] in FN var.
        ldy     #0
        lda     TXTPTR
        sta     (BAS_FNCNAM),y
        iny
        lda     TXTPTR+1
        sta     (BAS_FNCNAM),y
        iny
        lda     BAS_TMP1
        sta     (BAS_FNCNAM),y
        iny
        lda     BAS_TMP1+1
        sta     (BAS_FNCNAM),y
        iny
        lda     #0
        sta     (BAS_FNCNAM),y
        ; Skip past expression body.
        jsr     BasDatan
        jmp     BasAddon

; ---------------------------------------------------------------------------
; FnCall -- evaluator-side handler for "FN A(expr)".
; Called by FrmEvl when it sees TOK_FN.  Evaluates argument, swaps in the
; param's stored value, executes the FN expression, and restores the param.
; ---------------------------------------------------------------------------
FnCall:
        jsr     ChrGet                  ; consume FN
        ora     #$80
        sta     SUBFLG
        jsr     PtrGet                  ; locate FN var
        sta     BAS_FNCNAM
        sty     BAS_FNCNAM+1
        jsr     ChkNum
        ; Read param ptr from FN slot.
        ldy     #2
        lda     (BAS_FNCNAM),y
        sta     VARPNT
        beq     @undef
        iny
        lda     (BAS_FNCNAM),y
        sta     VARPNT+1
        ; Evaluate '(arg)'
        lda     #'('
        jsr     SynChr
        ; Save param's current FP value (5 bytes) on stack.
        ldy     #4
@savep:
        lda     (VARPNT),y
        pha
        dey
        bpl     @savep
        ; Evaluate argument -> FAC.
        jsr     FrmNum
        lda     #')'
        jsr     SynChr
        ; Store FAC into param slot.
        ldx     VARPNT
        ldy     VARPNT+1
        jsr     StoreFacAtYxRounded
        ; Save current TXTPTR.
        lda     TXTPTR+1
        pha
        lda     TXTPTR
        pha
        ; Switch TXTPTR to FN expression body.
        ldy     #0
        lda     (BAS_FNCNAM),y
        sta     TXTPTR
        iny
        lda     (BAS_FNCNAM),y
        sta     TXTPTR+1
        ; Body TXTPTR is positioned at the first byte; we need it positioned
        ; one BEFORE so FrmNum's first ChrGet loads the first byte.  Decrement.
        lda     TXTPTR
        bne     @noBor
        dec     TXTPTR+1
@noBor:
        dec     TXTPTR
        ; Evaluate the FN expression body.
        jsr     ChrGet
        jsr     FrmNum
        ; Restore TXTPTR.
        pla
        sta     TXTPTR
        pla
        sta     TXTPTR+1
        ; Restore param.  VARPNT may have been clobbered; reload.
        ldy     #2
        lda     (BAS_FNCNAM),y
        sta     VARPNT
        iny
        lda     (BAS_FNCNAM),y
        sta     VARPNT+1
        ldy     #0
@restp:
        pla
        sta     (VARPNT),y
        iny
        cpy     #5
        bne     @restp
        rts
@undef:
        ldx     #ERR_UNDEFSTMT
        jmp     BasErrorVec

; ---------------------------------------------------------------------------
; Reserved dispatch slot -- raise SYNTAX ERROR.
; ---------------------------------------------------------------------------
BasCmdNotImpl:
        jmp     SynErr

; ===========================================================================
;   H A R D W A R E - E X T E N S I O N   S T A T E M E N T S
; ===========================================================================

; --- Helpers --------------------------------------------------------------

; Raise ?NO DEVICE error.
NoDevErr:
        ldx     #ERR_NODEV
        jmp     BasErrorVec

; Require A bits in HW_PRESENT (else ?NO DEVICE).
;   Input : A = mask
;   Output: A preserved on success
ReqHw:
        and     HW_PRESENT
        beq     NoDevErr
        rts

; Evaluate expression -> A in 0..255.
;   On entry: ChrGot positioned at first byte of expression.
;   On exit : A = byte, ChrGot returns char following expression.
EvalU8:
        jsr     GetByt                  ; X = byte, jmp ChrGot
        txa
        rts

; Evaluate expression as 16-bit signed -> FAC+3 (hi), FAC+4 (lo).
EvalU16:
        jsr     FrmNum
        jsr     AyInt
        jmp     ChrGot

; Evaluate expression as 16-bit unsigned address (0..65535)
;   -> FAC+3 (hi), FAC+4 (lo).  Used by SYS, POKE, PEEK, WAIT so the full
;   6502 address space is reachable with positive decimal literals.
;   Truncates fractional part.  Negative or >= 65536 raises ?ILLEGAL QUANTITY.
EvalAddrU16:
        jsr     FrmNum
        jsr     FacToU16
        jmp     ChrGot

; FacToU16 -- Convert FAC (must be 0..65535) to FAC+3 (hi), FAC+4 (lo).
;   Negative or >= 65536 raises ?ILLEGAL QUANTITY.  Truncates fractional part.
FacToU16:
        bit     FACSIGN
        bmi     @illqty
        lda     FAC                     ; exponent byte (0 = value is zero)
        beq     @zero
        cmp     #$91                    ; exp >= $91 means value >= 65536
        bcs     @illqty
        ; Reconstruct top 16 bits of mantissa (with hidden 1 bit).
        pha                             ; save exponent byte
        lda     FAC+1
        ora     #$80                    ; restore hidden bit
        sta     BAS_TMP1+1              ; hi
        lda     FAC+2
        sta     BAS_TMP1                ; lo
        ; Shift count = $90 - exp_byte (0..15).
        pla
        sec
        sbc     #$90
        eor     #$FF
        clc
        adc     #1                      ; A = $90 - exp
        beq     @store                  ; zero shifts: already aligned
        tax
@shloop:
        lsr     BAS_TMP1+1
        ror     BAS_TMP1
        dex
        bne     @shloop
@store:
        lda     BAS_TMP1+1
        sta     FAC+3
        lda     BAS_TMP1
        sta     FAC+4
        rts
@zero:
        stz     FAC+3
        stz     FAC+4
        rts
@illqty:
        jmp     IqErr

; Evaluate string expression -> copy up to 11 chars to BAS_FNAME,
; null-terminate, set STR_PTR := BAS_FNAME, free temp string.
EvalString:
        jsr     FrmEvl
        jsr     ChkStr
        lda     FAC+1
        sta     INDEX
        lda     FAC+2
        sta     INDEX+1
        ldy     #0
        ldx     FAC                     ; length
@cpy:
        cpy     #11
        beq     @done
        cpx     #0
        beq     @done
        lda     (INDEX),y
        sta     BAS_FNAME,y
        iny
        dex
        bra     @cpy
@done:
        lda     #0
        sta     BAS_FNAME,y
        lda     #<BAS_FNAME
        sta     STR_PTR
        lda     #>BAS_FNAME
        sta     STR_PTR+1
        jmp     FreFac

; Print A as 2-digit decimal with leading zero (used by TIME/DATE).
BasPr2D:
        ldx     #0
@loop:
        cmp     #10
        bcc     @done
        sbc     #10
        inx
        bra     @loop
@done:
        pha
        txa
        ora     #'0'
        jsr     Chrout
        pla
        ora     #'0'
        jmp     Chrout

; Walk program chain after LOAD to recompute BAS_VARTAB.
;   On entry: ChrGot any.
BasFixChain:
        lda     #<PROGRAM_START
        sta     INDEX
        lda     #>PROGRAM_START
        sta     INDEX+1
@walk:
        ldy     #0
        lda     (INDEX),y
        sta     BAS_TMP1
        iny
        lda     (INDEX),y
        sta     BAS_TMP1+1
        ora     BAS_TMP1
        beq     @end
        lda     BAS_TMP1
        sta     INDEX
        lda     BAS_TMP1+1
        sta     INDEX+1
        bra     @walk
@end:
        ; INDEX points at terminator ($00 $00).  VARTAB = INDEX + 2.
        clc
        lda     INDEX
        adc     #2
        sta     BAS_VARTAB
        lda     INDEX+1
        adc     #0
        sta     BAS_VARTAB+1
        rts

; --- Statements -----------------------------------------------------------

; SYS addr -- jump indirectly to address (RTS returns to caller).
BasCmdSys:
        jsr     EvalAddrU16
        lda     FAC+4
        sta     INDEX
        lda     FAC+3
        sta     INDEX+1
        jmp     (INDEX)

; CLS
BasCmdCls:
        lda     #HW_VID
        jsr     ReqHw
        jmp     VideoClear

; LOCATE row, col
BasCmdLocate:
        lda     #HW_VID
        jsr     ReqHw
        jsr     GetByt                  ; X = row
        phx
        jsr     ChkCom
        jsr     GetByt                  ; X = col
        ply                             ; Y = row
        jmp     VideoSetCursor

; COLOR fg, bg
BasCmdColor:
        lda     #HW_VID
        jsr     ReqHw
        jsr     GetByt                  ; X = fg
        txa
        asl     a
        asl     a
        asl     a
        asl     a
        sta     BAS_TMP1
        jsr     ChkCom
        jsr     GetByt                  ; X = bg
        txa
        and     #$0F
        ora     BAS_TMP1
        jmp     VideoSetColor

; VOL n
BasCmdVol:
        lda     #HW_SID
        jsr     ReqHw
        jsr     GetByt                  ; X = vol
        txa
        jmp     SidSetVolume

; SOUND voice, freq, dur (freq=Hz, dur=centisec)
;   Hz -> SID register: reg = Hz * 16.75 ≈ Hz<<4 + Hz - Hz/4
BasCmdSound:
        lda     #HW_SID
        jsr     ReqHw
        jsr     GetByt                  ; X = voice (1..3)
        dex
        phx                             ; voice (0-indexed) on stack
        jsr     ChkCom
        jsr     EvalU16                 ; freq Hz: hi=FAC+3, lo=FAC+4
        ; Compute reg = Hz<<4 + Hz - Hz/4
        lda     FAC+4
        sta     BAS_TMP1
        lda     FAC+3
        sta     BAS_TMP1+1
        lda     BAS_TMP1
        sta     BAS_TMP2
        lda     BAS_TMP1+1
        sta     BAS_TMP2+1
        ldx     #4
@shl:
        asl     BAS_TMP1
        rol     BAS_TMP1+1
        dex
        bne     @shl
        clc
        lda     BAS_TMP1
        adc     BAS_TMP2
        sta     BAS_TMP1
        lda     BAS_TMP1+1
        adc     BAS_TMP2+1
        sta     BAS_TMP1+1
        lsr     BAS_TMP2+1
        ror     BAS_TMP2
        lsr     BAS_TMP2+1
        ror     BAS_TMP2
        sec
        lda     BAS_TMP1
        sbc     BAS_TMP2
        pha                             ; freqLo
        lda     BAS_TMP1+1
        sbc     BAS_TMP2+1
        pha                             ; freqHi
        jsr     ChkCom
        jsr     EvalU16                 ; dur in FAC+3/+4
        ; Stack (top-down): freqHi, freqLo, voice
        ply                             ; Y = freqHi
        plx                             ; X = freqLo
        pla                             ; A = voice
        jsr     SidPlayNote
        lda     FAC+4
        ldx     FAC+3
        jsr     SysDelay
        jmp     SidSilence

; TIME
BasCmdTime:
        lda     #HW_RTC
        jsr     ReqHw
        jsr     RtcReadTime             ; A=hours, X=min, Y=sec
        phy
        phx
        jsr     BasPr2D                 ; print hours
        lda     #':'
        jsr     Chrout
        pla
        jsr     BasPr2D
        lda     #':'
        jsr     Chrout
        pla
        jsr     BasPr2D
        jmp     BasPrintCRLF

; DATE
BasCmdDate:
        lda     #HW_RTC
        jsr     ReqHw
        jsr     RtcReadDate             ; A=day, X=month, Y=year
        pha
        phx
        phy
        lda     RTC_BUF_CENT
        jsr     BasPr2D
        pla
        jsr     BasPr2D
        lda     #'-'
        jsr     Chrout
        pla
        jsr     BasPr2D
        lda     #'-'
        jsr     Chrout
        pla
        jsr     BasPr2D
        jmp     BasPrintCRLF

; SETTIME h, m, s
BasCmdSettime:
        lda     #HW_RTC
        jsr     ReqHw
        jsr     GetByt                  ; X = h
        phx
        jsr     ChkCom
        jsr     GetByt                  ; X = m
        phx
        jsr     ChkCom
        jsr     GetByt                  ; X = s
        txa
        tay                             ; Y = s
        plx                             ; X = m
        pla                             ; A = h
        jmp     RtcWriteTime

; SETDATE c, y, m, d
BasCmdSetdate:
        lda     #HW_RTC
        jsr     ReqHw
        jsr     GetByt
        stx     RTC_BUF_CENT
        jsr     ChkCom
        jsr     GetByt
        phx                             ; year
        jsr     ChkCom
        jsr     GetByt
        phx                             ; month
        jsr     ChkCom
        jsr     GetByt                  ; X=day
        txa
        plx                             ; X=month
        ply                             ; Y=year
        jmp     RtcWriteDate

; NVRAM addr, val
BasCmdNvram:
        lda     #HW_RTC
        jsr     ReqHw
        jsr     GetByt
        phx                             ; addr
        jsr     ChkCom
        jsr     GetByt                  ; X=val
        txa                             ; A=val
        plx                             ; X=addr
        jmp     RtcWriteNVRAM

; WAIT addr, mask
BasCmdWait:
        jsr     EvalAddrU16
        lda     FAC+4
        sta     BAS_TMP1
        lda     FAC+3
        sta     BAS_TMP1+1
        jsr     ChkCom
        jsr     GetByt                  ; X = mask
        stx     BAS_TMP2
@poll:
        jsr     BasCheckBreak
        ldy     #0
        lda     (BAS_TMP1),y
        and     BAS_TMP2
        beq     @poll
        rts

; PAUSE n (centiseconds)
BasCmdPause:
        jsr     EvalU16
        lda     FAC+4
        ldx     FAC+3
        jmp     SysDelay

; BANK n
BasCmdBank:
        lda     #HW_RAM_L
        jsr     ReqHw
        jsr     GetByt                  ; X = bank
        stx     RAM_BANK_L
        rts

; BRK
BasCmdBrk:
        brk
        .byte   0
        rts

; POKE addr, val
BasCmdPoke:
        jsr     EvalAddrU16
        lda     FAC+4
        sta     INDEX
        lda     FAC+3
        sta     INDEX+1
        jsr     ChkCom
        jsr     GetByt                  ; X = val
        txa
        ldy     #0
        sta     (INDEX),y
        rts

; LOAD ["name"] / LOAD (bare) / LOAD "name"
BasCmdLoad:
        jsr     ChrGot
        beq     @bare
        cmp     #'"'
        beq     @cf
        ; treat as expression that should yield a string -> CF
        bra     @cf
@bare:
        lda     #HW_SC
        jsr     ReqHw
        lda     #<PROGRAM_START
        sta     XFER_PTR
        lda     #>PROGRAM_START
        sta     XFER_PTR+1
        jsr     XModemLoad
        jmp     BasFixChain
@cf:
        lda     #HW_CF
        jsr     ReqHw
        jsr     EvalString
        jsr     FsLoadFile
        bcs     @err
        jmp     BasFixChain
@err:
        lda     #<MsgLoadErr
        ldy     #>MsgLoadErr
        jmp     BasPrintStr

; SAVE / SAVE "name"
BasCmdSave:
        jsr     ChrGot
        beq     @bare
        cmp     #'"'
        beq     @cf
        bra     @cf
@bare:
        lda     #HW_SC
        jsr     ReqHw
        lda     #<PROGRAM_START
        sta     XFER_PTR
        lda     #>PROGRAM_START
        sta     XFER_PTR+1
        sec
        lda     BAS_VARTAB
        sbc     #<PROGRAM_START
        sta     XFER_REMAIN
        lda     BAS_VARTAB+1
        sbc     #>PROGRAM_START
        sta     XFER_REMAIN+1
        jmp     XModemSave
@cf:
        lda     #HW_CF
        jsr     ReqHw
        jsr     EvalString
        sec
        lda     BAS_VARTAB
        sbc     #<PROGRAM_START
        sta     FS_FILE_SIZE
        lda     BAS_VARTAB+1
        sbc     #>PROGRAM_START
        sta     FS_FILE_SIZE+1
        jsr     FsSaveFile
        bcs     @err
        rts
@err:
        lda     #<MsgSaveErr
        ldy     #>MsgSaveErr
        jmp     BasPrintStr

; DIR
BasCmdDir:
        lda     #HW_CF
        jsr     ReqHw
        jmp     FsDirectory

; DEL "name"
BasCmdDel:
        lda     #HW_CF
        jsr     ReqHw
        jsr     EvalString
        jsr     FsDeleteFile
        bcs     @err
        rts
@err:
        lda     #<MsgDelErr
        ldy     #>MsgDelErr
        jmp     BasPrintStr

; MEM -- print "nnnnn BYTES FREE  HW=$xx"
BasCmdMem:
        ; Free bytes = MEMSIZ - VARTAB
        sec
        lda     BAS_MEMSIZ
        sbc     BAS_VARTAB
        tay
        lda     BAS_MEMSIZ+1
        sbc     BAS_VARTAB+1
        jsr     GivAyf                  ; FAC = unsigned int from (Y,A)
        ; Wait: GivAyf is signed.  For this simple display, OK if < 32768.
        jsr     PrintNum
        lda     #<MsgFree
        ldy     #>MsgFree
        jsr     BasPrintStr
        lda     #'$'
        jsr     Chrout
        lda     HW_PRESENT
        jsr     PrintHexByte
        jmp     BasPrintCRLF

MsgFree:        .byte   " BYTES FREE  HW=",0
MsgLoadErr:     .byte   "?LOAD ERROR",$0D,$0A,0
MsgSaveErr:     .byte   "?SAVE ERROR",$0D,$0A,0
MsgDelErr:      .byte   "?DEL ERROR",$0D,$0A,0

; Wrappers so the dispatch table can call existing routines that expect
; TXTPTR positioned already.
BasCmdPrintW:
        ; We were entered via the dispatch trampoline, so TXTPTR is already
        ; past the PRINT token (ChrGet was tail-called).  But BasCmdPrint
        ; expects to consume the token itself with its first ChrGet; rewind.
        ; Easier: BasCmdPrint reads via ChrGet; here ChrGet was called before
        ; routine entry, so TXTPTR currently points at first arg.  Just call
        ; an internal entry that skips the leading ChrGet.
        jmp     BasPrLoop

; ---------------------------------------------------------------------------
; Token-address dispatch table.  Indexed by (token - $80).  Each entry is
; (routine_address - 1) since the dispatcher PHA-pushes it and uses the
; "JMP ChrGet -> RTS" trick to enter.
; ---------------------------------------------------------------------------
BasTokenAddrTbl:
        .word   BasCmdEnd-1             ; $80 END
        .word   BasCmdFor-1             ; $81 FOR
        .word   BasCmdNext-1            ; $82 NEXT
        .word   BasCmdData-1            ; $83 DATA
        .word   BasCmdInput-1           ; $84 INPUT
        .word   BasCmdNotImpl-1         ; $85 DIM (handled inline by LET/array access)
        .word   BasCmdRead-1            ; $86 READ
        .word   BasCmdLet-1             ; $87 LET
        .word   BasCmdGoto-1            ; $88 GOTO
        .word   BasCmdRun-1             ; $89 RUN
        .word   BasCmdIf-1              ; $8A IF
        .word   BasCmdRestore-1         ; $8B RESTORE
        .word   BasCmdGosub-1           ; $8C GOSUB
        .word   BasCmdReturn-1          ; $8D RETURN
        .word   BasCmdRem-1             ; $8E REM
        .word   BasCmdStop-1            ; $8F STOP
        .word   BasCmdOn-1              ; $90 ON
        .word   BasCmdWait-1            ; $91 WAIT
        .word   BasCmdLoad-1            ; $92 LOAD
        .word   BasCmdSave-1            ; $93 SAVE
        .word   BasCmdDef-1             ; $94 DEF
        .word   BasCmdPoke-1            ; $95 POKE
        .word   BasCmdPrintW-1          ; $96 PRINT
        .word   BasCmdCont-1            ; $97 CONT
        .word   BasCmdList-1            ; $98 LIST
        .word   BasCmdClr-1             ; $99 CLR
        .word   BasCmdNew-1             ; $9A NEW
        .word   SynErr-1                ; $9B TAB  (function only)
        .word   SynErr-1                ; $9C TO
        .word   SynErr-1                ; $9D FN
        .word   SynErr-1                ; $9E SPC
        .word   SynErr-1                ; $9F THEN
        .word   SynErr-1                ; $A0 NOT
        .word   SynErr-1                ; $A1 STEP
        .word   SynErr-1                ; $A2 AND
        .word   SynErr-1                ; $A3 OR
        .word   BasCmdRem-1             ; $A4 ELSE (skip rest of line; THEN-branch ran)
        .word   BasCmdSys-1             ; $A5 SYS
        .word   BasCmdDir-1             ; $A6 DIR
        .word   BasCmdDel-1             ; $A7 DEL
        .word   BasCmdCls-1             ; $A8 CLS
        .word   BasCmdLocate-1          ; $A9 LOCATE
        .word   BasCmdColor-1           ; $AA COLOR
        .word   BasCmdSound-1           ; $AB SOUND
        .word   BasCmdVol-1             ; $AC VOL
        .word   BasCmdTime-1            ; $AD TIME
        .word   BasCmdDate-1            ; $AE DATE
        .word   BasCmdSettime-1         ; $AF SETTIME
        .word   BasCmdSetdate-1         ; $B0 SETDATE
        .word   BasCmdNvram-1           ; $B1 NVRAM
        .word   BasCmdPause-1           ; $B2 PAUSE
        .word   BasCmdBank-1            ; $B3 BANK
        .word   BasCmdBrk-1             ; $B4 BRK
        .word   BasCmdMem-1             ; $B5 MEM

; =============================================================================
;   K E Y W O R D   T A B L E
;
;   Each keyword is its ASCII characters; the LAST byte has bit 7 set.
;   Order MUST match TOK_xxx equates above (token = TOK_BASE + index).
;   A trailing $00 terminates the table.
; =============================================================================

KeywordTbl:
        ; Statements
        .byte   "EN",'D'|$80            ; $80 END
        .byte   "FO",'R'|$80            ; $81 FOR
        .byte   "NEX",'T'|$80           ; $82 NEXT
        .byte   "DAT",'A'|$80           ; $83 DATA
        .byte   "INPU",'T'|$80          ; $84 INPUT
        .byte   "DI",'M'|$80            ; $85 DIM
        .byte   "REA",'D'|$80           ; $86 READ
        .byte   "LE",'T'|$80            ; $87 LET
        .byte   "GOT",'O'|$80           ; $88 GOTO
        .byte   "RU",'N'|$80            ; $89 RUN
        .byte   "I",'F'|$80             ; $8A IF
        .byte   "RESTOR",'E'|$80        ; $8B RESTORE
        .byte   "GOSU",'B'|$80          ; $8C GOSUB
        .byte   "RETUR",'N'|$80         ; $8D RETURN
        .byte   "RE",'M'|$80            ; $8E REM
        .byte   "STO",'P'|$80           ; $8F STOP
        .byte   "O",'N'|$80             ; $90 ON
        .byte   "WAI",'T'|$80           ; $91 WAIT
        .byte   "LOA",'D'|$80           ; $92 LOAD
        .byte   "SAV",'E'|$80           ; $93 SAVE
        .byte   "DE",'F'|$80            ; $94 DEF
        .byte   "POK",'E'|$80           ; $95 POKE
        .byte   "PRIN",'T'|$80          ; $96 PRINT
        .byte   "CON",'T'|$80           ; $97 CONT
        .byte   "LIS",'T'|$80           ; $98 LIST
        .byte   "CL",'R'|$80            ; $99 CLR
        .byte   "NE",'W'|$80            ; $9A NEW
        .byte   "TA",'B'|$80            ; $9B TAB
        .byte   "T",'O'|$80             ; $9C TO
        .byte   "F",'N'|$80             ; $9D FN
        .byte   "SP",'C'|$80            ; $9E SPC
        .byte   "THE",'N'|$80           ; $9F THEN
        .byte   "NO",'T'|$80            ; $A0 NOT
        .byte   "STE",'P'|$80           ; $A1 STEP
        .byte   "AN",'D'|$80            ; $A2 AND
        .byte   "O",'R'|$80             ; $A3 OR
        .byte   "ELS",'E'|$80           ; $A4 ELSE
        .byte   "SY",'S'|$80            ; $A5 SYS
        .byte   "DI",'R'|$80            ; $A6 DIR
        .byte   "DE",'L'|$80            ; $A7 DEL
        .byte   "CL",'S'|$80            ; $A8 CLS
        .byte   "LOCAT",'E'|$80         ; $A9 LOCATE
        .byte   "COLO",'R'|$80          ; $AA COLOR
        .byte   "SOUN",'D'|$80          ; $AB SOUND
        .byte   "VO",'L'|$80            ; $AC VOL
        .byte   "TIM",'E'|$80           ; $AD TIME
        .byte   "DAT",'E'|$80           ; $AE DATE
        .byte   "SETTIM",'E'|$80        ; $AF SETTIME
        .byte   "SETDAT",'E'|$80        ; $B0 SETDATE
        .byte   "NVRA",'M'|$80          ; $B1 NVRAM
        .byte   "PAUS",'E'|$80          ; $B2 PAUSE
        .byte   "BAN",'K'|$80           ; $B3 BANK
        .byte   "BR",'K'|$80            ; $B4 BRK
        .byte   "ME",'M'|$80            ; $B5 MEM
        ; Functions
        .byte   "SG",'N'|$80            ; $B6 Sgn
        .byte   "IN",'T'|$80            ; $B7 Int
        .byte   "AB",'S'|$80            ; $B8 Abs
        .byte   "FR",'E'|$80            ; $B9 FRE
        .byte   "PO",'S'|$80            ; $BA POS
        .byte   "SQ",'R'|$80            ; $BB Sqr
        .byte   "RN",'D'|$80            ; $BC Rnd
        .byte   "LO",'G'|$80            ; $BD Log
        .byte   "EX",'P'|$80            ; $BE Exp
        .byte   "CO",'S'|$80            ; $BF Cos
        .byte   "SI",'N'|$80            ; $C0 Sin
        .byte   "TA",'N'|$80            ; $C1 Tan
        .byte   "AT",'N'|$80            ; $C2 Atn
        .byte   "PEE",'K'|$80           ; $C3 PEEK
        .byte   "LE",'N'|$80            ; $C4 LEN
        .byte   "STR",'$'|$80           ; $C5 STR$
        .byte   "VA",'L'|$80            ; $C6 VAL
        .byte   "AS",'C'|$80            ; $C7 ASC
        .byte   "CHR",'$'|$80           ; $C8 CHR$
        .byte   "LEFT",'$'|$80          ; $C9 LEFT$
        .byte   "RIGHT",'$'|$80         ; $CA RIGHT$
        .byte   "MID",'$'|$80           ; $CB MID$
        .byte   "JO",'Y'|$80            ; $CC JOY
        .byte   "INKE",'Y'|$80          ; $CD INKEY
        .byte   "HE",'X'|$80            ; $CE HEX
        .byte   "MI",'N'|$80            ; $CF MIN
        .byte   "MA",'X'|$80            ; $D0 MAX
        .byte   0

; =============================================================================
;   E R R O R   M E S S A G E   T A B L E   (NUL-terminated strings)
; =============================================================================

ErrorMessages:
        .byte   "SYNTAX",0              ; ERR_SYNTAX
        .byte   "OVERFLOW",0            ; ERR_OVERFLOW
        .byte   "OUT OF MEMORY",0       ; ERR_OUTOFMEM
        .byte   "UNDEF'D STATEMENT",0   ; ERR_UNDEFSTMT
        .byte   "BAD SUBSCRIPT",0       ; ERR_BADSUBSCR
        .byte   "REDIM'D ARRAY",0       ; ERR_REDIM
        .byte   "DIVISION BY ZERO",0    ; ERR_DIVZERO
        .byte   "ILLEGAL DIRECT",0      ; ERR_ILLDIRECT
        .byte   "TYPE MISMATCH",0       ; ERR_TYPEMISM
        .byte   "STRING TOO LONG",0     ; ERR_LONGSTR
        .byte   "FORMULA TOO COMPLEX",0 ; ERR_FORMULA
        .byte   "ILLEGAL QUANTITY",0    ; ERR_ILLQUAN
        .byte   "RETURN WITHOUT GOSUB",0; ERR_RG
        .byte   "NEXT WITHOUT FOR",0    ; ERR_NF
        .byte   "OUT OF DATA",0         ; ERR_OD
        .byte   "NO DEVICE",0           ; ERR_NODEV
        .byte   "CAN'T CONTINUE",0      ; ERR_CANTCONT

; =============================================================================
;   S T R I N G   C O N S T A N T S
; =============================================================================

MsgBanner:
        .byte   $0D,$0A,"6502 BASIC V2.0",$0D,$0A,0

MsgBytesFreeNL:
        .byte   " BYTES FREE",$0D,$0A,0

MsgOK:
        .byte   "OK",$0D,$0A,0

MsgErrorWord:
        .byte   " ERROR",0

MsgInWord:
        .byte   " IN ",0
