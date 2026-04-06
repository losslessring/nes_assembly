.segment "HEADER" ; Don’t forget to always add the iNES header to your ROM files
.org $7FF0
.byte $4E,$45,$53,$1A,$02,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.segment "CODE" ; Define a segment called "CODE" for the PRG-ROM at $8000
.org $8000


 Reset:
 ; TODO:
    lda #10;Load the A register with the decimal value 10
 
    sta $80; Store the value from A into memory position $80

    inc $80; Increment the value inside a (zero page) memory position $80
    dec $80; Decrement the value inside a (zero page) memory position $80

NMI: ; NMI handler
 rti ; doesn't do anything

IRQ: ; IRQ handler
 rti ; doesn't do anything
.segment "VECTORS" ; Add addresses with vectors at $FFFA
.org $FFFA
.word NMI ; Put 2 bytes with the NMI address at memory position $FFFA
.word Reset ; Put 2 bytes with the break address at memory position $FFFC
.word IRQ ; Put 2 bytes with the IRQ address at memory position $FFFE