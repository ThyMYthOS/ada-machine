--  rp2040-hal_info.ads -- §6.1: static description of what this HAL
--  crate implements (spike subset, not the full RP2040 surface).
package RP2040.HAL_Info
  with Pure, SPARK_Mode
is
   Has_Clock : constant Boolean := True;
   Has_GPIO  : constant Boolean := True;
   Has_I2C0  : constant Boolean := True;
   Has_I2C1  : constant Boolean := False;
   Has_UART0 : constant Boolean := False;
   Has_SPI0  : constant Boolean := False;
end RP2040.HAL_Info;
