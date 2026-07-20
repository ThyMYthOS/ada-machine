--  Blocking UART writes over the never-blocking L2 data phase (§8.1),
--  mirroring Machine.Blocking.I2C/.SPI.
with Machine.UART.Generic_Port, Machine.Generic_Clock,
     Machine.Blocking.Generic_UART;
use type Machine.UART.Transaction_Status;  --  for the Post contracts' "="/"/="
generic
   with package Port  is new Machine.UART.Generic_Port (<>);
                                    --  the never-blocking L2 data phase
   with package Clock is new Machine.Generic_Clock (<>);
                                    --  time base for the timeout
package Machine.Blocking.UART
  with SPARK_Mode
is
   procedure Put (Data       : Byte_Array;
                  Timeout_Ms : Natural;
                  Status     : in out Machine.UART.Transaction_Status)
     with Post => (if Status'Old /= Machine.UART.Ok
                   then Status = Status'Old);      --  §7.1 rule 1

   package As_Signature is new Machine.Blocking.Generic_UART (Put => Put);
end Machine.Blocking.UART;
