

.include "zp_const.inc"
.include "ppu.inc"
.import default_font, default_palette
.export kernal_boot

.segment "CODE"
kernal_boot:
    lda #$20                     
    jsr clear_nametable
    
    jsr load_rom_palette

    jsr load_rom_font
    
    jsr sd_init
    bmi sd_init_failed
    
    jsr read_mbr
    bmi format_error
    
    jsr read_bootsector
    
    jsr init_sys_font
    jsr init_sys_palette 
    
    jmp launch_desktop
    
    
 sys_launch:
   @load_program:
   
    jsr sys_render_off
    jsr sys_nmi_off
    
    lda app_cluster_lo 
    sta cluster_lo
    lda app_cluster_hi
    sta cluster_hi

    lda #$00
    sta buff_lo
    lda #$60
    sta buff_hi
    
    jsr size_to_sectors
    jsr load_file
    beq  @safety_net
  
  @launch_failed:
    ;yet to code
    ;
    jmp launch_desktop
  @safety_net:
    lda sys_flags
    ora #APP_ACTIVE         ; Mark app as running
    and #~dirty_font        ; Clear ext font flag
    sta sys_flags
    
    lda #$00
    sta current_ram_bank
    sta RAM_BANK_ADDR               ; Set $A000-$BFFF to App SRAM Bank 0
    
    ldx #$FF
    txs                     ; Reset stack pointer to top of stack ($FF)
  
  @run_app:    
    jsr $6000
    jmp sys_exit
    
    
 sys_exit:
    jsr sys_render_off
    jsr sys_nmi_off
    
    ldx #$FF
    txs                     ; Reset stack pointer to top of stack ($FF)
     
    jsr load_sys_palette 
    
    jsr restore_sys_font
    
    lda sys_flags
    and #~APP_ACTIVE         ; Mark app as not running
    
    lda #$00
    sta current_ram_bank
    sta RAM_BANK_ADDR               ; Set $A000-$BFFF to App SRAM Bank 0

    jmp launch_desktop
    
 
 
 launch_desktop:
    lda #$00
    sta PPU_MASK    ;Taking Precaution by turning off render
    jsr sys_nmi_off
    
    lda #$00
    sta buff_lo
    lda #$60
    sta buff_hi  ;Setting universal load point
    
    lda sys_flags
    and #($FF ^ APP_ACTIVE)
    sta sys_flags
    
    lda sys_flags
    and #desktop_ready
    beq @launch_from_scratch
    
  @fast_launch:
    lda desktop_clus_lo
    sta cluster_lo
    lda desktop_clus_hi
    sta cluster_hi
    
    lda desktop_sectors
    sta sector_to_read
    
    jsr load_file
    bmi @desktop_missing
    
    jmp $6000
    
  @launch_from_scratch:   
    lda #<sys_desktop_path
    sta path_lo
    lda #>sys_desktop_path
    sta path_hi
    
    jsr path_resolve
    bmi @desktop_missing
    
    lda cluster_lo
    sta desktop_clus_lo
    lda cluster_hi
    sta desktop_clus_hi
    
    
    jsr size_to_sectors
    
    lda sector_to_read
    sta desktop_sectors
    
    jsr load_file
    bmi @desktop_missing
    
    lda sys_flags 
    ora #desktop_ready
    sta sys_flags
    
    jmp $6000
  
  @desktop_missing:
    ;
    ;yet to code