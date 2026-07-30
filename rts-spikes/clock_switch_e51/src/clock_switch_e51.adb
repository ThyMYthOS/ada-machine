--  E51 monitor image: reconfigure memory/clocking from code that is not
--  resident in the memory being reconfigured.
with Ada.Text_IO;
with MSS_Clock;

procedure Clock_Switch_E51 is
begin
   Ada.Text_IO.Put_Line ("E51 monitor: staging switch code into DTIM");
   MSS_Clock.Prepare;

   if MSS_Clock.Prepared then
      Ada.Text_IO.Put_Line ("E51 monitor: switching");
      MSS_Clock.Switch;
      Ada.Text_IO.Put_Line ("E51 monitor: switch complete");
   end if;

   loop
      null;
   end loop;
end Clock_Switch_E51;
