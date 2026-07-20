--  atmega328p-hal_info.ads -- §6.1: static description of what this HAL
--  crate implements (spike subset).
package ATmega328P.HAL_Info
  with Pure, SPARK_Mode
is
   Has_SPI    : constant Boolean := True;
   Has_GPIO   : constant Boolean := True;
   Has_Delays : constant Boolean := True;
   Has_I2C    : constant Boolean := False;   --  spike 2 open question (B.4/C.4)
   Has_UART   : constant Boolean := False;
end ATmega328P.HAL_Info;
