package body Recording_Log_Sink
  with SPARK_Mode,
       Refined_State => (State => (Events, Args, Cnt))
is

   subtype Event_Index is Positive range 1 .. Max_Events;

   Events : array (Event_Index) of Machine.Log.Event_Id := (others => 0);
   Args   : array (Event_Index) of Machine.Log.Arg := (others => 0);

   subtype Count_Range is Natural range 0 .. Max_Events;
   Cnt : Count_Range := 0;

   procedure Log_Event (E : Machine.Log.Event_Id;
                        A : Machine.Log.Arg := Machine.Log.No_Arg) is
   begin
      if Cnt < Max_Events then
         Cnt := Cnt + 1;
         Events (Cnt) := E;
         Args (Cnt)   := A;
      end if;
   end Log_Event;

   function Count return Natural is (Cnt);

   function Event (I : Positive) return Machine.Log.Event_Id is (Events (I));

   function Arg_At (I : Positive) return Machine.Log.Arg is (Args (I));

end Recording_Log_Sink;
