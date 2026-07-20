--  Root of the blocking execution model. Owned by the spec crate (it
--  hosts contracts); the implementation children (Machine.Blocking.I2C,
--  .Delays, ...) come from crate machine_blocking.
package Machine.Blocking
  with Pure, SPARK_Mode
is
   subtype Milliseconds is Natural;
end Machine.Blocking;
