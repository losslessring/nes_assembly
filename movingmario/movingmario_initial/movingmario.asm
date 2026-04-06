.include "consts.inc"
.include "header.inc"
.include "reset.inc"
.include "utils.inc"

.segment "ZEROPAGE"
Buttons: .res 1              ; Reserve 1 byte in RAM to store button state (A|B|Select|Start|Up|Down|Left|Right)
XPos:    .res 1              ; Player X position
YPos:    .res 1              ; Player Y position
Frame:   .res 1              ; Reserve 1 byte to store the number of frames
Clock60: .res 1              ; Reserve 1 byte to store a counter that increments every second (60 frames)
BgPtr:   .res 2              ; Reserve 2 bytes (16 bits) to store a pointer to the background address (lo-byte, hi-byte)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; PRG-ROM code located at $8000
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "CODE"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Routine to read controller state and store it inside "Buttons" in RAM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.proc ReadControllers
    lda #1                   ; A = 1
    sta Buttons              ; Buttons = 1
    sta $4016                ; Set Latch=1 to begin 'Input'/collection mode
    lsr                      ; A = 0
    sta $4016                ; Set Latch=0 to begin 'Output' mode
LoopButtons:
    lda $4016                ; This reads a bit from the controller data line and inverts its value,
                             ; And also sends a signal to the Clock line to shift the bits
    lsr                      ; We shift-right to place that 1-bit we just read into the Carry flag
    rol Buttons              ; Rotate bits left, placing the Carry value into the 1st bit of 'Buttons' in RAM
    bcc LoopButtons          ; Loop until Carry is set (from that initial 1 we loaded inside Buttons)
    rts
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Subroutine to load all 32 color palette values from ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.proc LoadPalette
    PPU_SETADDR $3F00
    ldy #0                   ; Y = 0
:   lda PaletteData,y        ; Lookup byte in ROM
    sta PPU_DATA             ; Set value to send to PPU_DATA
    iny                      ; Y++
    cpy #32                  ; Is Y equal to 32?
    bne :-                   ; Not yet, keep looping
    rts                      ; Return from subroutine
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Subroutine to load 32 bytes into OAM-RAM starting at $0200
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.proc LoadSprites
    ldx #0
LoopSprite:
    lda SpriteData,x         ; We fetch bytes from the SpriteData lookup table
    sta $0200,x              ; We store the bytes starting at OAM address $0200
    inx                      ; X++
    cpx #32
    bne LoopSprite           ; Loop 32 times (8 hardware sprites, 4 bytes each)
    rts
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Subroutine to load tiles and attributes into the first nametable
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.proc LoadBackground
    lda #<BackgroundData     ; Fetch the lo-byte of BackgroundData address
    sta BgPtr
    lda #>BackgroundData     ; Fetch the hi-byte of BackgroundData address
    sta BgPtr+1

    PPU_SETADDR $2000

    ldx #$00                 ; X = 0 --> x is the outer loop index (hi-byte) from $0 to $4
    ldy #$00                 ; Y = 0 --> y is the inner loop index (lo-byte) from $0 to $FF

OuterLoop:
InnerLoop:
    lda (BgPtr),y            ; Fetch the value *pointed* by BgPtr + Y
    sta PPU_DATA             ; Store in the PPU data
    iny                      ; Y++
    cpy #0                   ; If Y == 0 (wrapped around 256 times)?
    beq IncreaseHiByte       ;   Then: we need to increase the hi-byte
    jmp InnerLoop            ;   Else: Continue with the inner loop
IncreaseHiByte:
    inc BgPtr+1              ; We increment the hi-byte pointer to point to the next background section (next 255-chunk)
    inx                      ; X++
    cpx #4                   ; Compare X with #4
    bne OuterLoop            ;   If X is still not 4, then we keep looping back to the outer loop

    rts                      ; Return from subroutine
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Reset handler (called when the NES resets or powers on)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
Reset:
    INIT_NES                 ; Macro to initialize the NES to a known state

InitVariables:
    lda #0
    sta Frame                ; Frame = 0
    sta Clock60              ; Clock60 = 0

    ldx #0
    lda SpriteData,x
    sta YPos
    inx
    inx
    inx
    lda SpriteData,x
    sta XPos

Main:
    jsr LoadPalette          ; Call LoadPalette subroutine to load 32 colors into our palette
    jsr LoadBackground       ; Call LoadBackground subroutine to load a full nametable of tiles and attributes
    jsr LoadSprites          ; Call LoadSprites subroutine to load all sprites into OAM-RAM

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
;; NMI interrupt handler
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
NMI:
    inc Frame                ; Frame++

    ;-------------           ; DMA copy of OAM data from RAM to PPU
    lda #$02                 ; Every frame, we copy spite data starting at $02**.
    sta $4014                ; The OAM DMA copy starts when we write to $4014.
    ;-------------

    jsr ReadControllers      ; Jump to the subroutine that reads the controller buttons

CheckRightButton:
    lda Buttons
    and #%00000001
    beq CheckLeftButton
    inc XPos                 ; X++
CheckLeftButton:
    lda Buttons
    and #%00000010
    beq CheckDownButton
    dec XPos                 ; X--
CheckDownButton:
    lda Buttons
    and #%00000100
    beq CheckUpButton
    inc YPos                 ; Y++
CheckUpButton:
    lda Buttons
    and #%00001000
    beq :+
    dec YPos                 ; Y--
:

UpdateSpritePosition:
    ;---------------------------------------------
    ; TODO:
    ;---------------------------------------------
    ; Set the 1st sprite X position to be XPos
    ; Set the 3rd sprite X position to be XPos
    ; Set the 2nd sprite X position to be XPos + 8
    ; Set the 4th sprite X position to be XPos + 8
    ;---------------------------------------------
    ; Set the 1st sprite Y position to be YPos
    ; Set the 2nd sprite Y position to be YPos
    ; Set the 3rd sprite Y position to be YPos + 8
    ; Set the 4th sprite Y position to be YPos + 8
    ;---------------------------------------------

    lda Frame                ; Increment Clock60 every time we reach 60 frames (NTSC = 60Hz)
    cmp #60                  ; Is Frame equal to #60?
    bne :+                   ; If not, bypass Clock60 increment
    inc Clock60              ; But if it is 60, then increment Clock60 and zero Frame counter
    lda #0
    sta Frame
:
    rti                      ; Return from interrupt

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
;; Background data (including tiles and attributes, totalling 1KB)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
BackgroundData:
.incbin "background.nam"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; This is the OAM sprite attribute data data we will use in our game.
;; We have only one big metasprite that is composed of 4 hardware sprites.
;; The OAM is organized in sets of 4 bytes per tile.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SpriteData:
;--------------------------------
; Mario:
;      Y   tile#  attributes   X
.byte $AE,  $3A,  %00000000,  $98
.byte $AE,  $37,  %00000000,  $A0
.byte $B6,  $4F,  %00000000,  $98
.byte $B6,  $4F,  %01000000,  $A0
;--------------------------------
; Goomba:
;      Y   tile#  attributes   X
.byte $93,  $70,  %00100011,  $C7 
.byte $93,  $71,  %00100011,  $CF 
.byte $9B,  $72,  %00100011,  $C7
.byte $9B,  $73,  %00100011,  $CF
;--------------------------------

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
