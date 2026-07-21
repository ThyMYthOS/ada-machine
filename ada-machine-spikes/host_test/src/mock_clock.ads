--  Mock_Clock -- host stand-in for Machine.Generic_Clock's formals.
--  Test-settable so the epoch-write test can advance time by an exact,
--  known amount instead of racing the wall clock.
package Mock_Clock
  with SPARK_Mode,
       Abstract_State => State,
       Initializes    => State
is
   type Ticks is mod 2 ** 32;
   Ticks_Per_Second : constant := 1;

   procedure Set_Now (T : Ticks)
     with Global => (Output => State);

   function Now return Ticks
     with Volatile_Function, Global => (Input => State);
   --  Volatile_Function: Set_Now between calls means two
   --  textually-identical calls need not agree, same as any real L2
   --  clock read (RM 7.1.3(9)).

end Mock_Clock;
