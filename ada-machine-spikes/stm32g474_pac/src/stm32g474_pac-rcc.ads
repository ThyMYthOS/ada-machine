--  STM32G474 RCC -- base 0x4002_1000 (confirmed against the CMSIS device
--  header: AHB1PERIPH_BASE + 0x1000). Curated to exactly the enable
--  registers spike 4 needs (GPIOA/GPIOB/RNG on AHB2, TIM2/I2C1 on APB1)
--  plus CRRCR for the RNG's HSI48 clock;
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

   --  Register offsets and every bit position below were checked against
   --  ST's CMSIS device header (cmsis-device-g4, stm32g474xx.h:
   --  RCC_TypeDef offsets and the *_Pos macros), not transcribed from
   --  memory. That check *corrected* RNGEN: it was bit 18 (the L4
   --  position this file had assumed carried over) but is bit 26 on the
   --  G4.

   --  AHB2ENR (0x4C): GPIOAEN bit 0, GPIOBEN bit 1, RNGEN bit 26.
   AHB2ENR : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#4C#;
   AHB2ENR_GPIOAEN : constant := 2#1#;             --  bit 0
   AHB2ENR_GPIOBEN : constant := 2#1# * 2**1;       --  bit 1
   AHB2ENR_RNGEN   : constant := 2#1# * 2**26;      --  bit 26 (G4; was 18, the L4 bit)

   --  APB1ENR1 (0x58): TIM2EN bit 0, I2C1EN bit 21.
   APB1ENR1 : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#58#;
   APB1ENR1_TIM2EN : constant := 2#1#;              --  bit 0
   APB1ENR1_I2C1EN : constant := 2#1# * 2**21;       --  bit 21

   --  CRRCR (0x98) -- HSI48 control. The RNG's 48 MHz kernel clock comes
   --  from RCC_CCIPR.CLK48SEL, which resets to HSI48 -- but HSI48 itself
   --  is *off* after reset, so the RNG sees no clock (CECS) until
   --  HSI48ON is set and HSI48RDY comes up. Mixed RW/RO register:
   --  HSI48RDY is hardware-set.
   CRRCR : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#98#;
   CRRCR_HSI48ON  : constant := 2#1#;               --  bit 0
   CRRCR_HSI48RDY : constant := 2#1# * 2**1;         --  bit 1

end STM32G474_PAC.RCC;
