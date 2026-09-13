.export clear_nametable, ppu_update, ppu_off, os_drawUI, os_printblock, load_font, load_palette

.import NameTable_Hi, NameTable_Lo
.include "zp_const.inc"
.segment "CODE"

 sys_vram_flush:
    lda PPU_CONTROL_SHADOW
    pha 
    bmi @nmi_already_on
    
    jsr sys_nmi_on
   @nmi_already_on:
    lda #1
    sta nmi_ready
   @loop:
    lda nmi_ready
    bne @loop
       
    pla
    bpl @turn_off_nmi
    rts
    
  @turn_off_nmi:
    jmp sys_nmi_off
    
 sys_render_on:
   @wait_vblank:
    bit PPU_STATUS          ; Read $2002 (Bit 7 = VBlank)
    bpl @wait_vblank

    bit PPU_STATUS          ; Clear address latch toggle
    lda #$20                ; Nametable $2000
    sta PPU_VRAM_ADDRESS2   ; Write $2006 (High byte)
    lda #$00
    sta PPU_VRAM_ADDRESS2   ; Write $2006 (Low byte)
    sta PPU_VRAM_ADDRESS1   ; Scroll X = 0 ($2005)
    sta PPU_VRAM_ADDRESS1   ; Scroll Y = 0 ($2005)

    lda #%00011110      ; Turn ON background and sprites   
    sta PPU_MASK          
    rts

 sys_render_off:
    lda PPU_CONTROL_SHADOW
    bpl @force_off
    
    lda #2
    sta nmi_ready
  @loop:
    lda nmi_ready
    bne @loop
    rts
  @force_off:
  @wait_vblank_off:
    bit PPU_STATUS          ; Read $2002
    bpl @wait_vblank_off    ; Sync to VBlank before turning off
    lda #00
    sta PPU_MASK
    rts
 
 sys_nmi_off:
    lda PPU_CONTROL_SHADOW
    and #%01111111          ; Clear Bit 7 ($80)
    sta PPU_CONTROL_SHADOW  ; Keep shadow in RAM updated
    sta PPU_CONTROL         ; Write to $2000
    rts
    
 sys_nmi_on:
    lda PPU_CONTROL_SHADOW
    ora #%10000000          ; Set Bit 7 ($80)
    sta PPU_CONTROL_SHADOW
    sta PPU_CONTROL         ; Write to $2000
    rts      
    
    
 clear_nametable:
    tay ;Temp saving Nametable Hi byte
    lda PPU_STATUS
    tya
    sta PPU_VRAM_ADDRESS2
    lda #$00
    sta PPU_VRAM_ADDRESS2
    
    lda #$0  ;Space character
    ldx #4
    ldy #0
  @clear_loop:
    sta PPU_VRAM_IO
    iny
    bne @clear_loop

    dex
    bne @clear_loop
    rts

 
 sys_drawUI:
   ;A contain Screen No
   ldx #$20 
   cmp #0 ;If nametable 0 or 1
   beq :+
       ldx #$24
       :
   ldy #0
   sty PPU_MASK ;Forced blank (Render Off)
   lda PPU_STATUS
   stx PPU_VRAM_ADDRESS2
   sty PPU_VRAM_ADDRESS2

   ldx #4    
   @loop32: ;(32*4)*8=1024
       lda (CHR_LO),y
       sta PPU_VRAM_IO
       iny
       lda (CHR_LO),y
       sta PPU_VRAM_IO
       iny
       lda (CHR_LO),y
       sta PPU_VRAM_IO
       iny
       lda (CHR_LO),y
       sta PPU_VRAM_IO
       iny
       lda (CHR_LO),y
       sta PPU_VRAM_IO
       iny
       lda (CHR_LO),y
       sta PPU_VRAM_IO
       iny
       lda (CHR_LO),y
       sta PPU_VRAM_IO
       iny
       lda (CHR_LO),y
       sta PPU_VRAM_IO
       iny
       bne @loop32
   inc CHR_HI
   dex
   bne @loop32
   
   lda #%00011110         ; rendering back on 
   sta PPU_MASK
   rts
   
   
sys_printblock:

    lda #<CHR_BUFF
    sta CHR_LO
    lda #>CHR_BUFF
    sta CHR_HI

    lda HEIGHT
    sta ROW_COUNTER

    lda #252 ;(255-3)-width if crossed stop
    sec
    sbc WIDTH
    sta LIMIT
    
    ldx USER_ROW
    lda NameTable_Hi,x
    sta PPU_HI

    lda NameTable_Lo,x
    clc
    adc USER_COLUMN
    sta PPU_LO

    ldy #0
    ldx #0

  @write_header:
    lda PPU_HI
    sta CHR_BUFF,x
    inx

    lda PPU_LO
    sta CHR_BUFF,x
    inx

    lda WIDTH
    sta CHR_BUFF,x
    inx

  @init_counter:
    lda WIDTH
    sta COL_COUNTER

  @store_index_loop:
    lda (SRC_LO),y
    iny
    cmp #EOL
    beq @eol_resolver
    cmp #EOF               ; End of file
    beq @eof_resolver
  
    sec
    sbc #$20
    sta CHR_BUFF,x
    inx

    dec COL_COUNTER
    bne @store_index_loop
  @check_limit:
    cpx LIMIT
    bcs @page_end
    
  @calc_header:
    dec ROW_COUNTER
    beq @store_sential
    lda PPU_LO
    clc
    adc #32
    sta PPU_LO

    lda PPU_HI
    adc #0
    sta PPU_HI
    jmp @write_header

  @eol_resolver:
    lda SPACE_INDEX
    sta CHR_BUFF,x
    inx
    dec COL_COUNTER
    bne @eol_resolver
    jmp @check_limit

  @eof_resolver:
    lda SPACE_INDEX
    sta CHR_BUFF,x
    inx
    dec COL_COUNTER
    bne @eof_resolver
    dey
    jmp @check_limit
    
  @store_sential:
    lda #$FF
    sta CHR_BUFF,x
    
    jsr sys_vram_flush
    rts
    
  @page_end:
    lda #$FF
    sta CHR_BUFF,x
    inx
    
    jsr sys_vram_flush
    
    tya
    clc
    adc SRC_LO
    sta SRC_LO
    bcc :+
        inc SRC_HI
        :
    ldy #0
    ldx #0
    jmp @calc_header


 load_font:
    lda #$00
    sta PPU_MASK    ;Taking Precaution by turning off render
     
    lda PPU_STATUS
    lda #$00
    sta PPU_VRAM_ADDRESS2
    sta PPU_VRAM_ADDRESS2
 
    ldx #96
    ldy #0
  @plane_1:  
    lda (SRC_LO),Y
    sta PPU_VRAM_IO
    iny
    cpy #8
    bne @plane_1

    lda #0
    ldy #8
  @plane_2:
    sta PPU_VRAM_IO
    dey
    bne @plane_2

    clc
    lda #8
    adc SRC_LO
    sta SRC_LO
    bcc :+
        inc SRC_HI
        :
  
    dex 
    bne @plane_1
    rts

load_palette:
    ldy #$00
    sty PPU_MASK    ;Taking Precaution by turning off render
    
    lda PPU_STATUS
    lda #$3F
    sta PPU_VRAM_ADDRESS2
    lda #$00
    sta PPU_VRAM_ADDRESS2
  @load_ppu_palette:
    lda (SRC_LO),Y
    sta PPU_VRAM_IO
    iny
    cpy #32
    bcc @load_ppu_palette
    rts
    
    
 init_sys_font:
    lda #<sys_font_path
    sta path_lo
    lda #>sys_font_path
    sta path_hi
    
    jsr path_resolve
    bmi @no_custom_font
    
    lda cluster_lo
    sta font_cluster_lo
    lda cluster_hi
    sta font_cluster_hi
    
  @custom_font_found:  
    jsr load_sd_font
    bmi @sd_failed
    
    lda sys_flags
    ora #custom_font
    sta sys_flags
    rts
  @sd_failed: ;early exit due to corrupted sd
    jsr load_rom_font
  @no_custom_font:  
    lda sys_flags
    and #~custom_font
    sta sys_flags
    rts
         
    
 restore_sys_font: 
    lda sys_flags
    and #dirty_font 
    beq @done     ;font clean?
    
    lda sys_flags  ;clearing font dirty flag
    and #~dirty_font
    sta sys_flags
    
    lda sys_flags
    and #custom_font
    beq @restore_rom_font
  
  @restore_sd_font:
    lda font_cluster_hi
    sta cluster_hi
    lda font_cluster_lo
    sta cluster_lo
    
    jsr load_sd_font
    beq @done
    
  @restore_rom_font:
    jsr load_rom_font
  @done:   
    rts
    
      


 load_sd_font:
    jsr ClusterToLBA 
    
    lda sec_per_clus
    sta sector_remain 
    
    lda #<sd_buff
    sta buff_lo
    lda #>sd_buff
    sta buff_hi
    
    lda #$00
    sta PPU_MASK    ;Taking Precaution by turning off render
     
    lda PPU_STATUS
    lda #$00
    sta PPU_VRAM_ADDRESS2
    sta PPU_VRAM_ADDRESS2
    
    lda #3
    sta LIMIT
  @sector_loop: 
    jsr sd_read_block
    bmi @load_failed
    
    ldy #0
   @page_1:
    lda sd_buff,y
    sta PPU_VRAM_IO
    iny
    bne @page_1
    
    ldy #0
   @page_2:
    lda sd_buff+256,y
    sta PPU_VRAM_IO
    iny
    bne @page_2
    
    dec LIMIT
    beq @load_done
    
    jsr advance_sector
    bcs @sector_loop
  @load_failed:  
    lda #$ff ;fail flag
    rts 
  @load_done:
    lda #00 ;success flag
    rts    
    
 load_rom_font:
    lda #<default_font
    sta SRC_LO
    lda #>default_font
    sta SRC_HI

    jsr load_font
    rts
    
      
 init_sys_palette:
    lda #<sys_palette_path
    sta path_lo
    lda #>sys_palette_path
    sta path_hi
    
    jsr path_resolve
    bmi @default_palette
    
  @custom_palette:
    jsr ClusterToLBA 
    
    lda #<sd_buff
    sta buff_lo
    lda #>sd_buff
    sta buff_hi
    
    jsr sd_read_block
    bmi @sd_failed
    
    ldy #0
  @copy_palette:
    lda sd_buff,y
    sta palette_buff,y
    iny
    cpy #32
    bne @copy_palette
    
    jmp load_sys_palette
    
  @sd_failed:
    ldy #0
   @copy_loop: 
    lda rom_palette,y
    sta palette_buff,y
    iny
    cpy #32
    bne @copy_loop
    
    jmp load_sys_palette  
    
  @default_palette:
    ldy #0
   @copy_loop: 
    lda rom_palette,y
    sta palette_buff,y
    iny
    cpy #32
    bne @copy_loop
    rts
 
 load_rom_palette:
    lda #<rom_palette
    sta SRC_LO
    lda #>rom_palette
    sta SRC_HI   
    jsr load_palette
    rts
    
 load_sys_palette: 
    lda #<palette_buff
    sta SRC_LO
    lda #>palette_buff
    sta SRC_HI
    
    jsr load_palette
    rts
    
        