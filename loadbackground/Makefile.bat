ca65 loadbackground.asm -o loadbackground.o
ld65 -C nes.cfg loadbackground.o -o loadbackground.nes
qfceux loadbackground.nes
