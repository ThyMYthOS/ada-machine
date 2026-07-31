with Ada.Real_Time; use Ada.Real_Time;
with Workers;

procedure Tasking_MPFS is
begin
   loop
      delay until Clock + Seconds (1);
      exit when Workers.Counter.Value = Natural'Last;
   end loop;
end Tasking_MPFS;
