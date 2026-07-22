--  SPI class vocabulary. Chip select is NOT part of the class: it is a
--  Machine.GPIO.Generic_Digital_Out wired by whoever owns the bus topology.
package Machine.SPI
  with Pure, SPARK_Mode
is
   type Bus_Status is (Ok, Mode_Fault, Other_Error);   --  L2: never waits
   type Transaction_Status is
     (Ok, Timed_Out, Mode_Fault, Other_Error);
end Machine.SPI;
