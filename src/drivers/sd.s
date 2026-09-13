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
  ; Modifies: A,X
  ;___________________________________________
 sd_read_resp:
    sta resp_type
    ldx #0 ;256 retry
  @retry:
    jsr spi_receive_byte 
    cmp #$FF
    bne @got_response
    dex
    bne @retry
  
    lda #$FF ;No response error code
    sta  resp_byte
    rts
  @got_response:
    ldx #0
  @resp_loop:
    sta resp_byte,x
    inx
    cpx resp_type
    beq @done
    jsr spi_receive_byte 
    jmp @resp_loop 
 @done:   
    rts

  ;---------------------------------------------------
  ;         sd_init (Mid-Level)
  ; About:  initilise sd card with detailed error flag
  ; Output: success(CLC),Failure(SEC) with error code in Accumalator
  ; Modifies: A,X
  ;___________________________________________________

LAYER_3:
 sd_init:
    jsr spi_set_clock_slow      ;Init routine should held in low clock speed <400khz

    ;To wakeup sd,pull CS high,send 74 clock cycle with MOSI 1
    jsr sd_cs_high               ;Pull CS high  
    ldx #9                   ;9*8+8(from cs_high) = 80 total cycle
  @init_loop:
    lda #$FF                  ;Put MOSI 1 throughout
    jsr spi_transfer_byte     ;Do 8 cycle per routine
    dex 
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

    lda #ERR_CMD0
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

    lda #ERR_CMD8
    jmp @sd_init_fail   
  @check_echo:
    lda resp_byte+4        ;Read 5th byte
    cmp #echo_pattern
    beq @cmd8_success 

    lda #ERR_ECHO
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

    lda #ERR_CMD55
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

    lda #ERR_ACMD41
    jmp @sd_init_fail
  @do_timeout:
    ; Timeout counter dec
    dec timeout_low
    bne @init_card_loop
    dec timeout_high
    bne @init_card_loop
    
    lda #ERR_TIMEOUT
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
    
    lda #ERR_CMD16          ; Load CMD16 failure error code
    jmp @sd_init_fail

  @sd_init_success:
    jsr sd_cs_high          ;Deselect card

    jsr spi_set_clock_fast ;Seting maximium speed for rest operations
    clc             ;success flag
    rts
  @sd_init_fail:
    tax             ;Saves error byte in X
    jsr sd_cs_high
    sec             ;fail flag
    txa             ;Restore error byte
    rts