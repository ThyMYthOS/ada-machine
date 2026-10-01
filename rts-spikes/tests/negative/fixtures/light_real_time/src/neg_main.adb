--  MUST NOT COMPILE on the `light` profile: `delay until` and Ada.Real_Time,
--  the other half of what tasking_mpfs uses.
--  (tests/negative/cases.list: light_real_time.) Never built by `make build`.
with Ada.Real_Time; use Ada.Real_Time;

procedure Neg_Main is
begin
   delay until Clock + Seconds (1);
end Neg_Main;
