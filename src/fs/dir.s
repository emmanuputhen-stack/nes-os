



list_directory:  
     stx temp_x   ;Saving X reg
       
     lda #<sd_buff
     sta buff_lo
     lda #>sd_buff
     sta buff_hi
   
     jsr sd_read_block 
     bcc :+
         rts
         :
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
     ldx temp_x
     lda #$0
     clc
     rts
     
  @end_of_dir:
     ldx temp_x
     lda #$ff     ;Flag to represent EOD
     clc
     rts   
     
     
;---------------------------------------------------
;         Search_directory (Layer 4 Engine)
; Input:  cluster_lo/hi (0 = Root Directory, >0 = Subdirectory cluster)
;         target_name (11-byte padded 8.3 filename string in RAM)
; Output: Hardware Error: SEC, A = SD Error Code
;         Found:          CLC, A = $00 (N=0), metadata saved to ZP/RAM
;         Not Found:      CLC, A = $FF (N=1)
;---------------------------------------------------   
     
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
     bcc :+
         rts
         :
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
     
     lda #$00
     clc
     rts
   @not_found:
     clc
     lda #$FF
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
     bcc :+
         rts
         :
     bmi @not_found
     jsr ClusterToLBA
     lda sec_per_clus
     sta sector_remain
     jmp @sector_loop  
     
     
        ;-------------------------------------------------------------------------------
   ;                resolve_path(High-Level)
   ; Input:  path_lo/hi -> null-terminated ASCII path string (e.g., "/DIR/FILE.TXT")
   ; Output: Success:        CLC, A = $00, cluster_lo/hi = target item cluster
   ;         Path Not Found: CLC, A = $FF
   ;         SD Read Error:  SEC, A = SD error code
   ;-------------------------------------------------------------------------------
     
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
     ldx #10
   @pad_loop:
     sta target_name,x  
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
 
     cmp #"a"
     bcc :+
     cmp #"z"+1     ; Convert 'a'-'z' to 'A'-'Z'
     bcs :+
     and #$DF   
     :         
   
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
     
     cmp #"a"
     bcc :+
     cmp #"z"+1
     bcs :+
     sbc #$20
     :
     sta target_name,x
     inx
     jmp @ext_loop
    
   @path_ended:
     ldy #0
   @segment_ended:
     sty path_ofset
   @search_entry:
     jsr search_directory
     bcc :+
         rts
         :
     bmi @invalid_path ;Not found
     
     lda item_cluster_hi
     sta cluster_hi
     lda item_cluster_lo
     sta cluster_lo

     ldy path_ofset
     bne @start_segment
  @file_found:
     clc
     lda #0 ;success flag
     rts

  @invalid_path:
     clc
     lda #$ff ;missing path flag
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
   
   lda #32
   sta sector_remain
   jmp @start_scan
   
 @setup_subdir:
 
   lda dir_clus_lo
   sta cluster_lo
   lda dir_clus_hi
   sta cluster_hi
   jsr ClusterToLBA 
   
   lda sec_per_clus
   sta sector_remain
 @start_scan:
  @scan_sector:
   jsr sd_read_block
   bcc :+
        rts 
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
   
   lda dir_clus_lo
   ora dir_clus_hi
   beq @root_advance
   
   jsr advance_sector
   bcc :+
       rts
       :
   beq @start_scan
   jmp @dir_full
  
 @root_advance:
   dec sector_remain
   beq @dir_full
   
   inc arg_3
   bne :+
       inc arg_2
   :
   jmp @start_scan 
   
 @dir_full:
   sec
   lda #ERR_DIR_FULL
   rts  
       
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
   bcc :+
       rts
       :
   lda #0
   clc
   rts
 
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
   bcc :+
       rts
       :
   
   dec sector_remain
   beq @done
   
   inc arg_3
   bne :+ 
        inc arg_2
        :
   jmp @pad_with_zero

 @done:  
   lda #0
   clc
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
   bcc :+
       rts
       :
   
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
   bcc :+
        rts
        :
   
   lda #0
   clc
   rts
  
  
  
    