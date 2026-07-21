with STM32G474.GPIO;

package body Conformance
  with SPARK_Mode
is

   LED : constant STM32G474.GPIO.Pin_Id := 5;

   procedure LED_Set (High : Boolean) is
   begin
      if High then
         STM32G474.GPIO.Set_High (LED);
      else
         STM32G474.GPIO.Set_Low (LED);
      end if;
   end LED_Set;

   package LED_Check is new Machine.Generic_Digital_Out (Set => LED_Set);

end Conformance;
