with Machine.Log;
with Spike_Halt;
with Spike_Test_Runner;
with Board;

package body Test_Run
  with SPARK_Mode
is
   --  The same Info event main.adb's normal loop emits per measurement.
   procedure On_Measured (Temperature_Centi : Machine.Log.Arg) is
   begin
      if Machine.Log.Enabled (Machine.Log.Info) then
         Board.Sink.Emit
           (Machine.Log.Info, Board.Ev_Measured, Temperature_Centi);
      end if;
   end On_Measured;

   package Runner is new Spike_Test_Runner
     (Sensor      => Board.Env_Sensor,
      UART        => Board.UART0_Sig,
      Delay_Ms    => Board.Delays.Delay_Ms,
      Halt        => Spike_Halt.Halt,
      On_Measured => On_Measured);

   procedure Run_And_Halt is
   begin
      Runner.Run_And_Halt;
   end Run_And_Halt;

end Test_Run;
