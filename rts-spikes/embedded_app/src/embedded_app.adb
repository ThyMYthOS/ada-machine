--  What the embedded profile is for: real exception propagation.
with Ada.Exceptions;
with Ada.Real_Time; use Ada.Real_Time;
with Faulty;

procedure Embedded_App is
   Len : Natural := 0;
begin
   begin
      Faulty.Boom;
   exception
      when E : others =>
         Len := Ada.Exceptions.Exception_Message (E)'Length;
   end;

   loop
      delay until Clock + Seconds (1);
      exit when Len = Natural'Last;
   end loop;
end Embedded_App;
