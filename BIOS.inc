; ***                     ***
; ***   6502 INCLUDES     ***
; ***                     ***

; Zero Page
ZP                  := $00
READ_PTR            := $00
WRITE_PTR           := $01
STR_PTR             := $02               ; $02-$03 - String pointer (2 bytes)
KEYPAD_IN           := $0F               ; Keypad input buffer (1 byte)

; Stack
STACK               := $0100             ; $0100-$01FF

; Input Buffer
INPUT_BUFFER        := $0200             ; $0200-$02FF

; Kernal Vars
KERNAL_VARS         := $0300             ; $0300-$03FF
IRQ_PTR             := $0300             ; $0300-$0301
BRK_PTR             := $0302             ; $0302-$0303
NMI_PTR             := $0304             ; $0304-$0305

; User Vars
USER_VARS           := $0400             ; $0400-$07FF

; Program
PROGRAM_START       := $0800             ; $0800-$7FFF

; RAM Card | IO 1 | $8000-$83FF 
RAM_DATA_L          := $8000             ; R/W ($8000-$83FE)
RAM_BANK_L          := $83FF             ; Write-only RAM bank latch, value ($00-$FF) sets which of 256 ~1K banks of RAM is selected in both H or L

; RAM Card | IO 2 | $8400-$87FF 
RAM_DATA_H          := $8400             ; R/W ($8400-$87FE)
RAM_BANK_H          := $87FF             ; Write-only RAM bank latch, value ($00-$FF) sets which of 256 ~1K banks of RAM is selected in both H or L

; RTC Card | IO 3 | $8800-$881F
RTC_SEC             := $8800
RTC_MIN             := $8801
RTC_HR              := $8802
RTC_DAY             := $8803
RTC_DATE            := $8804
RTC_MON             := $8805
RTC_YR              := $8806
RTC_CENT            := $8807
RTC_ALARM_SEC       := $8808
RTC_ALARM_MIN       := $8809
RTC_ALARM_HR        := $880A
RTC_ALARM_DATE      := $880B
RTC_WD_L            := $880C
RTC_WD_H            := $880D
RTC_CTRL_A          := $880E
RTC_CTRL_B          := $880F
RTC_RAM_ADDR        := $8810
RTC_RAM_DATA        := $8813

; Storage Card | IO 4 | $8C00-$8C07
ST_DATA             := $8C00             ; R/W
ST_ERROR            := $8C01             ; Read
ST_FEATURE          := $8C01             ; Write
ST_SECT_CNT         := $8C02             ; R/W
ST_LBA_0            := $8C03             ; R/W
ST_LBA_1            := $8C04             ; R/W
ST_LBA_2            := $8C05             ; R/W
ST_LBA_3            := $8C06             ; R/W
ST_STATUS           := $8C07             ; Read
ST_CMD              := $8C07             ; Write
ST_ERR_AMNF         := %00000001
ST_ERR_ABRT         := %00000100
ST_ERR_IDNF         := %00010000
ST_ERR_UNC          := %01000000
ST_ERR_BBK          := %10000000
ST_STATUS_ERR       := %00000001
ST_STATUS_IDX       := %00000010
ST_STATUS_CORR      := %00000100
ST_STATUS_DRQ       := %00001000
ST_STATUS_DSC       := %00010000
ST_STATUS_DWF       := %00100000
ST_STATUS_RDY       := %01000000
ST_STATUS_BSY       := %10000000

; Storage Card Pro | IO 4 | $8C00-$8C01
STP_DATA            := $8C00             ; R/W
STP_CTRL            := $8C01             ; R/W
STP_CTRL_BUSY       := %10000000
STP_CTRL_CD         := %01000000
STP_CTRL_WP         := %00100000
STP_CTRL_SS         := %00011000
STP_CTRL_AUTO_TX    := %00000100
STP_CTRL_SLOW_CLK   := %00000010
STP_CTRL_SELECT     := %00000001

; Serial Card / Serial Card Pro | IO 5 | $9000-$9003
SC_DATA             := $9000             ; R/W
SC_RESET            := $9001             ; Write
SC_STATUS           := $9001             ; Read
SC_CMD              := $9002             ; R/W
SC_CTRL             := $9003             ; R/W
SC_STATUS_IRQ       := %10000000         ; Interrupt
SC_STATUS_DSR       := %01000000         ; Data Set Ready
SC_STATUS_DCD       := %00100000         ; Data Carrier Detect
SC_STATUS_TDRE      := %00010000         ; TX Data Register Empty
SC_STATUS_RDRF      := %00001000         ; RX Data Register Full
SC_STATUS_OVR       := %00000100         ; Overrun
SC_STATUS_FRME      := %00000010         ; Framing Error
SC_STATUS_PARE      := %00000001         ; Parity Error

; GPIO Card / Input Board | IO 6 | $9400-$940F
GPIO_PORTB          := $9400
GPIO_PORTA          := $9401
GPIO_DDRB           := $9402
GPIO_DDRA           := $9403
GPIO_T1CL           := $9404
GPIO_T1CH           := $9405
GPIO_T1LL           := $9406
GPIO_T1LH           := $9407
GPIO_T2CL           := $9408
GPIO_T2CH           := $9409
GPIO_SR             := $940A
GPIO_ACR            := $940B
GPIO_PCR            := $940C
GPIO_IFR            := $940D
GPIO_IER            := $940E
GPIO_ORA            := $940F

; Sound Card (SID/ARMSID) | IO 7 | $9800-$981C
SID_V1_FREQ_LO      := $9800             ; Voice 1 Frequency Low
SID_V1_FREQ_HI      := $9801             ; Voice 1 Frequency High
SID_V1_PW_LO        := $9802             ; Voice 1 Pulse Width Low
SID_V1_PW_HI        := $9803             ; Voice 1 Pulse Width High
SID_V1_CTRL         := $9804             ; Voice 1 Control Register
SID_V1_AD           := $9805             ; Voice 1 Attack/Decay
SID_V1_SR           := $9806             ; Voice 1 Sustain/Release

SID_V2_FREQ_LO      := $9807             ; Voice 2 Frequency Low
SID_V2_FREQ_HI      := $9808             ; Voice 2 Frequency High
SID_V2_PW_LO        := $9809             ; Voice 2 Pulse Width Low
SID_V2_PW_HI        := $980A             ; Voice 2 Pulse Width High
SID_V2_CTRL         := $980B             ; Voice 2 Control Register
SID_V2_AD           := $980C             ; Voice 2 Attack/Decay
SID_V2_SR           := $980D             ; Voice 2 Sustain/Release

SID_V3_FREQ_LO      := $980E             ; Voice 3 Frequency Low
SID_V3_FREQ_HI      := $980F             ; Voice 3 Frequency High
SID_V3_PW_LO        := $9810             ; Voice 3 Pulse Width Low
SID_V3_PW_HI        := $9811             ; Voice 3 Pulse Width High
SID_V3_CTRL         := $9812             ; Voice 3 Control Register
SID_V3_AD           := $9813             ; Voice 3 Attack/Decay
SID_V3_SR           := $9814             ; Voice 3 Sustain/Release

SID_FC_LO           := $9815             ; Filter Cutoff Low
SID_FC_HI           := $9816             ; Filter Cutoff High
SID_RES_FILT        := $9817             ; Resonance/Filter
SID_MODE_VOL        := $9818             ; Filter Mode/Volume
SID_PADDLE_X        := $9819             ; Paddle X (Read-only)
SID_PADDLE_Y        := $981A             ; Paddle Y (Read-only)
SID_OSC3            := $981B             ; Oscillator 3 (Read-only)
SID_ENV3            := $981C             ; Envelope 3 (Read-only)

; SID Control Register Bits
SID_CTRL_GATE       := %00000001         ; Gate bit
SID_CTRL_SYNC       := %00000010         ; Sync bit
SID_CTRL_RING       := %00000100         ; Ring modulation
SID_CTRL_TEST       := %00001000         ; Test bit
SID_CTRL_TRIANGLE   := %00010000         ; Triangle waveform
SID_CTRL_SAWTOOTH   := %00100000         ; Sawtooth waveform
SID_CTRL_PULSE      := %01000000         ; Pulse waveform
SID_CTRL_NOISE      := %10000000         ; Noise waveform

; SID Filter Mode Bits
SID_FILT_LP         := %00010000         ; Low-pass filter
SID_FILT_BP         := %00100000         ; Band-pass filter
SID_FILT_HP         := %01000000         ; High-pass filter
SID_FILT_3OFF       := %10000000         ; Voice 3 off

; Video Card / VGA Card (TMS9918/pico9918) | IO 8 | $9C00-$9C01
VC_DATA             := $9C00             ; R/W
VC_REG              := $9C01             ; Write
VC_STATUS           := $9C01             ; Read

; VERA | IO 8 | $9C00-$9C1F
VERA_ADDR_LOW       := $9C00
VERA_ADDR_MID       := $9C01
VERA_ADDR_HIGH      := $9C02
VERA_DATA0          := $9C03
VERA_DATA1          := $9C04
VERA_CTRL           := $9C05
VERA_IEN            := $9C06
VERA_ISR            := $9C07
VERA_IRQLINE_L      := $9C08             ; Write 
VERA_SCANLINE_L     := $9C08             ; Read

; Display Composer registers (DCSEL=0)
VERA_DC_VIDEO       := $9C09             ; DCSEL=0
VERA_DC_HSCALE      := $9C0A             ; DCSEL=0
VERA_DC_VSCALE      := $9C0B             ; DCSEL=0
VERA_DC_BORDER      := $9C0C             ; DCSEL=0

; Display Composer active area (DCSEL=1)
VERA_DC_HSTART      := $9C09             ; DCSEL=1
VERA_DC_HSTOP       := $9C0A             ; DCSEL=1
VERA_DC_VSTART      := $9C0B             ; DCSEL=1
VERA_DC_VSTOP       := $9C0C             ; DCSEL=1

; VERA FX Control registers (DCSEL=2)
VERA_FX_CTRL        := $9C09             ; DCSEL=2
VERA_FX_TILEBASE    := $9C0A             ; DCSEL=2 (Write)
VERA_FX_MAPBASE     := $9C0B             ; DCSEL=2 (Write)
VERA_FX_MULT        := $9C0C             ; DCSEL=2 (Write)

; VERA FX Increment registers (DCSEL=3)
VERA_FX_X_INCR_L    := $9C09             ; DCSEL=3 (Write)
VERA_FX_X_INCR_H    := $9C0A             ; DCSEL=3 (Write)
VERA_FX_Y_INCR_L    := $9C0B             ; DCSEL=3 (Write)
VERA_FX_Y_INCR_H    := $9C0C             ; DCSEL=3 (Write)

; VERA FX Position registers (DCSEL=4)
VERA_FX_X_POS_L     := $9C09             ; DCSEL=4 (Write)
VERA_FX_X_POS_H     := $9C0A             ; DCSEL=4 (Write)
VERA_FX_Y_POS_L     := $9C0B             ; DCSEL=4 (Write)
VERA_FX_Y_POS_H     := $9C0C             ; DCSEL=4 (Write)

; VERA FX Sub-pixel position / Polygon fill (DCSEL=5)
VERA_FX_X_POS_S     := $9C09             ; DCSEL=5 (Write)
VERA_FX_Y_POS_S     := $9C0A             ; DCSEL=5 (Write)
VERA_FX_POLY_FILL_L := $9C0B             ; DCSEL=5 (Read)
VERA_FX_POLY_FILL_H := $9C0C             ; DCSEL=5 (Read)

; VERA FX Cache / Accumulator (DCSEL=6)
VERA_FX_CACHE_L     := $9C09             ; DCSEL=6 (Write)
VERA_FX_ACCUM_RESET := $9C09             ; DCSEL=6 (Read)
VERA_FX_CACHE_M     := $9C0A             ; DCSEL=6 (Write)
VERA_FX_ACCUM       := $9C0A             ; DCSEL=6 (Read)
VERA_FX_CACHE_H     := $9C0B             ; DCSEL=6 (Write)
VERA_FX_CACHE_U     := $9C0C             ; DCSEL=6 (Write)

; VERA Version registers (DCSEL=63)
VERA_DC_VER0        := $9C09             ; DCSEL=63 (Read) - ASCII 'V'
VERA_DC_VER1        := $9C0A             ; DCSEL=63 (Read) - Major version
VERA_DC_VER2        := $9C0B             ; DCSEL=63 (Read) - Minor version
VERA_DC_VER3        := $9C0C             ; DCSEL=63 (Read) - Build number

; Layer 0/1 registers
VERA_L0_CONFIG      := $9C0D
VERA_L0_MAPBASE     := $9C0E
VERA_L0_TILEBASE    := $9C0F
VERA_L0_HSCROLL_L   := $9C10
VERA_L0_HSCROLL_H   := $9C11
VERA_L0_VSCROLL_L   := $9C12
VERA_L0_VSCROLL_H   := $9C13
VERA_L1_CONFIG      := $9C14
VERA_L1_MAPBASE     := $9C15
VERA_L1_TILEBASE    := $9C16
VERA_L1_HSCROLL_L   := $9C17
VERA_L1_HSCROLL_H   := $9C18
VERA_L1_VSCROLL_L   := $9C19
VERA_L1_VSCROLL_H   := $9C1A

; Audio and SPI registers
VERA_AUDIO_CTRL     := $9C1B
VERA_AUDIO_RATE     := $9C1C
VERA_AUDIO_DATA     := $9C1D
VERA_SPI_DATA       := $9C1E
VERA_SPI_CTRL       := $9C1F

; LCD Card / LCD Board / Keypad LCD Helper / Keypad Helper | IO 8 | $9C00-$9C0F
LCD_PORTB           := $9C00
LCD_PORTA           := $9C01
LCD_DDRB            := $9C02
LCD_DDRA            := $9C03
LCD_T1CL            := $9C04
LCD_T1CH            := $9C05
LCD_T1LL            := $9C06
LCD_T1LH            := $9C07
LCD_T2CL            := $9C08
LCD_T2CH            := $9C09
LCD_SR              := $9C0A
LCD_ACR             := $9C0B
LCD_PCR             := $9C0C
LCD_IFR             := $9C0D
LCD_IER             := $9C0E
LCD_ORA             := $9C0F

; LCD Bits
LCD_E               := %10000000    ; PORTA LCD ENABLE
LCD_RW              := %01000000    ; PORTA LCD R/W
LCD_RS              := %00100000    ; PORTA LCD REGISTER SELECT

; LCD Keypad Bits
LCD_KEYPAD          := %00011111    ; PORTA LCD KEYPAD DATA