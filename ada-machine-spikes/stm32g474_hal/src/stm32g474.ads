--  STM32G474 -- L2 root package (§6.1): child packages carry the
--  standardized names/profiles of the portable convention (.Clock,
--  .GPIO, .I2C1, .RNG). A type declaration and no "with" clauses here:
--  Pure holds, not just Preelaborate.
package STM32G474
  with Pure, SPARK_Mode
is
   --  Shared MCU-specific type used by the convention packages (§6.1).
   --  This spike's STM32G474.GPIO only wires GPIOA (the status LED,
   --  PA5) -- widen when a second port is needed (§9 rule 1: curate
   --  exactly what's used).
   type Pin_Id is range 0 .. 15;
end STM32G474;
