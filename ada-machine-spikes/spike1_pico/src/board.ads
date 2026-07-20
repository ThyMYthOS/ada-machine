--  board.ads -- Appendix B.3, verbatim: pure declarations; reads like
--  the schematic.
with Machine.Generic_Clock, Machine.I2C.Generic_Master;
with Machine.Regmap.Generic_I2C_Binding;
with RP2040.Clock, RP2040.I2C0;
with Machine.Blocking.Delays, Machine.Blocking.I2C, BME280;
package Board
  with SPARK_Mode
is

   package Clock_Sig is new Machine.Generic_Clock
     (Ticks            => RP2040.Clock.Ticks,
      Ticks_Per_Second => RP2040.Clock.Ticks_Per_Second,
      Now              => RP2040.Clock.Now);

   package I2C0_Sig is new Machine.I2C.Generic_Master   --  conformance check
     (Set_Target        => RP2040.I2C0.Set_Target,     --  of RP2040.I2C0,
      Can_Push          => RP2040.I2C0.Can_Push,       --  §6.1, for free
      Push_Write        => RP2040.I2C0.Push_Write,
      Push_Read_Request => RP2040.I2C0.Push_Read_Request,
      Can_Pop           => RP2040.I2C0.Can_Pop,
      Pop               => RP2040.I2C0.Pop);

   package Delays is new Machine.Blocking.Delays (Clock => Clock_Sig);
   package I2C    is new Machine.Blocking.I2C (Port => I2C0_Sig, Clock => Clock_Sig);

   package Regs is new Machine.Regmap.Generic_I2C_Binding
     (Bus => I2C.As_Signature, Device_Address => 16#76#);

   package Env_Sensor is new BME280
     (Regs => Regs.As_Device,
      Wait => Delays.As_Signature);

   --  Native configuration stays native (D8): main calls
   --    RP2040.I2C0.Enable ((Baud_Hz => 400_000, SDA_Pin => 4, SCL_Pin => 5));
   --  before first use of Env_Sensor.
end Board;
