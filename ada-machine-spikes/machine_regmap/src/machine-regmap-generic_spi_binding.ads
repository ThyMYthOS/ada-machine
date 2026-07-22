--  Register map over an SPI device, BME280-style convention: bit 7 of
--  the register address is 1 for read, 0 for write.
with Machine.SPI, Machine.Blocking.Generic_SPI_Master,
     Machine.SPI.Generic_Chip_Select, Machine.Regmap.Generic_Device;
generic
   with package Bus is new Machine.Blocking.Generic_SPI_Master (<>);
                                    --  blocking full-duplex exchanges
   with package CS  is new Machine.SPI.Generic_Chip_Select (<>);
                                    --  chip select, polarity set by the wiring
   Timeout_Ms : Natural := 100;     --  per register access
package Machine.Regmap.Generic_SPI_Binding
  with SPARK_Mode
is
   procedure Write_Reg (Reg : Reg_Address; Value : Byte;
                        Status : in out Access_Status)
     with Post => (if Status'Old /= Ok then Status = Status'Old);  --  §7.1 rule 1

   procedure Read_Regs (Start : Reg_Address; Data : out Byte_Array;
                        Status : in out Access_Status)
     with Post => (if Status'Old /= Ok
                   then Status = Status'Old
                        and then (for all I in Data'Range => Data (I) = 0));

   package As_Device is new Machine.Regmap.Generic_Device
     (Write_Reg => Write_Reg, Read_Regs => Read_Regs);
end Machine.Regmap.Generic_SPI_Binding;
