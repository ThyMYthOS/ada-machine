--  L3c SPI adapter, variant 2 (per machine_tasking's manifest): awaits
--  block-level DMA completion through a protected status flag, polled
--  under a genuine Ada.Real_Time deadline (Timeout_Ms), not a
--  Suspension_Object.
--
--  This is *not* a protected entry awaited via a timed entry call --
--  Ravenscar's No_Select_Statements restriction bans every select
--  statement, timed entry calls included (gnatprove confirmed this: an
--  earlier version of this file used exactly that and failed to compile
--  under the profile). The remaining Ravenscar-legal way to bound a wait
--  is the calling task polling a plain (entry-free) protected function
--  in a delay-until loop, which is what Exchange below does -- the
--  trade-off being up to one Poll_Period of added latency after the
--  real completion signal, versus a blocking entry's immediate wake.
--  Generic_SPI's Suspension_Object variant has zero such latency but no
--  deadline at all; this variant has a real deadline at the cost of
--  that latency -- the genuine trade-off between the two variants.
--
--  DMA stays an <mcu>_hal implementation detail (§8.2): this package
--  never touches a DMA descriptor itself. The three formals below are
--  the whole of what it needs from the HAL:
--    * Start_Transfer kicks one whole-block DMA transfer and returns
--      immediately (§6.2, never blocks);
--    * Cancel_Transfer, on a timeout, must SYNCHRONOUSLY stop the DMA
--      engine such that no completion signal can arrive after it
--      returns -- this is what makes it safe to re-arm for the next
--      Exchange without a stale, late signal from an abandoned transfer
--      being misattributed to it (§7.1 rule 2, "fail clean", extended to
--      DMA hardware rather than just a bus transaction);
--    * Read_Response copies the DMA-filled buffer out after completion.
with Machine.SPI, Machine.Blocking.Generic_SPI_Master;
use type Machine.SPI.Transaction_Status;  --  for the Post contract's "="/"/="
generic
   with procedure Start_Transfer (TX     : Byte_Array;
                                  Length : Positive;
                                  Status : in out Machine.SPI.Transaction_Status);
   with procedure Cancel_Transfer (Status : in out Machine.SPI.Transaction_Status);
   with procedure Read_Response (Into : out Byte_Array; Last : out Natural);
package Machine.Tasking.Generic_DMA_SPI
  with SPARK_Mode
is

   --  Called by the application's DMA-done interrupt handler (D5: the
   --  adapter never installs handlers, the application attaches one and
   --  calls in here) -- the block-level counterpart of
   --  machine_async.SPI.On_Interrupt. The protected object doing the
   --  actual arm/wait/signal bookkeeping is body-private, exactly as
   --  machine_async.SPI keeps its Active/Result state body-private
   --  behind the plain On_Interrupt procedure.
   procedure Signal_Complete (Status : Machine.SPI.Transaction_Status);

   procedure Exchange (TX         : Byte_Array;
                       RX         : out Byte_Array;
                       Timeout_Ms : Natural;
                       Status     : in out Machine.SPI.Transaction_Status)
     with Post => (if Status'Old /= Machine.SPI.Ok
                   then Status = Status'Old
                        and then (for all I in RX'Range => RX (I) = 0));

   package As_Blocking is new Machine.Blocking.Generic_SPI_Master
     (Exchange => Exchange);

end Machine.Tasking.Generic_DMA_SPI;
