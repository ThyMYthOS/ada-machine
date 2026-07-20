package body Machine.Blocking.Delays
  with SPARK_Mode
is

   use type Clock.Ticks;

   function Ticks_For_Us (Us : Natural) return Clock.Ticks is
      TPS : constant Long_Long_Integer :=
        Long_Long_Integer (Clock.Ticks_Per_Second);
      N   : constant Long_Long_Integer :=
        (Long_Long_Integer (Us) * TPS + 999_999) / 1_000_000;
   begin
      return Clock.Ticks'Mod (N);
   end Ticks_For_Us;

   procedure Delay_Us (Us : Natural) is
      Start : constant Clock.Ticks := Clock.Now;
      Need  : constant Clock.Ticks := Ticks_For_Us (Us);
      Now   : Clock.Ticks;
   begin
      loop
         --  Clock.Now read alone into a local first: it is itself a
         --  volatile function (successive calls needn't agree), and
         --  SPARK's interfering-context rule (RM 7.1.3(9)) applies to
         --  its result exactly as it does to a volatile object.
         Now := Clock.Now;
         exit when Now - Start >= Need;
      end loop;
   end Delay_Us;

   procedure Delay_Ms (Ms : Natural) is
   begin
      for I in 1 .. Ms loop
         Delay_Us (1_000);
      end loop;
   end Delay_Ms;

end Machine.Blocking.Delays;
