ca65 movingmario.asm -o movingmario.o
ld65 -C nes.cfg movingmario.o -o movingmario.nes
qfceux movingmario.nes
