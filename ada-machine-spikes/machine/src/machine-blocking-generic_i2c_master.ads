--  The blocking execution model's I2C master contract: whole bounded
--  transactions that complete (or fail) before returning.
with Machine.I2C;
generic
   with procedure Write (Address    : Machine.I2C.Address_7_Bit;
                         Data       : Byte_Array;
                         Timeout_Ms : Natural;
                         Status     : in out Machine.I2C.Transaction_Status);
                              --  one complete write transaction, bounded
   with procedure Write_Read (Address    : Machine.I2C.Address_7_Bit;
                              Command    : Byte_Array;
                              Response   : out Byte_Array;
                              Timeout_Ms : Natural;
                              Status     : in out Machine.I2C.Transaction_Status);
                              --  write, repeated start, read -- one transaction
package Machine.Blocking.Generic_I2C_Master
  with Pure, SPARK_Mode
is end Machine.Blocking.Generic_I2C_Master;
