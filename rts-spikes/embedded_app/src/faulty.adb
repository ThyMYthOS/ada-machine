with Ada.Real_Time; use Ada.Real_Time;

package body Faulty is

   procedure Boom is
   begin
      raise Constraint_Error with "propagated across a frame";
   end Boom;

   task body Ticker is
      Next : Time := Clock;
   begin
      loop
         Next := Next + Milliseconds (100);
         delay until Next;
      end loop;
   end Ticker;

end Faulty;
