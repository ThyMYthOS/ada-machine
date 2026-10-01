--  Library-level tasks and the protected log they report into. Jorvik forbids
--  local tasks and protected objects, so these live in a package (as in
--  tasking_mpfs's Workers).
with Ada.Real_Time; use Ada.Real_Time;

package Probe is

   --  Every release below is relative to this instant, taken at elaboration
   --  (before the tasks activate), so the schedule does not depend on how long
   --  task activation takes.
   Epoch : constant Time := Clock + Milliseconds (100);

   Max_Events : constant := 16;
   subtype Event_Text is String (1 .. Max_Events);

   protected Log is
      --  Who woke, and when it was supposed to. Records the lateness and
      --  whether the wake-up came EARLY (before Scheduled), which a correct
      --  `delay until` must never do.
      procedure Note (Who : Character; Scheduled : Time);
      function Count return Natural;
      function Text return Event_Text;
      function Ever_Early return Boolean;
      function Max_Late return Time_Span;
   private
      N      : Natural := 0;
      Items  : Event_Text := (others => '?');
      Early  : Boolean := False;
      Late   : Time_Span := Time_Span_Zero;
   end Log;

   --  A and B alternate at 100 ms steps, A at Epoch + 100, 300, 500 ms and B
   --  at Epoch + 200, 400, 600 ms: two tasks, one clock, a known order.
   task A  with Priority => 100, Storage_Size => 8 * 1024, Secondary_Stack_Size => 256;
   task B  with Priority => 100, Storage_Size => 8 * 1024, Secondary_Stack_Size => 256;

   --  Both released by the SAME alarm at Epoch + 700 ms. The dispatcher must
   --  run the higher-priority one first whatever order they were queued in.
   task Hi with Priority => 150, Storage_Size => 8 * 1024, Secondary_Stack_Size => 256;
   task Lo with Priority =>  50, Storage_Size => 8 * 1024, Secondary_Stack_Size => 256;

end Probe;
