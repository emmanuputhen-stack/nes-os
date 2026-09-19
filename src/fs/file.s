

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
   bcc :+
       rts
       :
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
   clc
   rts
        
load_bytes:
     stx temp_x
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
     bcs @sd_failed
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
     lda temp_lo  ;Restore User buffer ptr
     sta buff_lo
     lda temp_hi
     sta buff_hi
   
     ldx temp_x
     clc
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
     bcs @sd_failed
     
     inc buff_hi
     inc buff_hi
     
     lda size+1  ;sub 512 from size
     sec
     sbc #2
     sta size+1
     
     ora size+0
     beq @load_done
   
   @next_sector:   
     jsr advance_sector
     bcs @sd_failed
     beq @sector_loop
     ; If not beq,then file is correpted
     sec
     lda #ERR_PREMATURE_EOF
   @sd_failed:
     ldx temp_x
     rts



load_file:   
     lda sector_left
     beq @load_done         ; Safety: Exit immediately
     
     jsr ClusterToLBA 
    
     lda sec_per_clus
     sta sector_remain 
   
  @sector_loop:  
     jsr sd_read_block
     bcc :+
         rts
         :
    
     dec sector_left
     beq @load_done
   
     inc buff_hi
     inc buff_hi
  
  @next_sector:   
     jsr advance_sector
     bcc :+
         rts
         :
     beq @sector_loop
     
  @sd_failed:
     lda #ERR_PREMATURE_EOF
     sec
     rts
  @load_done:
     lda #0
     clc
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
   bcc :+
       rts
        :
   
   jsr write_to_cluster
   bcc :+
       rts
        :         ; Abort if SD write returned error ($FF)

   ; 3. Pass head cluster (clus_buff[0]) to directory entry stamper
   lda clus_buff+0
   sta start_clus_lo
   lda clus_buff+1
   sta start_clus_hi
   
   lda #$20 ;File attribute byte
   sta attribute_byte
   jsr create_directory_entry   
   bcc :+
       rts
        :
   
   lda #0  ;success flag
   clc
   rts
   
