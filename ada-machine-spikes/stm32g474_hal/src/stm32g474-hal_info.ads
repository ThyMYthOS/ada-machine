--  stm32g474-hal_info.ads -- §6.1: static description of what this HAL
--  crate implements (spike 4 subset, not the full STM32G474 surface).
package STM32G474.HAL_Info
  with Pure, SPARK_Mode
is
   Has_Clock       : constant Boolean := True;
   Has_GPIO        : constant Boolean := True;    --  GPIOA only
   Has_I2C1_Target : constant Boolean := True;    --  target/slave mode only, no master
   Has_RNG         : constant Boolean := True;
   Has_UART0       : constant Boolean := False;
   Has_SPI0        : constant Boolean := False;
end STM32G474.HAL_Info;
