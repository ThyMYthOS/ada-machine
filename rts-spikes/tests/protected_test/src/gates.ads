--  Two protected objects, each with one entry whose barrier is False until
--  something else makes it True.
with Ada.Real_Time;                 use Ada.Real_Time;
with Ada.Real_Time.Timing_Events;   use Ada.Real_Time.Timing_Events;
with System;

package Gates is

   --  Everything is relative to this instant, taken at elaboration.
   Epoch : constant Time := Clock + Milliseconds (100);

   ---------------------------------------------------------------------
   --  1. Released by another TASK.
   ---------------------------------------------------------------------
   protected Gate is
      procedure Open;
      entry Wait;                    --  barrier: Is_Open; closes it again
      function Opened_At return Time;
   private
      Is_Open : Boolean := False;
      Stamp   : Time := Time_First;
   end Gate;

   --  Opens Gate at Epoch + 150 ms and again at Epoch + 350 ms.
   task Opener with Priority => 100, Storage_Size => 8 * 1024, Secondary_Stack_Size => 256;

   ---------------------------------------------------------------------
   --  2. Released from the ALARM INTERRUPT: Fire is a Timing_Event handler,
   --  and a Timing_Event handler runs in the alarm handler, which is the
   --  runtime's only timer interrupt (System.BB.Board_Support.Time.
   --  Install_Alarm_Handler -> mtimecmp -> the M-mode timer trap on the
   --  owning hart). A handler's protected object needs an interrupt-priority
   --  ceiling.
   ---------------------------------------------------------------------
   protected Alarm_Gate with Interrupt_Priority => System.Interrupt_Priority'Last is
      procedure Fire (Event : in out Timing_Event);
      entry Wait;
      function Fired_At return Time;
      function Fire_Count return Natural;
   private
      Is_Open : Boolean := False;
      Stamp   : Time := Time_First;
      Fires   : Natural := 0;
   end Alarm_Gate;

   --  Timing_Event objects must be library-level (Jorvik: No_Local_Timing_Events).
   Ev1, Ev2 : Timing_Event;

end Gates;
