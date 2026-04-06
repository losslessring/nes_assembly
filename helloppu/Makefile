###############################################################################
# Rule to assemble and link all assembly files
###############################################################################
build:
	ca65 helloppu.asm -o helloppu.o
	ld65 -C nes.cfg helloppu.o -o helloppu.nes

###############################################################################
# Rule to remove all object (.o) files and cartridge (.nes) files
###############################################################################
clean:
	rm *.o *.nes

###############################################################################
# Rule to run the final cartridge .nes file in the FCEUX emulator
###############################################################################
run:
	fceux helloppu.nes
