.include "zp_const.inc"
.import kernal_boot

.segment "VECTORS"
.word nmi
.word reset
.word irq


.segment "CODE"
irq:
    rti
    
    
    
.segment "CODE"
.proc reset
  sei                   
  lda #0
  sta PPU_CONTROL       
  sta PPU_MASK          
  sta APU_DM_CONTROL    
  lda #$40
  sta JOYPAD2           

  cld ;Disable decimal mode
  ldx #$FF
  txs
  bit PPU_STATUS
wait_vblank:
    bit PPU_STATUS
    bpl wait_vblank
    
  lda #0
  ldx #0
clear_ram:
    sta $0000,x
    sta $0100,x
    sta $0200,x
    sta $0300,x
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    inx
    bne clear_ram
    
lda #255
    ldx #0
clear_oam:
    sta oam,x
    inx
    inx
    inx
    inx
    bne clear_oam
    
wait_vblank2:
    lda PPU_STATUS
    bpl wait_vblank2

    lda #%10001000
    sta PPU_CONTROL
 
    lda #%10001000 
    sta PPU_CONTROL_SHADOW
    sta PPU_CONTROL 
    lda PPU_STATUS
    lda #$3F                  
    sta PPU_VRAM_ADDRESS2
    stx PPU_VRAM_ADDRESS2
    ldx #0                    
    loop:
       lda palette, x
       sta PPU_VRAM_IO
       inx
       cpx #32
       bcc loop

 
    jmp kernal_boot
.endproc



.segment "CODE"
.proc nmi
;Save all reg
  pha
  txa
  pha
  tya
  pha
 
 
    ;OAM update
  ldx #0
  stx PPU_SPRRAM_ADDRESS
  lda #>oam
  sta SPRITE_DMA
   
  lda nmi_ready
  bne :+
    jmp ppu_update_end
  :
  cmp #2
  bne cont_render
    lda #%00000000
    sta PPU_MASK
    ldx #0
    stx nmi_ready
    jmp ppu_update_end
cont_render:
  ldy #0
  header_loop:
   cpy #220 ;255-(32+3)=220
   bcc :+
       clc
       tya
       adc CHR_LO
       sta CHR_LO
       lda CHR_HI
       adc #0
       sta CHR_HI
       ldy #0
    :
   lda PPU_STATUS
   lda (CHR_LO),y
   bpl :+
       jmp cpy_done
       :
   sta PPU_VRAM_ADDRESS2
   
   iny
   lda (CHR_LO),y
   sta PPU_VRAM_ADDRESS2
    
   iny
   lda (CHR_LO),y
   iny      ;inc to next byte
   tax      ;temp saving A
   and #%00011111     ;get length
   sta LEN
   txa      ;restore A
   and #%11000000     ;get flags
   asl      ;get fill mode flag as carry
   beq set_horizontal
       lda PPU_CONTROL_SHADOW
       ora #%00000100
       jmp apply
    set_horizontal:
       lda PPU_CONTROL_SHADOW
       and #%11111011
    apply:
       sta PPU_CONTROL_SHADOW
       sta PPU_CONTROL
    bcc :+
        jmp fill_handler
        :
    
literal_handler:
    ldx LEN
    beq literal_480
    
 literal_n:
    copy_loop:
       lda (CHR_LO),Y
       sta PPU_VRAM_IO
       iny
       dex
       bne copy_loop
    jmp header_loop
 literal_480:
    clc
    tya
    adc CHR_LO
    sta CHR_LO
    bcc :+
        inc CHR_HI
        :
    ldy #0  ;(32*8)+(28*8)=480
    loop32:
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
       bne loop32
    inc CHR_HI
    
    ldx #28
    loop28:
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
       dex
       bne loop28

    jmp header_loop
fill_handler:
    ldx LEN
    beq fill_960
   
 fill_n:
    lda (CHR_LO),Y
    fill_loop:
       sta PPU_VRAM_IO
       dex
       bne fill_loop
    iny
    jmp header_loop
 fill_960:
     ldx #60
     lda (CHR_LO),Y
     iny
     loop_60:
       sta PPU_VRAM_IO
       sta PPU_VRAM_IO
       sta PPU_VRAM_IO
       sta PPU_VRAM_IO
       sta PPU_VRAM_IO
       sta PPU_VRAM_IO
       sta PPU_VRAM_IO
       sta PPU_VRAM_IO
       sta PPU_VRAM_IO
       sta PPU_VRAM_IO
       sta PPU_VRAM_IO
       sta PPU_VRAM_IO
       sta PPU_VRAM_IO
       sta PPU_VRAM_IO
       sta PPU_VRAM_IO
       sta PPU_VRAM_IO
       dex
       bne loop_60
     jmp header_loop
  
cpy_done:   

    lda PPU_CONTROL_SHADOW  
    and #%11111011
    sta PPU_CONTROL_SHADOW  ; <-- Fix: Update shadow in RAM too!
    sta PPU_CONTROL

    lda PPU_STATUS
    lda #$20                ; High byte of Nametable $2000
    sta PPU_VRAM_ADDRESS2   ; Reset $2006 latch
    lda #$00                ; Low byte
    sta PPU_VRAM_ADDRESS2   ; Reset $2006 address to top-left of screen

    sta PPU_VRAM_ADDRESS1   ; Scroll X = 0 ($2005)
    sta PPU_VRAM_ADDRESS1
    
    lda #%00011110
    sta PPU_MASK
                     
    ldx #0
    stx nmi_ready
    
  
ppu_update_end:
    pla
    tay
    pla
    tax
    pla
    rti
.endproc