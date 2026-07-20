--  RP2040 -- L2 root package (§6.1): child packages carry the standardized
--  names/profiles of the portable convention (.Clock, .GPIO, .I2C0, ...)
--  plus the native full-feature surface (not all present in this spike).
--  A type declaration and no "with" clauses here: Pure holds, not just
--  Preelaborate (the child packages that actually touch hardware state
--  stay at Preelaborate, as they must).
package RP2040
  with Pure, SPARK_Mode
is
   --  Shared MCU-specific type used by the convention packages (§6.1):
   --  portable code never assumes a width, only what a given HAL offers.
   type Pin_Id is range 0 .. 29;
end RP2040;
