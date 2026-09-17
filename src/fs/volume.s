read_mbr:
    ; need to read sector 0
    lda #0
    sta arg_0
    sta arg_1
    sta arg_2
    sta arg_3
  
    ;  Passing a temp buffer ptr
    lda #<sd_buff
    sta buff_lo
    lda #>sd_buff
    sta buff_hi
 
    ;  Call sd_read_block to write sector0 to temp buffer
    jsr sd_read_block 
    bcc  :+
         rts
    :
  
    ;  check boot signature
    lda sd_buff+510
    cmp #$55
    bne @format_error
    lda sd_buff+511
    cmp #$aa
    bne @format_error
  
    lda sd_buff+454
    sta part_ofs+0
    lda sd_buff+455
    sta part_ofs+1
    lda sd_buff+456
    sta part_ofs+2
    lda sd_buff+457
    sta part_ofs+3  
     
    lda #ERR_NONE
    clc
    rts
   @format_error:
    sec
    lda #ERR_FORMAT
    rts
    
