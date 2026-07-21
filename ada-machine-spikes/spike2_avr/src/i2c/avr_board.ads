--  avr_board.ads -- spike 2's I2C wiring variant (Appendix B, TODO.md P0
--  #1): the same Machine.Blocking.I2C + bme280 spike 1 uses over RP2040's
--  command FIFO, here driven by ATmega328P.I2C's TWI state machine instead
--  -- unmodified, validating that the push/pop shape survives a second,
--  structurally different I2C controller. Blocking/polled, like spike 1
--  (not interrupt-driven like this crate's SPI variant): no ISR for TWI
--  itself, only for ATmega328P.Clock's Timer0 tick (needed because
--  Machine.Blocking.I2C, unlike SPI's Generic_Delays, takes a Clock formal).
with Machine.Generic_Clock, Machine.I2C.Generic_Master;
with Machine.Blocking.Delays, Machine.Blocking.I2C;
with Machine.Regmap.Generic_I2C_Binding;
with ATmega328P.I2C, ATmega328P.Clock;
with BME280;

package AVR_Board
  with SPARK_Mode
is

   package Clock_Sig is new Machine.Generic_Clock
     (Ticks            => ATmega328P.Clock.Ticks,
      Ticks_Per_Second => ATmega328P.Clock.Ticks_Per_Second,
      Now              => ATmega328P.Clock.Now);

   package I2C_Sig is new Machine.I2C.Generic_Master     --  I2C conformance,
     (Set_Target        => ATmega328P.I2C.Set_Target,    --  checked for free
      Can_Push          => ATmega328P.I2C.Can_Push,
      Push_Write        => ATmega328P.I2C.Push_Write,
      Push_Read_Request => ATmega328P.I2C.Push_Read_Request,
      Can_Pop           => ATmega328P.I2C.Can_Pop,
      Pop               => ATmega328P.I2C.Pop);

   --  Timer0-overflow pump: interrupt attachment is the application's
   --  decision (D5), same policy as the SPI variant's SPI_Interrupt.
   procedure Timer0_Interrupt
     with Export, External_Name => "__vector_16";  --  ATmega328P TIMER0_OVF_vect
   pragma Machine_Attribute (Timer0_Interrupt, "signal");
   --  (body: ATmega328P.Clock.On_Tick;)

   package Delays is new Machine.Blocking.Delays (Clock => Clock_Sig);
   package I2C    is new Machine.Blocking.I2C (Port => I2C_Sig, Clock => Clock_Sig);

   package Regs is new Machine.Regmap.Generic_I2C_Binding
     (Bus => I2C.As_Signature, Device_Address => 16#76#);

   --  Byte-for-byte the same driver as spike 1 and this crate's SPI variant
   --  (the shared bme280 crate, §11):
   package Env_Sensor is new BME280
     (Regs => Regs.As_Device,
      Wait => Delays.As_Signature);
end AVR_Board;
