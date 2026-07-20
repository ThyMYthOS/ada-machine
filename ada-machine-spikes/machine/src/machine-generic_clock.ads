--  Monotonic time signature.
generic
   type Ticks is mod <>;                    --  monotonic counter, >= 2**32
   Ticks_Per_Second : Positive;             --  rate at which Now advances
   with function Now return Ticks;          --  read the clock; never blocks
package Machine.Generic_Clock
  with Pure, SPARK_Mode
is end Machine.Generic_Clock;
