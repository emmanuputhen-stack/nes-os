.segment "RODATA"
.export NameTable_Hi, NameTable_Lo

; High byte of PPU address for each row (0-29) in Nametable $2000
NameTable_Hi:
    .byte $20, $20, $20, $20, $20, $20, $20, $20
    .byte $21, $21, $21, $21, $21, $21, $21, $21
    .byte $22, $22, $22, $22, $22, $22, $22, $22
    .byte $23, $23, $23, $23, $23, $23

; Low byte of PPU address for each row (0-29) stepping by 32 bytes ($00, $20, $40...)
NameTable_Lo:
    .byte $00, $20, $40, $60, $80, $A0, $C0, $E0
    .byte $00, $20, $40, $60, $80, $A0, $C0, $E0
    .byte $00, $20, $40, $60, $80, $A0, $C0, $E0
    .byte $00, $20, $40, $60, $80, $A0

; ASCII code to CHR tile index lookup table (256 bytes)
