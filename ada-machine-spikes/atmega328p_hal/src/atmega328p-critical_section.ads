--  atmega328p-critical_section.ads -- the concrete §14.4 critical
--  section for spike 2 (Appendix B): the I-bit in SREG, classic AVR's
--  only "disable everything" primitive (no priority-based masking to
--  fall back on, unlike Cortex-M's PRIMASK or a Ravenscar ceiling lock).
--  Enter saves the *whole* SREG byte, not just the I-bit, and disables;
--  Leave restores the saved byte verbatim -- so a nested Enter/Leave
--  pair is a correct no-op even when interrupts were already disabled
--  by an outer one (the same save/restore-not-set/clear shape as
--  avr-libc's ATOMIC_BLOCK/ATOMIC_RESTORESTATE).
with Interfaces;
package ATmega328P.Critical_Section
  with Preelaborate, SPARK_Mode,
       Abstract_State => (State with External => (Async_Readers, Async_Writers)),
       Initializes    => State  --  interrupts start disabled at reset,
                                --  same reasoning as ATmega328P.SPI's
                                --  own Busy/State default
is
   type Mask_State is private;

   --  Volatile_Function: Enter both reads and disables the real
   --  interrupt-enable state, so two textually-identical calls need not
   --  agree (SPARK RM 7.1.3(9)), same reasoning as every other
   --  hardware-reading function in this HAL. No Global here, unlike
   --  every other Volatile_Function in this HAL: a function's Global
   --  may only name Input items (Output/In_Out is a procedure-only
   --  mode) -- and Enter's real effect on State is exactly an output,
   --  which is precisely why §14.4 gives Leave, a procedure, the
   --  restoring half. State is therefore only named on Leave below;
   --  Enter's own Global stays unstated (an honest, unresolved gap for
   --  the later GNATprove pass this file's own header notes as
   --  optional, not this step's bar).
   --  Inline_Always on both (matches every other leaf primitive in this
   --  HAL, e.g. ATmega328P.Delays.Sleep_Idle): on the *native-host*
   --  stand-in build (this crate's own `alr build`, no AVR calls in
   --  sight) it lets the compiler drop the never-called body rather
   --  than assemble AVR-only mnemonics for the host's own backend; on
   --  the real AVR cross-build (spike2_avr, via avrada_rts) the actual
   --  call sites force genuine inlining against the real target.
   function  Enter return Mask_State
     with Inline_Always, Volatile_Function;
   procedure Leave (Prev : Mask_State)
     with Inline_Always, Global => (Output => State);

private
   type Mask_State is new Interfaces.Unsigned_8;  --  the raw SREG byte
end ATmega328P.Critical_Section;
