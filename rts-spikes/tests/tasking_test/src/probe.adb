package body Probe is

   protected body Log is

      procedure Note (Who : Character; Scheduled : Time) is
         Now : constant Time := Clock;
      begin
         if Now < Scheduled then
            Early := True;
         elsif Now - Scheduled > Late then
            Late := Now - Scheduled;
         end if;
         if N < Max_Events then
            N := N + 1;
            Items (N) := Who;
         end if;
      end Note;

      function Count return Natural is (N);
      function Text return Event_Text is (Items);
      function Ever_Early return Boolean is (Early);
      function Max_Late return Time_Span is (Late);

   end Log;

   task body A is
      T : Time := Epoch;
   begin
      for I in 1 .. 3 loop
         T := T + Milliseconds (200);
         delay until T - Milliseconds (100);   --  Epoch + 100, 300, 500
         Log.Note ('A', T - Milliseconds (100));
      end loop;
   end A;

   task body B is
      T : Time := Epoch;
   begin
      for I in 1 .. 3 loop
         T := T + Milliseconds (200);
         delay until T;                          --  Epoch + 200, 400, 600
         Log.Note ('B', T);
      end loop;
   end B;

   task body Hi is
      T : constant Time := Epoch + Milliseconds (700);
   begin
      delay until T;
      Log.Note ('H', T);
   end Hi;

   task body Lo is
      T : constant Time := Epoch + Milliseconds (700);
   begin
      delay until T;
      Log.Note ('L', T);
   end Lo;

end Probe;
