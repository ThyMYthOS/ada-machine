with RP2040.GPIO;
with Machine.GPIO.Generic_Digital_Out, Machine.GPIO.Generic_Digital_In;
use Machine.GPIO;

package body Conformance
  with SPARK_Mode
is

   procedure GPIO5_Set (To : Machine.GPIO.Level) is
   begin
      if To = High then
         RP2040.GPIO.Set_High (5);
      else
         RP2040.GPIO.Set_Low (5);
      end if;
   end GPIO5_Set;

   package GPIO5_Check is new Machine.GPIO.Generic_Digital_Out
     (Set => GPIO5_Set);

   function GPIO6_Get return Machine.GPIO.Level is
     (if RP2040.GPIO.Is_High (6) then High else Low);

   package GPIO6_Check is new Machine.GPIO.Generic_Digital_In
     (Get => GPIO6_Get);

end Conformance;
