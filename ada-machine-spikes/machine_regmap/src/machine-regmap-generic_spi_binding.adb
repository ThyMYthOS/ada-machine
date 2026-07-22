with Machine.GPIO;

package body Machine.Regmap.Generic_SPI_Binding
  with SPARK_Mode
is

   use Machine.SPI;
   use Machine.GPIO;

   Read_Flag : constant Byte := 16#80#;

   function To_Access (T : Transaction_Status) return Access_Status is
     (case T is
         when Machine.SPI.Ok        => Machine.Regmap.Ok,
         when Machine.SPI.Timed_Out => Machine.Regmap.Timed_Out,
         when others                => Bus_Fault);

   procedure Write_Reg (Reg : Reg_Address; Value : Byte;
                        Status : in out Access_Status)
   is
      T  : Transaction_Status := Machine.SPI.Ok;
      RX : Byte_Array (1 .. 2);
   begin
      if Status /= Machine.Regmap.Ok then
         return;                            --  chained
      end if;
      CS.Set (Low);
      Bus.Exchange ((1 => Byte (Reg) and not Read_Flag, 2 => Value),
                    RX, Timeout_Ms, T);
      CS.Set (High);                        --  fail clean: CS restored always
      if T /= Machine.SPI.Ok then
         Status := To_Access (T);
      end if;
   end Write_Reg;

   procedure Read_Regs (Start : Reg_Address; Data : out Byte_Array;
                        Status : in out Access_Status)
   is
      T  : Transaction_Status := Machine.SPI.Ok;
      TX : Byte_Array (1 .. Data'Length + 1) := (others => 0);
      RX : Byte_Array (1 .. Data'Length + 1);
   begin
      Data := (others => 0);
      if Status /= Machine.Regmap.Ok then
         return;                            --  chained
      end if;
      TX (1) := Byte (Start) or Read_Flag;
      CS.Set (Low);
      Bus.Exchange (TX, RX, Timeout_Ms, T);
      CS.Set (High);
      if T /= Machine.SPI.Ok then
         Status := To_Access (T);
         return;
      end if;
      for I in 1 .. Data'Length loop
         Data (Data'First + I - 1) := RX (I + 1);
      end loop;
   end Read_Regs;

end Machine.Regmap.Generic_SPI_Binding;
