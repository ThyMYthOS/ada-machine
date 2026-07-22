--  esp32c3-hal_info.ads -- §6.1: static description of what this HAL crate
--  implements (spike subset), in the standardized Machine.HAL_Info shape.
--  Mirrors tests/conformance.ads: every True has a matching conformance
--  instantiation there. (This package was previously missing entirely --
--  TODO #6.)
with Machine.HAL_Info;
package ESP32C3.HAL_Info
  with Pure, SPARK_Mode
is
   Provided : constant Machine.HAL_Info.Descriptor :=
     (Has_GPIO   => True,
      Has_UART   => True,
      Has_SPI    => True,
      Has_I2C    => False,   --  not in the spike subset
      Has_Clock  => False,   --  timekeeping via Ada.Real_Time, not a Machine clock
      Has_Delays => False);  --  delays come from machine_tasking (delay until)
end ESP32C3.HAL_Info;
