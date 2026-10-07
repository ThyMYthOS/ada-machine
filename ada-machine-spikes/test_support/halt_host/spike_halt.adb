--  Host stand-in body: the host crates are never run (host_test is the
--  one program that runs), so a plain endless loop suffices. No inline
--  assembly, so it builds on any native host.
package body Spike_Halt
  with SPARK_Mode => Off
is
   procedure Halt is
   begin
      loop
         null;
      end loop;
   end Halt;
end Spike_Halt;
