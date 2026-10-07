--  Spike_Halt -- "stop here for good" after a test-mode verdict. The spec
--  is shared; the body is picked per target by the project file
--  (test_support/halt_host, halt_cortex_m, halt_avr, halt_riscv).
package Spike_Halt
  with SPARK_Mode
is
   --  Disable interrupts and park the core in a low-power wait; never
   --  returns. Global => null: nothing runs afterwards, so no effect on
   --  the rest of the program is observable.
   procedure Halt
     with No_Return, Global => null;
end Spike_Halt;
