--  Non-shipped conformance unit (§6.1): instantiates every relevant
--  Machine signature against STM32G474's own packages. If this compiles,
--  the crate conforms -- CI-only, not part of the library sources.
--  First conformance unit in this repo to check a *target*-mode I2C
--  signature and the new RNG signature (spike 4, Appendix D).
with Interfaces;
with Machine.Generic_Clock;
with Machine.I2C.Generic_Target;
with Machine.RNG.Generic_Source;
with Machine.Generic_Digital_Out;
with STM32G474.Clock, STM32G474.I2C1, STM32G474.RNG, STM32G474.GPIO;
with STM32G474_PAC.GPIOA;

package Conformance
  with SPARK_Mode
is

   package Clock_Check is new Machine.Generic_Clock
     (Ticks            => STM32G474.Clock.Ticks,
      Ticks_Per_Second => STM32G474.Clock.Ticks_Per_Second,
      Now              => STM32G474.Clock.Now);

   package I2C1_Check is new Machine.I2C.Generic_Target
     (Is_Address_Matched    => STM32G474.I2C1.Is_Address_Matched,
      Is_Read_From_Master   => STM32G474.I2C1.Is_Read_From_Master,
      Ack_Address           => STM32G474.I2C1.Ack_Address,
      Can_Pop                => STM32G474.I2C1.Can_Pop,
      Pop                     => STM32G474.I2C1.Pop,
      Can_Push                => STM32G474.I2C1.Can_Push,
      Push                     => STM32G474.I2C1.Push,
      Is_Stop                 => STM32G474.I2C1.Is_Stop,
      Clear_Stop              => STM32G474.I2C1.Clear_Stop);

   package RNG_Check is new Machine.RNG.Generic_Source
     (Word     => Interfaces.Unsigned_32,
      Is_Ready => STM32G474.RNG.Is_Ready,
      Get_Word => STM32G474.RNG.Get_Word);

   --  Machine.Generic_Digital_Out needs one formal procedure bound to a
   --  fixed pin (§6.4): the status LED, PA5 -- same CS_Set-style wrapper
   --  RP2040_HAL's own conformance unit uses.
   procedure LED_Set (High : Boolean)
     with Global => (Output => STM32G474_PAC.GPIOA.BSRR);

end Conformance;
