--  A log sink is the §10.3 diagnostic channel wearing a different hat:
--  these spikes have no runtime FIFO to reuse, so the pragmatic
--  transport is a direct blocking drain over the L2 UART port -- no
--  Machine.Generic_Clock/timeout formal, since a log line that can't
--  be pushed within a few instructions is not something a bounded
--  timeout would meaningfully recover from at this layer (§14.2:
--  logging calls stay bounded-time, callable from an ISR pump).
with Machine.UART.Generic_Port, Machine.Log;
generic
   with package UART is new Machine.UART.Generic_Port (<>);
                                    --  the wired L2 UART port; UART.Frame
                                    --  is whatever word width it was
                                    --  instantiated with (§6.3) -- each
                                    --  byte of the wire format below is
                                    --  converted to it explicitly.
package Machine.Blocking.Log_Sink
  with SPARK_Mode
is
   --  Wire format (documented, not machine-checked -- §19 open question
   --  9 on event interning): Level'Pos (1B), Event_Id big-endian (2B),
   --  Arg big-endian (4B); a host-side tool renders text from the
   --  per-crate Event_Id enumerations.
   procedure Emit (Level : Machine.Log.Level;
                   E     : Machine.Log.Event_Id;
                   A     : Machine.Log.Arg := Machine.Log.No_Arg);
end Machine.Blocking.Log_Sink;
