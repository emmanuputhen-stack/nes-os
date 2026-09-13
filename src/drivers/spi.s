 .export  spi_transfer_byte, spi_receive_byte
.include "zp_const.inc"

.segment "CODE"
 
 ;------------------------------------------
;         spi_set_clock_slow (Low-Level)
; About: Set SPI bus clock to < 400 kHz for SD initialization
; Modifies: A
;------------------------------------------
spi_set_clock_slow:
    lda SPI_CTRL_REG
    ora #SPI_DIV_SLOW_MASK   ; Set clock divider bits for slow speed (<400kHz)
    sta SPI_CTRL_REG
    rts

;------------------------------------------
;         spi_set_clock_fast (Low-Level)
; About: Set SPI bus clock to max speed for data transfers
; Modifies: A
;------------------------------------------
spi_set_clock_fast:
    lda SPI_CTRL_REG
    and #~SPI_DIV_SLOW_MASK  ; Clear divider bits to restore maximum speed
    sta SPI_CTRL_REG
    rts
 
 ;------------------------------------------
  ;         spi_transfer (Low-Level)
  ; About: Hardwade accelerated transceive byte  
  ; Input:  Accumulater(A) = byte to send
  ; Output: Accumalator(A) = Byte to recieve  
  ; Modifies: A
  ;___________________________________________
 spi_transfer_byte:
    sta SPI_DATA_REG ;Transfer byte

  @wait_engine:
    lda SPI_CTRL_REG ; Test bit 7 (BUSY)
    bmi @wait_engine
    
    lda SPI_DATA_REG ;Read recieved byte
    rts
    
  ;------------------------------------------
  ;         spi_receive (Low-Level)
  ; About: receive byte  
  ; Output: Accumalator(A) = Byte to recieve 
  ; Modifies: A
  ;___________________________________________  
 spi_receive_byte:
    lda #SPI_DUMMY_BYTE
    jmp spi_transfer_byte
    