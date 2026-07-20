package body Machine.Async.SPI
  with SPARK_Mode
is

   use Machine.SPI;

   --  Adapter state: single producer of commands (mainline), single
   --  consumer (ISR pump). Volatile: shared with interrupt context.
   TX_Buf : Byte_Array (1 .. Buffer_Size) with Volatile;
   RX_Buf : Byte_Array (1 .. Buffer_Size) with Volatile;
   Length : Natural := 0 with Volatile;    --  bytes in this transfer
   Sent   : Natural := 0 with Volatile;    --  bytes pushed so far
   Got    : Natural := 0 with Volatile;    --  bytes popped so far
   Active : Boolean := False with Volatile;
   Result : Machine.SPI.Transaction_Status := Machine.SPI.Ok with Volatile;

   function To_Transaction (B : Bus_Status) return Transaction_Status is
     (case B is
         when Machine.SPI.Ok => Machine.SPI.Ok,
         when Mode_Fault     => Mode_Fault,
         when Other_Error    => Other_Error);

   function Busy return Boolean is (Active);

   procedure Start_Exchange (TX     : Byte_Array;
                             Status : in out Machine.SPI.Transaction_Status)
   is
      B : Bus_Status := Machine.SPI.Ok;
   begin
      if Status /= Machine.SPI.Ok then
         return;                            --  chained: skip if pending
      end if;
      if Active or else TX'Length = 0 or else TX'Length > Buffer_Size then
         Status := Other_Error;
         return;
      end if;
      TX_Buf (1 .. TX'Length) := TX;
      Length := TX'Length;
      Sent   := 0;
      Got    := 0;
      Result := Machine.SPI.Ok;
      Active := True;
      --  Kick the first byte; the rest moves in interrupt context.
      if Port.Can_Push then
         Port.Push (TX_Buf (1), B);
         if B /= Machine.SPI.Ok then
            Active := False;
            Status := To_Transaction (B);
            return;
         end if;
         Sent := 1;
      end if;
   end Start_Exchange;

   procedure On_Interrupt is
      B : Bus_Status := Machine.SPI.Ok;
      D : Byte;
   begin
      if not Active then
         return;
      end if;
      if Port.Can_Pop then
         Port.Pop (D, B);
         if B /= Machine.SPI.Ok then
            Result := To_Transaction (B);
            Active := False;
            On_Complete (Got, Result);
            return;
         end if;
         Got := Got + 1;
         RX_Buf (Got) := D;
      end if;
      if Got >= Length then
         Active := False;
         On_Complete (Got, Result);
      elsif Sent < Length and then Port.Can_Push then
         Sent := Sent + 1;
         Port.Push (TX_Buf (Sent), B);
         if B /= Machine.SPI.Ok then
            Result := To_Transaction (B);
            Active := False;
            On_Complete (Got, Result);
         end if;
      end if;
   end On_Interrupt;

   procedure Read_Response (Into : out Byte_Array; Last : out Natural) is
      N : constant Natural := Natural'Min (Into'Length, Got);
   begin
      Into := (others => 0);
      for I in 1 .. N loop
         Into (Into'First + I - 1) := RX_Buf (I);
      end loop;
      Last := Into'First + N - 1;
   end Read_Response;

   package body Generic_Await
     with SPARK_Mode
   is

      procedure Exchange (TX         : Byte_Array;
                          RX         : out Byte_Array;
                          Timeout_Ms : Natural;
                          Status     : in out Machine.SPI.Transaction_Status)
      is
         --  Clock-less bound: iterations, not a deadline (spike honesty).
         Spins_Per_Ms : constant := 10_000;
         Budget : Long_Long_Integer :=
           Long_Long_Integer (Timeout_Ms) * Spins_Per_Ms;
         Last : Natural;
      begin
         RX := (others => 0);
         if Status /= Machine.SPI.Ok then
            return;                          --  chained: skip if pending
         end if;
         Start_Exchange (TX, Status);
         if Status /= Machine.SPI.Ok then
            return;
         end if;
         while Busy loop
            Sleep_Until_Interrupt;
            Budget := Budget - 1;
            if Budget <= 0 then
               Active := False;              --  abort the transfer
               Status := Timed_Out;
               return;
            end if;
         end loop;
         Status := Result;
         if Status = Machine.SPI.Ok then
            Read_Response (RX, Last);
         end if;
      end Exchange;

   end Generic_Await;

end Machine.Async.SPI;
