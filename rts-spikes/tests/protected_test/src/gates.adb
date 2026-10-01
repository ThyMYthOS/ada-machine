package body Gates is

   protected body Gate is

      procedure Open is
      begin
         Stamp   := Clock;
         Is_Open := True;
      end Open;

      entry Wait when Is_Open is
      begin
         Is_Open := False;
      end Wait;

      function Opened_At return Time is (Stamp);

   end Gate;

   task body Opener is
   begin
      delay until Epoch + Milliseconds (150);
      Gate.Open;
      delay until Epoch + Milliseconds (350);
      Gate.Open;
   end Opener;

   protected body Alarm_Gate is

      procedure Fire (Event : in out Timing_Event) is
         pragma Unreferenced (Event);
      begin
         Stamp   := Clock;
         Fires   := Fires + 1;
         Is_Open := True;
      end Fire;

      entry Wait when Is_Open is
      begin
         Is_Open := False;
      end Wait;

      function Fired_At return Time is (Stamp);
      function Fire_Count return Natural is (Fires);

   end Alarm_Gate;

end Gates;
