--  stm32g474-hal_info.ads -- §6.1: static description of what this HAL
--  crate implements (spike 4 subset, not the full STM32G474 surface), in
--  the standardized Machine.HAL_Info shape (it carried ad-hoc Has_X
--  constants until Has_I2C_Target/Has_RNG joined the Descriptor, TODO.md
--  #11). Mirrors tests/conformance.ads.
with Machine.HAL_Info;
package STM32G474.HAL_Info
  with Pure, SPARK_Mode
is
   Provided : constant Machine.HAL_Info.Descriptor :=
     (Has_Clock      => True,
      Has_GPIO       => True,    --  GPIOA only
      Has_I2C_Target => True,    --  target/slave mode only, no master
      Has_RNG        => True,
      others         => False);  --  no UART, SPI, master I2C or Delays
end STM32G474.HAL_Info;
