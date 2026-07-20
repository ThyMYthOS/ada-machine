--  Recording_Log_Sink -- a host-side stand-in for a UART-backed log
--  sink: records emitted events in memory instead of draining bytes
--  over a UART, so a driver's logging formals double as test probes
--  (§14.5) without any real hardware. Bound directly as BME280's
--  Log_Event formal (Event_Id + Arg only -- the driver predates the
--  Level vocabulary, same as the board wiring in spike1_pico).
with Machine;     use Machine;
with Machine.Log; use Machine.Log;

package Recording_Log_Sink
  with SPARK_Mode,
       Abstract_State => State,
       Initializes    => State
is
   Max_Events : constant := 16;

   procedure Log_Event (E : Machine.Log.Event_Id;
                        A : Machine.Log.Arg := Machine.Log.No_Arg)
     with Global => (In_Out => State);

   function Count return Natural
     with Global => (Input => State), Post => Count'Result <= Max_Events;

   function Event (I : Positive) return Machine.Log.Event_Id
     with Global => (Input => State), Pre => I <= Count;

   function Arg_At (I : Positive) return Machine.Log.Arg
     with Global => (Input => State), Pre => I <= Count;

end Recording_Log_Sink;
