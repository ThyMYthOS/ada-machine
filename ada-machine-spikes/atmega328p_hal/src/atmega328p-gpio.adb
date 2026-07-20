with ATmega328P_PAC.Port_B; use ATmega328P_PAC.Port_B;
with Interfaces; use Interfaces;

package body ATmega328P.GPIO
  with SPARK_Mode
is

   function Mask (Pin : Pin_Id) return Unsigned_8 is
     (Shift_Left (1, Natural (Pin)));

   procedure Configure (Pin : Pin_Id; Dir : Direction) is
   begin
      case Dir is
         when Input  => DDRB := DDRB and not Mask (Pin);
         when Output => DDRB := DDRB or Mask (Pin);
      end case;
   end Configure;

   procedure Set_High (Pin : Pin_Id) is
   begin
      PORTB := PORTB or Mask (Pin);
   end Set_High;

   procedure Set_Low (Pin : Pin_Id) is
   begin
      PORTB := PORTB and not Mask (Pin);
   end Set_Low;

   function Is_High (Pin : Pin_Id) return Boolean is
     ((PINB and Mask (Pin)) /= 0);

end ATmega328P.GPIO;
