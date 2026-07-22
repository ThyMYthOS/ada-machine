with Ada.Real_Time;
with Machine.SPI;

use type Machine.SPI.Transaction_Status;

package body Machine.Tasking.Generic_DMA_SPI
  with SPARK_Mode
is

   --  Armed: guards against a completion signal from an ABANDONED
   --  transfer (one that timed out and was cancelled) being wrongly
   --  consumed by a later, unrelated Exchange call. Disarmed by the
   --  timeout path (after Cancel_Transfer has synchronously stopped the
   --  hardware) and by the polling loop itself on a real completion;
   --  re-armed only right before the next Start_Transfer.
   --
   --  No entries here (see the spec's header comment): Is_Done/Outcome
   --  are plain protected functions, polled by Exchange's delay-until
   --  loop, not awaited via a blocking/timed entry call.
   protected Completion is
      procedure Signal_Complete (Status : Machine.SPI.Transaction_Status);
      function  Is_Done return Boolean;
      function  Outcome return Machine.SPI.Transaction_Status;
      procedure Arm;
      procedure Disarm;
   private
      Armed  : Boolean := False;
      Done   : Boolean := False;
      Result : Machine.SPI.Transaction_Status := Machine.SPI.Ok;
   end Completion;

   protected body Completion is

      procedure Signal_Complete (Status : Machine.SPI.Transaction_Status) is
      begin
         if Armed then
            Result := Status;
            Done   := True;
         end if;
      end Signal_Complete;

      function Is_Done return Boolean is (Done);
      function Outcome return Machine.SPI.Transaction_Status is (Result);

      procedure Arm is
      begin
         Done  := False;
         Armed := True;
      end Arm;

      procedure Disarm is
      begin
         Armed := False;
         Done  := False;
      end Disarm;

   end Completion;

   procedure Signal_Complete (Status : Machine.SPI.Transaction_Status) is
   begin
      Completion.Signal_Complete (Status);
   end Signal_Complete;

   procedure Exchange (TX         : Byte_Array;
                       RX         : out Byte_Array;
                       Timeout_Ms : Natural;
                       Status     : in out Machine.SPI.Transaction_Status)
   is
      --  Ada.Real_Time.Clock is itself a volatile function (successive
      --  calls needn't agree): SPARK's interfering-context rule (RM
      --  7.1.3(9)) applies to its result exactly as it does to a
      --  volatile object, so every call is read alone into "Now" first
      --  and combined with other values only via that ordinary local.
      use type Ada.Real_Time.Time;
      Poll_Period : constant Ada.Real_Time.Time_Span :=
        Ada.Real_Time.Milliseconds (1);
      Deadline : Ada.Real_Time.Time;
      Now      : Ada.Real_Time.Time;
      Last     : Natural;
   begin
      RX := (others => 0);
      if Status /= Machine.SPI.Ok then
         return;                          --  chained: skip if pending
      end if;
      Now      := Ada.Real_Time.Clock;
      Deadline := Now + Ada.Real_Time.Milliseconds (Timeout_Ms);
      Completion.Arm;
      Start_Transfer (TX, TX'Length, Status);
      if Status /= Machine.SPI.Ok then
         Completion.Disarm;
         return;
      end if;
      loop
         declare
            --  Completion.Is_Done is effectively volatile too (its state
            --  is also written from outside the normal call graph, by
            --  the application's attached interrupt handler calling
            --  Signal_Complete) -- same isolate-the-read-first rule as
            --  Ada.Real_Time.Clock above.
            Done_Now : constant Boolean := Completion.Is_Done;
         begin
            exit when Done_Now;
         end;
         Now := Ada.Real_Time.Clock;
         if Now >= Deadline then
            Cancel_Transfer;               --  synchronous teardown; no late
                                           --  signal can arrive after it
            Completion.Disarm;
            Status := Machine.SPI.Timed_Out;  --  "it never finished" is the
                                            --  outcome; teardown is
                                            --  best-effort/statusless (§7.1)
            return;
         end if;
         declare
            Next_Wake : constant Ada.Real_Time.Time := Now + Poll_Period;
         begin
            delay until (if Next_Wake < Deadline then Next_Wake else Deadline);
         end;
      end loop;
      Status := Completion.Outcome;
      if Status = Machine.SPI.Ok then
         Read_Response (RX, Last);
      end if;
   end Exchange;

end Machine.Tasking.Generic_DMA_SPI;
