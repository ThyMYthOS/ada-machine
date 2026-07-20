--  Deferred-formatting logging vocabulary: ids + scalars, no strings.
package Machine.Log
  with Pure, SPARK_Mode
is
   type Event_Id is mod 2**16;
   type Arg is mod 2**32;
   No_Arg : constant Arg := 0;
end Machine.Log;
