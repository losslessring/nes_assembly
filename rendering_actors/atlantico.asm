.include "consts.inc"
.include "header.inc"
.include "actor.inc"
.include "reset.inc"
.include "utils.inc"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Variables declared in RAM zero-page
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "ZEROPAGE"
Buttons:        .res 1       ; Pressed buttons (A|B|Sel|Start|Up|Dwn|Lft|Rgt)

XPos:           .res 1       ; Player X 16-bit position (8.8 fixed-point): hi+lo/256px
YPos:           .res 1       ; Player Y 16-bit position (8.8 fixed-point): hi+lo/256px

XVel:           .res 1       ; Player X (signed) velocity (in pixels per 256 frames)
YVel:           .res 1       ; Player Y (signed) velocity (in pixels per 256 frames)

Frame:          .res 1       ; Counts frames (0 to 255 and repeats)
IsDrawComplete: .res 1       ; Flag to indicate when VBlank is done drawing
Clock60:        .res 1       ; Counter that increments per second (60 frames)

BgPtr:          .res 2       ; Pointer to background address - 16bits (lo,hi)
SprPtr:         .res 2       ; Pointer to the sprite address - 16bits (lo,hi)

XScroll:        .res 1       ; Store the horizontal scroll position
CurrNametable:  .res 1       ; Store the current starting nametable (0 or 1)
Column:         .res 1       ; Stores the column (of tiles) we are in the level
NewColAddr:     .res 2       ; The destination address of the new column in PPU
SourceAddr:     .res 2       ; The source address in ROM of the new column tiles

ParamType:      .res 1       ; Used as parameter to subroutine
ParamXPos:      .res 1       ; Used as parameter to subroutine
ParamYPos:      .res 1       ; Used as parameter to subroutine
ParamXVel:      .res 1       ; Used as parameter to subroutine
ParamYVel:      .res 1       ; Used as parameter to subroutine
ParamTileNum:   .res 1       ; Used as parameter to subroutine
ParamNumTiles:  .res 1       ; Used as parameter to subroutine
ParamAttribs:   .res 1       ; Used as parameter to subroutine

ActorsArray:    .res MAX_ACTORS * .sizeof(Actor)

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
    sta JOYPAD1              ; Set Latch=1 to begin 'Input'/collection mode
    lsr                      ; A = 0
    sta JOYPAD1              ; Set Latch=0 to begin 'Output' mode
LoopButtons:
    lda JOYPAD1              ; This reads a bit from the controller data line and inverts its value,
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
;; Routine to draw a new column of tiles off-screen every 8 pixels
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.proc DrawNewColumn
    lda XScroll              ; We'll set the NewColAddr lo-byte and hi-byte
    lsr
    lsr
    lsr                      ; Shift right 3 times to divide XScroll by 8
    sta NewColAddr           ; Set the lo-byte of the column address

    lda CurrNametable        ; The hi-byte comes from the nametable
    eor #1                   ; Invert the low bit (0 or 1)
    asl
    asl                      ; Multiply by 4 (A is $00 or $04)
    clc
    adc #$20                 ; Add $20 (A is $20 or $24) for nametabe 0 or 1
    sta NewColAddr+1         ; Set the hi-byte of the column address ($20xx or $24xx)

    lda Column               ; Multiply (col * 32) to compute the data offset
    asl
    asl
    asl
    asl
    asl
    sta SourceAddr           ; Store lo-byte (--XX) of column source address

    lda Column
    lsr
    lsr
    lsr                      ; Divide current Column by 8 (using 3 shift rights)
    sta SourceAddr+1         ; Store hi-byte (XX--) of column source addres

                             ; Here we'll add the offset the column source address with the address of where the BackgroundData
    lda SourceAddr           ; Lo-byte of the column data start + offset = address to load column data from
    clc
    adc #<BackgroundData     ; Add the lo-byte
    sta SourceAddr           ; Save the result of the offset back to the source address lo-byte

    lda SourceAddr+1         ; Hi-byte of the column source address
    adc #>BackgroundData     ; Add the hi-byte
    sta SourceAddr+1         ; Add the result of the offset back to the source address hi-byte

    DrawColumn:
      lda #%00000100
      sta PPU_CTRL           ; Tell the PPU that the increments will be +32 mode

      lda PPU_STATUS         ; Hit PPU_STATUS to reset hi/lo address latch
      lda NewColAddr+1
      sta PPU_ADDR           ; Set the hi-byte of the new column start address
      lda NewColAddr
      sta PPU_ADDR           ; Set the lo-byte of the new column start address

      ldx #30                ; We'll loop 30 times (=30 rows)
      ldy #0
      DrawColumnLoop:
        lda (SourceAddr),y   ; Copy from the address of the column source + y offset
        sta PPU_DATA
        iny                  ; Y++
        dex                  ; X--
        bne DrawColumnLoop   ; Loop 30 times to draw all 30 rows of this column
    rts
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Routine to draw attributes off-screen every 32 pixels
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.proc DrawNewAttribs
    lda CurrNametable
    eor #1                   ; Invert low bit (0 or 1)
    asl                      ; Multiuply by 2, ($00 or $02)
    asl                      ; Multiply by 2 again ($00 or $04)
    clc
    adc #$23                 ; Add high byte of attribute base address ($23-- or $27--)
    sta NewColAddr+1         ; The hi-byte now has address = $23 or $27 for nametable 0 or 1

    lda XScroll
    lsr
    lsr
    lsr
    lsr
    lsr                      ; Divide by 32 (shift right 5 times)
    clc
    adc #$C0
    sta NewColAddr           ; The lo-byte contains (attribute base + XScroll/32)

    lda Column               ; (Column/4) * 8, since each row of attribute data in ROM is 8 bytes
    and #%11111100           ; Mask the lowest two bits to get the closest lowest multiple of 4
    asl                      ; One shift left equivelant to a multiplication by 2
    sta SourceAddr           ; Stores the lo-byte of the source attribute address offset (in ROM)

    lda Column               ; Proceed to compute the hi-byte of the source address offset in ROM
    lsr                      ; /2
    lsr                      ; /4
    lsr                      ; /8
    lsr                      ; /16
    lsr                      ; /32
    lsr                      ; /64
    lsr                      ; /128, shift right 7 times to divide by 128
    sta SourceAddr+1         ; Stores the hi-byte of the Source address offset

    lda SourceAddr
    clc
    adc #<AttributeData      ; Add the lo-byte of the base address where AttributeData is in ROM
    sta SourceAddr           ; Stores the result of the add back into the lo-byte of the SourceAddr

    lda SourceAddr+1
    adc #>AttributeData      ; Add the hi-byte of the base address where AttributeData is in ROM
    sta SourceAddr+1         ; Stores the result of the add back into the hi-byte of the SourceAddr

    DrawAttribute:
      bit PPU_STATUS         ; Hit PPU_STATUS to reset the high/low address latch
      ldy #0                 ; Y = 0
      DrawAttribLoop:
        lda NewColAddr+1
        sta PPU_ADDR         ; Write the hi-byte of attribute PPU destination address
        lda NewColAddr
        sta PPU_ADDR         ; Write the lo-byte of attribute PPU destination address
        lda (SourceAddr),y   ; Fetch attribute byte from ROM
        sta PPU_DATA         ; Stores new attribute data into the PPU memory
        iny                  ; Y++
        cpy #8
        beq :+               ; Loop 8 times (to copy 8 attribute bytes)
          lda NewColAddr
          clc
          adc #8
          sta NewColAddr     ; Next attribute will be at (NewColAddr + 8)
          jmp DrawAttribLoop
       :
    rts
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Subroutine to add new actor to the array in the first empty slot found
;; Params = ParamType, ParamXPos, ParamYPos, ParamXVel, ParamYVel
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.proc AddNewActor
    ldx #0                            ; X = 0
  ArrayLoop:
    cpx #MAX_ACTORS * .sizeof(Actor)  ; Reached maximum number of actors allowed in the array?
    beq EndRoutine                    ; Then we skip and don't add a new actor
    lda ActorsArray+Actor::Type,x
    cmp #ActorType::NULL              ; If the actor type of this array position is NULL
    beq AddNewActorToArray            ;   Then: we found an empty slot, proceed to add actor to position [x]
   NextActor:
    txa
    clc
    adc #.sizeof(Actor)               ; Otherwise, we offset to the check the next actor in the array
    tax                               ; X += sizeof(Actor)
    jmp ArrayLoop

  AddNewActorToArray:                 ; Here we add a new actor at index [x] of the array
    lda ParamType                     ; Fetch parameter "actor type" from RAM
    sta ActorsArray+Actor::Type,x
    lda ParamXPos                     ; Fetch parameter "actor position X" from RAM
    sta ActorsArray+Actor::XPos,x
    lda ParamYPos                     ; Fetch parameter "actor position Y" from RAM
    sta ActorsArray+Actor::YPos,x
    lda ParamXVel                     ; Fetch parameter "actor velocity X" from RAM
    sta ActorsArray+Actor::XVel,x
    lda ParamYVel                     ; Fetch parameter "actor velocity Y" from RAM
    sta ActorsArray+Actor::YVel,x
EndRoutine:
    rts
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Subroutine to loop all actors and send their tiles to the OAM-RAM at $200
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.proc RenderActors
    lda #$02
    sta SprPtr+1
    lda #$00
    sta SprPtr                         ; Point SprPtr to $0200

    ldy #0                             ; Count how many tiles we are sending
    ldx #0                             ; Counts how many actors we are looping
    ActorsLoop:
      lda ActorsArray+Actor::Type,x

      cmp #ActorType::PLAYER
      bne :+
        lda ActorsArray+Actor::XPos,x
        sta ParamXPos
        lda ActorsArray+Actor::YPos,x
        sta ParamYPos
        lda #$60
        sta ParamTileNum
        lda #%00000000
        sta ParamAttribs
        lda #4
        sta ParamNumTiles
        jsr DrawSprite                 ; Call routine to draw 4 PLAYER tiles to the OAM
        jmp NextActor
      :
      
       cmp #ActorType::MISSILE
      bne :+
        lda ActorsArray+Actor::XPos,x
        sta ParamXPos
        lda ActorsArray+Actor::YPos,x        
        sta ParamYPos
        lda #$50
        sta ParamTileNum
        lda #%00000000
        sta ParamAttribs
        lda #1
        sta ParamNumTiles
        jsr DrawSprite                 ; Call routine to draw 4 PLAYER tiles to the OAM
        jmp NextActor
      :

      NextActor:
        txa
        clc
        adc #.sizeof(Actor)
        tax
        cmp #MAX_ACTORS * .sizeof(Actor)
        bne ActorsLoop
    rts
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Routine to loop "NumTiles" times, sending bytes to the OAM-RAM.
;; Params = ParamXPos, ParamYPos, ParamTileNum, ParamAttribs, ParamNumTiles
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.proc DrawSprite
    txa
    pha                                ; Save the value of the X register before anything
    
    ldx #0
    TileLoop:
       lda ParamYPos                   ; Send Y position to the OAM
       sta (SprPtr),y
       iny

       lda ParamTileNum                ; Send the Tile # to the OAM
       sta (SprPtr),y
       inc ParamTileNum                ; ParamTileNum++
       iny

       lda ParamAttribs                ; Send the attributes to the OAM
       sta (SprPtr),y
       iny

       lda ParamXPos                   ; Send X position to the OAM
       sta (SprPtr),y
       clc
       adc #8
       sta ParamXPos                   ; ParamXPos += 8

       iny

       inx                             ; X++
       cpx ParamNumTiles               ; Loop until X == NumTiles
       bne TileLoop

    pla
    tax                                ; Restore the previous value of X register

    rts
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
    sta XScroll              ; XScroll = 0
    sta CurrNametable        ; CurrNametable = 0
    sta Column               ; Column = 0
    lda #113
    sta XPos
    lda #165
    sta YPos

Main:
    jsr LoadPalette          ; Call LoadPalette subroutine to load 32 colors into our palette

AddSprite0:
    lda #ActorType::SPRITE0
    sta ParamType
    lda #0
    sta ParamXPos
    lda #27
    sta ParamYPos
    lda #0
    sta ParamXVel
    sta ParamYVel
    jsr AddNewActor          ; Add new actor to array

AddPlayer:
    lda #ActorType::PLAYER
    sta ParamType
    lda XPos
    sta ParamXPos
    lda YPos
    sta ParamYPos
    lda #0
    sta ParamXVel
    sta ParamYVel
    jsr AddNewActor         ; Add new actor to array

InitBackgroundTiles:
    lda #1
    sta CurrNametable        ; CurrNametable = 1
    lda #0
    sta XScroll              ; XScroll = 0
    sta Column               ; Column = 0
InitBackgroundLoop:
    jsr DrawNewColumn        ; Draw all rows of new column (from top to bottom)
    
    lda XScroll
    clc
    adc #8
    sta XScroll              ; XScroll += 8
    
    inc Column               ; Column++
    
    lda Column
    cmp #32
    bne InitBackgroundLoop   ; Repeat all 32 columns of the first nametable

    lda #0
    sta CurrNametable        ; CurrNametable = 0
    lda #1
    sta XScroll              ; Scroll = 1

    jsr DrawNewColumn        ; Draw first column of the second nametable
    inc Column               ; Column++

    lda #%00000000
    sta PPU_CTRL             ; Set PPU increment to +1 mode

InitAttribs:
    lda #1
    sta CurrNametable
    lda #0
    sta XScroll
    sta Column
InitAttribsLoop:
    jsr DrawNewAttribs       ; Draw attributes in the correct place of the first nametable
    lda XScroll
    clc
    adc #32
    sta XScroll              ; XScroll += 32

    lda Column               ; Repeat for all elements of the first nametable
    clc
    adc #4
    sta Column               ; Column += 4
    cmp #32
    bne InitAttribsLoop      ; Loop until we reach Column 32

    lda #0
    sta CurrNametable
    lda #1
    sta XScroll
    jsr DrawNewAttribs       ; Draw first attributes of second nametable

    inc Column               ; Column = 33

EnableRendering:
    lda #%10010000           ; Enable NMI and set background to use the 2nd pattern table (at $1000)
    sta PPU_CTRL
    lda #0
    sta PPU_SCROLL           ; Disable scroll in X
    sta PPU_SCROLL           ; Disable scroll in Y
    lda #%00011110
    sta PPU_MASK             ; Set PPU_MASK bits to render the background

GameLoop:
    jsr ReadControllers      ; Read joypad and load button state
  CheckAButton:
    lda Buttons
    and #BUTTON_A
    beq :+
        lda #ActorType::MISSILE
        sta ParamType
        lda XPos
        sta ParamXPos
        lda YPos
        sec
        sbc #8  
        sta ParamYPos
        lda #0
        sta ParamXVel
        lda #1
        sta ParamYVel
        jsr AddNewActor      ; Call the subroutine to add a new missile actor
    :

    ;; TODO:
    ;; -----------------
    ;; jsr SpawnActors
    ;; jsr UpdateActors
    jsr RenderActors
    ;; -----------------

    WaitForVBlank:           ; We lock the execution of the game logic here
      lda IsDrawComplete     ; Here we check and only perform a game loop call once NMI is done drawing
      beq WaitForVBlank      ; Otherwise, we keep looping

    lda #0
    sta IsDrawComplete       ; Once we're done, we set the DrawComplete flag back to 0

    jmp GameLoop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; NMI interrupt handler
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
NMI:
    PUSH_REGS                ; Macro to save register values by pushing them to the stack

    inc Frame                ; Frame++

OAMStartDMACopy:             ; DMA copy of OAM data from RAM to PPU
    lda #$02                 ; Every frame, we copy spite data starting at $02**
    sta PPU_OAM_DMA          ; The OAM-DMA copy starts when we write to $4014

NewColumnCheck:
    lda XScroll
    and #%00000111           ; Check if the scroll a multiple of 8
    bne :+                   ; If it isn't, we still don't need to draw a new column
      jsr DrawNewColumn      ; If it is a multiple of 8, we proceed to draw a new column of tiles!
      Clamp128Cols:
        lda Column
        clc
        adc #1               ; Column++
        and #%01111111       ; Drop the left-most bit to wrap around 128
        sta Column           ; Clamping the value to never go beyond 128
    :

NewAttribsCheck:
    lda XScroll
    and #%00011111           ; Check if the scroll is a multiple of 32 (lowest 5 bits are 00000)
    bne :+                   ; If it isn't, we still don't need to draw new attributes
      jsr DrawNewAttribs       ; It it is a multiple of 32, we draw the new attributes!
    :

;;;;;;;;;;;;;;; BYPASS SPLIT-SCREEN FOR NOW!
;SetPPUNoScroll:
;    lda #0
;    sta PPU_SCROLL
;    sta PPU_SCROLL           ; Set *no* scroll for the status bar
;
;EnablePPUSprite0:
;    lda #%10010000           ; Enable PPU sprites for sprite 0
;    sta PPU_CTRL
;    lda #%00011110           ; Enable sprites and enable background
;    sta PPU_MASK
;
;WaitForNoSprite0:
;    lda PPU_STATUS
;    and #%01000000           ; PPU address $2002 bit 6 is the sprite 0 hit flag
;    bne WaitForNoSprite0     ; Loop until we do *not* have a sprite 0 hit
;
;WaitForSprite0:
;    lda PPU_STATUS
;    and #%01000000           ; PPU address $2002 bit 6 is the sprite 0 hit flag
;    beq WaitForSprite0       ; Loop until we do have a sprite 0 hit
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

ScrollBackground:
    inc XScroll              ; XScroll++
    lda XScroll
    bne :+                   ; Check if XScroll rolled back to 0, then we swap nametables!
      lda CurrNametable
      eor #1                 ; An XOR with %00000001 will flip the right-most bit.
      sta CurrNametable      ; If it was 0, it becomes 1. If it was 1, it becomes 0.
    :
    lda XScroll
    sta PPU_SCROLL           ; Set the horizontal X scroll first
    lda #0
    sta PPU_SCROLL           ; No vertical scrolling

RefreshRendering:
    lda #%10010000           ; Enable NMI, sprites from Pattern Table 0, background from Pattern Table 1
    ora CurrNametable        ; OR with CurrNametable (0 or 1) to set PPU_CTRL bit-0 (starting nametable)
    sta PPU_CTRL
    lda #%00011110           ; Enable sprites, enable background, no clipping on left side
    sta PPU_MASK

SetGameClock:
    lda Frame                ; Increment Clock60 every time we reach 60 frames (NTSC = 60Hz)
    cmp #60                  ; Is Frame equal to #60?
    bne :+                   ; If not, bypass Clock60 increment
    inc Clock60              ; But if it is 60, then increment Clock60 and zero Frame counter
    lda #0
    sta Frame
:

SetDrawComplete:
    lda #1
    sta IsDrawComplete       ; Set the DrawComplete flag to indicate we are done drawing to the PPU

    PULL_REGS

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
.byte $1C,$0F,$22,$1C, $1C,$37,$3D,$0F, $1C,$37,$3D,$30, $1C,$0F,$3D,$30 ; Background palette
.byte $1C,$0F,$2D,$10, $1C,$0F,$20,$27, $1C,$2D,$38,$18, $1C,$0F,$1A,$32 ; Sprite palette

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Background data (contains 4 screens that should scroll horizontally)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
BackgroundData:
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$23,$33,$15,$21,$12,$00,$31,$31,$31,$55,$56,$00,$00 ; ---> screen column 1 (from top to bottom)
.byte $13,$13,$75,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$42,$21,$21,$21,$24,$34,$15,$15,$12,$00,$31,$31,$53,$56,$56,$00,$00 ; ---> screen column 2 (from top to bottom)
.byte $13,$13,$6e,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$43,$21,$21,$21,$14,$11,$3e,$15,$12,$00,$00,$00,$31,$52,$56,$00,$00 ; ---> screen column 3 (from top to bottom)
.byte $13,$13,$7f,$13,$20,$21,$21,$21,$21,$21,$21,$21,$42,$21,$21,$44,$21,$21,$21,$14,$11,$3f,$15,$12,$00,$00,$00,$31,$5a,$56,$00,$00 ; ...
.byte $13,$13,$6e,$13,$20,$21,$21,$21,$21,$21,$21,$21,$44,$21,$21,$45,$21,$21,$21,$22,$32,$15,$15,$12,$00,$00,$00,$31,$58,$56,$00,$00 ; ...
.byte $13,$13,$75,$13,$20,$21,$21,$21,$21,$21,$21,$21,$45,$21,$21,$46,$21,$21,$21,$26,$36,$15,$15,$12,$00,$00,$00,$51,$5c,$56,$00,$00 ; ...
.byte $13,$13,$84,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$27,$37,$15,$15,$12,$00,$00,$00,$00,$58,$56,$00,$00
.byte $13,$13,$61,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$28,$38,$15,$15,$12,$00,$00,$00,$00,$5c,$56,$00,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$57,$56,$00,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$47,$21,$21,$21,$48,$21,$21,$22,$32,$3e,$15,$12,$00,$00,$00,$00,$58,$56,$00,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$42,$21,$21,$21,$4a,$21,$21,$23,$33,$4e,$15,$12,$00,$00,$00,$00,$59,$56,$00,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$43,$21,$21,$21,$21,$21,$21,$24,$34,$3f,$15,$12,$00,$00,$00,$00,$58,$56,$00,$00
.byte $13,$13,$7c,$13,$20,$21,$21,$21,$21,$21,$21,$21,$44,$21,$21,$21,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$57,$56,$00,$00
.byte $13,$13,$6c,$13,$20,$21,$21,$21,$21,$21,$21,$21,$45,$21,$21,$21,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$59,$56,$00,$00
.byte $13,$13,$78,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$15,$15,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$58,$56,$00,$00
.byte $13,$13,$7b,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$15,$15,$15,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$53,$56,$00,$00
.byte $13,$13,$6e,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$15,$21,$15,$21,$21,$25,$35,$15,$15,$12,$00,$60,$00,$00,$54,$56,$00,$00
.byte $13,$13,$84,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$15,$21,$21,$21,$26,$36,$15,$15,$12,$00,$00,$00,$00,$58,$56,$00,$00
.byte $13,$13,$60,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$15,$27,$37,$15,$15,$12,$00,$00,$00,$00,$58,$56,$00,$00
.byte $13,$13,$60,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$48,$21,$21,$15,$27,$37,$15,$15,$12,$00,$00,$00,$00,$5d,$56,$00,$00
.byte $13,$13,$60,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$49,$21,$21,$21,$28,$38,$3e,$21,$12,$00,$00,$00,$00,$58,$56,$00,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$49,$21,$21,$21,$22,$35,$3f,$21,$12,$00,$00,$00,$00,$58,$56,$00,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$49,$21,$21,$21,$26,$36,$3f,$21,$12,$00,$00,$00,$00,$57,$56,$00,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$4a,$21,$21,$21,$27,$37,$21,$15,$12,$00,$00,$00,$00,$58,$56,$00,$00
.byte $13,$13,$76,$13,$20,$21,$21,$21,$21,$21,$21,$21,$42,$21,$21,$21,$21,$21,$21,$28,$38,$15,$15,$12,$00,$00,$00,$00,$58,$56,$00,$00
.byte $13,$13,$72,$13,$20,$21,$21,$21,$21,$21,$21,$21,$44,$21,$21,$21,$21,$21,$21,$14,$11,$3e,$21,$12,$00,$00,$00,$00,$59,$56,$00,$00
.byte $13,$13,$7c,$13,$20,$21,$21,$21,$21,$21,$21,$21,$43,$21,$21,$21,$21,$21,$21,$14,$11,$4e,$21,$12,$00,$00,$00,$51,$59,$56,$00,$00
.byte $13,$13,$7c,$13,$20,$21,$21,$21,$21,$21,$21,$21,$44,$21,$21,$21,$21,$21,$21,$14,$11,$3f,$15,$12,$00,$00,$00,$00,$5c,$56,$00,$00
.byte $13,$13,$75,$13,$20,$21,$21,$21,$21,$21,$21,$21,$44,$21,$21,$21,$21,$21,$21,$29,$39,$21,$21,$12,$00,$00,$00,$00,$55,$56,$00,$00
.byte $13,$13,$84,$13,$20,$21,$21,$21,$21,$21,$21,$21,$45,$21,$21,$21,$48,$21,$2c,$2a,$3a,$3c,$21,$12,$00,$00,$00,$54,$56,$56,$00,$00
.byte $13,$13,$65,$13,$20,$21,$21,$21,$21,$21,$21,$21,$46,$21,$21,$21,$4a,$21,$2d,$2a,$3a,$3d,$15,$12,$00,$00,$00,$00,$52,$56,$00,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$2b,$3b,$15,$15,$12,$00,$00,$00,$00,$57,$56,$00,$00

.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$14,$11,$15,$21,$12,$00,$31,$31,$31,$55,$56,$ff,$9a
.byte $13,$13,$75,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$15,$21,$15,$21,$14,$11,$15,$15,$12,$00,$31,$31,$53,$56,$56,$ff,$5a
.byte $13,$13,$6e,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$15,$15,$15,$21,$14,$11,$3e,$15,$12,$00,$00,$00,$31,$52,$56,$ff,$5a
.byte $13,$13,$7f,$13,$20,$21,$21,$21,$21,$21,$21,$21,$42,$21,$21,$15,$15,$15,$21,$14,$11,$3f,$15,$12,$00,$00,$00,$31,$5a,$56,$ff,$56
.byte $13,$13,$6e,$13,$20,$21,$21,$21,$21,$21,$21,$21,$44,$21,$21,$15,$15,$15,$21,$14,$11,$15,$15,$12,$00,$00,$00,$31,$58,$56,$ff,$59
.byte $13,$13,$75,$13,$20,$21,$21,$21,$21,$21,$21,$21,$45,$21,$21,$15,$15,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$51,$5c,$56,$ff,$5a
.byte $13,$13,$84,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$15,$15,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$58,$56,$ff,$5a
.byte $13,$13,$61,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$5c,$56,$ff,$5a
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$57,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$47,$21,$21,$21,$48,$21,$21,$14,$11,$3e,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$42,$21,$21,$21,$4a,$21,$21,$14,$11,$4e,$15,$12,$00,$00,$00,$00,$59,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$43,$21,$21,$21,$21,$21,$21,$25,$35,$3f,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$7c,$13,$20,$21,$21,$21,$21,$21,$21,$21,$44,$21,$21,$21,$21,$21,$21,$26,$36,$15,$15,$12,$00,$00,$00,$00,$57,$56,$aa,$00
.byte $13,$13,$6c,$13,$20,$21,$21,$21,$21,$21,$21,$21,$45,$21,$21,$21,$21,$21,$21,$27,$37,$15,$15,$12,$00,$00,$00,$00,$59,$56,$aa,$00
.byte $13,$13,$78,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$15,$15,$21,$21,$21,$28,$38,$15,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$7b,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$15,$15,$15,$21,$21,$29,$39,$15,$15,$12,$00,$00,$00,$00,$53,$56,$aa,$00
.byte $13,$13,$6e,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$15,$21,$15,$21,$1f,$2a,$3a,$3c,$15,$12,$00,$61,$00,$00,$54,$56,$aa,$00
.byte $13,$13,$84,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$15,$21,$21,$21,$28,$3b,$15,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$60,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$15,$14,$11,$15,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$60,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$48,$21,$21,$15,$14,$11,$15,$15,$12,$00,$00,$00,$00,$5d,$56,$aa,$00
.byte $13,$13,$60,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$49,$21,$21,$21,$14,$11,$3e,$21,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$49,$21,$21,$21,$14,$11,$3f,$21,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$49,$21,$21,$21,$14,$11,$3f,$21,$12,$00,$00,$00,$00,$57,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$4a,$21,$21,$21,$14,$11,$21,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$76,$13,$20,$21,$21,$21,$21,$21,$21,$21,$42,$21,$21,$21,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$58,$56,$5a,$00
.byte $13,$13,$72,$13,$20,$21,$21,$21,$21,$21,$21,$21,$44,$21,$21,$21,$21,$21,$21,$14,$11,$3e,$21,$12,$00,$00,$00,$00,$59,$56,$9a,$00
.byte $13,$13,$7c,$13,$20,$21,$21,$21,$21,$21,$21,$21,$43,$21,$21,$21,$21,$21,$21,$22,$32,$4e,$21,$12,$00,$00,$00,$51,$59,$56,$aa,$00
.byte $13,$13,$7c,$13,$20,$21,$21,$21,$21,$21,$21,$21,$44,$21,$21,$21,$21,$21,$21,$23,$33,$3f,$15,$12,$00,$00,$00,$00,$5c,$56,$6a,$00
.byte $13,$13,$75,$13,$20,$21,$21,$21,$21,$21,$21,$21,$44,$21,$21,$21,$21,$21,$21,$24,$34,$21,$21,$12,$00,$00,$00,$00,$55,$56,$9a,$00
.byte $13,$13,$84,$13,$20,$21,$21,$21,$21,$21,$21,$21,$45,$21,$21,$21,$48,$15,$15,$14,$11,$15,$21,$12,$00,$00,$00,$54,$56,$56,$aa,$00
.byte $13,$13,$65,$13,$20,$21,$21,$21,$21,$21,$21,$21,$46,$21,$21,$21,$4a,$21,$15,$14,$11,$15,$15,$12,$00,$00,$00,$00,$52,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$57,$56,$aa,$00

.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$14,$11,$15,$21,$12,$00,$31,$31,$31,$58,$56,$ff,$9a
.byte $13,$13,$75,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$42,$21,$21,$21,$14,$11,$15,$15,$12,$00,$31,$31,$00,$5d,$56,$ff,$5a
.byte $13,$13,$6e,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$43,$21,$21,$21,$14,$11,$3e,$15,$12,$00,$00,$00,$31,$58,$56,$ff,$5a
.byte $13,$13,$7f,$13,$20,$21,$21,$21,$21,$21,$21,$21,$42,$21,$21,$44,$21,$21,$21,$14,$11,$3f,$15,$12,$00,$00,$00,$31,$58,$56,$ff,$aa
.byte $13,$13,$6e,$13,$20,$21,$21,$21,$21,$21,$21,$21,$44,$21,$21,$45,$21,$21,$21,$22,$32,$15,$15,$12,$00,$00,$00,$31,$58,$56,$ff,$56
.byte $13,$13,$75,$13,$20,$21,$21,$21,$21,$21,$21,$21,$45,$21,$21,$46,$21,$21,$21,$26,$36,$15,$15,$12,$00,$00,$00,$51,$58,$56,$ff,$9a
.byte $13,$13,$84,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$27,$37,$15,$15,$12,$00,$00,$00,$00,$58,$56,$ff,$59
.byte $13,$13,$61,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$28,$38,$15,$15,$12,$00,$00,$00,$00,$55,$56,$ff,$5a
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$57,$56,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$47,$21,$21,$21,$48,$21,$21,$22,$32,$3e,$15,$12,$00,$00,$00,$00,$52,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$42,$21,$21,$21,$4a,$21,$21,$23,$33,$4e,$15,$12,$00,$00,$00,$00,$53,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$43,$21,$21,$21,$21,$21,$21,$24,$34,$3f,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$7c,$13,$20,$21,$21,$21,$21,$21,$21,$21,$44,$21,$21,$21,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$6c,$13,$20,$21,$21,$21,$21,$21,$21,$21,$45,$21,$21,$21,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$78,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$7b,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$59,$56,$aa,$00
.byte $13,$13,$6e,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$14,$11,$15,$15,$12,$00,$62,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$84,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$29,$39,$15,$15,$12,$00,$00,$00,$00,$59,$56,$aa,$00
.byte $13,$13,$60,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$15,$1f,$2a,$3a,$3d,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$60,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$48,$21,$15,$2d,$2a,$3a,$3c,$15,$12,$00,$00,$00,$00,$5b,$56,$aa,$00
.byte $13,$13,$60,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$49,$21,$21,$2f,$2a,$3a,$3d,$21,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$49,$21,$21,$21,$28,$3b,$3e,$21,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$49,$21,$21,$21,$14,$11,$4e,$21,$12,$00,$00,$00,$51,$58,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$4a,$21,$21,$21,$14,$11,$21,$15,$12,$00,$00,$00,$51,$58,$56,$aa,$00
.byte $13,$13,$76,$13,$20,$21,$21,$21,$21,$21,$21,$21,$42,$21,$21,$21,$21,$21,$15,$29,$39,$15,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$72,$13,$20,$21,$21,$21,$21,$21,$21,$21,$44,$21,$21,$21,$21,$15,$2c,$2a,$3a,$3e,$21,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$7c,$13,$20,$21,$21,$21,$21,$21,$21,$21,$43,$21,$21,$21,$21,$21,$2e,$2a,$3a,$4e,$21,$12,$00,$00,$00,$51,$58,$56,$aa,$00
.byte $13,$13,$7c,$13,$20,$21,$21,$21,$21,$21,$21,$21,$44,$21,$21,$21,$21,$21,$1f,$2a,$3a,$3f,$15,$12,$00,$00,$00,$00,$5d,$56,$aa,$00
.byte $13,$13,$75,$13,$20,$21,$21,$21,$21,$21,$21,$21,$44,$21,$21,$21,$21,$21,$15,$28,$3b,$3f,$21,$12,$00,$00,$00,$00,$57,$56,$aa,$00
.byte $13,$13,$84,$13,$20,$21,$21,$21,$21,$21,$21,$21,$45,$21,$21,$21,$48,$21,$15,$14,$11,$15,$21,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$65,$13,$20,$21,$21,$21,$21,$21,$21,$21,$46,$21,$21,$21,$4a,$21,$15,$14,$11,$15,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00

.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$14,$11,$15,$21,$12,$00,$31,$31,$31,$58,$56,$ff,$9a
.byte $13,$13,$75,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$15,$21,$21,$21,$14,$11,$15,$15,$12,$00,$31,$31,$00,$58,$56,$ff,$5a
.byte $13,$13,$6e,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$15,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$31,$58,$56,$ff,$5a
.byte $13,$13,$7f,$13,$20,$21,$21,$21,$21,$21,$21,$21,$15,$21,$21,$15,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$31,$54,$56,$ff,$59
.byte $13,$13,$6e,$13,$20,$21,$21,$21,$21,$21,$21,$21,$15,$21,$21,$15,$21,$21,$21,$14,$11,$3e,$15,$12,$00,$00,$00,$31,$54,$56,$ff,$56
.byte $13,$13,$75,$13,$20,$21,$21,$21,$21,$21,$21,$42,$15,$21,$21,$15,$21,$21,$21,$14,$11,$4e,$15,$12,$00,$00,$00,$51,$58,$56,$ff,$5a
.byte $13,$13,$84,$13,$20,$21,$21,$21,$21,$21,$21,$43,$21,$21,$21,$21,$21,$21,$21,$14,$11,$4e,$15,$12,$00,$00,$00,$00,$58,$56,$ff,$59
.byte $13,$13,$61,$13,$20,$21,$21,$21,$21,$21,$21,$44,$21,$21,$21,$21,$21,$21,$21,$14,$11,$3f,$15,$12,$00,$00,$00,$00,$58,$56,$ff,$5a
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$45,$21,$21,$21,$21,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$47,$15,$21,$21,$21,$15,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$53,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$15,$21,$21,$21,$15,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$15,$21,$21,$21,$21,$21,$21,$14,$11,$15,$15,$12,$00,$00,$00,$00,$57,$56,$aa,$00
.byte $13,$13,$7c,$13,$20,$21,$21,$21,$21,$21,$21,$21,$15,$21,$21,$21,$21,$21,$21,$29,$39,$15,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$6c,$13,$20,$21,$21,$21,$21,$21,$48,$21,$15,$21,$21,$21,$21,$1d,$1e,$2a,$3a,$3c,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$78,$13,$20,$21,$21,$21,$21,$21,$49,$21,$21,$21,$21,$21,$21,$21,$21,$2b,$3b,$3e,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$7b,$13,$20,$21,$21,$21,$21,$21,$4a,$21,$21,$21,$21,$21,$21,$21,$21,$14,$11,$4e,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$6e,$13,$20,$21,$21,$21,$21,$15,$48,$21,$21,$21,$21,$21,$21,$21,$21,$14,$11,$4e,$15,$12,$00,$63,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$84,$13,$20,$21,$21,$21,$21,$21,$49,$21,$21,$21,$21,$21,$21,$21,$21,$14,$11,$3f,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$60,$13,$20,$21,$21,$21,$21,$21,$4a,$21,$21,$21,$21,$21,$21,$15,$15,$14,$11,$15,$15,$12,$00,$00,$00,$00,$59,$56,$aa,$00
.byte $13,$13,$60,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$15,$21,$15,$15,$14,$11,$15,$15,$12,$00,$00,$00,$00,$59,$56,$aa,$00
.byte $13,$13,$60,$13,$20,$21,$21,$21,$21,$21,$21,$21,$15,$21,$21,$15,$21,$21,$15,$14,$11,$15,$21,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$42,$21,$21,$21,$15,$21,$21,$21,$29,$39,$15,$21,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$43,$21,$21,$21,$15,$21,$21,$2c,$2a,$3a,$3c,$21,$12,$00,$00,$00,$50,$58,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$44,$15,$21,$21,$15,$21,$21,$2d,$2a,$3a,$3e,$15,$12,$00,$00,$00,$50,$58,$56,$aa,$00
.byte $13,$13,$76,$13,$20,$21,$21,$21,$21,$21,$21,$45,$15,$21,$21,$21,$21,$21,$15,$2b,$3b,$3f,$15,$12,$00,$00,$00,$00,$54,$56,$aa,$00
.byte $13,$13,$72,$13,$20,$21,$21,$21,$21,$21,$21,$46,$15,$21,$21,$21,$21,$15,$15,$14,$11,$3f,$21,$12,$00,$00,$00,$00,$59,$56,$aa,$00
.byte $13,$13,$7c,$13,$20,$21,$21,$21,$21,$21,$21,$21,$15,$21,$21,$21,$21,$21,$15,$14,$11,$15,$21,$12,$00,$00,$00,$51,$58,$56,$aa,$00
.byte $13,$13,$7c,$13,$20,$21,$21,$21,$21,$21,$21,$21,$15,$21,$21,$21,$21,$21,$15,$14,$11,$15,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$75,$13,$20,$21,$21,$21,$21,$21,$21,$21,$15,$21,$21,$21,$21,$21,$15,$14,$11,$15,$21,$12,$00,$00,$00,$00,$5d,$56,$aa,$00
.byte $13,$13,$84,$13,$20,$21,$21,$21,$21,$21,$21,$21,$15,$21,$21,$21,$15,$21,$15,$14,$11,$15,$21,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$65,$13,$20,$21,$21,$21,$21,$21,$21,$21,$15,$21,$21,$21,$15,$15,$15,$14,$11,$15,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00
.byte $13,$13,$13,$13,$20,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$21,$22,$32,$15,$15,$12,$00,$00,$00,$00,$58,$56,$aa,$00

AttributeData:
.byte $ff,$aa,$aa,$aa,$9a,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$5a,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$5a,$00,$00,$00
.byte $ff,$aa,$aa,$6a,$a6,$00,$00,$00
.byte $ff,$aa,$aa,$9a,$59,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$5a,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$9a,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$5a,$00,$00,$00

.byte $ff,$aa,$aa,$5a,$9a,$00,$00,$00
.byte $ff,$aa,$aa,$9a,$5a,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$5a,$00,$00,$00
.byte $ff,$aa,$aa,$6a,$56,$00,$00,$00
.byte $ff,$aa,$aa,$9a,$59,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$5a,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$5a,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$5a,$00,$00,$00

.byte $ff,$aa,$aa,$aa,$9a,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$5a,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$5a,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$aa,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$56,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$9a,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$59,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$5a,$00,$00,$00

.byte $ff,$aa,$aa,$aa,$9a,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$5a,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$5a,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$59,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$56,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$5a,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$59,$00,$00,$00
.byte $ff,$aa,$aa,$aa,$5a,$00,$00,$00

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Here we add the CHR-ROM data, included from an external .CHR file
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "CHARS"
.incbin "atlantico.chr"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Vectors with the addresses of the handlers that we always add at $FFFA
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "VECTORS"
.word NMI                    ; Address (2 bytes) of the NMI handler
.word Reset                  ; Address (2 bytes) of the Reset handler
.word IRQ                    ; Address (2 bytes) of the IRQ handler