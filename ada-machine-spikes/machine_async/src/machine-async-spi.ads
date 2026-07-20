--  Interrupt-driven SPI transfers: transfer-oriented, access-free.
--  The adapter owns the buffers (no access types => no caller buffers);
--  the application attaches On_Interrupt to the SPI vector.
with Machine.SPI.Generic_Master, Machine.Blocking.Generic_SPI_Master;
use type Machine.SPI.Transaction_Status;  --  for the Post contracts' "="/"/="
generic
   with package Port is new Machine.SPI.Generic_Master (<>);
                                    --  never-blocking L2 data phase to pump
   Buffer_Size : Positive := 32;    --  adapter-owned TX/RX buffers
   with procedure On_Complete (Transferred : Natural;
                               Status : Machine.SPI.Transaction_Status) is null;
                                    --  completion hook; runs in ISR context
package Machine.Async.SPI
  with SPARK_Mode
is

   --  Initiation: never blocks; chained; rejected while Busy.
   procedure Start_Exchange (TX     : Byte_Array;
                             Status : in out Machine.SPI.Transaction_Status)
     with Post => (if Status'Old /= Machine.SPI.Ok
                   then Status = Status'Old);      --  §7.1 rule 1
   function  Busy return Boolean with Inline;
   procedure Read_Response (Into : out Byte_Array;
                            Last : out Natural);  --  copy out after completion

   --  The pump: bounded, never blocks; the APPLICATION attaches it.
   procedure On_Interrupt;

   --  Await: turns the async core into a blocking view -- and thereby
   --  into a Generic_SPI_Master conformance.
   generic
      with procedure Sleep_Until_Interrupt is null;  --  default: spin
   package Generic_Await
     with SPARK_Mode
   is
      procedure Exchange (TX         : Byte_Array;
                          RX         : out Byte_Array;
                          Timeout_Ms : Natural;
                          Status     : in out Machine.SPI.Transaction_Status)
        with Post => (if Status'Old /= Machine.SPI.Ok
                      then Status = Status'Old
                           and then (for all I in RX'Range => RX (I) = 0));
      package As_Blocking is new Machine.Blocking.Generic_SPI_Master
        (Exchange => Exchange);
   end Generic_Await;

end Machine.Async.SPI;
