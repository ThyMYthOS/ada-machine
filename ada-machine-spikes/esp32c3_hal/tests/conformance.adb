with ESP32C3.GPIO;
with Machine.GPIO; use Machine.GPIO;

package body Conformance
  with SPARK_Mode
is

   procedure GPIO10_Set (To : Machine.GPIO.Level) is
   begin
      if To = High then
         ESP32C3.GPIO.Set_High (10);
      else
         ESP32C3.GPIO.Set_Low (10);
      end if;
   end GPIO10_Set;

   function GPIO11_Get return Machine.GPIO.Level is
     (if ESP32C3.GPIO.Is_High (11) then High else Low);

end Conformance;
