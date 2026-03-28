; IBM Code Page 437 Character Set
; 5x8 pixel font in 8x8 area, 8 bytes per character (256 characters total)
; Each byte represents one horizontal row of pixels (5 pixels left-aligned in 8-bit space)

CharacterSet:
    ; Character $00 - NULL (blank)
    .byte $00, $00, $00, $00, $00, $00, $00, $00
    ; Character $01 - ☺ (white smiling face)
    .byte $70, $88, $D8, $88, $A8, $88, $70, $00
    ; Character $02 - ☻ (black smiling face)
    .byte $70, $F8, $A8, $F8, $88, $F8, $70, $00
    ; Character $03 - ♥ (heart)
    .byte $00, $50, $F8, $F8, $F8, $70, $20, $00
    ; Character $04 - ♦ (diamond)
    .byte $00, $20, $70, $F8, $F8, $70, $20, $00
    ; Character $05 - ♣ (club)
    .byte $20, $70, $70, $20, $F8, $F8, $20, $00
    ; Character $06 - ♠ (spade)
    .byte $00, $20, $70, $F8, $F8, $20, $70, $00
    ; Character $07 - • (bullet)
    .byte $00, $00, $00, $30, $30, $00, $00, $00
    ; Character $08 - ◘ (inverse bullet)
    .byte $FC, $FC, $FC, $CC, $CC, $FC, $FC, $FC
    ; Character $09 - ○ (white circle)
    .byte $00, $00, $78, $48, $48, $78, $00, $00
    ; Character $0A - ◙ (inverse white circle)
    .byte $FC, $FC, $84, $B4, $B4, $84, $FC, $FC
    ; Character $0B - ♂ (male symbol)
    .byte $00, $38, $18, $68, $90, $90, $60, $00
    ; Character $0C - ♀ (female symbol)
    .byte $70, $88, $88, $70, $20, $70, $20, $00
    ; Character $0D - ♪ (eighth note)
    .byte $20, $30, $28, $20, $60, $E0, $C0, $00
    ; Character $0E - ♫ (beamed eighth notes)
    .byte $18, $68, $58, $68, $58, $D8, $C0, $00
    ; Character $0F - ☼ (sun)
    .byte $00, $A8, $70, $D8, $70, $A8, $00, $00
    ; Character $10 - ► (right-pointing triangle)
    .byte $40, $60, $70, $78, $70, $60, $40, $00
    ; Character $11 - ◄ (left-pointing triangle)
    .byte $10, $30, $70, $F0, $70, $30, $10, $00
    ; Character $12 - ↕ (up/down arrow)
    .byte $20, $70, $F8, $20, $F8, $70, $20, $00
    ; Character $13 - ‼ (double exclamation mark)
    .byte $50, $50, $50, $50, $50, $00, $50, $00
    ; Character $14 - ¶ (pilcrow)
    .byte $78, $A8, $A8, $68, $28, $28, $28, $00
    ; Character $15 - § (section sign)
    .byte $70, $88, $60, $50, $30, $88, $70, $00
    ; Character $16 - ▬ (black rectangle)
    .byte $00, $00, $00, $00, $00, $F0, $F0, $00
    ; Character $17 - ↨ (up/down arrow with base)
    .byte $20, $70, $F8, $20, $F8, $70, $20, $70
    ; Character $18 - ↑ (up arrow)
    .byte $20, $70, $F8, $20, $20, $20, $20, $00
    ; Character $19 - ↓ (down arrow)
    .byte $20, $20, $20, $20, $F8, $70, $20, $00
    ; Character $1A - → (right arrow)
    .byte $00, $20, $30, $F8, $30, $20, $00, $00
    ; Character $1B - ← (left arrow)
    .byte $00, $20, $60, $F8, $60, $20, $00, $00
    ; Character $1C - ∟ (right angle)
    .byte $00, $00, $00, $80, $80, $80, $F8, $00
    ; Character $1D - ↔ (left/right arrow)
    .byte $00, $50, $50, $F8, $50, $50, $00, $00
    ; Character $1E - ▲ (up-pointing triangle)
    .byte $20, $20, $70, $70, $F8, $F8, $00, $00
    ; Character $1F - ▼ (down-pointing triangle)
    .byte $F8, $F8, $70, $70, $20, $20, $00, $00
    ; Character $20 - SPACE
    .byte $00, $00, $00, $00, $00, $00, $00, $00
    ; Character $21 - !
    .byte $20, $70, $70, $20, $20, $00, $20, $00
    ; Character $22 - "
    .byte $D8, $D8, $90, $00, $00, $00, $00, $00
    ; Character $23 - #
    .byte $00, $50, $F8, $50, $50, $F8, $50, $00
    ; Character $24 - $
    .byte $40, $70, $80, $60, $10, $E0, $20, $00
    ; Character $25 - %
    .byte $C8, $C8, $10, $20, $40, $98, $98, $00
    ; Character $26 - &
    .byte $40, $A0, $A0, $40, $A8, $90, $68, $00
    ; Character $27 - '
    .byte $C0, $C0, $80, $00, $00, $00, $00, $00
    ; Character $28 - (
    .byte $40, $80, $80, $80, $80, $80, $40, $00
    ; Character $29 - )
    .byte $80, $40, $40, $40, $40, $40, $80, $00
    ; Character $2A - *
    .byte $00, $50, $70, $F8, $70, $50, $00, $00
    ; Character $2B - +
    .byte $00, $20, $20, $F8, $20, $20, $00, $00
    ; Character $2C - ,
    .byte $00, $00, $00, $00, $00, $C0, $C0, $80
    ; Character $2D - -
    .byte $00, $00, $00, $F8, $00, $00, $00, $00
    ; Character $2E - .
    .byte $00, $00, $00, $00, $00, $C0, $C0, $00
    ; Character $2F - /
    .byte $00, $08, $10, $20, $40, $80, $00, $00
    ; Character $30 - 0
    .byte $70, $88, $98, $A8, $C8, $88, $70, $00
    ; Character $31 - 1
    .byte $20, $60, $20, $20, $20, $20, $70, $00
    ; Character $32 - 2
    .byte $70, $88, $08, $30, $40, $80, $F8, $00
    ; Character $33 - 3
    .byte $70, $88, $08, $70, $08, $88, $70, $00
    ; Character $34 - 4
    .byte $10, $30, $50, $90, $F8, $10, $10, $00
    ; Character $35 - 5
    .byte $F8, $80, $80, $F0, $08, $88, $70, $00
    ; Character $36 - 6
    .byte $30, $40, $80, $F0, $88, $88, $70, $00
    ; Character $37 - 7
    .byte $F8, $08, $10, $20, $40, $40, $40, $00
    ; Character $38 - 8
    .byte $70, $88, $88, $70, $88, $88, $70, $00
    ; Character $39 - 9
    .byte $70, $88, $88, $78, $08, $10, $60, $00
    ; Character $3A - :
    .byte $00, $00, $60, $60, $00, $60, $60, $00
    ; Character $3B - ;
    .byte $00, $00, $60, $60, $00, $60, $60, $40
    ; Character $3C - <
    .byte $10, $20, $40, $80, $40, $20, $10, $00
    ; Character $3D - =
    .byte $00, $00, $F8, $00, $00, $F8, $00, $00
    ; Character $3E - >
    .byte $80, $40, $20, $10, $20, $40, $80, $00
    ; Character $3F - ?
    .byte $70, $88, $08, $30, $20, $00, $20, $00
    ; Character $40 - @
    .byte $70, $88, $B8, $A8, $B8, $80, $70, $00
    ; Character $41 - A
    .byte $70, $88, $88, $88, $F8, $88, $88, $00
    ; Character $42 - B
    .byte $F0, $88, $88, $F0, $88, $88, $F0, $00
    ; Character $43 - C
    .byte $70, $88, $80, $80, $80, $88, $70, $00
    ; Character $44 - D
    .byte $F0, $88, $88, $88, $88, $88, $F0, $00
    ; Character $45 - E
    .byte $F8, $80, $80, $F0, $80, $80, $F8, $00
    ; Character $46 - F
    .byte $F8, $80, $80, $F0, $80, $80, $80, $00
    ; Character $47 - G
    .byte $70, $88, $80, $B8, $88, $88, $78, $00
    ; Character $48 - H
    .byte $88, $88, $88, $F8, $88, $88, $88, $00
    ; Character $49 - I
    .byte $70, $20, $20, $20, $20, $20, $70, $00
    ; Character $4A - J
    .byte $08, $08, $08, $08, $88, $88, $70, $00
    ; Character $4B - K
    .byte $88, $90, $A0, $C0, $A0, $90, $88, $00
    ; Character $4C - L
    .byte $80, $80, $80, $80, $80, $80, $F8, $00
    ; Character $4D - M
    .byte $88, $D8, $A8, $88, $88, $88, $88, $00
    ; Character $4E - N
    .byte $88, $C8, $A8, $98, $88, $88, $88, $00
    ; Character $4F - O
    .byte $70, $88, $88, $88, $88, $88, $70, $00
    ; Character $50 - P
    .byte $F0, $88, $88, $F0, $80, $80, $80, $00
    ; Character $51 - Q
    .byte $70, $88, $88, $88, $A8, $90, $68, $00
    ; Character $52 - R
    .byte $F0, $88, $88, $F0, $90, $88, $88, $00
    ; Character $53 - S
    .byte $70, $88, $80, $70, $08, $88, $70, $00
    ; Character $54 - T
    .byte $F8, $20, $20, $20, $20, $20, $20, $00
    ; Character $55 - U
    .byte $88, $88, $88, $88, $88, $88, $70, $00
    ; Character $56 - V
    .byte $88, $88, $88, $88, $88, $50, $20, $00
    ; Character $57 - W
    .byte $88, $88, $A8, $A8, $A8, $A8, $50, $00
    ; Character $58 - X
    .byte $88, $88, $50, $20, $50, $88, $88, $00
    ; Character $59 - Y
    .byte $88, $88, $88, $50, $20, $20, $20, $00
    ; Character $5A - Z
    .byte $F0, $10, $20, $40, $80, $80, $F0, $00
    ; Character $5B - [
    .byte $70, $40, $40, $40, $40, $40, $70, $00
    ; Character $5C - \
    .byte $00, $80, $40, $20, $10, $08, $00, $00
    ; Character $5D - ]
    .byte $70, $10, $10, $10, $10, $10, $70, $00
    ; Character $5E - ^
    .byte $20, $50, $88, $00, $00, $00, $00, $00
    ; Character $5F - _
    .byte $00, $00, $00, $00, $00, $00, $00, $F8
    ; Character $60 - `
    .byte $60, $60, $20, $00, $00, $00, $00, $00
    ; Character $61 - a
    .byte $00, $00, $70, $08, $78, $88, $78, $00
    ; Character $62 - b
    .byte $80, $80, $F0, $88, $88, $88, $F0, $00
    ; Character $63 - c
    .byte $00, $00, $70, $88, $80, $88, $70, $00
    ; Character $64 - d
    .byte $08, $08, $78, $88, $88, $88, $78, $00
    ; Character $65 - e
    .byte $00, $00, $70, $88, $F0, $80, $70, $00
    ; Character $66 - f
    .byte $30, $40, $40, $F0, $40, $40, $40, $00
    ; Character $67 - g
    .byte $00, $00, $78, $88, $88, $78, $08, $70
    ; Character $68 - h
    .byte $80, $80, $E0, $90, $90, $90, $90, $00
    ; Character $69 - i
    .byte $20, $00, $20, $20, $20, $20, $30, $00
    ; Character $6A - j
    .byte $10, $00, $30, $10, $10, $10, $90, $60
    ; Character $6B - k
    .byte $80, $80, $90, $A0, $C0, $A0, $90, $00
    ; Character $6C - l
    .byte $20, $20, $20, $20, $20, $20, $30, $00
    ; Character $6D - m
    .byte $00, $00, $D0, $A8, $A8, $88, $88, $00
    ; Character $6E - n
    .byte $00, $00, $E0, $90, $90, $90, $90, $00
    ; Character $6F - o
    .byte $00, $00, $70, $88, $88, $88, $70, $00
    ; Character $70 - p
    .byte $00, $00, $F0, $88, $88, $88, $F0, $80
    ; Character $71 - q
    .byte $00, $00, $70, $88, $88, $88, $78, $08
    ; Character $72 - r
    .byte $00, $00, $B0, $48, $40, $40, $E0, $00
    ; Character $73 - s
    .byte $00, $00, $70, $80, $70, $08, $70, $00
    ; Character $74 - t
    .byte $00, $40, $F0, $40, $40, $50, $20, $00
    ; Character $75 - u
    .byte $00, $00, $90, $90, $90, $B0, $50, $00
    ; Character $76 - v
    .byte $00, $00, $88, $88, $88, $50, $20, $00
    ; Character $77 - w
    .byte $00, $00, $88, $88, $A8, $F8, $50, $00
    ; Character $78 - x
    .byte $00, $00, $90, $90, $60, $90, $90, $00
    ; Character $79 - y
    .byte $00, $00, $90, $90, $90, $70, $20, $C0
    ; Character $7A - z
    .byte $00, $00, $F0, $10, $60, $80, $F0, $00
    ; Character $7B - {
    .byte $30, $40, $40, $C0, $40, $40, $30, $00
    ; Character $7C - |
    .byte $20, $20, $20, $00, $20, $20, $20, $00
    ; Character $7D - }
    .byte $C0, $20, $20, $30, $20, $20, $C0, $00
    ; Character $7E - ~
    .byte $50, $A0, $00, $00, $00, $00, $00, $00
    ; Character $7F - ⌂ (house)
    .byte $20, $70, $D8, $88, $88, $F8, $00, $00
    ; Character $80 - Ç
    .byte $70, $88, $80, $80, $88, $70, $20, $60
    ; Character $81 - ü
    .byte $90, $00, $90, $90, $90, $B0, $50, $00
    ; Character $82 - é
    .byte $18, $00, $70, $88, $F0, $80, $70, $00
    ; Character $83 - â
    .byte $70, $00, $70, $08, $78, $88, $78, $00
    ; Character $84 - ä
    .byte $50, $00, $70, $08, $78, $88, $78, $00
    ; Character $85 - à
    .byte $60, $00, $70, $08, $78, $88, $78, $00
    ; Character $86 - å
    .byte $70, $50, $70, $08, $78, $88, $78, $00
    ; Character $87 - ç
    .byte $00, $70, $88, $80, $88, $70, $20, $60
    ; Character $88 - ê
    .byte $70, $00, $70, $88, $F0, $80, $70, $00
    ; Character $89 - ë
    .byte $50, $00, $70, $88, $F0, $80, $70, $00
    ; Character $8A - è
    .byte $60, $00, $70, $88, $F0, $80, $70, $00
    ; Character $8B - ï
    .byte $50, $00, $20, $20, $20, $20, $30, $00
    ; Character $8C - î
    .byte $20, $50, $00, $20, $20, $20, $30, $00
    ; Character $8D - ì
    .byte $40, $00, $20, $20, $20, $20, $30, $00
    ; Character $8E - Ä
    .byte $50, $00, $20, $50, $88, $F8, $88, $00
    ; Character $8F - Å
    .byte $70, $50, $70, $D8, $88, $F8, $88, $00
    ; Character $90 - É
    .byte $18, $00, $F8, $80, $F0, $80, $F8, $00
    ; Character $91 - æ
    .byte $00, $00, $F0, $28, $F8, $A0, $78, $00
    ; Character $92 - Æ
    .byte $78, $A0, $A0, $F8, $A0, $A0, $B8, $00
    ; Character $93 - ô
    .byte $70, $00, $60, $90, $90, $90, $60, $00
    ; Character $94 - ö
    .byte $50, $00, $60, $90, $90, $90, $60, $00
    ; Character $95 - ò
    .byte $C0, $00, $60, $90, $90, $90, $60, $00
    ; Character $96 - û
    .byte $70, $00, $90, $90, $90, $B0, $50, $00
    ; Character $97 - ù
    .byte $C0, $00, $90, $90, $90, $B0, $50, $00
    ; Character $98 - ÿ
    .byte $50, $00, $90, $90, $90, $70, $20, $C0
    ; Character $99 - Ö
    .byte $90, $60, $90, $90, $90, $90, $60, $00
    ; Character $9A - Ü
    .byte $50, $00, $90, $90, $90, $90, $60, $00
    ; Character $9B - ¢
    .byte $00, $20, $70, $80, $80, $70, $20, $00
    ; Character $9C - £
    .byte $30, $48, $40, $F0, $40, $48, $B8, $00
    ; Character $9D - ¥
    .byte $88, $50, $20, $F8, $20, $F8, $20, $00
    ; Character $9E - ₧
    .byte $C0, $A0, $A0, $D0, $B8, $90, $90, $00
    ; Character $9F - ƒ
    .byte $10, $28, $20, $70, $20, $20, $A0, $40
    ; Character $A0 - á
    .byte $30, $00, $70, $08, $78, $88, $78, $00
    ; Character $A1 - í
    .byte $60, $00, $40, $40, $40, $40, $60, $00
    ; Character $A2 - ó
    .byte $30, $00, $60, $90, $90, $90, $60, $00
    ; Character $A3 - ú
    .byte $30, $00, $90, $90, $90, $B0, $50, $00
    ; Character $A4 - ñ
    .byte $50, $A0, $00, $E0, $90, $90, $90, $00
    ; Character $A5 - Ñ
    .byte $50, $A0, $00, $90, $D0, $B0, $90, $00
    ; Character $A6 - ª
    .byte $70, $08, $78, $88, $78, $00, $78, $00
    ; Character $A7 - º
    .byte $60, $90, $90, $90, $60, $00, $F0, $00
    ; Character $A8 - ¿
    .byte $20, $00, $20, $60, $80, $88, $70, $00
    ; Character $A9 - ⌐
    .byte $00, $00, $FC, $80, $80, $80, $00, $00
    ; Character $AA - ¬
    .byte $00, $00, $FC, $04, $04, $04, $00, $00
    ; Character $AB - ½
    .byte $80, $90, $A0, $70, $88, $10, $38, $00
    ; Character $AC - ¼
    .byte $80, $90, $A0, $58, $A8, $38, $08, $00
    ; Character $AD - ¡
    .byte $20, $00, $20, $20, $70, $70, $20, $00
    ; Character $AE - «
    .byte $00, $00, $48, $90, $48, $00, $00, $00
    ; Character $AF - »
    .byte $00, $00, $90, $48, $90, $00, $00, $00
    ; Character $B0 - ░ (light shade)
    .byte $54, $00, $A8, $00, $54, $00, $A8, $00
    ; Character $B1 - ▒ (medium shade)
    .byte $54, $A8, $54, $A8, $54, $A8, $54, $A8
    ; Character $B2 - ▓ (dark shade)
    .byte $A8, $FC, $54, $FC, $A8, $FC, $54, $FC
    ; Character $B3 - │ (box drawing vertical)
    .byte $10, $10, $10, $10, $10, $10, $10, $10
    ; Character $B4 - ┤ (box drawing vertical and left)
    .byte $10, $10, $10, $F0, $10, $10, $10, $10
    ; Character $B5 - ╡ (box drawing vertical double and left single)
    .byte $10, $F0, $10, $F0, $10, $10, $10, $10
    ; Character $B6 - ╢ (box drawing down double and left single)
    .byte $50, $50, $50, $D0, $50, $50, $50, $50
    ; Character $B7 - ╖ (box drawing down single and left double)
    .byte $00, $00, $00, $F0, $50, $50, $50, $50
    ; Character $B8 - ╕ (box drawing double vertical and left)
    .byte $00, $F0, $10, $F0, $10, $10, $10, $10
    ; Character $B9 - ╣ (box drawing double vertical and left)
    .byte $50, $D0, $10, $D0, $50, $50, $50, $50
    ; Character $BA - ║ (box drawing double vertical)
    .byte $50, $50, $50, $50, $50, $50, $50, $50
    ; Character $BB - ╗ (box drawing double down and left)
    .byte $00, $F0, $10, $D0, $50, $50, $50, $50
    ; Character $BC - ╝ (box drawing double up and left)
    .byte $50, $D0, $10, $F0, $00, $00, $00, $00
    ; Character $BD - ╜ (box drawing up double and left single)
    .byte $50, $50, $50, $F0, $00, $00, $00, $00
    ; Character $BE - ╛ (box drawing up single and left double)
    .byte $10, $F0, $10, $F0, $00, $00, $00, $00
    ; Character $BF - ┐ (box drawing down and left)
    .byte $00, $00, $00, $F0, $10, $10, $10, $10
    ; Character $C0 - └ (box drawing up and right)
    .byte $10, $10, $10, $1C, $00, $00, $00, $00
    ; Character $C1 - ┴ (box drawing vertical and horizontal)
    .byte $10, $10, $10, $FC, $00, $00, $00, $00
    ; Character $C2 - ┬ (box drawing down and horizontal)
    .byte $00, $00, $00, $FC, $10, $10, $10, $10
    ; Character $C3 - ├ (box drawing vertical and right)
    .byte $10, $10, $10, $1C, $10, $10, $10, $10
    ; Character $C4 - ─ (box drawing horizontal)
    .byte $00, $00, $00, $FC, $00, $00, $00, $00
    ; Character $C5 - ┼ (box drawing vertical and horizontal)
    .byte $10, $10, $10, $FC, $10, $10, $10, $10
    ; Character $C6 - ╞ (box drawing vertical single and right double)
    .byte $10, $1C, $10, $1C, $10, $10, $10, $10
    ; Character $C7 - ╟ (box drawing vertical double and right single)
    .byte $50, $50, $50, $5C, $50, $50, $50, $50
    ; Character $C8 - ╚ (box drawing double up and right)
    .byte $50, $5C, $40, $7C, $00, $00, $00, $00
    ; Character $C9 - ╔ (box drawing double down and right)
    .byte $00, $7C, $40, $5C, $50, $50, $50, $50
    ; Character $CA - ╩ (box drawing double up and horizontal)
    .byte $50, $DC, $00, $FC, $00, $00, $00, $00
    ; Character $CB - ╦ (box drawing double down and horizontal)
    .byte $00, $FC, $00, $DC, $50, $50, $50, $50
    ; Character $CC - ╠ (box drawing double vertical and right)
    .byte $50, $5C, $40, $5C, $50, $50, $50, $50
    ; Character $CD - ═ (box drawing double horizontal)
    .byte $00, $FC, $00, $FC, $00, $00, $00, $00
    ; Character $CE - ╬ (box drawing double vertical and horizontal)
    .byte $50, $DC, $00, $DC, $50, $50, $50, $50
    ; Character $CF - ╧ (box drawing up single and horizontal double)
    .byte $10, $FC, $00, $FC, $00, $00, $00, $00
    ; Character $D0 - ╨ (box drawing up double and horizontal single)
    .byte $50, $50, $50, $FC, $00, $00, $00, $00
    ; Character $D1 - ╤ (box drawing down single and horizontal double)
    .byte $00, $FC, $00, $FC, $10, $10, $10, $10
    ; Character $D2 - ╥ (box drawing down double and horizontal single)
    .byte $00, $00, $00, $FC, $50, $50, $50, $50
    ; Character $D3 - ╙ (box drawing up double and right single)
    .byte $50, $50, $50, $7C, $00, $00, $00, $00
    ; Character $D4 - ╘ (box drawing up single and right double)
    .byte $10, $1C, $10, $1C, $00, $00, $00, $00
    ; Character $D5 - ╒ (box drawing down single and right double)
    .byte $00, $1C, $10, $1C, $10, $10, $10, $10
    ; Character $D6 - ╓ (box drawing down double and right single)
    .byte $00, $00, $00, $7C, $50, $50, $50, $50
    ; Character $D7 - ╫ (box drawing vertical double and horizontal single)
    .byte $50, $50, $50, $DC, $50, $50, $50, $50
    ; Character $D8 - ╪ (box drawing vertical single and horizontal double)
    .byte $10, $FC, $00, $FC, $10, $10, $10, $10
    ; Character $D9 - ┘ (box drawing up and left)
    .byte $10, $10, $10, $F0, $00, $00, $00, $00
    ; Character $DA - ┌ (box drawing down and right)
    .byte $00, $00, $00, $1C, $10, $10, $10, $10
    ; Character $DB - █ (full block)
    .byte $FC, $FC, $FC, $FC, $FC, $FC, $FC, $FC
    ; Character $DC - ▄ (lower half block)
    .byte $00, $00, $00, $00, $FC, $FC, $FC, $FC
    ; Character $DD - ▌ (left half block)
    .byte $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0
    ; Character $DE - ▐ (right half block)
    .byte $1C, $1C, $1C, $1C, $1C, $1C, $1C, $1C
    ; Character $DF - ▀ (upper half block)
    .byte $FC, $FC, $FC, $FC, $00, $00, $00, $00
    ; Character $E0 - α
    .byte $00, $68, $90, $90, $68, $00, $00, $00
    ; Character $E1 - ß
    .byte $00, $E0, $90, $E0, $90, $90, $E0, $80
    ; Character $E2 - Γ
    .byte $F0, $90, $80, $80, $80, $80, $80, $00
    ; Character $E3 - π
    .byte $00, $F8, $50, $50, $50, $50, $50, $00
    ; Character $E4 - Σ
    .byte $F0, $90, $40, $20, $40, $90, $F0, $00
    ; Character $E5 - σ
    .byte $00, $00, $78, $90, $90, $60, $00, $00
    ; Character $E6 - µ
    .byte $00, $00, $90, $90, $90, $E0, $80, $80
    ; Character $E7 - τ
    .byte $00, $00, $50, $A0, $20, $20, $20, $00
    ; Character $E8 - Φ
    .byte $70, $20, $70, $88, $70, $20, $70, $00
    ; Character $E9 - Θ
    .byte $60, $90, $90, $F0, $90, $90, $60, $00
    ; Character $EA - Ω
    .byte $00, $70, $88, $88, $50, $50, $D8, $00
    ; Character $EB - δ
    .byte $60, $80, $40, $20, $70, $90, $60, $00
    ; Character $EC - ∞
    .byte $00, $00, $50, $A8, $A8, $50, $00, $00
    ; Character $ED - φ
    .byte $00, $20, $70, $A8, $A8, $70, $20, $00
    ; Character $EE - ε
    .byte $00, $70, $80, $F0, $80, $70, $00, $00
    ; Character $EF - ∩
    .byte $00, $60, $90, $90, $90, $90, $00, $00
    ; Character $F0 - ≡
    .byte $00, $F0, $00, $F0, $00, $F0, $00, $00
    ; Character $F1 - ±
    .byte $00, $20, $70, $20, $00, $70, $00, $00
    ; Character $F2 - ≥
    .byte $80, $60, $10, $60, $80, $00, $F0, $00
    ; Character $F3 - ≤
    .byte $10, $60, $80, $60, $10, $00, $F0, $00
    ; Character $F4 - ⌠ (top half integral)
    .byte $00, $10, $28, $20, $20, $20, $20, $20
    ; Character $F5 - ⌡ (bottom half integral)
    .byte $20, $20, $20, $20, $20, $A0, $40, $00
    ; Character $F6 - ÷
    .byte $00, $20, $00, $F8, $00, $20, $00, $00
    ; Character $F7 - ≈
    .byte $00, $50, $A0, $00, $50, $A0, $00, $00
    ; Character $F8 - °
    .byte $60, $90, $90, $60, $00, $00, $00, $00
    ; Character $F9 - ∙
    .byte $00, $00, $00, $60, $60, $00, $00, $00
    ; Character $FA - · (middle dot)
    .byte $00, $00, $00, $40, $00, $00, $00, $00
    ; Character $FB - √
    .byte $00, $38, $20, $20, $A0, $A0, $40, $00
    ; Character $FC - ⁿ
    .byte $A0, $50, $50, $50, $00, $00, $00, $00
    ; Character $FD - ²
    .byte $C0, $20, $40, $E0, $00, $00, $00, $00
    ; Character $FE - ■ (black square)
    .byte $00, $00, $78, $78, $78, $78, $00, $00
    ; Character $FF - nbsp (non-breaking space, displayed as blank)
    .byte $00, $00, $00, $00, $00, $00, $00, $00
