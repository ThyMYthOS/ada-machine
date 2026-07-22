--  ATmega328P_PAC -- root of the curated register bindings (§9 AVR note;
--  §16 keeps the device namespace separate from ATmega328P.* portable
--  convention packages in atmega328p_hal). No subprograms, no
--  dependencies: Pure holds, not just Preelaborate.
--
--  TODO #8 / §9 rule 2 note: no register in this PAC carries
--  Volatile_Full_Access. VFA documents a *bus* requirement (only a
--  full-width transaction is defined) that matters when a register
--  could otherwise be accessed at less than its natural width -- on
--  AVR's 8-bit I/O bus every register here is already Unsigned_8, the
--  bus's one and only natural access width, so there is no narrower
--  transaction VFA could rule out. This is a genuine "does not apply"
--  (unlike RP2040_PAC.SIO/ESP32C3_PAC.GPIO's 32-bit-only registers,
--  where VFA documents a real, otherwise-implicit constraint), not an
--  oversight.
package ATmega328P_PAC
  with Pure, SPARK_Mode
is
end ATmega328P_PAC;
