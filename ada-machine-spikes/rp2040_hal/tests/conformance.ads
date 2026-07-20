--  Non-shipped conformance unit (§6.1): instantiates every relevant
--  Machine signature against RP2040's own packages. If this compiles,
--  the crate conforms -- CI-only, not part of the library sources.
with Machine.Generic_Clock;
with Machine.I2C.Generic_Master;
with Machine.Generic_Digital_Out;
with RP2040.Clock, RP2040.I2C0, RP2040.GPIO;
with RP2040_PAC.SIO;

package Conformance
  with SPARK_Mode
is

   package Clock_Check is new Machine.Generic_Clock
     (Ticks            => RP2040.Clock.Ticks,
      Ticks_Per_Second => RP2040.Clock.Ticks_Per_Second,
      Now              => RP2040.Clock.Now);

   package I2C0_Check is new Machine.I2C.Generic_Master
     (Set_Target        => RP2040.I2C0.Set_Target,
      Can_Push          => RP2040.I2C0.Can_Push,
      Push_Write        => RP2040.I2C0.Push_Write,
      Push_Read_Request => RP2040.I2C0.Push_Read_Request,
      Can_Pop           => RP2040.I2C0.Can_Pop,
      Pop               => RP2040.I2C0.Pop);

   --  Machine.Generic_Digital_Out needs one formal procedure bound to a
   --  fixed pin (§6.4): a real conformance unit wraps RP2040.GPIO the
   --  same way board wiring does (the §6.4 CS_Set pattern).
   procedure GPIO5_Set (High : Boolean)
     with Global => (Output => (RP2040_PAC.SIO.GPIO_OUT_SET,
                                RP2040_PAC.SIO.GPIO_OUT_CLR));

end Conformance;
