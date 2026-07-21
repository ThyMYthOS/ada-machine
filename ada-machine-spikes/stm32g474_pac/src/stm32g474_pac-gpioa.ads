--  STM32G474 GPIOA -- base 0x4800_0000 (AHB2PERIPH_BASE + 0x0000, confirmed
--  against the CMSIS device header). Curated to exactly what the status
--  LED (PA5, the Nucleo-G474RE convention) needs: mode-select and the
--  atomic set/reset register. No IDR/OTYPER/PUPDR -- an LED is a plain
--  push-pull output (OTYPER's reset default), never read back.
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package STM32G474_PAC.GPIOA
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#4800_0000#);

   --  MODER (0x00) -- 2 bits per pin: 00 input / 01 output / 10 AF / 11
   --  analog. Written once at Configure time.
   MODER : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#00#;

   --  BSRR (0x18) -- atomic set/reset: bit n sets pin n, bit (n+16)
   --  resets it. Write-only pulse register (§9's converged ESP32-C3
   --  encoding, TODO #8): Effective_Writes, not a blanket Volatile --
   --  this IS the data phase (§6.4), touched on every Set_High/Set_Low.
   BSRR : Unsigned_32
     with Volatile, Async_Readers, Effective_Writes => True,
          Address => Base + 16#18#;

end STM32G474_PAC.GPIOA;
