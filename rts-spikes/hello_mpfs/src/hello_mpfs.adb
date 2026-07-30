--  Hello world for the PolarFire SoC, light profile, resident in L2 LIM.
with Ada.Text_IO;
with Fast_Path;

procedure Hello_MPFS is
begin
   Ada.Text_IO.Put_Line ("Hello from PolarFire SoC (U54 hart 1, LIM)");
   Fast_Path.Tick;

   --  A bare-metal image must not return from its main subprogram.
   loop
      null;
   end loop;
end Hello_MPFS;
