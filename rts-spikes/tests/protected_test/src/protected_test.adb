--  RTS-PRODUCTION.md A4, "protected objects": an entry whose barrier is
--  released by another task, and one released from the alarm interrupt.
--
--  The ISR case is a Timing_Event, not a PLIC source. That is deliberate: the
--  timer interrupt is the one interrupt the runtime already wires up end to end
--  (the same alarm that implements `delay until`), whereas attaching a handler
--  to an external interrupt needs the hart-indexed PLIC work of plan step D1.
--  There is also no other task able to run the handler here -- the environment
--  task is blocked in the entry and Opener has finished -- so if the barrier
--  opens, the interrupt did it.
--
--  Timing tolerance: see tasking_test.adb. "Not before its time" is exact; the
--  upper bound is a loose 500 ms.
with Ada.Real_Time;                 use Ada.Real_Time;
with Ada.Real_Time.Timing_Events;   use Ada.Real_Time.Timing_Events;
with Gates;                         use Gates;
with Test_Report;                   use Test_Report;

procedure Protected_Test is

   Slack : constant Time_Span := Milliseconds (500);

   function Ms (S : Time_Span) return Integer is (S / Milliseconds (1));

   T0, T1, Due : Time;
   Cancelled : Boolean;
begin
   Start ("protected_test");

   ----------------------------------------------------------------------
   --  Barrier released by another task.
   ----------------------------------------------------------------------
   T0 := Clock;
   Check (T0 < Epoch + Milliseconds (150), "the call is made before the barrier opens");
   Gate.Wait;                                       --  blocks until Opener opens it
   T1 := Clock;
   Info ("first wait: blocked ms", Ms (T1 - T0));
   Check (Gate.Opened_At >= Epoch + Milliseconds (150),
          "the barrier opened no earlier than the task released it");
   Check (T1 >= Gate.Opened_At, "the caller resumed after the release");
   Check (T1 - Epoch <= Milliseconds (150) + Slack, "and within the slack");

   --  The entry body closed the barrier again: a second call must block until
   --  the second release, 200 ms after the first.
   Gate.Wait;
   T1 := Clock;
   Check (T1 >= Epoch + Milliseconds (350),
          "second call blocks again (barrier re-evaluated after the body)");
   Check (Gate.Opened_At >= Epoch + Milliseconds (350),
          "second release is the later one");

   ----------------------------------------------------------------------
   --  Barrier released from the alarm interrupt (Timing_Event handler).
   ----------------------------------------------------------------------
   T0  := Clock;
   Due := T0 + Milliseconds (150);
   Set_Handler (Ev1, Due, Alarm_Gate.Fire'Access);
   Check (Current_Handler (Ev1) /= null, "the handler is set on the event");
   Alarm_Gate.Wait;                                 --  only the alarm interrupt can open it
   T1 := Clock;
   Info ("interrupt release: blocked ms", Ms (T1 - T0));
   Check (Alarm_Gate.Fire_Count = 1, "the handler ran exactly once");
   Check (Alarm_Gate.Fired_At >= Due,
          "the handler ran no earlier than its time");
   Check (T1 - T0 <= Milliseconds (150) + Slack, "and the caller resumed within the slack");
   Check (Current_Handler (Ev1) = null, "the event is clear once it has fired");

   --  A cancelled event must not fire.
   Set_Handler (Ev2, Clock + Milliseconds (50), Alarm_Gate.Fire'Access);
   Cancel_Handler (Ev2, Cancelled);
   Check (Cancelled, "Cancel_Handler reports that it cancelled");
   delay until Clock + Milliseconds (200);
   Check (Alarm_Gate.Fire_Count = 1, "a cancelled event never fires");

   Finish;
end Protected_Test;
