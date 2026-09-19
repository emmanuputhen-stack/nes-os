read_bootsector:
    ;   passing boot sector no as argument
    lda part_ofs+0
    sta arg_3      
    lda part_ofs+1
    sta arg_2
    lda part_ofs+2
    sta arg_1   
    lda part_ofs+3
    sta arg_0
   
    ; Passing a temp buffer ptr
    lda #<sd_buff
    sta buff_lo
    lda #>sd_buff
    sta buff_hi
    
    ;   Call sd_read_block to to write boot sect to temp buffer
    jsr sd_read_block 
    bcc :+
        rts
        :
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
    
    ;   fat_start = part_ofs+res_sectors
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

    ;   root_start=fat_start +(sec_per_fat×2)
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

    ;  root directory sectors = max_root_ent/16
    lda max_root_ent+0
    sta temp+0
    lda max_root_ent+1
    sta temp+1
    
    ldy #4
  @div_16:
    lsr temp+1   
    ror temp+0
    dey
    bne @div_16
    
    ;  data_start = root_start + root directory sectors
    clc
    lda root_start
    adc temp+0
    sta data_start
    lda root_start+1
    adc temp+1
    sta data_start+1
    lda root_start+2
    adc #0
    sta data_start+2
    lda  root_start+3
    adc #0
    sta data_start+3
    
    clc    ;success 
    rts
  ;----------------------------------------------
  ;         ClusterToLBA (Mid-Level)
  ; Formula:  LBA = data_start_lba +(cluster-2)*sec_per_clus
  ; Input:    cluster_lo,cluster_hi
  ; Output:   sector id -> arg_0,...arg_3
  ; Modifies: A (Preserve X and Y)
  ;_______________________________________________
  ClusterToLBA:
    lda cluster_lo
    ora cluster_hi
    bne @data_cluster

 @root_dir:
    ; Cluster 0 maps directly to root_start LBA
    lda root_start+0
    sta arg_3
    lda root_start+1
    sta arg_2
    lda root_start+2
    sta arg_1
    lda root_start+3
    sta arg_0
    rts

 @data_cluster:
    sec                  ;cluster - 2
    lda cluster_lo
    sbc #2
    sta temp+0
    lda cluster_hi
    sbc #0
    sta temp+1
    lda #0
    sta temp+2
    sta temp+3
  
    lda sec_per_clus
    lsr
  @shift_loop:
    beq @add_data_start
    asl temp+0
    rol temp+1
    rol temp+2
    rol temp+3
   
    lsr
    jmp @shift_loop
    
  @add_data_start:
    lda temp+0
    clc
    adc data_start+0
    sta arg_3

    lda temp+1
    adc data_start+1
    sta arg_2

    lda temp+2
    adc data_start+2
    sta arg_1

    lda temp+3
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
    
    lda #<sd_buff
    sta buff_lo
    lda #>sd_buff
    sta buff_hi
    
    jsr sd_read_block
    bcc :+
        rts
        :
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
    sta temp+0
   
    iny
    lda (buff_lo),y
    sta temp+1
    
           ;Check for EOF ($FFF8 - $FFFF)
           
    cmp #$FF    ;Compare against hi byte in A
    bne @valid_cluster
    lda temp+0
    cmp #$F8
    bcc @valid_cluster

 @end_of_file:
    clc
    lda #$FF       ;end of file flag
    rts

 @valid_cluster:
    lda temp+0
    sta cluster_lo
    lda temp+1   
    sta cluster_hi
    lda #$0
    clc    ; Clear Carry = Valid Next Cluster Found!
    rts


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
   bcc :+
       rts
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
       inc buff_hi
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
   bcc :+
       rts
       :
 @write_FAT2:    
   lda arg_3
   clc
   adc sec_per_fat+0
   sta arg_3
   
   lda arg_2
   adc sec_per_fat+1
   sta arg_2
   
   jsr sd_write_block
   bcc :+
       rts
       :
   
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
   clc
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
   bcc :+
       plp
       rts
       :
   
   plp
   bcc @get_next_cluster
   
  @success:
   lda #0
   clc
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
   sta clus_count 
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
    bcc :+
        rts
         :
    bmi @no_more_sector    
    jsr ClusterToLBA
     
    lda sec_per_clus
    sta sector_remain
   @has_sector:  
    lda #0
    clc
    rts
   @no_more_sector:  ;A contain $FF
    rts
    
    
 calc_append_offsets:
    lda size+0            ;get byte ofset
    sta byte_ofs_lo
    lda size+1
    and #$01
    sta byte_ofs_hi
    
    lda size+1
    lsr                 ;size+1>>1 & sec_per_clus-1
    ldy sec_per_clus
    dey
    sty temp
    
    and temp
    sta sector_index
    
    lda sec_per_clus
    sec
    sbc sector_index
    sta sector_remain
    rts


link_two_chain:
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
    
    lda #<sd_buff
    sta buff_lo
    lda #>sd_buff
    sta buff_hi
    
    jsr sd_read_block
    bcc :+
        rts
        :
           ;Byte ofset = cluster_lo*2
    
    lda cluster_lo
    asl
    sta buff_lo
    
    lda #>sd_buff
    adc #0
    sta buff_hi
    
           ;Read next cluster
    
    ldy #0
    lda clus_buff+0
    sta (buff_lo),y
   
    iny
    lda clus_buff+1
    sta (buff_lo),y
    
    lda #<sd_buff
    sta buff_lo
    lda #>sd_buff
    sta buff_hi
  @write_FAT1:   
    jsr sd_write_block
    bcc :+
        rts
        :
        
  @write_FAT2:    
    lda arg_3
    clc
    adc sec_per_fat+0
    sta arg_3
    
    lda arg_2
    adc sec_per_fat+1
    sta arg_2
    bcc :+
    inc arg_1
    bne :+
    inc arg_0
    :
    
    jsr sd_write_block
    bcc :+
       rts
       :
    clc
    rts   
       