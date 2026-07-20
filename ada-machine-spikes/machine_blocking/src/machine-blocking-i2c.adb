package body Machine.Blocking.I2C
  with SPARK_Mode
is

   use Machine.I2C;
   use type Clock.Ticks;

   function To_Transaction (B : Bus_Status) return Transaction_Status is
     (case B is
         when Machine.I2C.Ok  => Machine.I2C.Ok,
         when Nack_Address    => Nack_Address,
         when Nack_Data       => Nack_Data,
         when Arbitration_Lost => Arbitration_Lost,
         when Bus_Error       => Bus_Error,
         when Other_Error     => Other_Error);

   function Ticks_For_Ms (Ms : Natural) return Clock.Ticks is
      TPS : constant Long_Long_Integer :=
        Long_Long_Integer (Clock.Ticks_Per_Second);
      N   : constant Long_Long_Integer :=
        (Long_Long_Integer (Ms) * TPS + 999) / 1_000;
   begin
      return Clock.Ticks'Mod (N);
   end Ticks_For_Ms;

   procedure Write (Address    : Machine.I2C.Address_7_Bit;
                    Data       : Byte_Array;
                    Timeout_Ms : Natural;
                    Status     : in out Machine.I2C.Transaction_Status)
   is
      Start : constant Clock.Ticks := Clock.Now;
      Limit : constant Clock.Ticks := Ticks_For_Ms (Timeout_Ms);
      B     : Bus_Status := Machine.I2C.Ok;
   begin
      if Status /= Machine.I2C.Ok then
         return;                             --  chained: skip if pending
      end if;
      Port.Set_Target (Address);
      for I in Data'Range loop
         while not Port.Can_Push loop
            if Clock.Now - Start >= Limit then
               Status := Timed_Out;
               return;
            end if;
         end loop;
         Port.Push_Write (Data (I), Stop => I = Data'Last, Status => B);
         if B /= Machine.I2C.Ok then
            Status := To_Transaction (B);
            return;
         end if;
      end loop;
   end Write;

   procedure Write_Read (Address    : Machine.I2C.Address_7_Bit;
                         Command    : Byte_Array;
                         Response   : out Byte_Array;
                         Timeout_Ms : Natural;
                         Status     : in out Machine.I2C.Transaction_Status)
   is
      Start   : constant Clock.Ticks := Clock.Now;
      Limit   : constant Clock.Ticks := Ticks_For_Ms (Timeout_Ms);
      B       : Bus_Status := Machine.I2C.Ok;
      Pushed  : Natural := 0;                --  read requests enqueued
      Got     : Natural := 0;                --  response bytes received
      Total   : constant Natural := Response'Length;

      function Expired return Boolean is (Clock.Now - Start >= Limit);
   begin
      Response := (others => 0);             --  defined values on skip/fail
      if Status /= Machine.I2C.Ok then
         return;                             --  chained: skip if pending
      end if;
      Port.Set_Target (Address);

      --  Command phase (no STOP: the read phase issues a repeated start).
      for I in Command'Range loop
         while not Port.Can_Push loop
            if Expired then Status := Timed_Out; return; end if;
         end loop;
         Port.Push_Write (Command (I), Stop => False, Status => B);
         if B /= Machine.I2C.Ok then
            Status := To_Transaction (B); return;
         end if;
      end loop;

      --  Read phase: keep the command FIFO fed while draining the RX FIFO.
      while Got < Total loop
         if Pushed < Total and then Port.Can_Push then
            Pushed := Pushed + 1;
            Port.Push_Read_Request (Stop => Pushed = Total, Status => B);
            if B /= Machine.I2C.Ok then
               Status := To_Transaction (B); return;
            end if;
         end if;
         if Port.Can_Pop then
            Got := Got + 1;
            Port.Pop (Response (Response'First + Got - 1), B);
            if B /= Machine.I2C.Ok then
               Status := To_Transaction (B); return;
            end if;
         elsif Expired then
            Status := Timed_Out;
            return;
         end if;
      end loop;
   end Write_Read;

end Machine.Blocking.I2C;
