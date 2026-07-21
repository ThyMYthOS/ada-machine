--  STM32G474 GPIOB -- base 0x4800_0400 (AHB2PERIPH_BASE + 0x0400,
--  confirmed against the CMSIS device header). Curated to exactly what
--  I2C1's own native pin muxing needs for PB6 (SCL) / PB7 (SDA), done
--  inside STM32G474.I2C1.Enable (D8: peripheral pin muxing is native
--  config, not routed through the general GPIO HAL package -- same
--  split RP2040.I2C0.Enable uses against IO_Bank0/Pads_Bank0 directly).
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package STM32G474_PAC.GPIOB
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#4800_0400#);

   --  MODER (0x00) -- 2 bits/pin, "10" routes a pin through its
   --  alternate function (AFRL below picks which one).
   MODER : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#00#;

   --  OTYPER (0x04) -- 1 bit/pin, "1" = open-drain. I2C is open-drain by
   --  the electrical spec; leaving this at its push-pull reset default
   --  would drive the bus instead of releasing it.
   OTYPER : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#04#;

   --  PUPDR (0x0C) -- 2 bits/pin, "01" = pull-up. Weak internal pull-ups
   --  for bring-up, same caveat RP2040.I2C0.Enable documents: external
   --  pulls are still recommended in production.
   PUPDR : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#0C#;

   --  AFRL (0x20) -- AF[0], 4 bits/pin for pins 0..7 (pins 6/7 here).
   --  AF4 is I2C1's alternate function on the whole F0/F3/L4/G4-style
   --  AF-mux scheme -- verify against the datasheet's AF table (not the
   --  reference manual) before real hardware bring-up, same bar as the
   --  RCC bit positions in stm32g474_pac-rcc.ads.
   AFRL : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#20#;
   I2C1_AF : constant := 4;

end STM32G474_PAC.GPIOB;
