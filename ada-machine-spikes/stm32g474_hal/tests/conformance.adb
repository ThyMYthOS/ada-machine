with STM32G474.GPIO;
with Machine.GPIO; use Machine.GPIO;

package body Conformance
  with SPARK_Mode
is

   LED : constant STM32G474.GPIO.Pin_Id := 5;

   procedure LED_Set (To : Machine.GPIO.Level) is
   begin
      if To = High then
         STM32G474.GPIO.Set_High (LED);
      else
         STM32G474.GPIO.Set_Low (LED);
      end if;
   end LED_Set;

   package LED_Check is new Machine.GPIO.Generic_Digital_Out (Set => LED_Set);

end Conformance;
