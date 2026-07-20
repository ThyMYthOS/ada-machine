--  RP2040_PAC -- root of the curated register bindings (svd2ada-style
--  naming: the device namespace stays separate from RP2040.* portable
--  convention packages in rp2040_hal, §9/§16). No subprograms, no
--  elaboration code, no dependencies (§9 rule 5) -- Pure holds, not just
--  Preelaborate.
package RP2040_PAC
  with Pure, SPARK_Mode
is
end RP2040_PAC;
