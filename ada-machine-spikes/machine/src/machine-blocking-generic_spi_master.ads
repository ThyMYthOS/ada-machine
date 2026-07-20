--  The blocking execution model's SPI master contract (chip select
--  excluded, as in Machine.SPI).
with Machine.SPI;
generic
   with procedure Exchange (TX         : Byte_Array;
                            RX         : out Byte_Array;
                            Timeout_Ms : Natural;
                            Status     : in out Machine.SPI.Transaction_Status);
                              --  full duplex; RX'Length = TX'Length
package Machine.Blocking.Generic_SPI_Master
  with Pure, SPARK_Mode
is end Machine.Blocking.Generic_SPI_Master;
