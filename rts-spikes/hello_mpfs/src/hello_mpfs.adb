--  Hello world for the PolarFire SoC, light profile, resident in L2 LIM.
--  Ada.Text_IO on this runtime reaches System.Text_IO, whose body is the
--  MMUART selected by light_mpfs's Console configuration variable.
with Ada.Text_IO;

procedure Hello_MPFS is
begin
   Ada.Text_IO.Put_Line ("Hello from PolarFire SoC (U54 hart 1, LIM)");

   --  A bare-metal image must not return from its main subprogram.
   loop
      null;
   end loop;
end Hello_MPFS;
