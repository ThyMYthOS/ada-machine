with Machine.Generic_Digital_Out;

package body Conformance
  with SPARK_Mode
is

   procedure CS2_Set (High : Boolean) is
   begin
      if High then
         ATmega328P.GPIO.Set_High (2);
      else
         ATmega328P.GPIO.Set_Low (2);
      end if;
   end CS2_Set;

   package CS2_Check is new Machine.Generic_Digital_Out (Set => CS2_Set);

end Conformance;
