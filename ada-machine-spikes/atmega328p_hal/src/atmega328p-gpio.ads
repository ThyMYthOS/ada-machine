--  atmega328p-gpio.ads -- §6.4's GPIO shape, PORTB-only for this spike
--  (the chip select in Appendix C.3 is an ordinary output pin here).
--  Global contracts added beyond the literal §6.4 excerpt (§6.6).
with ATmega328P_PAC.Port_B;

package ATmega328P.GPIO
  with Preelaborate, SPARK_Mode
is
   subtype Pin_Id is ATmega328P.Pin_Id;   --  PB0..PB7
   type Direction is (Input, Output);

   procedure Configure (Pin : Pin_Id; Dir : Direction)
     with Global => (In_Out => ATmega328P_PAC.Port_B.DDRB);
   procedure Set_High (Pin : Pin_Id)
     with Inline_Always, Global => (In_Out => ATmega328P_PAC.Port_B.PORTB);
   procedure Set_Low  (Pin : Pin_Id)
     with Inline_Always, Global => (In_Out => ATmega328P_PAC.Port_B.PORTB);
   function  Is_High  (Pin : Pin_Id) return Boolean
     with Inline_Always, Global => (Input => ATmega328P_PAC.Port_B.PINB);
end ATmega328P.GPIO;
