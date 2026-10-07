--  Cortex-M (RP2040, STM32G4): mask interrupts, then `wfi` forever. No
--  `bkpt`: without a debugger attached it escalates to a HardFault.
--  Inline assembly is outside the SPARK subset, hence SPARK_Mode Off on
--  the body (the spec stays SPARK-visible).
with System.Machine_Code; use System.Machine_Code;

package body Spike_Halt
  with SPARK_Mode => Off
is
   procedure Halt is
   begin
      Asm ("cpsid i", Volatile => True);
      loop
         Asm ("wfi", Volatile => True);
      end loop;
   end Halt;
end Spike_Halt;
