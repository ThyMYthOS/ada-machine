--  Non-shipped conformance unit (§6.1): instantiates the Machine
--  signatures this HAL claims against its own packages.
with Machine.SPI.Generic_Master;
with Machine.Generic_Digital_Out;
with ATmega328P.SPI, ATmega328P.GPIO;
with ATmega328P_PAC.Port_B;

package Conformance
  with SPARK_Mode
is

   package SPI_Check is new Machine.SPI.Generic_Master
     (Can_Push => ATmega328P.SPI.Can_Push,
      Push     => ATmega328P.SPI.Push,
      Can_Pop  => ATmega328P.SPI.Can_Pop,
      Pop      => ATmega328P.SPI.Pop);

   procedure CS2_Set (High : Boolean)
     with Global => (In_Out => ATmega328P_PAC.Port_B.PORTB);

end Conformance;
