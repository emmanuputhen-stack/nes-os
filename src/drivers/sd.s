.export sd_init
.include "zp_const.inc"

.segment "CODE"


LAYER_1:
  cs_low:
    lda out_port_copy
    and #cs_low_mask
    sta out_port_copy
    sta out_port
    rts
  cs_high:
    lda out_port_copy
    ora #cs_high_mask
    sta out_port_copy
    sta out_port
    rts

LAYER_2:
 spi_send_byte:
    sta temp_byte
    ldx #8
 @bit_loop:
    asl temp_byte  
    lda out_port_copy
    bcc @mosi_low
    ora #mosi_high_mask
    bcs @mosi_done
    @mosi_low:
    and #mosi_low_mask
    @mosi_done:
    sta out_port

    ora #sck_high_mask
    sta out_port
    and #sck_low_mask
    sta out_port
   
    dex
    bne @bit_loop
    rts

 spi_recv_byte:
    ldx #8
    lda #0
    sta temp_byte
  @bit_loop:   
    lda out_port_copy  ;Output 0xFF during reciving response while SCK low
    ora #mosi_high_mask   
    sta out_port

    ora #sck_high_mask ;Pull SCK high while reading response
    sta out_port   

    lda  in_port
    and #miso_mask
    cmp #miso_mask
    rol temp_byte
    
    lda out_port_copy 
    and #sck_low_mask 
    sta out_port

    dex
    bne @bit_loop
    lda temp_byte
    rts

LAYER_3:
 spi_send_cmd:
    lda cmd_byte
    jsr spi_send_byte 
    lda arg_0
    jsr spi_send_byte
    lda arg_1
    jsr spi_send_byte 
    lda arg_2
    jsr spi_send_byte
    lda arg_3
    jsr spi_send_byte 
    lda crc_byte
    jsr spi_send_byte
    rts

 spi_read_resp:
    sta resp_type
    ldy #0 ;256 retry
  @retry:
    jsr spi_recv_byte 
    cmp #$FF
    bne @got_response
    dey
    bne @retry
    lda #$FF ;No response error code
    sta  resp_byte
    rts
  @got_response:
    ldy #0
  @resp_loop:
    sta resp_byte,y
    iny
    cpy resp_type
    beq @done
    jsr spi_recv_byte 
    jmp @resp_loop 
 @done:   
    rts

LAYER_4:
 sd_init:
    ;To wakeup sd,pull CS high,send 74 clock cycle with MOSI 1
    jsr cs_high ;Pull CS high  
    ldy #10 ;10*8 = 80 total cycle
    @init_loop:
    lda #$FF ;Put MOSI 1 throughout
    jsr spi_send_byte  ;Do 8 cycle per routine
    dey
    bne @init_loop 
    ;To enter SPI mode,pull CS low,send CMD0 
    jsr cs_low
    lda #CMD0 ;reset cmd
    sta cmd_byte
  
    lda #0  ;no argument
    sta arg_0
    sta arg_1
    sta arg_2
    sta arg_3
     
    lda #CMD0_CRC
    sta crc_byte
    jsr spi_send_cmd 

    lda #R1 ;response type
    jsr spi_read_resp ;Get response
    lda resp_byte+0
    cmp #idle_state
    beq @spi_success 
    jmp @sd_init_fail
  @spi_success:
    jsr cs_high ;pull CS high after completing a command -response series 
    lda #$ff
    jsr spi_send_byte ;send dummy byte
    ;To check voltage compability    
    jsr cs_low
    lda #CMD8 
    sta cmd_byte
  
    lda #0  ;argument 0x000001AA
    sta arg_0
    sta arg_1
    lda #1
    sta arg_2
    lda #$AA
    sta arg_3
     
    lda #CMD8_CRC
    sta crc_byte
    jsr spi_send_cmd 

    ;Get response
    lda #R7 
    jsr spi_read_resp 
    lda resp_byte+0 ;Read first byte
    cmp #idle_state
    beq @check_echo
    jmp @sd_init_fail   
  @check_echo:
    lda resp_byte+4 ;Read 5th byte
    cmp #echo_pattern
    beq @cmd8_success 
    jmp @sd_init_fail
 
  @cmd8_success:
    jsr cs_high
    lda #$ff
    jsr spi_send_byte ;send dummy byte

  ;To init a counter for count retry
    lda #00   ;allows 1024 retries before giveup
    sta timeout_low
    lda #04
    sta timeout_high
    
    ;To init card,Send cmd55 followed by acmd41 in a loop
 @init_card_loop:
    jsr cs_low
    lda #CMD55
    sta cmd_byte
    lda #0 ;no arg
    sta arg_0
    sta arg_1
    sta arg_2
    sta arg_3
     
    lda #CMD55_CRC
    sta crc_byte
    jsr spi_send_cmd 
    
    lda #R1 ;response type
    jsr spi_read_resp ;Get response
    lda resp_byte+0
    cmp #idle_state
    beq @cmd55_success
    jmp @sd_init_fail
  @cmd55_success:
    jsr cs_high
    lda #$ff
    jsr spi_send_byte ;send dummy byte
   
    ; sending ACMD41
    jsr cs_low
    lda #ACMD41
    sta cmd_byte
     lda #$40 ; argument 0x40000000
    sta arg_0
    lda #0
    sta arg_1
    sta arg_2
    sta arg_3
     
    lda #ACMD41_CRC
    sta crc_byte
    jsr spi_send_cmd 
    
    lda #R1 ;response type
    jsr spi_read_resp ;Get response
    lda resp_byte+0
    pha 
    jsr cs_high
    lda #$ff
    jsr spi_send_byte ;send dummy byte
    pla 

    cmp #active_state
    beq @sd_init_success
    cmp #idle_state
    bne @failed_exit
   ; Timeout counter dec
    dec timeout_low
    bne @init_card_loop
    dec timeout_high
    bne @init_card_loop
 
  @failed_exit:
     jmp @sd_init_fail
    
  @sd_init_success:
    lda #0 ;success flag
    rts
  @sd_init_fail:
    lda #$FF ;Failed flag
    rts

sd_read_block:
    jsr cs_low ;Start of transaction
    ;Send cmd17 with sector no as argument
    lda #CMD17
    sta cmd_byte
   ;Assuming caller already put sector no as arg
    lda #CMD17_CRC
    sta crc_byte
    jsr spi_send_cmd 
    
    lda #R1 ;response type
    jsr spi_read_resp ;Get response
    lda resp_byte+0 
    cmp #active_state
    beq @cmd17_success 
    jmp @sd_read_fail

 @cmd17_success:
     ;setup a timeout counter
    lda #$00
    sta timeout_lo
    lda #$10        ;4096 tries
    sta timeout_hi
    
 @wait_token:
     jsr spi_recv_byte 
     cmp #$fe ;Start token
     beq @got_response 
     dec timeout_lo
     bne @wait_token 
     dec timeout_hi
     bne @wait_token
     jmp @sd_read_fail

 @got_response:
     ldy #0
 @page1_loop:
     jsr spi_recv_byte 
     sta (buff_lo),y ;storing output
     iny
     bne @page1_loop
    ;inc ptr to next 256 block
     inc buff_hi
     
  @page2_loop: ;Y is at 0
     jsr spi_recv_byte 
     sta (buff_lo),y ;storing output
     iny
     bne @page2_loop
   
    ; read 2 extra crc byte and discard it
     jsr spi_recv_byte   
     jsr spi_recv_byte   
     
     jsr cs_high ;transaction closed 
     lda #$FF
     jsr spi_send_byte ;dummy bytes

     dec buff_hi ;Preserving state
     
     lda #0  ;success flag
     rts
  @sd_read_fail:
     jsr cs_high 
     lda #$ff
     jsr spi_send_byte  ;Send dummy bytes to release MISO line
     lda #$ff ;Fail Flag
     rts

     
  sd_write_block:
     jsr cs_low ;Start of transaction
    ;Send cmd24 with sector no as argument
    lda #CMD24
    sta cmd_byte
   ;Assuming caller already put sector no as arg
    lda #CMD24_CRC
    sta crc_byte
    jsr spi_send_cmd 
    
    lda #R1 ;response type
    jsr spi_read_resp ;Get response
    lda resp_byte+0 
    cmp #active_state
    beq @cmd24_success 
    jmp @sd_write_fail
  @cmd24_success:
    lda #$ff
    jsr spi_send_byte ;send a dummy
   
    lda #$fe ; send Data start token
    jsr spi_send_byte
    ldy #0
  @page1_loop:
    lda (buff_lo),y
    jsr spi_send_byte
    iny
    bne @page1_loop
    ;inc to next 256 byte
    inc buff_hi
  @page2_loop:
    lda (buff_lo),y
    jsr spi_send_byte
    iny
    bne @page2_loop
     
    ;Send 2 dummy CRC bytes 
    lda #$ff
    jsr spi_send_byte
    jsr spi_send_byte  
 @wait_token:    
   ;get token
    jsr spi_recv_byte 
    cmp #$ff
    beq @wait_token 

    and #$1F ;mask out top 3 bits 
    cmp #data_accepted ;$05 for success 
    beq @wait_busy 
    jmp @sd_write_fail
 @wait_busy:  ;wait to complete write cycle
    jsr spi_recv_byte 
    cmp #$00
    beq @wait_busy

 @write_success:
 
    dec buff_hi ;restoring buff_hi
    
    jsr cs_high ;transaction closed 
    lda #$FF
    jsr spi_send_byte ;dummy bytes

    lda #0  ;success flag
    rts
 @sd_write_fail:
    jsr cs_high          ; Release CS line on failure
    lda #$FF
    jsr spi_send_byte
    lda #$ff
    rts
LAYER_5:
  read_mbr:
    ; need to read sector 0
    lda #0
    sta arg_0
    sta arg_1
    sta arg_2
    sta arg_3
    ;Passing a temp buffer ptr
    lda #<sd_buff
    sta buff_lo
    lda #>sd_buff
    sta buff_hi
    ;Call sd_read_block to write sector0 to temp buffer
    jsr sd_read_block 
   ;check boot signature
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
   
     lda #0
     rts
   @format_error:
    lda #$FF
    rts
LAYER_6:
 read_bootsector:
  ;passing boot sector no as argument
    lda part_ofs+0
    sta arg_3      
    lda part_ofs+1
    sta arg_2
    lda part_ofs+2
    sta arg_1   
    lda part_ofs+3
    sta arg_0
     ;Passing a temp buffer ptr
    lda #<sd_buff
    sta buff_lo
    lda #>sd_buff
    sta buff_hi
    ;Call sd_read_block to to write boot sect to temp buffer
    jsr sd_read_block 

     lda sd_buff+13
     sta sec_per_clus

     lda sd_buff+14
     sta res_sectors+0
     lda sd_buff+15
     sta res_sectors+1
 
     lda sd_buff+16
     sta num_fats  
    
     lda sd_buff+17
     sta max_root_ent
     lda sd_buff+18
     sta max_root_ent+1
    
     lda sd_buff+22
     sta sec_per_fat+0
     lda sd_buff+23
     sta sec_per_fat+1
 ;   fat_stqrt = part_ofs+res_sectors
     clc
     lda res_sectors
     adc part_ofs
     sta fat_start
     lda res_sectors+1
     adc part_ofs+1
     sta fat_start+1
     lda part_ofs+2
     adc #0
     sta fat_start+2
     lda part_ofs+3
     adc #0
     sta fat_start+3

  ;root_start=fat_start +(sec_per_fat×2)
     lda sec_per_fat
     asl
     sta temp
     lda sec_per_fat+1
     rol
     sta temp+1
     lda #0
     adc #0
     sta temp+2

     lda fat_start
     clc
     adc temp
     sta root_start
     lda fat_start+1
     adc temp+1
     sta root_start+1
     lda fat_start+2
     adc temp+2
     sta root_start+2
     lda fat_start+3
     adc #0
     sta root_start+3
  ;data_start = root_start +32
     clc
     lda root_start
     adc #32
     sta data_start
     lda root_start+1
     adc #0
     sta data_start+1
     lda root_start+2
     adc #0
     sta data_start+2
     lda  root_start+3
     adc #0
     sta data_start+3
     rts






LAYER_7:
  ClusterToLBA:
    ;LBA = data_start_lba +(cluster-2)*sec_per_clus
    
    sec  ;cluster - 2
    lda cluster_lo
    sbc #2
    sta temp_lo
    lda cluster_hi
    sbc #0
    sta temp_hi
    
  @init_32bit:
    lda temp_lo
    sta temp_0
    lda temp_hi
    sta temp_1
    lda #0
    sta temp_2
    sta temp_3
  
    lda sec_per_clus
    lsr
  @shift_loop:
    beq @add_data_start
    asl temp_0
    rol temp_1
    rol temp_2
    rol temp_3
   
    lsr
    jmp @shift_loop
    
  @add_data_start:
    lda temp_0
    clc
    adc data_start+0
    sta arg_3

    lda temp_1
    adc data_start+1
    sta arg_2

    lda temp_2
    adc data_start+2
    sta arg_1

    lda temp_3
    adc data_start+3
    sta arg_0

    rts
    
 get_next_cluster:   
           ;LBA = fat1_lba + cluster_hi
    
    lda fat_start+0
    clc
    adc cluster_hi
    sta arg_3
    lda fat_start+1
    adc #0
    sta arg_2
    lda fat_start+2
    adc #0
    sta arg_1
    lda fat_start+3
    adc #0
    sta arg_0
    
    jsr sd_read_block
    
           ;Byte ofset = cluster_lo*2
    
    lda cluster_lo
    asl
    sta buff_lo
    
    lda #>sd_buff
    adc #0
    sta buff_hi
    
           ;Read next cluster
    
    ldy #0
    lda (buff_lo),y
    tax
   
    iny
    lda (buff_lo),y
    tay
    
    
    stx cluster_lo
    sty cluster_hi
    
           ;Check for EOF ($FFF8 - $FFFF)
           
    cpy #$FF
    bne @valid_cluster
    cpx #$F8
    bcc @valid_cluster

 @end_of_file:
    sec    ; Set Carry = Reached End of File
    rts

 @valid_cluster:
    clc    ; Clear Carry = Valid Next Cluster Found!
    rts
    
    
LAYER_8:
advance_sector:
     dec sector_remain
     beq @next_cluster 
     
     inc arg_3    ;Getting next sector adr
     bne @has_sector
     inc arg_2
     bne @has_sector
     inc arg_1
     bne @has_sector
     inc arg_0
     jmp @has_sector

   @next_cluster:
     jsr get_next_cluster
     bcs @no_more_sector
     jsr ClusterToLBA
 
     lda sec_per_clus
     sta sector_remain
   @has_sector:  
     sec 
     rts
   @no_more_sector:  
     clc
     rts


  list_directory:  
     lda #<sd_buff
     sta buff_lo
     lda #>sd_buff
     sta buff_hi
   
     jsr sd_read_block 
 
     lda #0
     sta ENTRY_REC
     ldx #16
 @parse_loop:
     ldy #0
     lda (buff_lo),y
     beq @end_of_dir ;end sential of directory

     cmp #$E5
     beq @skip_entry ;Deleted file?

     cmp #$2E
     beq @skip_entry ; '.'?
     
     ldy #11
     lda (buff_lo),y
     cmp #$0F             ; Skip VFAT Long File Name entries
     beq @skip_entry
     
     and #$08             ; Skip Volume Labels
     bne @skip_entry

     ldy #0    
     
  @copy_12byte:
     lda (buff_lo),y
     sta (list_lo),y
     iny
     cpy #12
     bne @copy_12byte
    
     lda list_lo ;C already set
     sbc #14
     sta list_lo
     bcs :+
           dec list_hi
           :
     ldy #26    
  @copy_clus_size:
     lda (buff_lo),y
     sta (list_lo),y
     iny
     cpy #32
     bne @copy_clus_size
  @next:
     lda #32
     clc
     adc list_lo
     sta list_lo
     bcc :+
           inc list_hi
           :
     inc ENTRY_REC      
  @skip_entry:
     lda #32
     clc
     adc buff_lo
     sta buff_lo
     bcc :+
         inc buff_hi
         :
     
     dex
     bne @parse_loop
         
  @end_of_sec:    
     lda #$FF
     rts
  @end_of_dir:
     lda #0
     rts

      
 search_directory:
     lda cluster_hi
     ora cluster_lo
     beq @root_resolve
     
   @subfolder_resolve:
     jsr ClusterToLBA
     
     lda sec_per_clus
     sta sector_remain
     jmp @sector_loop
     
   @root_resolve:
     lda root_start+3
     sta arg_0
     lda root_start+2
     sta arg_1
     lda root_start+1
     sta arg_2
     lda root_start+0
     sta arg_3
    
     lda #32
     sta sector_remain
     
   @sector_loop:
     lda #<sd_buff  ;init buff
     sta buff_lo
     lda #>sd_buff
     sta buff_hi
     
     jsr sd_read_block 
   
     ldx #16  ;16 entry per 512 byte sector
   @entry_loop:
     ldy #0
     lda (buff_lo),y
     beq @not_found
     cmp #$E5
     beq @skip_entry ;Deleted file?
     cmp #$2E
     beq @skip_entry ; '.'?
     
     ldy #11
     lda (buff_lo),y
     cmp #$0F             ; Skip VFAT Long File Name entries
     beq @skip_entry
     
     and #$08             ; Skip Volume Labels
     bne @skip_entry
     
     ldy #0
   @cmp_loop:
     lda (buff_lo),y
     cmp target_name,y
     bne @skip_entry
     iny
     cpy #11
     bne @cmp_loop
     
   @name_matched:
     ldy #26
     lda (buff_lo),y
     sta item_cluster_lo
  
     iny
     lda (buff_lo),y
     sta item_cluster_hi
     
     ldy #28
     lda (buff_lo),y
     sta size+0
     iny
     lda (buff_lo),y
     sta size+1
     iny
     lda (buff_lo),y
     sta size+2
     iny
     lda (buff_lo),y
     sta size+3
     
     lda arg_3
     sta entry_lba+0
     lda arg_2
     sta entry_lba+1
     lda arg_1
     sta entry_lba+2
     lda arg_0
     sta entry_lba+3
     
     lda buff_lo
     sta entry_ptr_lo
     lda buff_hi
     sta entry_ptr_hi 
     
     clc
     rts
   @not_found:
     sec
     rts
   
   @skip_entry:
     lda #32
     clc
     adc buff_lo
     sta buff_lo
     bcc :+
         inc buff_hi
         :
     dex ;entry remaning (total 16)
     bne @entry_loop
    
     dec sector_remain
     beq @next_cluster
     
     inc arg_3 ;geting next sector adr
     bne :+
     inc arg_2
     bne :+
     inc arg_1
     bne :+
     inc arg_0
     :
     jmp @sector_loop
   
   @next_cluster:
     lda cluster_hi
     ora cluster_lo
     beq @not_found
     
     jsr get_next_cluster
     bcs @not_found
     
     jsr ClusterToLBA
     lda sec_per_clus
     sta sector_remain
     jmp @sector_loop
    
    
LAYER_9:

  load_bytes:
     jsr ClusterToLBA
     
     lda sec_per_clus
     sta sector_remain 
   
   @sector_loop:  
     lda size+1 ;if <= 512b
     cmp #2
     bcs @full_sector
     
   @partial_sector:
     lda size+1
     ora size+0
     beq @load_done
     
     lda buff_lo
     sta temp_lo
     lda buff_hi
     sta temp_hi
     
     lda #<sd_buff
     sta buff_lo
     lda #>sd_buff
     sta buff_hi
     
     jsr sd_read_block
     bmi @sd_failed
     ldy #0
     
     lda size+1
     beq @partial_page
     
   @full_page:
     lda sd_buff,y
     sta (temp_lo),y
     iny
     bne @full_page
     
     inc temp_hi
     
  @tail_page:
     lda size+0
     beq @load_done
     
     ldx size+0
   @copy_loop:
     lda sd_buff+256,y
     sta (temp_lo),y
     iny
     dex
     bne @copy_loop
     
   @load_done:
     lda #$00
     rts  
 
  @partial_page:
     lda size+0
     beq @load_done
     
     ldx size+0
   @loop:
     lda sd_buff,y
     sta (temp_lo),y
     iny
     dex
     bne @loop   
     jmp @load_done
     
   @full_sector:
     jsr sd_read_block
     bmi @sd_failed
     
     inc buff_hi
     inc buff_hi
     
     lda size+1  ;sub 512 from size
     sec
     sbc #2
     sta size+1
   
   @next_sector:   
     jsr advance_sector
     bcs @sector_loop
     
   @sd_failed:
     lda #$ff
     rts
   
     
resolve_path:
     ldy #0   

     lda (path_lo),y
     cmp #"/"
     bne @use_cwd

   @use_root:
     sty cluster_hi
     sty cluster_lo  ;filling with 0
     jmp @start_segment
   @use_cwd:
     lda cwd_cluster_lo
     sta cluster_lo
     lda cwd_cluster_hi
     sta cluster_hi 
  @start_segment:
   @skip_slashes:
     lda (path_lo),y
     beq @file_found
     iny
     cmp #"/"
     beq @skip_slashes 
     dey
  @pre_padding:
     lda #" "
     ldx #11
   @pad_loop:
     sta target_name-1,x  
     dex
     bne @pad_loop
   @parse_name:  ;x already at 0
     lda (path_lo),y
     beq @path_ended
     iny
     cmp #"."
     beq @check_dot
     cmp #"/"
     beq @segment_ended
   
     sta target_name,x
     inx
     cpx #8
     bne @parse_name

     lda (path_lo),y
     beq @path_ended
     iny
     cmp #"."
     beq @parse_extension
     cmp #"/"
     beq @segment_ended
     
     jmp @invalid_path ;file name too long

   @check_dot:
     cpx #1
     bcc @store_dot
     bne @parse_extension

     lda target_name-1,x
     cmp #"."
     bne @parse_extension
    @store_dot: 
     sta target_name,x
     inx
     jmp @parse_name
     
   @parse_extension:
     ldx #8     
   @ext_loop:
     lda (path_lo),y
     
     beq @path_ended
     iny
     cmp #"/"
     beq @segment_ended

     cpx #11
     beq @invalid_path
     
     sta target_name,x
     inx
     jmp @ext_loop
    
   @path_ended:
     ldy #0
   @segment_ended:
     sty path_ofset
   @search_entry:
     jsr search_directory
     bcs @invalid_path ;Not found
     
     lda item_cluster_hi
     sta cluster_hi
     lda item_cluster_lo
     sta cluster_lo

     ldy path_ofset
     bne @start_segment
  @file_found:
     lda #0 ;success flag
     rts

  @invalid_path:
     lda #$ff ;missing path flag
     rts
     

 size_to_sectors:
    ; 1. Divide size+1 by 2 (bit 0 falls into Carry)
     lda size+1
     lsr a                   ; A = Sector count (0 to 32); Carry = 1 if 256-byte remainder
     sta sector_left 
 
    ; 2. Check for remainder bytes (to round up partial sectors)
     bcc @check_low_byte     ; No 256-byte remainder
     inc sector_left     ; Carry = 1 means 256+ bytes remaining -> Add 1 sector
     rts

  @check_low_byte:
     lda size+0
     beq @done               ; Exact sector match
     inc sector_left   ; size+0 > 0 means 1-255 leftover bytes -> Add 1 sector

  @done:
     rts


      
  load_file:   
     lda sector_left
     beq @load_done         ; Safety: Exit immediately
     
     jsr ClusterToLBA 
    
     lda sec_per_clus
     sta sector_remain 
   
  @sector_loop:  
     jsr sd_read_block
     bmi @sd_failed
    
     dec sector_left
     beq @load_done
   
     inc buff_hi
     inc buff_hi
  
  @next_sector:   
     jsr advance_sector
     bcs @sector_loop
     
  @sd_failed:
     lda #$FF ;failed flag
     rts 
  @load_done:
     lda #0
     rts 
     

  size_to_clusters:
    jsr size_to_sectors
    
    lda sec_per_clus
    ldx #$FF
  @shift_loop:
    inx
    lsr
    bcc @shift_loop
    
    lda sector_left
    cpx #0
    beq @store_clus 
  @div_loop:
    lsr
    dex
    bne @div_loop
  @store_count: 
    sta clus_clus
    rts
LAYER 10:    
allocate_cluster_chain:
   lda #<sd_buff
   sta buff_lo
   lda #>sd_buff
   sta buff_hi

   lda fat_start+0
   sta arg_3
   lda fat_start+1
   sta arg_2
   lda #0
   sta arg_1
   sta arg_0
   sta temp
   
   lda #$ff
   sta prev_clus_lo
   sta prev_clus_hi
   
   jsr size_to_clusters ;output  clus_count on A
   sta clus_remain
   asl  ;Mult No.of clus by 2 to get last +1 ofset
   sta temp_x
   
   
 @sector_loop:
   jsr sd_read_block
   bpl :+
       jmp @sd_failed
       :
   ldy #0
   sty TEMP_FLAG
 @page_1: 
   lda sd_buff,y
   ora sd_buff+1,y
   beq @found
   iny
   iny
   bne @page_1
 @next_page:  
   inc temp
   
   lda #$FF
   
   sta TEMP_FLAG
  @page_2:   
   lda sd_buff+256,y
   ora sd_buff+257,y
   beq @found
   iny
   iny
   bne @page_2
   
   
 @next_sector:
   inc temp
   
   inc arg_3  ;MAX Sector size for fat will be 256
   bne @sector_loop
   inc arg_2
   jmp @sector_loop
 @found: ;Do 16bit division by 2 
   ldx temp_x
   lda temp
   lsr 
   sta clus_buff-1,x
   pha
   
   dex
   tya
   ror 
   sta clus_buff-1,x
   pha
   
   dex
   stx temp_x
   
 @writing_chain:
   
   lda TEMP_FLAG
   bpl :+
       inc BUFF_HI
       :
       
   lda prev_clus_lo
   sta (buff_lo),y
   lda prev_clus_hi
   iny
   sta (buff_lo),y
   iny
   sty temp_y  ;Save Y reg
   
   lda TEMP_FLAG
   bpl :+
       dec buff_hi ;Restoring BUFF_HI
       :
 @write_FAT1:
   lda arg_3
   pha
   lda arg_2
   pha
   
   jsr sd_write_block
   bmi @sd_failed
 @write_FAT2:    
   lda arg_3
   clc
   adc sec_per_fat+0
   sta arg_3
   
   lda arg_2
   adc sec_per_fat+1
   sta arg_2
   
   jsr sd_write_block
   bmi @sd_failed
   
   pla
   sta arg_2
   pla
   sta arg_3
   
   pla
   sta prev_clus_lo
   pla
   sta prev_clus_hi
   
   
   dec clus_remain
   beq @done
   
   ldy temp_y  ;Restoring Y reg
   bne :+
       lda TEMP_FLAG
       beq @next_page
       jmp @next_sector
   :
   lda TEMP_FLAG
   beq  @page_1
   jmp @page_2
  @done: 
   lda #0
   rts
 @sd_failed:
   lda #$ff
   rts  
   
 write_to_cluster:
   lda src_lo
   sta buff_lo
   lda src_hi
   sta buff_hi
   
   lda clus_count
   sta clus_remain
   
   ldy #0
   sty temp_y
 @fetch_next_cluster:
   ldy temp_y
   lda clus_buff,y
   sta cluster_lo
   lda clus_buff+1,y
   sta cluster_hi
   iny
   iny
   sty temp_y
   
   lda sec_per_clus
   sta sector_remain
   
   jsr ClusterToLBA 
   
 @write_sector:
   jsr sd_write_block ;write first page
   bmi @sd_failed
   inc buff_hi
   inc buff_hi
  
   inc arg_3
   bne :+
        inc arg_2
        :
        
   dec sector_left ;How many total sector left
   beq @write_done
   dec sector_remain ;How many sector left just in a cluster
   bne @write_sector
   
   dec clus_remain
   bne @fetch_next_cluster
  @write_done:
   lda #0
   rts
  @sd_failed:
   lda #$ff
   rts 
   
create_directory_entry:
   lda #<sd_buff
   sta buff_lo
   lda #>sd_buff
   sta buff_hi
   
   lda dir_clus_lo
   ora dir_clus_hi
   bne @setup_subdir
   
 @setup_rootdir:
   lda root_start+0
   sta arg_3
   lda root_start+1
   sta arg_2
   lda #0
   sta arg_1
   sta arg_0
   jmp @start_scan
   
 @setup_subdir:
   lda dir_clus_lo
   sta cluster_lo
   lda dir_clus_hi
   sta cluster_hi
   jsr ClusterToLBA 
   
 @start_scan:
  @scan_sector:
   jsr sd_read_block
   bpl :+
        jmp @sd_failed
        :
   ldy #0
   ldx #0
  @scan_entry:
   lda (buff_lo),y
   beq @found_slot
   cmp #$E5
   beq @found_slot
  
   tya
   clc
   adc #32
   tay
   bne @scan_entry
   
   lda #>sd_buff
   cmp buff_hi
   bne @next_sector
   
   inc buff_hi
   jmp @scan_entry
       
 @next_sector:
   lda #>sd_buff
   sta buff_hi 
   inc arg_3
   bne :+
       inc arg_2
       :  
   jmp @scan_sector
       
       
  @found_slot:
  @stamp_metadata:
   ldx #0
  @stamp_file_name:
   lda target_name,x
   sta (buff_lo),y
   inx
   iny
   cpx #11
   bne @stamp_file_name
   
 @stamp_attribute:
   lda attribute_byte
   sta (buff_lo),y
   iny
 @stamp_reserved:  
   lda #0
   ldx #14
   :
   sta (buff_lo),y
   iny
   dex
   bne :-
 @stamp_cluster_id: 
   lda start_clus_lo
   sta (buff_lo),y
   lda start_clus_hi
   iny
   sta (buff_lo),y
   iny
 @stamp_size:
   lda size+0
   sta (buff_lo),y
   iny
   lda size+1
   sta (buff_lo),y
   iny
   lda #0
   sta (buff_lo),y
   iny
   sta (buff_lo),y
 
 @save_dir:
   lda #<sd_buff
   sta buff_lo
   lda #>sd_buff
   sta buff_hi    
   
   jsr sd_write_block
   bmi @sd_failed
   lda #0
   rts
 @sd_failed:
   lda #$ff
   rts

delete_directory_entry:
   lda #<sd_buff
   sta buff_lo
   lda #>sd_buff
   sta buff_hi
   
   lda dir_clus_lo
   ora dir_clus_hi
   bne @setup_subdir
   
 @setup_rootdir:
   lda root_start+0
   sta arg_3
   lda root_start+1
   sta arg_2
   lda #0
   sta arg_1
   sta arg_0
   jmp @start_scan
   
 @setup_subdir:
   lda dir_clus_lo
   sta cluster_lo
   lda dir_clus_hi
   sta cluster_hi
   jsr ClusterToLBA 
   
   
init_folder_cluster:
   lda #<sd_buff
   sta buff_lo
   lda #>sd_buff
   sta buff_hi
   
 @clear_buff: ;Clear first 512 byte 
   lda #$0
   ldy #0
  :
   sta sd_buff+0,y
   sta sd_buff+256,y
   iny
   bne :-
   
 @create_dot_entry:
   lda #"."
   sta sd_buff+0
   
   ldx #10
   lda " "
  :
   sta sd_buff,x
   dex
   bne :-
   
   lda #$10 ;directory attribute
   sta sd_buff+$0B
   
   lda start_clus_lo
   sta sd_buff+$1A
   lda start_clus_hi
   sta sd_buff+$1B
   
 @create_dotdot_entry:
   lda #"."
   sta sd_buff+$20
   sta sd_buff+$21
   
   ldx #9
   lda #" "
  :
   sta sd_buff+$21,x
   dex
   bne :-
   
   lda #$10 ;directory attribute
   sta sd_buff+$2B
   
   lda dir_clus_lo
   sta sd_buff+$3A
   lda dir_clus_hi
   sta sd_buff+$3B
   
 @init_cluster:   
   lda start_clus_lo
   sta cluster_lo
   lda start_clus_hi
   sta cluster_hi
   jsr ClusterToLBA 
   
   lda sec_per_clus
   sta sector_remain
   
   jmp @write
 @pad_with_zero:
   lda #$0
   ldy #0
  :
   sta sd_buff+0,y
   sta sd_buff+256,y
   iny
   bne :-
  @write:  
   jsr sd_write_block
   bmi @sd_failed
   
   dec sector_remain
   beq @done
   
   inc arg_3
   bne :+ 
        inc arg_2
        :
   jmp @pad_with_zero

 @done:  
   lda #0
   rts
   
 @sd_failed:
   lda #$ff
   rts  
   

free_cluster_chain:
   lda start_clus_lo
   ora start_clus_hi
   beq @success
    
   lda start_clus_lo
   sta cluster_lo
   lda start_clus_hi
   sta cluster_hi
 
  @get_next_cluster:
   jsr get_next_cluster
   php
   
  @write_empty:
   ldy #0
   lda #0
   sta (buff_lo),y
   iny
   sta (buff_lo),y   
   
   lda #<sd_buff
   sta buff_lo
   lda #>sd_buff
   sta buff_hi

   jsr sd_write_block
   bmi @sd_failed
   
   plp
   bcc @get_next_cluster
   
  @success:
   lda #0
   rts
   
  @sd_failed:
   lda #$ff
   rts
   
 delete_dir_entry:
   lda entry_lba+0
   sta arg_3
   lda entry_lba+1
   sta arg_2
   lda entry_lba+2
   sta arg_1
   lda entry_lba+3
   sta arg_0
   
   lda #<sd_buff
   sta buff_lo
   lda #>sd_buff
   sta buff_hi
   
   jsr sd_read_block
   bmi @sd_failed
   
   lda entry_lo
   sta buff_lo
   lda entry_hi
   sta buff_hi
   
   ldy #0
   lda #$E5 ;delete flag byte
   sta (buff_lo),y
   
   lda #<sd_buff
   sta buff_lo
   lda #>sd_buff
   sta buff_hi
   
   jsr sd_write_block
   bmi @sd_failed
   
   lda #0
   rts
  @sd_failed:
   lda #$ff
   rts  
   
   
;                   LAYER 11

;===========================================================================
;Function:   save_file
;Layer:      High-Level API (system call)
;Input:      source pointer -> src_lo,src_hi 
;            file size -> size_0,size_1 (64kb max)
;            8.3 Filename -> target_name[11 byte] 
;            directory cluster id -> dir_clus_lo,dir_clus_hi ($0000 for root dir)
;Output:     Success($00)/Fail($FF) flag -> Accumulator (A)
;===========================================================================
 save_file:
   jsr allocate_cluster_chain
   bmi @save_failed
   
   jsr write_to_cluster
   bmi @save_failed            ; Abort if SD write returned error ($FF)

   ; 3. Pass head cluster (clus_buff[0]) to directory entry stamper
   lda clus_buff+0
   sta start_clus_lo
   lda clus_buff+1
   sta start_clus_hi
   
   lda #$20 ;File attribute byte
   sta attribute_byte
   jsr create_directory_entry   
   bmi @save_failed
   
   lda #0  ;success flag
   rts
   
  @save_failed:
   lda #$ff
   rts
   
;============================================================
;Function:   create_folder
;Layer:      High-Level API (system call)
;Input:      8.3 folder name -> target_name[11 byte] (pad with space)
;            Parent dir cluster ID -> dir_clus_lo,dir_clus_hi ($0000 = FAT16 root dir)
;Output:     Success($00)/Fail($FF) flag -> Accumulator (A)
;=============================================================
create_folder:
   lda #1
   sta clus_count
   jsr allocate_cluster_chain
   bmi @sd_failed
   
   lda clus_buff+0
   sta start_clus_lo
   lda clus_buff+1
   sta start_clus_hi
   
   jsr init_folder_cluster
   bmi @sd_failed
   
   lda #0
   sta size+0
   sta size+1
   
   lda #$10 ;directory attribute byte
   sta attribute_byte
   jsr create_directory_entry
   bmi @sd_failed
   
   lda #0
   rts
 @sd_failed:
   lda #$ff
   rts  
   
   
 fs_remove:
   jsr resolve_path
   bmi @file_not_found

   lda item_cluster_lo
   ora item_cluster_hi
   beq @skip_fat_free      ; If cluster == 0, skip freeing chain
   
   lda item_cluster_lo
   sta start_clus_lo
   lda item_cluster_hi
   sta start_clus_hi
   
   jsr free_cluster_chain
   bmi @sd_failed
   
 @skip_fat_free: 
   jsr delete_dir_entry
   bmi @sd_failed
   
   lda #0
   rts
 @file_not_found:
 @sd_failed:
   lda #$ff
   rts  
   
   
 fs_mkdir:
   jsr resolve_path
   bpl @file_already_exit
   
   lda cluster_lo
   sta dir_clus_lo
   lda cluster_hi
   sta dir_clus_hi
   
   jsr create_folder
   
  @done:
   lda #0
   rts
   
   
 @file_already_exist:
   lda #$ff
   rts
