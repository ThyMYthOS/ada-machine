--  Non-shipped conformance unit (§6.1): instantiates every relevant
--  Machine signature against RP2040's own packages. If this compiles,
--  the crate conforms -- CI-only, not part of the library sources.
with Machine.Generic_Clock;
with Machine.I2C.Generic_Master;
with Machine.UART.Generic_Port;
with Machine.GPIO.Generic_Digital_Out, Machine.GPIO.Generic_Digital_In;
with RP2040.Clock, RP2040.I2C0, RP2040.UART0, RP2040.GPIO;
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

   package UART0_Check is new Machine.UART.Generic_Port
     (Frame       => RP2040.UART0.Frame,
      Is_Tx_Ready => RP2040.UART0.Is_Tx_Ready,
      Put_Frame   => RP2040.UART0.Put_Frame,
      Is_Rx_Ready => RP2040.UART0.Is_Rx_Ready,
      Get_Frame   => RP2040.UART0.Get_Frame);

   --  Machine.GPIO.Generic_Digital_Out needs one formal procedure bound to
   --  a fixed pin (§6.4): a real conformance unit wraps RP2040.GPIO the
   --  same way board wiring does (the §6.4 CS_Set pattern).
   procedure GPIO5_Set (To : Machine.GPIO.Level)
     with Global => (Output => (RP2040_PAC.SIO.GPIO_OUT_SET,
                                RP2040_PAC.SIO.GPIO_OUT_CLR));

   --  Machine.GPIO.Generic_Digital_In needs one formal function bound to
   --  a fixed pin, checked against RP2040.GPIO.Is_High -- the gap TODO.md
   --  P0 #3 closes: Is_High conformed to nothing before this.
   function GPIO6_Get return Machine.GPIO.Level
     with Volatile_Function, Global => (Input => RP2040_PAC.SIO.GPIO_IN);

end Conformance;
