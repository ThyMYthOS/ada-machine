package body Machine.SPI.Generic_Chip_Select
  with SPARK_Mode
is

   procedure Assert is
   begin
      if Polarity = Active_Low then
         Pin.Set (To => Machine.GPIO.Low);
      else
         Pin.Set (To => Machine.GPIO.High);
      end if;
   end Assert;

   procedure Deassert is
   begin
      if Polarity = Active_Low then
         Pin.Set (To => Machine.GPIO.High);
      else
         Pin.Set (To => Machine.GPIO.Low);
      end if;
   end Deassert;

end Machine.SPI.Generic_Chip_Select;
