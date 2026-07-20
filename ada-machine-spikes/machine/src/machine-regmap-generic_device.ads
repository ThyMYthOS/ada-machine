--  What register-map drivers (L4) program against; implemented by the
--  I2C/SPI bindings of crate machine_regmap.
generic
   with procedure Write_Reg (Reg : Reg_Address; Value : Byte;
                             Status : in out Access_Status);
                                    --  one register write, bounded time
   with procedure Read_Regs (Start : Reg_Address;
                             Data  : out Byte_Array;
                             Status : in out Access_Status);
                                    --  auto-incrementing burst read
package Machine.Regmap.Generic_Device
  with Pure, SPARK_Mode
is end Machine.Regmap.Generic_Device;
