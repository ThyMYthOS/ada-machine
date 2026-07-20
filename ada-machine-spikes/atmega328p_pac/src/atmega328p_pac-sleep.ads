--  ATmega328P SMCR -- Sleep Mode Control Register, data-space address
--  0x53. Idle mode (SM[2:0] = 000) keeps every peripheral clocked, so
--  the SPI_STC interrupt still wakes the core (Appendix B's Sleep_Idle).
with System;
with Interfaces; use Interfaces;

package ATmega328P_PAC.Sleep
  with Preelaborate, SPARK_Mode
is
   SMCR : Unsigned_8
     with Volatile, Async_Readers, Async_Writers,
          Address => System'To_Address (16#53#);

   SMCR_SE : constant := 2#1#;   --  bit 0: sleep enable (arm, one shot)
end ATmega328P_PAC.Sleep;
