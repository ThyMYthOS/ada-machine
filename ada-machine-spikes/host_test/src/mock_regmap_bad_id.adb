package body Mock_Regmap_Bad_Id
  with SPARK_Mode
is

   procedure Write_Reg (Reg : Reg_Address; Value : Byte;
                        Status : in out Access_Status) is
      pragma Unreferenced (Reg, Value, Status);
   begin
      null;                                 --  never reached: Initialize
   end Write_Reg;                            --  bails out before writing

   procedure Read_Regs (Start : Reg_Address; Data : out Byte_Array;
                        Status : in out Access_Status) is
      pragma Unreferenced (Start, Status);
   begin
      Data := (others => 0);                --  chip id (0xD0) reads 0x00
   end Read_Regs;

end Mock_Regmap_Bad_Id;
