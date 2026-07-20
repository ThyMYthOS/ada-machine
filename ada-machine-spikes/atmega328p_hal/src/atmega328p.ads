--  ATmega328P -- L2 root package (§6.1): child packages carry the
--  standardized names/profiles of the portable convention (.SPI,
--  .Delays, .GPIO, ...) plus whatever native surface this spike needs.
--  A type declaration and no "with" clauses here: Pure holds, not just
--  Preelaborate (the child packages that actually touch hardware state
--  stay at Preelaborate, as they must).
package ATmega328P
  with Pure, SPARK_Mode
is
   --  PORTB spans PB0..PB7 on the 328P (§6.1's own example figure, "0..5
   --  per port", was illustrative for a smaller AVR; this is the real
   --  width of the port this spike actually wires).
   type Pin_Id is range 0 .. 7;
end ATmega328P;
