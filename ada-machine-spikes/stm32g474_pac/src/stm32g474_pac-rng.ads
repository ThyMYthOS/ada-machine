--  STM32G474 RNG -- base 0x5006_0800 (confirmed against the CMSIS device
--  header: an AHB2-region peripheral, alongside OTG_FS/ADC/AES on the
--  L4/G4-family memory map -- the classic 3-register RNG block, present
--  since F2/F4 (RM0440 ch. 26). Some newer STM32 parts (L5/U5) need an
--  extra NIST-conditioning init sequence (CONDRST/CONFIG fields, AN4230);
--  whether STM32G474 needs it too is an open item this hand-authored PAC
--  does not resolve -- out of scope for a logic-only spike (no real RNG
--  is ever read outside host_test's mock).
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package STM32G474_PAC.RNG
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#5006_0800#);

   --  CR (0x00) -- bit 2 RNGEN. Written once at Enable time.
   CR : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#00#;
   CR_RNGEN : constant := 2#1# * 2**2;

   --  SR (0x04) -- status, hardware-set, no side effect from reading.
   SR : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#04#;
   SR_DRDY : constant := 2#1#;                     --  bit 0: a word is ready
   SR_CECS : constant := 2#1# * 2**1;               --  bit 1: clock error
   SR_SECS : constant := 2#1# * 2**2;               --  bit 2: seed error

   --  DR (0x08) -- reading consumes the word and clears DRDY (a side
   --  effect); hardware refills it. Same aspect set as I2C1.RXDR.
   DR : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Effective_Reads => True,
          Address => Base + 16#08#;

end STM32G474_PAC.RNG;
