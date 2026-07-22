--  SPI class vocabulary. Chip select is NOT part of the class: it is a
--  Machine.GPIO.Generic_Digital_Out wired by whoever owns the bus topology
--  (optionally via the Generic_Chip_Select polarity wrapper, a child below).
package Machine.SPI
  with Pure, SPARK_Mode
is
   type Bus_Status is (Ok, Mode_Fault, Other_Error);   --  L2: never waits
   type Transaction_Status is
     (Ok, Timed_Out, Mode_Fault, Other_Error);

   --  Chip-select polarity. Binary by construction (D8), same discipline as
   --  Machine.GPIO.Level: no tri-state/open-drain CS.
   type CS_Polarity is (Active_Low, Active_High);
end Machine.SPI;
