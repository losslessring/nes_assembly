ca65 loadtext.asm -o loadtext.o
ld65 -C nes.cfg loadtext.o -o loadtext.nes
qfceux loadtext.nes
