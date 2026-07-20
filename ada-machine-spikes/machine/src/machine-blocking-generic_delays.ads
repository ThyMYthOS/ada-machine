--  Delaying is inherently blocking, so the delays contract lives under
--  the blocking model.
generic
   with procedure Delay_Us (Us : Natural);  --  wait at least Us microseconds
   with procedure Delay_Ms (Ms : Natural);  --  wait at least Ms milliseconds
package Machine.Blocking.Generic_Delays
  with Pure, SPARK_Mode
is end Machine.Blocking.Generic_Delays;
