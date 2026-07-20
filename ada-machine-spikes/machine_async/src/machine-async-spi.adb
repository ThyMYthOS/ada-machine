package body Machine.Async.SPI
  with SPARK_Mode
is

   use Machine.SPI;

   --  Adapter state: single producer of commands (mainline), single
   --  consumer (ISR pump). Volatile: shared with interrupt context.
   --  Async_Readers/Async_Writers named explicitly: bare Volatile
   --  defaults to *all four* of Async_Readers/Async_Writers/
   --  Effective_Reads/Effective_Writes (SPARK RM C.6), and
   --  Effective_Reads on a plain in-memory flag/counter/buffer (as
   --  opposed to a hardware register with real read side-effects) makes
   --  a function that merely reads it look, to flow analysis, like it
   --  has an output too -- exactly what tripped up Busy below.
   TX_Buf : Byte_Array (1 .. Buffer_Size) with Volatile, Async_Readers, Async_Writers;
   RX_Buf : Byte_Array (1 .. Buffer_Size) with Volatile, Async_Readers, Async_Writers;
   Length : Natural := 0 with Volatile, Async_Readers, Async_Writers;    --  bytes in this transfer
   Sent   : Natural := 0 with Volatile, Async_Readers, Async_Writers;    --  bytes pushed so far
   Got    : Natural := 0 with Volatile, Async_Readers, Async_Writers;    --  bytes popped so far
   Active : Boolean := False with Volatile, Async_Readers, Async_Writers;
   Result : Machine.SPI.Transaction_Status := Machine.SPI.Ok
     with Volatile, Async_Readers, Async_Writers;

   function To_Transaction (B : Bus_Status) return Transaction_Status is
     (case B is
         when Machine.SPI.Ok => Machine.SPI.Ok,
         when Mode_Fault     => Mode_Fault,
         when Other_Error    => Other_Error);

   function Busy return Boolean is (Active);

   --  Every volatile (Active/Length/Sent/Got/Result/TX_Buf/RX_Buf) read
   --  below, and every Port.Can_Push/Can_Pop call, is taken alone into a
   --  local first, then combined with other operators (or passed as an
   --  actual) via that ordinary local -- SPARK requires a volatile read
   --  to be the whole right-hand side of an assignment/declaration, the
   --  whole condition of an if/while, or the whole actual parameter, not
   --  combined with anything else in the same expression, nor passed
   --  directly as an actual (SPARK RM 7.1.3(9)).

   procedure Start_Exchange (TX     : Byte_Array;
                             Status : in out Machine.SPI.Transaction_Status)
   is
      B            : Bus_Status := Machine.SPI.Ok;
      Active_Now   : constant Boolean := Active;
      Can_Push_Now : Boolean;
   begin
      if Status /= Machine.SPI.Ok then
         return;                            --  chained: skip if pending
      end if;
      if Active_Now or else TX'Length = 0 or else TX'Length > Buffer_Size
      then
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
      Can_Push_Now := Port.Can_Push;
      if Can_Push_Now then
         declare
            Byte_To_Send : constant Byte := TX_Buf (1);
         begin
            Port.Push (Byte_To_Send, B);
         end;
         if B /= Machine.SPI.Ok then
            Active := False;
            Status := To_Transaction (B);
            return;
         end if;
         Sent := 1;
      end if;
   end Start_Exchange;

   procedure On_Interrupt is
      B            : Bus_Status := Machine.SPI.Ok;
      D            : Byte;
      Active_Now   : constant Boolean := Active;
      Can_Pop_Now  : Boolean;
      Can_Push_Now : Boolean;
      Got_Now      : Natural;
      Sent_Now     : Natural;
      Length_Now   : Natural;
      Result_Now   : Machine.SPI.Transaction_Status;
   begin
      if not Active_Now then
         return;
      end if;
      Can_Pop_Now := Port.Can_Pop;
      if Can_Pop_Now then
         Port.Pop (D, B);
         if B /= Machine.SPI.Ok then
            Result     := To_Transaction (B);
            Active     := False;
            Got_Now    := Got;
            Result_Now := Result;
            On_Complete (Got_Now, Result_Now);
            return;
         end if;
         --  "Got := Got + 1" reads and writes Got in the same statement
         --  (RHS combines the read with "+1") -- read once into a local,
         --  do the arithmetic there, then write the whole object.
         Got_Now := Got;
         Got_Now := Got_Now + 1;
         Got     := Got_Now;
         RX_Buf (Got_Now) := D;
      end if;
      Got_Now    := Got;
      Length_Now := Length;
      if Got_Now >= Length_Now then
         Active     := False;
         Result_Now := Result;
         On_Complete (Got_Now, Result_Now);
      else
         Sent_Now     := Sent;
         Can_Push_Now := Port.Can_Push;
         if Sent_Now < Length_Now and then Can_Push_Now then
            Sent_Now := Sent_Now + 1;
            Sent     := Sent_Now;
            declare
               Byte_To_Send : constant Byte := TX_Buf (Sent_Now);
            begin
               Port.Push (Byte_To_Send, B);
            end;
            if B /= Machine.SPI.Ok then
               Result     := To_Transaction (B);
               Active     := False;
               Got_Now    := Got;
               Result_Now := Result;
               On_Complete (Got_Now, Result_Now);
            end if;
         end if;
      end if;
   end On_Interrupt;

   procedure Read_Response (Into : out Byte_Array; Last : out Natural) is
      Got_Now : constant Natural := Got;
      N       : constant Natural := Natural'Min (Into'Length, Got_Now);
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
         Last     : Natural;
         Busy_Now : Boolean;
      begin
         RX := (others => 0);
         if Status /= Machine.SPI.Ok then
            return;                          --  chained: skip if pending
         end if;
         Start_Exchange (TX, Status);
         if Status /= Machine.SPI.Ok then
            return;
         end if;
         loop
            --  Busy read alone into a local first, then used bare as the
            --  exit condition via that local (SPARK RM 7.1.3(9): a
            --  volatile-reading call can't be the condition of a while
            --  loop directly, even unaccompanied).
            Busy_Now := Busy;
            exit when not Busy_Now;
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
