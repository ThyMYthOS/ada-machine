--  STM32G474 TIM2 -- base 0x4000_0000 (APB1PERIPH_BASE + 0x0000, confirmed
--  against the CMSIS device header). TIM2 is one of G474's 32-bit
--  general-purpose timers; curated to exactly what STM32G474.Clock needs
--  to drive it as a free-running 1 Hz seconds counter (§6.5: L2 exposes
--  reading time, never owning an interrupt -- this spike's Clock has no
--  interrupt at all, just a prescaled free-running CNT).
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package STM32G474_PAC.TIM2
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#4000_0000#);

   --  CR1 (0x00) -- bit 0 CEN (counter enable). Written once at Enable time.
   CR1 : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#00#;
   CR1_CEN : constant := 2#1#;

   --  PSC (0x28) / ARR (0x2C) -- prescaler and auto-reload, set once at
   --  Enable time to turn the APB1 timer clock into a 1 Hz count rate
   --  (D8: derived from an assumed default HSI16 core clock, native
   --  configuration -- same footing as RP2040.I2C0's HCNT/LCNT).
   PSC : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#28#;
   ARR : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#2C#;

   --  CNT (0x24) -- the free-running counter itself: read-only from
   --  software, no side effect from reading, changes asynchronously.
   --  Same shape as RP2040_PAC.Timer's TIMERAWH/TIMERAWL.
   CNT : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#24#;

end STM32G474_PAC.TIM2;
