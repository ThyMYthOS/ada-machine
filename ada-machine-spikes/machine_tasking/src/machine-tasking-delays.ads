--  Ravenscar/Jorvik delays: real "delay until" against Ada.Real_Time,
--  rather than machine_blocking.Delays' busy-wait over a native Clock
--  (§6.5). Ada.Real_Time.Clock is a standard facility of every tasking
--  runtime, so -- unlike the busy-wait adapter -- this needs no
--  Machine.Generic_Clock formal at all: the time base comes for free
--  from the runtime profile itself.
with Ada.Real_Time;
with Machine.Blocking.Generic_Delays;
package Machine.Tasking.Delays
  with SPARK_Mode
is
   procedure Delay_Us (Us : Natural);
   procedure Delay_Ms (Ms : Natural);

   --  The adapter exports its own conformance (normative pattern, as in
   --  machine_blocking.Delays):
   package As_Signature is new Machine.Blocking.Generic_Delays
     (Delay_Us => Delay_Us, Delay_Ms => Delay_Ms);
end Machine.Tasking.Delays;
