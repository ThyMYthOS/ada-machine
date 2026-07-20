with ATmega328P_PAC.Port_B; use ATmega328P_PAC.Port_B;
with Interfaces; use Interfaces;

package body ATmega328P.GPIO
  with SPARK_Mode
is

   function Mask (Pin : Pin_Id) return Unsigned_8 is
     (Shift_Left (1, Natural (Pin)));

   --  Every volatile (DDRB/PORTB/PINB) read below is taken alone into a
   --  local constant first, then combined with other operators via that
   --  ordinary local -- SPARK requires a volatile read to be the whole
   --  right-hand side of an assignment/declaration, not combined with
   --  other operators in the same expression (SPARK RM 7.1.3(9)).

   procedure Configure (Pin : Pin_Id; Dir : Direction) is
      Ddrb_Now : constant Unsigned_8 := DDRB;
   begin
      case Dir is
         when Input  => DDRB := Ddrb_Now and not Mask (Pin);
         when Output => DDRB := Ddrb_Now or Mask (Pin);
      end case;
   end Configure;

   procedure Set_High (Pin : Pin_Id) is
      Portb_Now : constant Unsigned_8 := PORTB;
   begin
      PORTB := Portb_Now or Mask (Pin);
   end Set_High;

   procedure Set_Low (Pin : Pin_Id) is
      Portb_Now : constant Unsigned_8 := PORTB;
   begin
      PORTB := Portb_Now and not Mask (Pin);
   end Set_Low;

   function Is_High (Pin : Pin_Id) return Boolean is
      Pinb_Now : constant Unsigned_8 := PINB;
   begin
      return (Pinb_Now and Mask (Pin)) /= 0;
   end Is_High;

end ATmega328P.GPIO;
