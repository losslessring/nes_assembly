.include "consts.inc"
.include "header.inc"
.include "reset.inc"
.include "utils.inc"

.segment "ZEROPAGE"
Frame:   .res 1              ; Reserve 1 byte to store the number of frames
Clock60: .res 1              ; Reserve 1 byte to store a counter that increments every second (60 frames)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; PRG-ROM code located at $8000
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "CODE"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Subroutine to load all 32 color palette values from ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.proc LoadPalette
    ldy #0                   ; Y = 0
:   lda PaletteData,y        ; Lookup byte in ROM
    sta PPU_DATA             ; Set value to send to PPU_DATA
    iny                      ; Y++
    cpy #32                  ; Is Y equal to 32?
    bne :-                   ; Not yet, keep looping
    rts                      ; Return from subroutine
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Subroutine to load 255 tiles in the first nametable
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.proc LoadBackground
    ldy #0                   ; Y = 0
:   lda BackgroundData,y     ; Lookup byte in ROM
    sta PPU_DATA             ; Set value to send to PPU_DATA
    iny                      ; Y++
    cpy #255                 ; Is Y equal to 255?
    bne :-                   ; Not yet, keep looping
    rts                      ; Return from subroutine
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Subroutine to load 16 bytes of attributes for the first nametable
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.proc LoadAttributes
    ldy #0                   ; Y = 0
:   lda AttributeData,y      ; Lookup byte in ROM
    sta PPU_DATA             ; Set value to send to PPU_DATA
    iny                      ; Y++
    cpy #16                  ; Is Y equal to 16?
    bne :-                   ; Not yet, keep looping
    rts                      ; Return from subroutine
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Subroutine to increment clock
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; .proc IncrementClock clock
;    inc clock ; Increment Clock60 every time our frame counter reaches #60.
;    rts                      ; Return from subroutine
; .endproc

.macro IncrementClock clock
    inc clock
.endmacro

.macro IncrementClockWithFrames clock, frame 
    inc frame                ; Frame++

    lda frame                ; Load frame
    cmp #59  ; Compare the value in A with the decimal value 60
    ;; Since NTSC runs at 60Hz, Clock60 should behave as a countner of seconds.
    bne Exit ; Branch back out of interrupt if the comparison was not equals (to zero)   

    IncrementClock clock
    lda #0
    sta frame ; Reset frame counter after 60 ticks    
Exit:    
.endmacro




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Reset handler (called when the NES resets or powers on)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
Reset:
    INIT_NES                 ; Macro to initialize the NES to a known state

InitVariables:
    lda #0
    sta Frame                ; Frame = 0

Main:
    PPU_SETADDR $3F00
    jsr LoadPalette          ; Jump to subroutine LoadPalette

    PPU_SETADDR $2000
    jsr LoadBackground       ; Jump to subroutine LoadBackground

    PPU_SETADDR $23C0
    jsr LoadAttributes       ; Jump to subroutine LoadAttributes

EnablePPURendering:
    lda #%10010000           ; Enable NMI and set background to use the 2nd pattern table (at $1000)
    sta PPU_CTRL
    lda #0
    sta PPU_SCROLL           ; Disable scroll in X
    sta PPU_SCROLL           ; Disable scroll in Y
    lda #%00011110
    sta PPU_MASK             ; Set PPU_MASK bits to render the background

LoopForever:
    jmp LoopForever          ; Force an infinite execution loop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; NMI interrupt handler (triggered once per frame, at the start of VBlank)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
NMI:
     IncrementClockWithFrames Clock60, Frame
     rti
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; IRQ interrupt handler
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
IRQ:
    rti                      ; Return from interrupt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Hardcoded list of color values in ROM to be loaded by the PPU
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
PaletteData:
.byte $22,$29,$1A,$0F, $22,$36,$17,$0F, $22,$30,$21,$0F, $22,$27,$17,$0F ; Background palette
.byte $22,$16,$27,$18, $22,$1A,$30,$27, $22,$16,$30,$27, $22,$0F,$36,$17 ; Sprite palette

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Background data that must be copied to the nametable
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
BackgroundData:
.byte $24,$24,$24,$24,$24,$24,$24,$24,$24,$36,$37,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
.byte $24,$24,$24,$24,$24,$24,$24,$24,$35,$25,$25,$38,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$60,$61,$62,$63,$24,$24,$24,$24
.byte $24,$36,$37,$24,$24,$24,$24,$24,$39,$3a,$3b,$3c,$24,$24,$24,$24,$53,$54,$24,$24,$24,$24,$24,$24,$64,$65,$66,$67,$24,$24,$24,$24
.byte $35,$25,$25,$38,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$55,$56,$24,$24,$24,$24,$24,$24,$68,$69,$26,$6a,$24,$24,$24,$24
.byte $45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45
.byte $47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47
.byte $47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Attribute data that is used for 4x4 sections of the background
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
AttributeData:
.byte %00000000, %00000000, %10101010, %00000000, %11110000, %00000000, %00000000, %00000000
.byte %11111111, %11111111, %11111111, %11111111, %11111111, %11111111, %11111111, %11111111

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Here we add the CHR-ROM data, included from an external .CHR file
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "CHARS"
.incbin "mario.chr"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Vectors with the addresses of the handlers that we always add at $FFFA
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "VECTORS"
.word NMI                    ; Address (2 bytes) of the NMI handler
.word Reset                  ; Address (2 bytes) of the Reset handler
.word IRQ                    ; Address (2 bytes) of the IRQ handler
