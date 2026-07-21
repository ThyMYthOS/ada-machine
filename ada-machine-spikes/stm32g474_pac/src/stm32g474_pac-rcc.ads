--  STM32G474 RCC -- base 0x4002_1000 (confirmed against the CMSIS device
--  header: AHB1PERIPH_BASE + 0x1000). Curated to exactly the two enable
--  registers spike 4 needs (GPIOA/GPIOB/RNG on AHB2, TIM2/I2C1 on APB1);
--  everything else (clock tree/PLL config, reset control, ...) is out of
--  scope for this spike -- native config stays native (D8), and this
--  spike boots on the default HSI16 clock rather than configuring a PLL.
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package STM32G474_PAC.RCC
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#4002_1000#);

   --  AHB2ENR (0x4C) -- bit positions confirmed against the CMSIS RCC_TypeDef
   --  offset table; GPIOAEN/GPIOBEN follow the universal "bit = port
   --  index" rule (very high confidence). RNGEN's exact bit (18) is
   --  transcribed from memory of the shared L4/G4 RCC layout and is the
   --  one field in this file NOT yet cross-checked against a fetched
   --  primary source -- see alire.toml's note.
   AHB2ENR : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#4C#;
   AHB2ENR_GPIOAEN : constant := 2#1#;             --  bit 0
   AHB2ENR_GPIOBEN : constant := 2#1# * 2**1;       --  bit 1
   AHB2ENR_RNGEN   : constant := 2#1# * 2**18;      --  bit 18 (unverified, see above)

   --  APB1ENR1 (0x58) -- TIM2EN at bit 0 is the most stable bit position
   --  in the whole STM32 line (TIM2 is always the first APB1 peripheral).
   --  I2C1EN at bit 21 is transcribed from memory of the shared L4/G4
   --  layout, same caveat as RNGEN above.
   APB1ENR1 : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#58#;
   APB1ENR1_TIM2EN : constant := 2#1#;              --  bit 0
   APB1ENR1_I2C1EN : constant := 2#1# * 2**21;       --  bit 21 (unverified, see above)

end STM32G474_PAC.RCC;
