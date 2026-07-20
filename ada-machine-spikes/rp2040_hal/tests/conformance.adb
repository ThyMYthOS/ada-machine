with RP2040.GPIO;
with Machine.Generic_Digital_Out;

package body Conformance
  with SPARK_Mode
is

   procedure GPIO5_Set (High : Boolean) is
   begin
      if High then
         RP2040.GPIO.Set_High (5);
      else
         RP2040.GPIO.Set_Low (5);
      end if;
   end GPIO5_Set;

   package GPIO5_Check is new Machine.Generic_Digital_Out (Set => GPIO5_Set);

end Conformance;
