with ESP32C3.GPIO;

package body Conformance
  with SPARK_Mode
is

   procedure GPIO10_Set (High : Boolean) is
   begin
      if High then
         ESP32C3.GPIO.Set_High (10);
      else
         ESP32C3.GPIO.Set_Low (10);
      end if;
   end GPIO10_Set;

end Conformance;
