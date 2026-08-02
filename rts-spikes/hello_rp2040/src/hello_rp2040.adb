--  Hello world for the Raspberry Pi RP2040, light-tasking profile.
with Ada.Text_IO;

procedure Hello_RP2040 is
begin
   Ada.Text_IO.Put_Line ("Hello from RP2040 (Cortex-M0+, light_tasking_pico)");

   --  A bare-metal image must not return from its main subprogram.
   loop
      null;
   end loop;
end Hello_RP2040;
