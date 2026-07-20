--  esp32c3.ads -- root of the ESP32-C3 L2 (mirrors RP2040/ATmega328P's
--  own root: pure declarations, the child packages carry the substance).
--  A subtype declaration and no "with" clauses: Pure holds, not just
--  Preelaborate (RP2040/ATmega328P's own roots declare a type the same
--  way and can be corrected to Pure too).
package ESP32C3
  with Pure, SPARK_Mode
is
   --  GPIO0..GPIO21 are the chip's full pad range; on many modules
   --  GPIO11..GPIO17 are reserved for in-package flash and not brought
   --  out (curation note, not modeled as a narrower subtype here since
   --  it is a board/module property, not a chip property).
   subtype Pin_Id is Natural range 0 .. 21;
end ESP32C3;
