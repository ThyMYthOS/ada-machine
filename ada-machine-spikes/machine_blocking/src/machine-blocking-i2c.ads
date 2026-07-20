--  Blocking I2C master transactions over the never-blocking L2 data phase.
with Machine.I2C.Generic_Master, Machine.Generic_Clock,
     Machine.Blocking.Generic_I2C_Master;
use type Machine.I2C.Transaction_Status;  --  for the Post contracts' "="/"/="
generic
   with package Port  is new Machine.I2C.Generic_Master (<>);
                                    --  the never-blocking L2 data phase
   with package Clock is new Machine.Generic_Clock (<>);
                                    --  time base for the timeouts
package Machine.Blocking.I2C
  with SPARK_Mode
is
   procedure Write (Address    : Machine.I2C.Address_7_Bit;
                    Data       : Byte_Array;
                    Timeout_Ms : Natural;
                    Status     : in out Machine.I2C.Transaction_Status)
     with Post => (if Status'Old /= Machine.I2C.Ok
                   then Status = Status'Old);      --  §7.1 rule 1

   procedure Write_Read (Address    : Machine.I2C.Address_7_Bit;
                         Command    : Byte_Array;
                         Response   : out Byte_Array;
                         Timeout_Ms : Natural;
                         Status     : in out Machine.I2C.Transaction_Status)
     with Post => (if Status'Old /= Machine.I2C.Ok
                   then Status = Status'Old
                        and then (for all I in Response'Range => Response (I) = 0));

   package As_Signature is new Machine.Blocking.Generic_I2C_Master
     (Write => Write, Write_Read => Write_Read);
end Machine.Blocking.I2C;
