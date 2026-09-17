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
