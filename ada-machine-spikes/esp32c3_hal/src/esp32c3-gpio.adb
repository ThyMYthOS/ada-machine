with ESP32C3_PAC.GPIO; use ESP32C3_PAC.GPIO;
with Interfaces; use Interfaces;

package body ESP32C3.GPIO
  with SPARK_Mode
is

   procedure Configure (Pin : Pin_Id; Dir : Direction) is
   begin
      case Dir is
         when Output => GPIO_ENABLE_W1TS := Shift_Left (1, Pin);
         when Input  => GPIO_ENABLE_W1TC := Shift_Left (1, Pin);
      end case;
   end Configure;

   procedure Set_High (Pin : Pin_Id) is
   begin
      GPIO_OUT_W1TS := Shift_Left (1, Pin);
   end Set_High;

   procedure Set_Low (Pin : Pin_Id) is
   begin
      GPIO_OUT_W1TC := Shift_Left (1, Pin);
   end Set_Low;

   function Is_High (Pin : Pin_Id) return Boolean is
      --  GPIO_IN read alone into a local first: SPARK requires a
      --  volatile (Async_Writers) object's read to be the whole
      --  right-hand side of an assignment/declaration, not combined
      --  with other operators in the same expression (SPARK RM
      --  7.1.3(9)) -- "In" is an ordinary, non-volatile local from here.
      In_Bits : constant Unsigned_32 := GPIO_IN;
   begin
      return (In_Bits and Shift_Left (1, Pin)) /= 0;
   end Is_High;

end ESP32C3.GPIO;
