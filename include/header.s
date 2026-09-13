.segment "HEADER"
.byte "NES", $1A   ; Magic identifier header
.byte 2            ; PRG-ROM size in 16KB units (32KB total)
.byte 0            ; CHR-ROM size in 8KB units (8KB total)
.byte $01          ; Mapper 0 (NROM), Vertical Mirroring
.byte $00          ; Mapper high nibble
.res 8, $00        ; Reserved zero-padding