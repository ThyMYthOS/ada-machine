--  Non-shipped conformance unit (§6.1): instantiates the Machine
--  signatures this HAL claims against its own packages.
with Machine.SPI.Generic_Master;
with Machine.I2C.Generic_Master;
with Machine.I2C.Generic_Target;
with Machine.UART.Generic_Port;
with Machine.Generic_Clock;
with Machine.GPIO.Generic_Digital_Out, Machine.GPIO.Generic_Digital_In;
with ATmega328P.SPI, ATmega328P.GPIO, ATmega328P.I2C, ATmega328P.I2C_Target,
     ATmega328P.Clock,
     ATmega328P.USART0;
with ATmega328P_PAC.Port_B;

package Conformance
  with SPARK_Mode
is

   package SPI_Check is new Machine.SPI.Generic_Master
     (Can_Push => ATmega328P.SPI.Can_Push,
      Push     => ATmega328P.SPI.Push,
      Can_Pop  => ATmega328P.SPI.Can_Pop,
      Pop      => ATmega328P.SPI.Pop);

   package I2C_Check is new Machine.I2C.Generic_Master
     (Set_Target        => ATmega328P.I2C.Set_Target,
      Can_Push          => ATmega328P.I2C.Can_Push,
      Push_Write        => ATmega328P.I2C.Push_Write,
      Push_Read_Request => ATmega328P.I2C.Push_Read_Request,
      Can_Pop           => ATmega328P.I2C.Can_Pop,
      Pop               => ATmega328P.I2C.Pop);

   --  The second target-mode controller (TODO.md #11): checks the *target*
   --  signature against a structurally different peripheral than STM32G474's.
   package I2C_Target_Check is new Machine.I2C.Generic_Target
     (Is_Address_Matched  => ATmega328P.I2C_Target.Is_Address_Matched,
      Is_Read_From_Master => ATmega328P.I2C_Target.Is_Read_From_Master,
      Ack_Address         => ATmega328P.I2C_Target.Ack_Address,
      Can_Pop             => ATmega328P.I2C_Target.Can_Pop,
      Pop                 => ATmega328P.I2C_Target.Pop,
      Can_Push            => ATmega328P.I2C_Target.Can_Push,
      Push                => ATmega328P.I2C_Target.Push,
      Is_Stop             => ATmega328P.I2C_Target.Is_Stop,
      Clear_Stop          => ATmega328P.I2C_Target.Clear_Stop);

   package Clock_Check is new Machine.Generic_Clock
     (Ticks            => ATmega328P.Clock.Ticks,
      Ticks_Per_Second => ATmega328P.Clock.Ticks_Per_Second,
      Now              => ATmega328P.Clock.Now);

   package UART0_Check is new Machine.UART.Generic_Port
     (Frame       => ATmega328P.USART0.Frame,
      Is_Tx_Ready => ATmega328P.USART0.Is_Tx_Ready,
      Put_Frame   => ATmega328P.USART0.Put_Frame,
      Is_Rx_Ready => ATmega328P.USART0.Is_Rx_Ready,
      Get_Frame   => ATmega328P.USART0.Get_Frame);

   procedure CS2_Set (To : Machine.GPIO.Level)
     with Global => (In_Out => ATmega328P_PAC.Port_B.PORTB);

   --  Machine.GPIO.Generic_Digital_In needs one formal function bound to
   --  a fixed pin, checked against ATmega328P.GPIO.Is_High -- the gap
   --  TODO.md P0 #3 closes: Is_High conformed to nothing before this.
   function CS3_Get return Machine.GPIO.Level
     with Volatile_Function, Global => (Input => ATmega328P_PAC.Port_B.PINB);

end Conformance;
