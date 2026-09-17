.export sd_init
.import  spi_transfer_byte, spi_receive_byte
.include "zp_const.inc"

.segment "CODE"


LAYER_1:

  sd_cs_low:
    lda SPI_CTRL_REG
    and #~SD_CS_BIT_MASK
    sta SPI_CTRL_REG
    rts
    
  sd_cs_high:
    lda SPI_CTRL_REG
    ora #SD_CS_BIT_MASK
    sta SPI_CTRL_REG

    lda #$FF
    jmp spi_transfer_byte
    


LAYER_2:  
      
  ;------------------------------------------
  ;         spi_send_cmd (Low-Level)
  ; About:  Send 6-byte SD command packet
  ; Input:  command byte -> cmd_byte
  ;         sector id -> arg_0(MSB),..arg_3(LSB)
  ;         CRC byte -> crc_byte
  ; Modifies: A
  ;___________________________________________
  sd_send_cmd:
    lda cmd_byte
    jsr spi_transfer_byte 
    lda arg_0
    jsr spi_transfer_byte
    lda arg_1
    jsr spi_transfer_byte 
    lda arg_2
    jsr spi_transfer_byte
    lda arg_3
    jsr spi_transfer_byte 
    lda crc_byte
    jsr spi_transfer_byte
    rts

  ;------------------------------------------
  ;         spi_read_resp (Low-Level)
  ; About:  Recieve response packet
  ; Input:  A = response type
  ; Output: response bytes -> resp_byte[resp_type]
  ; Modifies: A,Y
  ;___________________________________________
 sd_read_resp:
    sta resp_type
    ldy #0 ;256 retry
  @retry:
    jsr spi_receive_byte 
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
    jsr spi_receive_byte 
    jmp @resp_loop 
 @done:   
    rts

  ;---------------------------------------------------
  ;         sd_init (Mid-Level)
  ; About:  initilise sd card with detailed error flag
  ; Output: success(CLC),Failure(SEC) with error code in Accumalator
  ; Modifies: A,Y
  ;___________________________________________________

 sd_init:
    jsr spi_set_clock_slow      ;Init routine should held in low clock speed <400khz

    ;To wakeup sd,pull CS high,send 74 clock cycle with MOSI 1
    jsr sd_cs_high               ;Pull CS high  
    ldy #9                   ;9*8+8(from cs_high) = 80 total cycle
  @init_loop:
    lda #$FF                  ;Put MOSI 1 throughout
    jsr spi_transfer_byte     ;Do 8 cycle per routine
    dey
    bne @init_loop
    
    ;To enter SPI mode,pull CS low,send CMD0 
    jsr sd_cs_low
    lda #CMD0                 ;reset cmd
    sta cmd_byte
  
    lda #0                    ;no argument
    sta arg_0
    sta arg_1
    sta arg_2
    sta arg_3
     
    lda #CMD0_CRC
    sta crc_byte
    jsr sd_send_cmd 

    lda #R1                   ;response type
    jsr sd_read_resp         ;Get response
    lda resp_byte+0
    cmp #idle_state
    beq @spi_success 

    ldy #ERR_CMD0
    jmp @sd_init_fail
  @spi_success:
    jsr sd_cs_high            ;pull CS high after completing a command -response series 

    ;To check voltage compability    
    jsr sd_cs_low
    lda #CMD8 
    sta cmd_byte
  
    lda #0             ;argument 0x000001AA
    sta arg_0
    sta arg_1
    lda #1
    sta arg_2
    lda #$AA
    sta arg_3
     
    lda #CMD8_CRC
    sta crc_byte
    jsr sd_send_cmd 

    ;Get response
    lda #R7 
    jsr sd_read_resp 
    lda resp_byte+0        ;Read first byte
    cmp #idle_state
    beq @check_echo

    ldy #ERR_CMD8
    jmp @sd_init_fail   
  @check_echo:
    lda resp_byte+4        ;Read 5th byte
    cmp #echo_pattern
    beq @cmd8_success 

    ldy #ERR_ECHO
    jmp @sd_init_fail
 
  @cmd8_success:
    jsr sd_cs_high

        ;To init a counter for count retry
    lda #00   ;allows 1024 retries before giveup
    sta timeout_low
    lda #04
    sta timeout_high
    
    ;To init card,Send cmd55 followed by acmd41 in a loop
  @init_card_loop:
    jsr sd_cs_low
    lda #CMD55
    sta cmd_byte
    lda #0 ;no arg
    sta arg_0
    sta arg_1
    sta arg_2
    sta arg_3
     
    lda #CMD55_CRC
    sta crc_byte
    jsr sd_send_cmd 
    
    lda #R1                   ;response type
    jsr sd_read_resp         ;Get response
    lda resp_byte+0
    cmp #idle_state
    beq @cmd55_success

    ldy #ERR_CMD55
    jmp @sd_init_fail
  @cmd55_success:
    jsr sd_cs_high
   
    ; sending ACMD41
    jsr sd_cs_low
    lda #ACMD41
    sta cmd_byte
    lda #$40                 ;argument 0x40000000
    sta arg_0
    lda #0
    sta arg_1
    sta arg_2
    sta arg_3
     
    lda #ACMD41_CRC
    sta crc_byte
    jsr sd_send_cmd 
    
    lda #R1               ;response type
    jsr sd_read_resp     ;Get response
    lda resp_byte+0
    pha                      ; Save response byte on stack

    jsr sd_cs_high           ; Deselect CS to finish ACMD41 transaction

    pla
    cmp #active_state
    beq @do_cmd16
    cmp #idle_state
    beq  @do_timeout

    ldy #ERR_ACMD41
    jmp @sd_init_fail
  @do_timeout:
    ; Timeout counter dec
    dec timeout_low
    bne @init_card_loop
    dec timeout_high
    bne @init_card_loop
    
    ldy #ERR_TIMEOUT
    jmp @sd_init_fail
    
  @do_cmd16:
    ; Force 512 block reading for SDSC cards
    jsr sd_cs_low
    lda  #CMD16         
    sta cmd_byte
    lda #$0                 ;argument 0x00000200
    sta arg_0
    sta arg_1
    sta arg_3
    lda #$02
    sta arg_2

    lda #$01                ; Set dummy CRC (end bit must be 1)
    sta crc_byte
    jsr sd_send_cmd

    lda #R1                 ; Read R1 response byte
    jsr sd_read_resp
    
    lda resp_byte+0
    cmp #active_state       ; Check if CMD16 returned $00 (success)
    beq  @sd_init_success
    
    ldy #ERR_CMD16          ; Load CMD16 failure error code
    jmp @sd_init_fail

  @sd_init_success:
    jsr sd_cs_high          ;Deselect card

    jsr spi_set_clock_fast ;Seting maximium speed for rest operations
    clc             ;success flag
    rts
  @sd_init_fail:
    jsr sd_cs_high
    sec             ;fail flag
    tya             ;Restore error byte
    rts
  
  ;---------------------------------------------------
  ;         sd_read_block (Mid-Level)
  ; About:  Read 512 bytes(a block) from sd
  ; Input:  sector id -> arg_0(MSB),..arg_3(LSB)
  ;         Stream location -> buff_lo/buff_hi
  ; Output: 512 byte in buff_lo/buff_hi ptr
  ;         success(CLC),Failure(SEC) with error code in Accumalator
  ; Modifies: A,Y (X preserved)
  ;___________________________________________________
 sd_read_block:
    jsr sd_cs_low ;Start of transaction
    
    ; Send cmd17 with sector no as argument
    lda #CMD17
    sta cmd_byte
   
    lda #CMD17_CRC
    sta crc_byte
    jsr sd_send_cmd 
    
    lda #R1 ;response type
    jsr sd_read_resp ;Get response
    lda resp_byte+0 
    beq @cmd17_success       ;Response $00 = Active/success 
    
    ldy #ERR_CMD17
    jmp @sd_read_fail

 @cmd17_success:
     ;setup a timeout counter
    ldy #0
    lda #$10                 ;4096 tries
    sta timeout_hi
    
 @wait_token:
     jsr spi_receive_byte 
     cmp #$fe ;Start token
     beq @got_response 
     
     dey
     bne @wait_token 
     dec timeout_hi
     bne @wait_token
     
     ldy #ERR_TIMEOUT
     jmp @sd_read_fail

 @got_response:
     ldy #0
 @page1_loop:
     jsr spi_receive_byte 
     sta (buff_lo),y ;storing output
     iny
     bne @page1_loop
     
     inc buff_hi
  @page2_loop: ;Y is at 0
     jsr spi_receive_byte 
     sta (buff_lo),y ;storing output
     iny
     bne @page2_loop
   
     ; Read 2 extra crc byte and discard it
     jsr spi_receive_byte   
     jsr spi_receive_byte   
     
     jsr sd_cs_high ;transaction closed 

     dec buff_hi ;Preserving state
     
     clc  ;success flag
     rts
  @sd_read_fail:
     jsr sd_cs_high
     tya 
     sec
     rts
     
     
  ;---------------------------------------------------
  ;         sd_write_block (Mid-Level)
  ; About:  Write 512 bytes(a block) to sd
  ; Input:  sector id -> arg_0(MSB),..arg_3(LSB)
  ;         Read location -> buff_lo/buff_hi
  ; Output: success(CLC),Failure(SEC) with error code in Accumalator
  ; Modifies: A,Y (X preserved)
  ;___________________________________________________
     
  sd_write_block:
    jsr sd_cs_low          ;Start of transaction
    
    ; Send cmd24 with sector no as argument
    lda #CMD24
    sta cmd_byte
    
    lda #CMD24_CRC
    sta crc_byte
    jsr sd_send_cmd 
    
    lda #R1               ;response type
    jsr sd_read_resp      ;Get response
    lda resp_byte+0 
    cmp #active_state
    beq @cmd24_success 
    
    ldy #ERR_CMD24
    jmp @sd_write_fail
  @cmd24_success:
    lda #$ff
    jsr spi_transfer_byte ;send a dummy
   
    lda #$fe              ;send Data start token
    jsr spi_transfer_byte
    ldy #0
  @page1_loop:
    lda (buff_lo),y
    jsr spi_transfer_byte
    iny
    bne @page1_loop
    
    inc buff_hi           ;Increment to next 256 byte
  @page2_loop:
    lda (buff_lo),y
    jsr spi_transfer_byte
    iny
    bne @page2_loop
     
    ; Send 2 dummy CRC bytes
    lda #$ff
    jsr spi_transfer_byte
    jsr spi_transfer_byte  

    
    ; setup a timeout counter
    ldy #0
    lda #$10               ;4096 tries
    sta timeout_hi 
    
 @wait_token:    
    ;get token
    jsr spi_receive_byte 
    cmp #$ff
    bne @got_token

    dey 
    bne @wait_token
    dec timeout_hi
    bne @wait_token
    
    ldy #ERR_TIMEOUT
    jmp @mid_failed
  @got_token: 
    and #$1F               ;mask out top 3 bits 
    cmp #$05 ;$05 for success 
    beq @wait_busy 
    
    ldy #ERR_WRITE_REJ     ;write rejection error
    jmp @mid_failed
    
 @start_wait_busy:
    ldy #0
    lda #$80
    sta timeout_hi   
 @wait_busy:               ;wait to complete write cycle
    jsr spi_receive_byte 
    cmp #$00
    bne @write_success 
    
    dey
    bne @wait_busy
    dec timeout_hi
    bne @wait_busy
    
    ldy #ERR_TIMEOUT
    jmp @sd_write_fail

 @write_success:
    dec buff_hi            ;restoring buff_hi
    
    jsr sd_cs_high         ;transaction closed
    lda #0 
    clc
    rts
  @mid_failed:
    dec buff_hi            ;restoring buff_hi
  @sd_write_fail:
    jsr sd_cs_high
    sec
    tya                    ;Restore error code
    rts
    
    
    