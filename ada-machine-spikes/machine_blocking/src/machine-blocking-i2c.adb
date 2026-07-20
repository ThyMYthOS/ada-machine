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
      Start     : constant Clock.Ticks := Clock.Now;
      Limit     : constant Clock.Ticks := Ticks_For_Ms (Timeout_Ms);
      B         : Bus_Status := Machine.I2C.Ok;
      Now       : Clock.Ticks;
      Can_Push_Now : Boolean;
   begin
      if Status /= Machine.I2C.Ok then
         return;                             --  chained: skip if pending
      end if;
      Port.Set_Target (Address);
      for I in Data'Range loop
         loop
            --  Port.Can_Push/Clock.Now read alone into a local first
            --  (SPARK RM 7.1.3(9)): both are volatile functions, and a
            --  volatile call's result can't be combined with other
            --  operators -- nor even used bare as an if/while/exit-when
            --  condition without first being assigned to an ordinary
            --  local.
            Can_Push_Now := Port.Can_Push;
            exit when Can_Push_Now;
            Now := Clock.Now;
            if Now - Start >= Limit then
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
      Can_Push_Now, Can_Pop_Now, Expired_Now : Boolean;

      --  Volatile_Function: Expired reads volatile clock state (through
      --  Clock.Now) so two textually-identical calls need not agree
      --  (SPARK RM 7.1.3(9)); the read is taken alone into a local first
      --  for the same rule's "no combining" requirement.
      function Expired return Boolean
        with Volatile_Function
      is
         Now : constant Clock.Ticks := Clock.Now;
      begin
         return Now - Start >= Limit;
      end Expired;
   begin
      Response := (others => 0);             --  defined values on skip/fail
      if Status /= Machine.I2C.Ok then
         return;                             --  chained: skip if pending
      end if;
      Port.Set_Target (Address);

      --  Command phase (no STOP: the read phase issues a repeated start).
      for I in Command'Range loop
         loop
            Can_Push_Now := Port.Can_Push;
            exit when Can_Push_Now;
            Expired_Now := Expired;
            if Expired_Now then Status := Timed_Out; return; end if;
         end loop;
         Port.Push_Write (Command (I), Stop => False, Status => B);
         if B /= Machine.I2C.Ok then
            Status := To_Transaction (B); return;
         end if;
      end loop;

      --  Read phase: keep the command FIFO fed while draining the RX FIFO.
      while Got < Total loop
         Can_Push_Now := Port.Can_Push;
         if Pushed < Total and then Can_Push_Now then
            Pushed := Pushed + 1;
            Port.Push_Read_Request (Stop => Pushed = Total, Status => B);
            if B /= Machine.I2C.Ok then
               Status := To_Transaction (B); return;
            end if;
         end if;
         Can_Pop_Now := Port.Can_Pop;
         if Can_Pop_Now then
            Got := Got + 1;
            Port.Pop (Response (Response'First + Got - 1), B);
            if B /= Machine.I2C.Ok then
               Status := To_Transaction (B); return;
            end if;
         else
            Expired_Now := Expired;
            if Expired_Now then
               Status := Timed_Out;
               return;
            end if;
         end if;
      end loop;
   end Write_Read;

end Machine.Blocking.I2C;
