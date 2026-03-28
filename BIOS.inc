; ***                     ***
; ***   6502 INCLUDES     ***
; ***                     ***

; Zero Page
ZP                  := $00
READ_PTR            := $00
WRITE_PTR           := $01
STR_PTR             := $02               ; $02-$03 - String pointer (2 bytes)
; $04-$23 reserved by BASIC interpreter
CF_BUF_PTR          := $24               ; $24-$25 - CF sector data buffer pointer (2 bytes)
CF_LBA              := $26               ; $26-$29 - CF 28-bit LBA address (4 bytes, little-endian)
XFER_PTR            := $2A               ; $2A-$2B - Serial transfer data pointer (2 bytes)

; Stack
STACK               := $0100             ; $0100-$01FF

; Input Buffer
INPUT_BUFFER        := $0200             ; $0200-$02FF

; Kernal Vars
KERNAL_VARS         := $0300             ; $0300-$03FF
IRQ_PTR             := $0300             ; $0300-$0301
BRK_PTR             := $0302             ; $0302-$0303
NMI_PTR             := $0304             ; $0304-$0305
IO_MODE             := $0306             ; Bit 0: 0=video, 1=serial output
VID_CURSOR_X        := $0307             ; Video cursor column (0-39)
VID_CURSOR_Y        := $0308             ; Video cursor row (0-23)
VID_CURSOR_ADDR     := $0309             ; Video cursor VRAM address ($0309-$030A)
RTC_BUF_CENT        := $030B             ; Century value from last RtcReadDate / for RtcWriteDate
RTC_TMP             := $030C             ; Scratch byte for BCD conversion
                                         ; $030D-$030F Reserved
BRK_P               := $0310             ; Saved P at time of BRK
BRK_PCL             := $0311             ; Saved PCL at time of BRK (points to BRK+2)
BRK_PCH             := $0312             ; Saved PCH at time of BRK
                                         ; $0313-$0316 Reserved
XFER_REMAIN         := $0317             ; $0317-$0318 - Remaining bytes to transfer (2 bytes)
XFER_IO_SAVE        := $0319             ; Saved IO_MODE before switching to serial
                                         ; $031A-$031F Reserved
SCROLL_BUF          := $0320             ; $0320-$0347 - 40-byte scroll temp buffer
; Filesystem temp vars ($0348+)
FS_START_SEC        := $0348             ; $0348-$0349 - File start sector (2 bytes)
FS_FILE_SIZE        := $034A             ; $034A-$034B - File size in bytes (2 bytes)
FS_SEC_COUNT        := $034C             ; Number of sectors to read/write
FS_DIR_IDX          := $034D             ; Directory entry index (0-15)
FS_NEXT_SEC         := $034E             ; $034E-$034F - Next free sector for allocation (2 bytes)
FS_FNAME_BUF        := $0350             ; $0350-$035A - 11-byte filename buffer (8 name + 3 ext)
FS_SECTOR_BUF       := $0600             ; $0600-$07FF - 512-byte sector buffer (overlaps BAS_TOKBUF/BAS_STRBUF)

; User Vars
USER_VARS           := $0400             ; $0400-$07FF

; Program
PROGRAM_START       := $0800             ; $0800-$7FFF

; RAM Card | IO 1 | $8000-$83FF 
RAM_DATA_L          := $8000             ; R/W ($8000-$83FE)
RAM_BANK_L          := $83FF             ; Write-only RAM bank latch, value ($00-$FF) sets which of 256 ~1K banks of RAM is selected

; RAM Card | IO 2 | $8400-$87FF 
RAM_DATA_H          := $8400             ; R/W ($8400-$87FE)
RAM_BANK_H          := $87FF             ; Write-only RAM bank latch, value ($00-$FF) sets which of 256 ~1K banks of RAM is selected

; RTC Card (DS1511Y) | IO 3 | $8800-$881F
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
; DS1511Y Control Register B Bits
RTC_CTRL_B_TE       := %10000000         ; Transfer Enable — set to inhibit updates during write

; Storage Card (CompactFlash 8-bit IDE) | IO 4 | $8C00-$8C07
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
; ATA Command Constants
ST_CMD_READ         := $20               ; Read Sectors
ST_CMD_WRITE        := $30               ; Write Sectors
ST_CMD_SET_FEAT     := $EF               ; Set Features
ST_FEAT_8BIT        := $01               ; Enable 8-bit data I/O
ST_LBA3_MASTER      := $E0               ; LBA mode, master drive (bits 7-5 = 111, bit 4 = 0)
; Filesystem Constants
FS_DIR_LBA          = 0                  ; Directory sector at LBA 0
FS_DATA_START       = 1                  ; Data sectors start at LBA 1
FS_MAX_FILES        = 16                 ; Max directory entries
FS_ENTRY_SIZE       = 32                 ; Bytes per directory entry
FS_ENTRY_FLAGS      = 11                 ; Offset of flags byte within entry
FS_ENTRY_START      = 12                 ; Offset of start sector (2 bytes)
FS_ENTRY_FSIZE      = 14                 ; Offset of file size (2 bytes)
FS_FLAG_USED        = %00000001          ; Entry in use

; Serial Card / Serial Card Pro (R65C51) | IO 5 | $9000-$9003
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

; GPIO Card / Input Board (65C22) | IO 6 | $9400-$940F
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
; Keyboard (VIA) Constants
GPIO_PCR_CB2_LO     := %11000000         ; PCR CB2 mode = manual output low (enables matrix keyboard encoder)
GPIO_PCR_CB2_HI     := %11100000         ; PCR CB2 mode = manual output high (disables matrix keyboard encoder)
GPIO_PCR_CB1_NEG    := %00000000         ; PCR CB1 active on falling (high-to-low) edge
GPIO_PCR_CA2_LO     := %00001100         ; PCR CA2 mode = manual output low (enables PS/2 keyboard encoder)
GPIO_PCR_CA2_HI     := %00001110         ; PCR CA2 mode = manual output high (disables PS/2 keyboard encoder)
GPIO_PCR_CA1_NEG    := %00000000         ; PCR CA1 active on falling (high-to-low) edge
GPIO_INT_CB1        := %00010000         ; IFR/IER bit 4 = CB1 interrupt flag/enable
GPIO_INT_CA1        := %00000010         ; IFR/IER bit 1 = CA1 interrupt flag/enable
GPIO_IER_SET        := %10000000         ; IER bit 7 = set mode (1=set named bits, 0=clear)

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