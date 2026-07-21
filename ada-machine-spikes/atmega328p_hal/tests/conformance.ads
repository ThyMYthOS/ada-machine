--  Non-shipped conformance unit (§6.1): instantiates the Machine
--  signatures this HAL claims against its own packages.
with Machine.SPI.Generic_Master;
with Machine.I2C.Generic_Master;
with Machine.UART.Generic_Port;
with Machine.Generic_Clock;
with Machine.Generic_Digital_Out;
with ATmega328P.SPI, ATmega328P.GPIO, ATmega328P.I2C, ATmega328P.Clock,
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

   procedure CS2_Set (High : Boolean)
     with Global => (In_Out => ATmega328P_PAC.Port_B.PORTB);

end Conformance;
