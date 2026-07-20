--  Busy-wait delays over any monotonic clock.
with Machine.Generic_Clock, Machine.Blocking.Generic_Delays;
generic
   with package Clock is new Machine.Generic_Clock (<>);
                                    --  time base to busy-wait on
package Machine.Blocking.Delays
  with SPARK_Mode
is
   procedure Delay_Us (Us : Natural);
   procedure Delay_Ms (Ms : Natural);

   --  The adapter exports its own conformance (normative pattern):
   package As_Signature is new Machine.Blocking.Generic_Delays
     (Delay_Us => Delay_Us, Delay_Ms => Delay_Ms);
end Machine.Blocking.Delays;
