with Ada.Real_Time; use Ada.Real_Time;

package body Workers is

   protected body Counter is
      procedure Bump is
      begin
         N := N + 1;
      end Bump;

      function Value return Natural is
      begin
         return N;
      end Value;
   end Counter;

   task body Ticker is
      Next : Time := Clock;
   begin
      loop
         Next := Next + Milliseconds (100);
         delay until Next;
         Counter.Bump;
      end loop;
   end Ticker;

end Workers;
