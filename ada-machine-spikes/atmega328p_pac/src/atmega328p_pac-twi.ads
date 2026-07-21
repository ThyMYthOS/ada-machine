--  ATmega328P TWI (I2C) -- TWBR/TWSR/TWAR/TWDR/TWCR, data-space addresses per
--  the datasheet register summary (already memory-mapped, no +0x20 I/O-space
--  offset needed -- unlike PORTB/SPI below 0x40). No FIFO: one hardware action
--  (START, address+R/W, or one data byte) in flight at a time, gated by TWINT
--  (TODO.md P0 #1's "register-event state machine, not a command FIFO").
with System;
with Interfaces; use Interfaces;

package ATmega328P_PAC.TWI
  with Preelaborate, SPARK_Mode
is
   TWBR : Unsigned_8         --  bit rate divisor
     with Volatile, Async_Readers, Async_Writers,
          Address => System'To_Address (16#B8#);
   TWSR : Unsigned_8         --  status: TWS7:3 (code), TWPS1:0 (prescaler)
     with Volatile, Async_Readers, Async_Writers,
          Address => System'To_Address (16#B9#);
   TWAR : Unsigned_8         --  slave address (unused: master-only driver)
     with Volatile, Async_Readers, Async_Writers,
          Address => System'To_Address (16#BA#);
   TWDR : Unsigned_8         --  data: address+R/W or one data byte
     with Volatile, Async_Readers, Async_Writers,
          Effective_Reads => True, Effective_Writes => True,
          Address => System'To_Address (16#BB#);
   TWCR : Unsigned_8         --  control: TWINT, TWEA, TWSTA, TWSTO, TWEN, TWIE
     with Volatile, Async_Readers, Async_Writers,
          Address => System'To_Address (16#BC#);
                              --  no Effective_Reads/Writes: read by
                              --  Can_Push/Can_Pop, and SPARK forbids a
                              --  function from reading a global with
                              --  Effective_Reads -- same shape as
                              --  ATmega328P_PAC.SPI's SPCR/SPSR (read by
                              --  functions there too, unlike SPDR/TWDR
                              --  which are only ever touched by procedures).

   TWCR_TWIE  : constant := 2#1# * 2**0;  --  bit 0: interrupt enable (unused)
   TWCR_TWEN  : constant := 2#1# * 2**2;  --  bit 2: TWI enable
   TWCR_TWWC  : constant := 2#1# * 2**3;  --  bit 3: write collision (status)
   TWCR_TWSTO : constant := 2#1# * 2**4;  --  bit 4: issue STOP
   TWCR_TWSTA : constant := 2#1# * 2**5;  --  bit 5: issue (repeated) START
   TWCR_TWEA  : constant := 2#1# * 2**6;  --  bit 6: ACK enable (else NACK)
   TWCR_TWINT : constant := 2#1# * 2**7;  --  bit 7: action-complete flag,
                                            --  write 1 to clear + start next

   TWSR_STATUS_MASK : constant := 16#F8#;  --  TWS7:3

   --  Status codes (TWSR and TWSR_STATUS_MASK), per the datasheet's TWI
   --  status-code tables -- confirmed against avr-libc's <util/twi.h>.
   TW_BUS_ERROR    : constant := 16#00#;
   TW_START        : constant := 16#08#;
   TW_REP_START    : constant := 16#10#;
   TW_MT_SLA_ACK   : constant := 16#18#;  --  Master Transmitter
   TW_MT_SLA_NACK  : constant := 16#20#;
   TW_MT_DATA_ACK  : constant := 16#28#;
   TW_MT_DATA_NACK : constant := 16#30#;
   TW_MT_ARB_LOST  : constant := 16#38#;
   TW_MR_ARB_LOST  : constant := 16#38#;  --  Master Receiver
   TW_MR_SLA_ACK   : constant := 16#40#;
   TW_MR_SLA_NACK  : constant := 16#48#;
   TW_MR_DATA_ACK  : constant := 16#50#;
   TW_MR_DATA_NACK : constant := 16#58#;
end ATmega328P_PAC.TWI;
