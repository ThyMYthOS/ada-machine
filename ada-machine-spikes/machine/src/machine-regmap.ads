--  Bus-neutral register-access vocabulary: external devices exposing a
--  register map behind I2C/SPI. Remote registers are transactional data.
package Machine.Regmap
  with Pure, SPARK_Mode
is
   type Reg_Address is new Byte;    --  device-local register index
   type Access_Status is            --  chained; mapped from bus kinds
     (Ok, Timed_Out, Bus_Fault, Other_Error);
end Machine.Regmap;
