.segment "RODATA"
.export default_palette

default_palette:
    ; Background Palettes (16 bytes)
    .byte $0f, $27, $21, $30  ; Palette 0 (Black, Dark Blue, Medium Blue, Crisp White)
    .byte $0f, $06, $16, $26  ; Palette 1 (Black, Dark Red, Medium Red, Light Red)
    .byte $0f, $09, $19, $29  ; Palette 2 (Black, Dark Green, Medium Green, Light Green)
    .byte $0f, $0C, $1C, $2C  ; Palette 3 (Black, Dark Cyan, Medium Cyan, Bright Cyan)

    ; Sprite Palettes (16 bytes)
    .byte $0f, $16, $27, $37  ; Palette 4
    .byte $0f, $12, $22, $32  ; Palette 5
    .byte $0f, $15, $25, $35  ; Palette 6
    .byte $0f, $04, $14, $24  ; Palette 7