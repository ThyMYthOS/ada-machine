--  rp2040-hal_info.ads -- §6.1: static description of what this HAL crate
--  implements (spike subset, not the full RP2040 surface), in the
--  standardized Machine.HAL_Info shape. Mirrors tests/conformance.ads:
--  every True here has a matching conformance instantiation there.
with Machine.HAL_Info;
package RP2040.HAL_Info
  with Pure, SPARK_Mode
is
   Provided : constant Machine.HAL_Info.Descriptor :=
     (Has_GPIO   => True,
      Has_UART   => True,
      Has_SPI    => False,   --  not in the spike subset
      Has_I2C    => True,
      Has_Clock  => True,
      Has_Delays => False);  --  delays come from machine_blocking over Clock
end RP2040.HAL_Info;
