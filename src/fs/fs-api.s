; ==============================================================================
;
;   ███████╗███████╗     █████╗ ██████╗ ██╗
;   ██╔════╝██╔════╝    ██╔══██╗██╔══██╗██║
;   █████╗  ███████╗    ███████║██████╔╝██║
;   ██╔══╝  ╚════██║    ██╔══██║██╔═══╝ ██║
;   ██║     ███████║    ██║  ██ ║██║     ██║
;   ╚═╝     ╚══════╝    ╚═╝  ╚═╝╚══╝     ╚═╝
;
;   Layer:       High-Level API (system call interface)
;   Description: Contain all mainstream file system manuplation routines
; ==============================================================================




;===========================================================================
; Function:   fs_mkdir
; Layer:      High-Level API (system call)
; Input:      path_lo/hi -> null-terminated ASCII path string
; Output:     CLC (Success) or SEC + Error Code in A (Fail)
;===========================================================================

fs_mkdir:
   jsr resolve_path
   bcc @file_already_exist       ;If file already exist,then exit
   
   cmp #ERR_INV_PATH 
   beq :+           ;If file does not exist then continue,otherwise rts
       rts
       :
       
   lda cluster_lo
   sta dir_clus_lo
   lda cluster_hi
   sta dir_clus_hi
           
   jsr create_folder
   bcc :+
       rts
       :
   
  @done:
   clc
   rts
   
  @file_already_exist:
   sec
   lda #ERR_FILE_EXIST
   rts
   


;===========================================================================
; Function:   fs_create
; Layer:      High-Level API (system call)
; Purpose:    Allocates an empty 32-byte file record with 0 size & cluster.
; Input:      Path String Pointer -> path_lo, path_hi
; Output:     Carry Clear = Success (A = $00)
;             Carry Set   = Error (A = ERR_FILE_EXIST, ERR_INV_PATH, or SD Err)
; Modifies:   A, X, Y, dir_clus_lo/hi, target_name
;===========================================================================
   
 fs_create:
   jsr resolve_path
   bcc @file_already_exist       ;If file already exist,then exit
   
   cmp #ERR_INV_PATH 
   beq :+           ;If file does not exist then continue,otherwise rts
       rts
       :
   
   lda cluster_lo
   sta dir_clus_lo
   lda cluster_hi
   sta dir_clus_hi
           
   lda #0
   sta size+0
   sta size+1
   sta start_clus_lo
   sta start_clus_hi
   
   lda #$20    ;fetch file attribute 
   sta attribute_byte
   
   jsr create_directory_entry
   bcc :+
       rts
       :
  @done:
   clc
   rts
   
  @file_already_exist:
   sec
   lda #ERR_FILE_EXIST
   rts

;===========================================================================
; Function:   fs_remove
; Layer:      High-Level API (system call)
; Input:      target path -> path_lo/hi 
; Output:     Success(CLC) / Fail(SEC) flag -> Accumulator (A)
;===========================================================================

fs_remove:
   jsr resolve_path
   bcc  :+
          rts
         :
   
   ; 1. Invalidate the directory entry FIRST (Data safety)
   jsr delete_dir_entry
   bcc  :+
          rts
         :

   ; 2. Then free the cluster chain in the FAT
   lda item_cluster_lo
   ora item_cluster_hi
   beq @skip_fat_free      ; If cluster == 0, skip freeing chain
   
   lda item_cluster_lo
   sta start_clus_lo
   lda item_cluster_hi
   sta start_clus_hi
   
   jsr free_cluster_chain
   bcc  :+
          rts
         :
  
@skip_fat_free: 
   lda #0
   clc
   rts

;===========================================================================
; Function:   fs_open
; Layer:      High-Level API (system call)
; Purpose:    Resolves file path, validates it is a file, and caches metadata.
; Input:      Path String Pointer -> path_lo, path_hi
; Output:     Carry Clear = Success (A = $00)
;               -> Populates item_cluster_lo/hi, size+0..3, 
;                  entry_lba+0..3, entry_ptr_lo/hi
;             Carry Set   = Error (A = ERR_INV_PATH, ERR_IS_A_DIRECTORY, etc.)
; Modifies:   A, X, Y, item_attr, item_cluster_lo/hi, size+0..3
;===========================================================================
      
fs_open:
   lda fs_flags
   and #~FS_OPEN
   bne @already_open
   
   jsr resolve_path
   bcc :+
       rts
       :
   
   lda item_attr
   cmp #$10         ;If it is directory?
   beq @is_dir
 
   lda #FS_OPEN
   sta fs_flags
    
   clc
   rts
 @already_open:
   lda #ERR_INV_OPERATION
   sec
   rts  
 @is_dir:
   lda fs_flags
   ora #DIR_OPEN
   sta fs_flags 
   
   lda #0
   sta dir_index
   
   clc
   rts

;===========================================================================
; Function:   fs_close
; Layer:      High-Level API (system call)
; Purpose:    Commits final file size and head cluster back to directory entry.
; Input:      Directory Entry LBA -> entry_lba+0..3
;             Entry Buffer Offset -> entry_ptr_lo, entry_ptr_hi
;             File Head Cluster   -> start_clus_lo, start_clus_hi
;             32-bit File Size    -> size+0, size+1, size+2, size+3
; Output:     Carry Clear = Success (A = $00)
;             Carry Set   = Error (A = SD Hardware Error Code)
; Modifies:   A, X, Y, arg_0..3, buff_lo/hi
;===========================================================================  
     
fs_close:
   lda fs_flags
   and #FS_OPEN
   bne :+
       lda #ERR_INV_OPERATION 
       sec
       rts
       :
       
   lda fs_flags    
   and #FS_MODIFIED
   beq @done
   
  @update_dir: 
   lda entry_lba+0
   sta arg_3
   lda entry_lba+1
   sta arg_2
   lda entry_lba+2
   sta arg_1
   lda entry_lba+3
   sta arg_0
   
   lda #<sd_buff  ;init buff
   sta buff_lo
   lda #>sd_buff
   sta buff_hi
     
   jsr sd_read_block 
   bcc :+
       rts
       :
  
   ldy #26
   lda start_clus_lo
   sta (entry_ptr_lo),y
   iny
   lda start_clus_hi
   sta (entry_ptr_lo),y  
  
   ldy #28
   lda size+0
   sta (entry_ptr_lo),y
   iny
   lda size+1
   sta (entry_ptr_lo),y
   iny    
   lda #0
   sta (entry_ptr_lo),y  
   iny
   sta (entry_ptr_lo),y  
   
   jsr sd_write_block 
   bcc :+
       rts
       :
       
  @done:
   lda #0
   sta fs_flags
   clc
   rts
   
;===========================================================================
; Function:   fs_read
; Layer:      High-Level System Call (fs_api.s)
; Purpose:    Bulk streams exact file byte count directly into RAM buffer.
; Inputs:     item_cluster_lo/hi = File start cluster (from directory entry)
;             size+0, size+1     = 16-bit byte count to read
;             buff_lo, buff_hi   = Target RAM buffer address
; Outputs:    Carry Clear = Read successful
;             Carry Set   = Error (A = Error code or SD failure)
; Modifies:   A, X, Y, cluster_lo/hi, sector_remain, temp_lo/hi
;===========================================================================
 
  fs_read:
  
     lda buff_lo   ;Saving user buffer pointer
     pha
     lda buff_hi
     pha
     
     lda item_cluster_lo
     sta cluster_lo
     lda item_cluster_hi
     sta cluster_hi
     
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
     pla  ;Restore User buffer ptr
     sta buff_hi
     pla
     sta buff_lo
   
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
     lda #ERR_PREMATURE_EOF
  @sd_failed:  
     tax 
     pla
     pla        ;clean up stack
     sec
     txa
     rts
;===========================================================================
; Function:   fs_write
; Layer:      High-Level System Call (fs_api.s)
; Purpose:    Writes or appends data payload to a FAT16 file on disk.
; Inputs:     A                  = Mode (MODE_APPEND or MODE_WRITE)
;             start_clus_lo/hi   = File start cluster (from directory entry)
;             size+0, size+1     = Current file size in bytes
;             payload_size+0..1  = 16-bit byte count to write
;             src_lo, src_hi     = Source RAM buffer address
; Outputs:    Carry Clear = Write successful (size & start_clus updated)
;             Carry Set   = Error (A = Error code or SD failure)
; Modifies:   A, X, Y, cluster_lo/hi, sector_remain, temp_lo/hi, arg_0..3
;===========================================================================

 
 fs_write:
    cmp #MODE_APPEND
    beq @append_mode
    cmp #MODE_WRITE
    bne :+
        jmp @overwrite_mode 
        :
    lda #ERR_INV_MODE
    sec
    rts
   
   
 @append_mode:
    lda item_cluster_lo
    sta cluster_lo
    lda item_cluster_hi
    sta cluster_hi
    
  @loop:
    jsr get_next_cluster   ;find last cluster 
    bcc :+
        rts
        :
    bpl @loop  
    
    jsr calc_append_offsets
    
    jsr ClusterToLBA 
    
    lda arg_3
    clc
    adc sector_index
    sta arg_3
    bcc :+
        inc arg_2
    bne :+
        inc arg_1
    bne :+
        inc arg_0
        :
    
    lda size+0
    sta temp+2
    lda size+1
    sta temp+3
    
    lda payload_size+0
    sta size+0
    lda payload_size+1
    sta size+1
    
    jsr size_to_sectors      ;get sector_left 
    lda sector_remain
    beq @allocate_cluster
    
    lda #0
    sta temp_lo
    sta temp_hi
    
    lda byte_ofs_lo
    ora byte_ofs_hi
    beq @write_sector
    
    
    lda #<sd_buff
    sta buff_lo
    lda #>sd_buff
    sta buff_hi
     
    jsr sd_read_block
    bcc :+
        rts
        :
        
    lda byte_ofs_lo      ;carry already cleared
    adc buff_lo
    sta buff_lo
    lda byte_ofs_hi
    adc buff_hi
    sta buff_hi
    
    lda byte_ofs_hi
    beq @full_page
    
    lda byte_ofs_lo
    bne @partial_page
    
  @full_page:  
    ldy #0
   : 
    lda (src_lo),y
    sta (buff_lo),y
    iny
    bne :-
    
    inc buff_hi
    inc src_hi
    inc temp_hi
    
  @partial_page:
    lda #0
    sec
    sbc byte_ofs_lo
    beq @write_tail
    tax
    
    ldy #0
    :  
    lda (src_lo),y
    sta (buff_lo),y
    iny
    dex
    bne :-
    
    tya 
    clc
    adc src_lo
    sta src_lo
    bcc :+
         inc src_hi
         :
    
    sty temp_lo
  @write_tail:
    lda #<sd_buff
    sta buff_lo
    lda #>sd_buff
    sta buff_hi
    
    jsr sd_write_block
    bcc :+
        rts
        :
        
    dec sector_left
    beq @write_done 
    
    dec sector_remain
    beq @update_size
    
    inc arg_3
    bne :+
        inc arg_2
    bne :+      
        inc arg_1
    bne :+
        inc arg_0
        :    
  @write_sector:
    lda src_lo
    sta buff_lo
    lda src_hi
    sta buff_hi
    
    jsr sd_write_block
    bcc :+
         rts
         :
       
    inc arg_3
    bne :+
        inc arg_2
    bne :+      
        inc arg_1
    bne :+
        inc arg_0
        :    
    inc src_hi
    inc src_hi
    
    inc temp_hi 
    inc temp_hi
    
    dec sector_left
    beq @write_done
    dec sector_remain
    bne @write_sector

 @update_size:
    lda size+0
    sec
    sbc temp_lo
    sta size+0
    lda size+1
    sbc temp_hi
    sta size+1
    
  @allocate_cluster:
    jsr allocate_cluster_chain
    bcc :+
        rts
        :
        
    jsr link_two_chain
    bcc :+
        rts
        :
        
    jsr write_to_cluster
    bcc :+
        rts
        :     
        
  @write_done: 
    lda temp+2
    clc
    adc payload_size+0
    sta size+0
    lda temp+3
    adc payload_size+1
    sta size+1
    
    jmp @done
    
    
 @overwrite_mode:
    lda item_cluster_lo
    sta start_clus_lo
    lda item_cluster_hi
    sta start_clus_hi
    
    jsr free_cluster_chain 
    bcc :+
        rts
        :
    jsr allocate_cluster_chain
    bcc :+
       rts
        :
    
    jsr write_to_cluster
    bcc :+
       rts
        :         
    
    lda clus_buff+0
    sta start_clus_lo
    lda clus_buff+1
    sta start_clus_hi
     
    lda payload_size+0
    sta size+0
    lda payload_size+1
    sta size+1
 
  @done:   
    lda fs_flags
    ora #FS_MODIFIED 
    sta fs_flags
    clc  
    rts
;===========================================================================
; Function:   fs_readdir
; Layer:      High-Level System Call (fs_api.s)
; Purpose:    Streams the next 512-byte directory sector, extracts up to 16
;             valid entries (288 bytes max) into RAM, and steps cluster chains.
; Inputs:     list_lo, list_hi   = Pointer to application's 288-byte RAM buffer
;             item_cluster_lo/hi = Active directory cluster pointer
;             dir_index          = Current sector offset ($00..$7F, $FF = EOF)
;             fs_flags           = Active handle bitmask (DIR_OPEN, DIR_ROOT)
;             sec_per_clus       = FAT sectors-per-cluster count
; Outputs:    Carry Clear = Read successful (A = Valid entry count, 0-16)
;             Carry Set   = Error (A = ERR_INV_OPERATION, ERR_DIR_END, SD failure)
; Modifies:   A, X, Y, dir_index, item_cluster_lo/hi, cluster_lo/hi, arg_0..3
;===========================================================================    
 
fs_readdir:
   lda fs_flags
   and #DIR_OPEN
   bne :+
       lda #ERR_INV_OPERATION
       sec
       rts
       :
       
   lda item_cluster_lo
   sta cluster_lo
   lda item_cluster_hi
   sta cluster_hi
   
   jsr ClusterToLBA
   
   lda dir_index
   bpl :+
       lda #ERR_DIR_END
       sec
       rts
       :
   clc
   adc arg_3
   sta arg_3
   bcc :+
       inc arg_2
   bne :+
       inc arg_1
   bne :+
       inc arg_0
       :        
   
   jsr list_directory 
   bcc :+
       rts
       :
   cmp #$FF
   beq @end_of_dir 
   
   lda fs_flags
   and #DIR_ROOT
   beq @not_root 
   
   ldx dir_index
   inx
   cpx #32
   bne @update_index
   
 @end_of_dir:    
   lda #$ff
   sta dir_index
   lda ENTRY_REC       
   clc
   rts
       
 @not_root:  
   ldx dir_index
   inx
   cpx sec_per_clus
   beq @next_cluster
 
 @update_index:
   lda ENTRY_REC       
   stx dir_index
   clc
   rts
       
 @next_cluster:
   jsr get_next_cluster
   bcc :+
       rts
       :
   bmi @end_of_dir
   
   lda cluster_lo
   sta item_cluster_lo 
   lda cluster_hi
   sta item_cluster_hi
   
   lda #0
   sta dir_index
   
   lda ENTRY_REC       
   clc
   rts