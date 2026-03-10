TARGET = BIOS
CONFIG = BIOS

.PHONY: all clean

all: build

build: $(TARGET).asm
	cl65 -t none -C $(CONFIG).cfg -l $(TARGET).lst -o $(TARGET).bin $(TARGET).asm 
	
view:
	hexdump -C $(TARGET).bin

eeprom:
	minipro -p AT28C256	-w $(TARGET).bin

clean:
	rm $(TARGET).bin
	rm $(TARGET).lst