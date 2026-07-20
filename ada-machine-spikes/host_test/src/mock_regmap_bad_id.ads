--  Mock_Regmap_Bad_Id -- exercises BME280's Wrong_Chip_Id fault path
--  (Machine.Regmap.Generic_Device's shape, same as Mock_Regmap) so that
--  Recording_Log_Sink has something to record: every register reads as
--  0x00, so the chip-id probe in Initialize never matches 0x60.
with Machine;        use Machine;
with Machine.Regmap; use Machine.Regmap;

package Mock_Regmap_Bad_Id
  with SPARK_Mode
is
   procedure Write_Reg (Reg : Reg_Address; Value : Byte;
                        Status : in out Access_Status)
     with Global => null,
          Post   => (if Status'Old /= Ok then Status = Status'Old);

   procedure Read_Regs (Start : Reg_Address; Data : out Byte_Array;
                        Status : in out Access_Status)
     with Global => null,
          Post   => (if Status'Old /= Ok
                     then Status = Status'Old
                          and then (for all I in Data'Range => Data (I) = 0));

end Mock_Regmap_Bad_Id;
