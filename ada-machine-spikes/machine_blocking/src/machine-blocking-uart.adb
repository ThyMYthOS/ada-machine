package body Machine.Blocking.UART
  with SPARK_Mode
is

   use Machine.UART;
   use type Clock.Ticks;

   --  Put_Frame carries no Line_Status (§6.2/6.3): only the read side can
   --  observe framing/parity/overrun, so the only failure Put can report
   --  is Timed_Out -- there is no Bus_Status-style mapping to do here,
   --  unlike Machine.Blocking.I2C's Write.

   function Ticks_For_Ms (Ms : Natural) return Clock.Ticks is
      TPS : constant Long_Long_Integer :=
        Long_Long_Integer (Clock.Ticks_Per_Second);
      N   : constant Long_Long_Integer :=
        (Long_Long_Integer (Ms) * TPS + 999) / 1_000;
   begin
      return Clock.Ticks'Mod (N);
   end Ticks_For_Ms;

   procedure Put (Data       : Byte_Array;
                  Timeout_Ms : Natural;
                  Status     : in out Machine.UART.Transaction_Status)
   is
      Start        : constant Clock.Ticks := Clock.Now;
      Limit        : constant Clock.Ticks := Ticks_For_Ms (Timeout_Ms);
      Now          : Clock.Ticks;
      Tx_Ready_Now : Boolean;
   begin
      if Status /= Machine.UART.Ok then
         return;                             --  chained: skip if pending
      end if;
      for I in Data'Range loop
         loop
            --  Port.Is_Tx_Ready/Clock.Now read alone into a local first
            --  (SPARK RM 7.1.3(9)): both are volatile functions.
            Tx_Ready_Now := Port.Is_Tx_Ready;
            exit when Tx_Ready_Now;
            Now := Clock.Now;
            if Now - Start >= Limit then
               Status := Timed_Out;
               return;
            end if;
         end loop;
         Port.Put_Frame (Port.Frame (Data (I)));
      end loop;
   end Put;

end Machine.Blocking.UART;
