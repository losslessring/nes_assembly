;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Constants for PPU registers mapped from addresses $2000 to $2007
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
PPU_CTRL   = $2000
PPU_MASK   = $2001
PPU_STATUS = $2002
OAM_ADDR   = $2003
OAM_DATA   = $2004
PPU_SCROLL = $2005
PPU_ADDR   = $2006
PPU_DATA   = $2007

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; The iNES header (contains a total of 16 bytes with the flags at $7F00)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "HEADER"
.byte $4E,$45,$53,$1A        ; 4 bytes with the characters 'N','E','S','\n'
.byte $02                    ; How many 16KB of PRG-ROM we'll use (=32KB)
.byte $01                    ; How many 8KB of CHR-ROM we'll use (=8KB)
.byte %00000000              ; Horz mirroring, no battery, mapper 0
.byte %00000000              ; mapper 0, playchoice, NES 2.0
.byte $00                    ; No PRG-RAM
.byte $00                    ; NTSC TV format
.byte $00                    ; Extra flags for TV format and PRG-RAM
.byte $00,$00,$00,$00,$00    ; Unused padding to complete 16 bytes of header

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; PRG-ROM code located at $8000
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "CODE"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Reset handler (called when the NES resets or powers on)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
Reset:
    sei                      ; Disable all IRQ interrupts
    cld                      ; Clear decimal mode (not supported by the NES)
    ldx #$FF
    txs                      ; Initialize the stack pointer at address $FF

    inx                      ; Increment X, causing a rolloff from $FF to $00
    txa                      ; A = 0
ClearRAM:
    sta $0000,x              ; Zero RAM addresses from $0000 to $00FF
    sta $0100,x              ; Zero RAM addresses from $0100 to $01FF
    sta $0200,x              ; Zero RAM addresses from $0200 to $02FF
    sta $0300,x              ; Zero RAM addresses from $0300 to $03FF
    sta $0400,x              ; Zero RAM addresses from $0400 to $04FF
    sta $0500,x              ; Zero RAM addresses from $0500 to $05FF
    sta $0600,x              ; Zero RAM addresses from $0600 to $06FF
    sta $0700,x              ; Zero RAM addresses from $0700 to $07FF
    inx
    bne ClearRAM

Main:
    ldx #$3F
    stx PPU_ADDR             ; Set hi-byte of PPU_ADDR to $3F
    ldx #$00
    stx PPU_ADDR             ; Set lo-byte of PPU_ADDR to $00
    lda #$2A
    sta PPU_DATA             ; Send $2A (lime-green color code) to PPU_DATA
    lda #%00011110
    sta PPU_MASK             ; Set PPU_MASK bits to show background and sprites

LoopForever:
    jmp LoopForever

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; NMI interrupt handler
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
NMI:
    rti                      ; Return from interrupt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; IRQ interrupt handler
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
IRQ:
    rti                      ; Return from interrupt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Vectors with the addresses of the handlers that we always add at $FFFA
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "VECTORS"
.word NMI                    ; Address (2 bytes) of the NMI handler
.word Reset                  ; Address (2 bytes) of the Reset handler
.word IRQ                    ; Address (2 bytes) of the IRQ handler