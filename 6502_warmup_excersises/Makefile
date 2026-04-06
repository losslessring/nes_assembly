###############################################################################
# Rule to assemble and link all exercise files
###############################################################################
all:
	ca65 exercise-01.asm -o exercise-01.o
	ld65 exercise-01.o   -o exercise-01.nes -C nes.cfg
	qfceux exercise-01.nes

	ca65 exercise-02.asm -o exercise-02.o
	ld65 exercise-02.o   -o exercise-02.nes -C nes.cfg

	ca65 exercise-03.asm -o exercise-03.o
	ld65 exercise-03.o   -o exercise-03.nes -C nes.cfg 

	ca65 exercise-04.asm -o exercise-04.o
	ld65 exercise-04.o   -o exercise-04.nes -C nes.cfg 
	
	ca65 exercise-05.asm -o exercise-05.o
	ld65 exercise-05.o   -o exercise-05.nes -C nes.cfg 
	
	ca65 exercise-06.asm -o exercise-06.o
	ld65 exercise-06.o   -o exercise-06.nes -C nes.cfg 

	ca65 exercise-07.asm -o exercise-07.o
	ld65 exercise-07.o   -o exercise-07.nes -C nes.cfg 

	ca65 exercise-08.asm -o exercise-08.o
	ld65 exercise-08.o   -o exercise-08.nes -C nes.cfg

	ca65 exercise-09.asm -o exercise-09.o
	ld65 exercise-09.o   -o exercise-09.nes -C nes.cfg

###############################################################################
# Rule to remove all object (.o) and cartridge (.nes) files
###############################################################################
clean:
	rm *.o *.nes