package body Board
  with SPARK_Mode
is

   procedure Log_Event (E : Machine.Log.Event_Id;
                        A : Machine.Log.Arg := Machine.Log.No_Arg) is
   begin
      if Machine.Log.Enabled (Machine.Log.Warning) then
         Sink.Emit (Machine.Log.Warning, E, A);
      end if;
   end Log_Event;

end Board;
