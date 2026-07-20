package body Machine.Regmap.Generic_I2C_Binding
  with SPARK_Mode
is

   use Machine.I2C;

   function To_Access (T : Transaction_Status) return Access_Status is
     (case T is
         when Machine.I2C.Ok        => Machine.Regmap.Ok,
         when Machine.I2C.Timed_Out => Machine.Regmap.Timed_Out,
         when others                => Bus_Fault);

   procedure Write_Reg (Reg : Reg_Address; Value : Byte;
                        Status : in out Access_Status)
   is
      T : Transaction_Status := Machine.I2C.Ok;
   begin
      if Status /= Machine.Regmap.Ok then
         return;                            --  chained
      end if;
      Bus.Write (Device_Address, (1 => Byte (Reg), 2 => Value),
                 Timeout_Ms, T);
      if T /= Machine.I2C.Ok then
         Status := To_Access (T);
      end if;
   end Write_Reg;

   procedure Read_Regs (Start : Reg_Address; Data : out Byte_Array;
                        Status : in out Access_Status)
   is
      T : Transaction_Status := Machine.I2C.Ok;
   begin
      Data := (others => 0);
      if Status /= Machine.Regmap.Ok then
         return;                            --  chained
      end if;
      Bus.Write_Read (Device_Address, (1 => Byte (Start)), Data,
                      Timeout_Ms, T);
      if T /= Machine.I2C.Ok then
         Status := To_Access (T);
      end if;
   end Read_Regs;

end Machine.Regmap.Generic_I2C_Binding;
