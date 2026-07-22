--  §14.4: a few instructions of atomicity for an adapter/driver against
--  its own ISR pump (machine_async's completion state). The portable
--  mechanism differs per target -- PRIMASK masking on Cortex-M, the
--  I-bit in SREG on AVR, a protected object under Ravenscar -- so, like
--  everything else, it is a signature: Enter disables and returns the
--  previous state; Leave restores it. Mask_State (not a bare Boolean)
--  so a nested Enter/Leave pair is always safe to compose, even where
--  the target's own disable primitive isn't itself reentrant. No
--  default: every instantiation must say what "disable" means on its
--  target, even if the honest answer is a documented no-op.
generic
   type Mask_State is private;               --  saved interrupt/mask state
   with function  Enter return Mask_State;   --  disable, return previous state
   with procedure Leave (Prev : Mask_State); --  restore (supports nesting)
package Machine.Generic_Critical_Section
  with Pure, SPARK_Mode
is end Machine.Generic_Critical_Section;
