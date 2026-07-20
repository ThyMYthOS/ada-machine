--  Root of the tasking-profile execution model (L3c, §8.3): protected
--  objects wrapping the event plumbing -- interrupt handlers as protected
--  procedures, entries/suspension objects for completion, "delay until"
--  for real deadlines. Requires a light-tasking/embedded runtime (§10);
--  deliberately thin, since applications with tasking may equally use
--  machine_async + suspension objects directly. Owned by this spec crate
--  as the contract host; the implementation children (.Delays,
--  .Generic_SPI, .Generic_DMA_SPI) come from crate machine_tasking.
pragma SPARK_Mode;
package Machine.Tasking
  with Pure
is
end Machine.Tasking;
