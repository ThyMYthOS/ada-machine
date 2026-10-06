--  atmega328p-hal_info.ads -- §6.1: static description of what this HAL
--  crate implements (spike subset), in the standardized Machine.HAL_Info
--  shape. Mirrors tests/conformance.ads: every True has a matching
--  conformance instantiation there.
with Machine.HAL_Info;

package ATmega328P.HAL_Info
  with Pure, SPARK_Mode
is
   Provided : constant Machine.HAL_Info.Descriptor :=
     (Has_GPIO       => True,
      Has_UART       => True,
      Has_SPI        => True,
      Has_I2C        => True,   --  TWI, added in TODO #1 (was the B.4/C.4 open point)
      Has_Clock      => True,
      Has_Delays     => True,   --  native calibrated busy-wait (ATmega328P.Delays)
      Has_I2C_Target => True,   --  TWI slave mode (ATmega328P.I2C_Target)
      others         => False); --  no RNG
end ATmega328P.HAL_Info;
