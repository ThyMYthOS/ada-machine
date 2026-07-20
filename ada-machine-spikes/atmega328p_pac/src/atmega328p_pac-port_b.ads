--  ATmega328P PORTB -- data-space (memory-mapped I/O) addresses, per the
--  datasheet register summary. SPI's hardware pins (SCK=PB5, MISO=PB4,
--  MOSI=PB3, /SS=PB2) live here; chip selects for spike 2's regmap
--  binding are ordinary PORTB outputs too (Appendix C.1).
with System;
with Interfaces; use Interfaces;

package ATmega328P_PAC.Port_B
  with Preelaborate, SPARK_Mode
is
   PINB  : Unsigned_8
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => System'To_Address (16#23#);
   DDRB  : Unsigned_8
     with Volatile, Async_Readers, Async_Writers,
          Address => System'To_Address (16#24#);
   PORTB : Unsigned_8
     with Volatile, Async_Readers, Async_Writers,
          Address => System'To_Address (16#25#);
end ATmega328P_PAC.Port_B;
