package body Mock_Clock
  with SPARK_Mode,
       Refined_State => (State => Current)
is
   Current : Ticks := 0;

   procedure Set_Now (T : Ticks) is
   begin
      Current := T;
   end Set_Now;

   function Now return Ticks is (Current);

end Mock_Clock;
