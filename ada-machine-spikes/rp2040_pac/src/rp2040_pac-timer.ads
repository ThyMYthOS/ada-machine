--  RP2040 TIMER -- free-running 1 MHz 64-bit counter, base 0x4005_4000.
--  TIMERAWH/TIMERAWL are the un-latched raw halves (read-only); the safe
--  64-bit read pattern (reread-on-rollover) lives in the HAL body, not
--  here -- the PAC owns only the register shapes (§9 rule 5).
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package RP2040_PAC.Timer
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#4005_4000#);

   TIMERAWH : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#24#;
   TIMERAWL : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#28#;

end RP2040_PAC.Timer;
