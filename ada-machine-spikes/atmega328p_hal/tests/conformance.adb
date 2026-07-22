with Machine.GPIO.Generic_Digital_Out, Machine.GPIO.Generic_Digital_In;
use Machine.GPIO;

package body Conformance
  with SPARK_Mode
is

   procedure CS2_Set (To : Machine.GPIO.Level) is
   begin
      if To = High then
         ATmega328P.GPIO.Set_High (2);
      else
         ATmega328P.GPIO.Set_Low (2);
      end if;
   end CS2_Set;

   package CS2_Check is new Machine.GPIO.Generic_Digital_Out
     (Set => CS2_Set);

   function CS3_Get return Machine.GPIO.Level is
     (if ATmega328P.GPIO.Is_High (3) then High else Low);

   package CS3_Check is new Machine.GPIO.Generic_Digital_In
     (Get => CS3_Get);

end Conformance;
