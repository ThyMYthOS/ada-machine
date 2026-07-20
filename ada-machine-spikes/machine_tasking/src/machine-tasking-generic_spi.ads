--  L3c SPI adapter, variant 1 (per machine_tasking's manifest): wraps
--  machine_async's interrupt-driven core with a Suspension_Object await,
--  replacing Generic_Await's busy-spin with a real task suspension.
--
--  Design note on Timeout_Ms: Ada.Synchronous_Task_Control has no timed
--  suspension primitive -- Suspend_Until_True blocks until Set_True or
--  forever. This variant therefore accepts Timeout_Ms only for
--  Machine.Blocking.Generic_SPI_Master conformance and does not enforce
--  it (it never produces Timed_Out); it assumes the interrupt eventually
--  fires, which is the right trade for a cheap, always-on bus. Where a
--  hard deadline matters, use Machine.Tasking.Generic_DMA_SPI instead --
--  its protected entry is awaited through a genuine timed entry call.
--  This split is deliberate (two variants, two trade-offs), not
--  incidental.
with Machine.SPI.Generic_Master, Machine.Async.SPI,
     Machine.Blocking.Generic_SPI_Master;
use type Machine.SPI.Transaction_Status;  --  for the Post contract's "="/"/="
generic
   with package Port is new Machine.SPI.Generic_Master (<>);
                                    --  never-blocking L2 data phase to pump
   Buffer_Size : Positive := 32;    --  adapter-owned TX/RX buffers
package Machine.Tasking.Generic_SPI
  with SPARK_Mode
is

   procedure Exchange (TX         : Byte_Array;
                       RX         : out Byte_Array;
                       Timeout_Ms : Natural;
                       Status     : in out Machine.SPI.Transaction_Status)
     with Post => (if Status'Old /= Machine.SPI.Ok
                   then Status = Status'Old
                        and then (for all I in RX'Range => RX (I) = 0));

   --  The pump: bounded, never blocks; the APPLICATION attaches it (D5) --
   --  same contract as machine_async.SPI.On_Interrupt.
   procedure On_Interrupt;

   package As_Blocking is new Machine.Blocking.Generic_SPI_Master
     (Exchange => Exchange);

end Machine.Tasking.Generic_SPI;
