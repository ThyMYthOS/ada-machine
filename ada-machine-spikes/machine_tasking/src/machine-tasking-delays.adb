package body Machine.Tasking.Delays
  with SPARK_Mode
is

   use type Ada.Real_Time.Time;

   procedure Delay_Us (Us : Natural) is
      --  Ada.Real_Time.Clock is itself a volatile function: SPARK's
      --  interfering-context rule (RM 7.1.3(9)) requires its result to
      --  be read alone, not combined with "+" in the same expression.
      Now : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
   begin
      delay until Now + Ada.Real_Time.Microseconds (Us);
   end Delay_Us;

   procedure Delay_Ms (Ms : Natural) is
      Now : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
   begin
      delay until Now + Ada.Real_Time.Milliseconds (Ms);
   end Delay_Ms;

end Machine.Tasking.Delays;
