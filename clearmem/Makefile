###############################################################################
# Rule to assemble and link all assembly files
###############################################################################
build:
	ca65 clearmem.asm -o clearmem.o
	ld65 -C nes.cfg clearmem.o -o clearmem.nes

###############################################################################
# Rule to remove all object (.o) files and cartridge (.nes) files
###############################################################################
clean:
	rm *.o *.nes

###############################################################################
# Rule to run the final cartridge .nes file in the FCEUX emulator
###############################################################################
run:
	fceux clearmem.nes
