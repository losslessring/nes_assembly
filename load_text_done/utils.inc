.macro PPU_SETADDR addr
    bit PPU_STATUS           ; Read from PPU_STATUS to reset my address latch
    lda #>addr               ; Fetch the hi-byte from 16-bit address
    sta PPU_ADDR             ; Store the hi-byte into PPU_ADDR $2006
    lda #<addr               ; Fetch the lo-byte from 16-bit address
    sta PPU_ADDR             ; Store the lo-byte into PPU_ADDR $2006
.endmacro

.macro PPU_SETDATA val
    lda val
    sta PPU_DATA             ; Send value to PPU register $2007
.endmacro
