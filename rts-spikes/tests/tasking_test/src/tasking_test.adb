--  RTS-PRODUCTION.md A4, "tasking": two tasks, `delay until`, ordering and
--  elapsed time, on light_tasking_mpfs.
--
--  TIMING TOLERANCE, and why. QEMU's mtime follows the HOST's clock, so a
--  QEMU delay is not real-time-exact: the host can deschedule the whole
--  emulator for tens of milliseconds. What a delay must NEVER do is return
--  before its time -- that bound is asserted exactly, with no slack, and it is
--  the one that catches a wrongly-programmed alarm or a mis-scaled
--  Clock_Frequency. The upper bound is deliberately loose (Slack = 500 ms):
--  it is there to catch "the alarm fires at the wrong scale or not at all",
--  not to measure jitter, and a limit tight enough to measure it would make
--  this test flaky on a loaded CI runner. Measured lateness is printed as
--  info so a drift is visible without being a failure.
with Ada.Real_Time; use Ada.Real_Time;
with Probe;
with Test_Report;   use Test_Report;

procedure Tasking_Test is

   Slack : constant Time_Span := Milliseconds (500);

   function Ms (S : Time_Span) return Integer is (S / Milliseconds (1));

   --  Measure one `delay until` of D from now, check it against the clock.
   procedure Measure (D : Time_Span; What : String) is
      T0 : constant Time := Clock;
      T1 : Time;
   begin
      delay until T0 + D;
      T1 := Clock;
      Info (What & ": requested ms", Ms (D));
      Info (What & ": elapsed ms",   Ms (T1 - T0));
      Check (T1 - T0 >= D,         What & ": never returns early");
      Check (T1 - T0 <= D + Slack, What & ": returns within the slack");
   end Measure;

   Last   : Time;
   Mono   : Boolean := True;
   Order  : Probe.Event_Text;
begin
   Start ("tasking_test");

   --  The clock itself: monotonic, and its unit meets RM D.8 (30).
   Last := Clock;
   for I in 1 .. 1000 loop
      declare
         Now : constant Time := Clock;
      begin
         if Now < Last then
            Mono := False;
         end if;
         Last := Now;
      end;
   end loop;
   Check (Mono, "Clock never goes backwards (1000 reads)");
   Check (Time_Span_Unit <= Microseconds (20), "Time_Span_Unit <= 20 us (RM D.8)");
   Check (Milliseconds (250) = Microseconds (250_000), "Milliseconds / Microseconds agree");

   --  Let the library-level tasks run their whole schedule: the last release
   --  is at Epoch + 700 ms.
   delay until Probe.Epoch + Milliseconds (1000);

   Order := Probe.Log.Text;
   Info ("events logged", Probe.Log.Count);
   Check (Probe.Log.Count = 8, "all eight scheduled wake-ups happened");
   Check (Order (1 .. 8) = "ABABABHL",
          "two tasks interleave in release order, higher priority first at a tie ("
          & Order (1 .. 8) & ")");
   Check (not Probe.Log.Ever_Early, "no task ever woke before its time");
   Info ("worst task lateness ms", Ms (Probe.Log.Max_Late));
   Check (Probe.Log.Max_Late <= Slack, "worst task lateness is within the slack");

   --  The environment task's own delays, with the other tasks finished.
   Measure (Milliseconds (50),  "delay until +50 ms");
   Measure (Milliseconds (250), "delay until +250 ms");

   Finish;
end Tasking_Test;
