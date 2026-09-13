
                             ;SD CARD 

; Hardware ports & masks
out_port       = $6000
out_port_copy  = $00
cs_low_mask    = %11111110
cs_high_mask   = %00000001
in_port        = $6001
miso_mask      = %00000001
sck_high_mask  = %00000010
sck_low_mask   = %11111101
mosi_high_mask = %00000100
mosi_low_mask  = %11111011

; Constants
R1            = $01
R7            = $07
CMD0          = $40
CMD0_CRC      = $95
CMD8          = $48
CMD8_CRC      = $87
CMD17         = $51
CMD17_CRC     = $01
CMD24         = $58
CMD24_CRC     = $01
CMD55         = $77
CMD55_CRC     = $01
ACMD41        = $69
ACMD41_CRC    = $01
echo_pattern  = $AA
idle_state    = $01
active_state  = $00
data_accepted = $05
sd_write_fail = $FF
ENTRY_REC     = $20
timeout_low   = $00
timeout_high  = $10
timeout_lo    = $00
timeout_hi    = $10
                         ;PPU

; Define PPU Registers
PPU_CONTROL = $2000              
PPU_MASK = $2001                 
PPU_STATUS = $2002               
PPU_SPRRAM_ADDRESS = $2003      
PPU_SPRRAM_IO = $2004            
PPU_VRAM_ADDRESS1 = $2005        
PPU_VRAM_ADDRESS2 = $2006        
PPU_VRAM_IO = $2007              
SPRITE_DMA = $4014

; Define APU Registers
APU_DM_CONTROL = $4010           
APU_CLOCK = $4015                
  
; Joystick/Controller values
JOYPAD1 = $4016                  
JOYPAD2 = $4017                  

PPU_CONTROL_SHADOW = $10
LEN = $11

EOL         = $0A       ; End of Line (ASCII linefeed or custom code)
EOF         = $FF       ; End of File / String Terminator
SPACE_INDEX = $00

; ==============================================================================
; ZERO PAGE VARIABLES ($0000 - $00FF)
; ==============================================================================
sd_status        = $00
arg_0            = $01
arg_1            = $02
arg_2            = $03
arg_3            = $04
cmd_byte         = $05
crc_byte         = $06
resp_byte        = $07
resp_type        = $08
temp_byte        = $09
buff_lo          = $0A
buff_hi          = $0B
temp_0           = $0C
temp_1           = $0D
temp_2           = $0E
temp_3           = $0F
temp_lo          = $10
temp_hi          = $11
temp             = $12
cluster_lo       = $13
cluster_hi       = $14
list_lo          = $15
list_hi          = $16
item_cluster_lo  = $17
item_cluster_hi  = $18
des_lo           = $19
des_hi           = $1A
size             = $1B  ; 4 bytes ($1B-$1E)
sector_remain    = $1F
target_name      = $20  ; 11 bytes ($20-$2A)
part_ofs         = $2B  ; 4 bytes ($2B-$2E)
res_sectors      = $2F  ; 2 bytes ($2F-$30)
sec_per_clus     = $31
num_fats         = $32
max_root_ent     = $33  ; 2 bytes ($33-$34)
sec_per_fat      = $35  ; 2 bytes ($35-$36)
fat_start        = $37  ; 4 bytes ($37-$3A)
root_start       = $3B  ; 4 bytes ($3B-$3E)
data_start       = $3F  ; 4 bytes ($3F-$42)

nmi_ready        = $43
CHR_LO           = $44
CHR_HI           = $45
PPU_HI           = $46
PPU_LO           = $47
ROW_COUNTER      = $48
COL_COUNTER      = $49
LIMIT            = $4A
Y_TEMP           = $4B
SRC_LO           = $4C
SRC_HI           = $4D
HEIGHT           = $4E
WIDTH            = $4F
USER_ROW         = $50
USER_COLUMN      = $51

; ==============================================================================
; MAIN RAM BUFFERS ($0200 - $07FF)
; ==============================================================================
oam              = $0200  ; 256 bytes ($0200 - $02FF) reserved for Sprite DMA
palette          = $0300  ; 32 bytes  ($0300 - $031F)
CHR_BUFF         = $0320  ; 256 bytes ($0320 - $041F)
sd_buff          = $0420  ; 512 bytes ($0420 - $061F)