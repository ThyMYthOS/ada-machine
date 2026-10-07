--  RISC-V (ESP32-C3): clear mstatus.MIE, then `wfi` forever. Not linked
--  into anything yet (spike3_esp is a host stand-in until its runtime
--  exists, TODO.md #15) -- it replaces halt_host in spike3_esp.gpr then.
with System.Machine_Code; use System.Machine_Code;

package body Spike_Halt
  with SPARK_Mode => Off
is
   procedure Halt is
   begin
      Asm ("csrci mstatus, 8", Volatile => True);   --  MIE is bit 3
      loop
         Asm ("wfi", Volatile => True);
      end loop;
   end Halt;
end Spike_Halt;
