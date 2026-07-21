--  Time_RNG_Target -- spike 4's device-side responder (Appendix D): the
--  inverse of Machine.Regmap.Generic_Device. Regmap is "master reads a
--  remote device's registers"; this crate makes the local MCU *be* that
--  device -- a tiny fixed register file an external I2C master reads to
--  fetch the current epoch and a fresh random word. Spike-local by
--  design (§6.3 "standardize proven classes only"): hand-rolled over the
--  two new signatures rather than proposed as a
--  Machine.I2C.Generic_Target_Regfile generic -- one data point isn't
--  enough to freeze a shape, the same bar Generic_Master itself was
--  held to until AVR TWI (a second, structurally different controller)
--  closed TODO.md P0 #1.
--
--  Register map (big-endian on the wire -- most-significant byte at the
--  lowest address; a documented choice, not derived from any external
--  requirement):
--    0x00          status/version byte (Version below)
--    0x01 .. 0x04  current epoch, seconds, 4 bytes
--    0x05 .. 0x08  one fresh random word, 4 bytes
--  A well-formed 4-byte write starting at 0x01 sets the epoch (the
--  "settable epoch" design: the master writes a Unix timestamp once;
--  this responder free-runs from Clock.Now offset by it afterward,
--  §6.5). Before any write, reads report boot-relative seconds
--  (Epoch_Base = 0) -- the documented pre-set state, not a fault.
--  Writes to any other register, or of any other length, are accepted
--  on the bus (never NACKed) but discarded when the transaction ends --
--  no crash, no defined behavior claimed beyond "ignored".
--
--  Both the epoch and the RNG word are *latched* the moment a
--  read-direction transaction is acknowledged, and served from that
--  latch until the transaction ends -- otherwise a multi-byte burst
--  read could straddle a rollover or hand out two different random
--  words mid-transfer. Same reason RTC chips latch their register
--  snapshot on first read (§7.1-adjacent: consistency of a multi-byte
--  transfer, not chained status, is the property being protected here).
with Machine.I2C.Generic_Target, Machine.RNG.Generic_Source, Machine.Generic_Clock;
generic
   with package Bus   is new Machine.I2C.Generic_Target (<>);
   with package Rng   is new Machine.RNG.Generic_Source (<>);
   with package Clock is new Machine.Generic_Clock (<>);
package Time_RNG_Target
  with SPARK_Mode
is
   Version : constant Machine.Byte := 1;

   type Epoch_Seconds is mod 2 ** 32;

   procedure Poll;
   --  Service one pending bus event, if any, else return immediately
   --  (§5's L2 "never blocks" discipline, extended to this responder).
   --  Call from the main loop as fast as the target's clock-stretch
   --  budget requires -- a native, board-specific concern (D8).
   --
   --  No Status parameter (§7.1 rule 4, infallible-operations-are-
   --  procedures-without-status, stretched to a new case): a target
   --  responder has no caller-actionable failure. A master transaction
   --  has a "next step" the chained convention lets it skip after an
   --  error; this loop has no next step to skip, only "the next bus
   --  event", which the hardware presents fresh regardless of what
   --  happened on the previous one.

   function Current_Epoch_Seconds return Epoch_Seconds
     with Volatile_Function;
   --  Volatile_Function: reads Clock.Now transitively (via
   --  Elapsed_Seconds), so two textually-identical calls need not agree
   --  (SPARK RM 7.1.3(9)) -- same reasoning as any L2 clock read.
   --
   --  For status/logging/tests; not required for the responder itself
   --  to function -- main.adb can use it for a diagnostic blink pattern.

end Time_RNG_Target;
