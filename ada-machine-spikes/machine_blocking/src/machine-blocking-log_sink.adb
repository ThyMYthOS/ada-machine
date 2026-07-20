package body Machine.Blocking.Log_Sink
  with SPARK_Mode
is

   use Machine.Log;

   procedure Send (D : Byte) is
      Tx_Ready_Now : Boolean;
   begin
      loop
         --  UART.Is_Tx_Ready read alone into a local first (SPARK RM
         --  7.1.3(9)): it is a volatile function.
         Tx_Ready_Now := UART.Is_Tx_Ready;
         exit when Tx_Ready_Now;
      end loop;
      UART.Put_Frame (UART.Frame (D));
   end Send;

   procedure Emit (Level : Machine.Log.Level;
                   E     : Machine.Log.Event_Id;
                   A     : Machine.Log.Arg := Machine.Log.No_Arg) is
   begin
      Send (Byte (Machine.Log.Level'Pos (Level)));
      Send (Byte (E / 256));
      Send (Byte (E mod 256));
      Send (Byte (A / 2**24));
      Send (Byte ((A / 2**16) mod 256));
      Send (Byte ((A / 2**8) mod 256));
      Send (Byte (A mod 256));
   end Emit;

end Machine.Blocking.Log_Sink;
