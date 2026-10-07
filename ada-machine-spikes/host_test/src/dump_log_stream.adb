--  dump_log_stream -- produces REAL encoded UART bytes for the host-side
--  decoder's self-test (tools/decode_log.py, tools/test_decode_log.py):
--  Machine.Blocking.Log_Sink instantiated over Mock_Uart, plus the shared
--  test-mode runner (test_support/common/spike_test_runner) judging the
--  BME280 driver over the mock register files, so the bytes are exactly
--  what a board's test-mode build puts on its UART.
--
--    dump_log_stream <pass-file> <fail-file>
--
--  pass-file : driver Wrong_Chip_Id-style event, a negative-temperature
--              event, then 3 good cycles + "ADA-MACHINE-TEST: PASS".
--  fail-file : bad-chip-id sensor -> Wrong_Chip_Id event + "FAIL INIT-
--              WRONG_CHIP_ID".
with Ada.Command_Line;
with Ada.Streams.Stream_IO;
with Machine.Log;
with Machine.Regmap.Generic_Device;
with Machine.Blocking.Generic_Delays;
with Machine.Blocking.Log_Sink;
with Machine.UART.Generic_Port;
with Mock_Regmap, Mock_Regmap_Bad_Id, Mock_Delays, Mock_Uart;
with BME280;
with Spike_Halt;
with Spike_Test_Runner;

procedure Dump_Log_Stream is

   package Port is new Machine.UART.Generic_Port
     (Frame       => Mock_Uart.Frame,
      Is_Tx_Ready => Mock_Uart.Is_Tx_Ready,
      Put_Frame   => Mock_Uart.Put_Frame,
      Is_Rx_Ready => Mock_Uart.Is_Rx_Ready,
      Get_Frame   => Mock_Uart.Get_Frame);

   package Sink is new Machine.Blocking.Log_Sink (UART => Port);

   --  Same wiring as the boards' Log_Event / Ev_Measured (board.ads).
   Ev_Measured : constant Machine.Log.Event_Id := 16#1000#;

   procedure Log_Event (E : Machine.Log.Event_Id;
                        A : Machine.Log.Arg := Machine.Log.No_Arg) is
   begin
      Sink.Emit (Machine.Log.Warning, E, A);
   end Log_Event;

   procedure On_Measured (Temperature_Centi : Machine.Log.Arg) is
   begin
      Sink.Emit (Machine.Log.Info, Ev_Measured, Temperature_Centi);
   end On_Measured;

   package Wait is new Machine.Blocking.Generic_Delays
     (Delay_Us => Mock_Delays.Delay_Us,
      Delay_Ms => Mock_Delays.Delay_Ms);

   package Good_Regs is new Machine.Regmap.Generic_Device
     (Write_Reg => Mock_Regmap.Write_Reg,
      Read_Regs => Mock_Regmap.Read_Regs);
   package Good_Sensor is new BME280
     (Regs => Good_Regs, Wait => Wait, Log_Event => Log_Event);

   package Bad_Regs is new Machine.Regmap.Generic_Device
     (Write_Reg => Mock_Regmap_Bad_Id.Write_Reg,
      Read_Regs => Mock_Regmap_Bad_Id.Read_Regs);
   package Bad_Sensor is new BME280
     (Regs => Bad_Regs, Wait => Wait, Log_Event => Log_Event);

   package Good_Run is new Spike_Test_Runner
     (Sensor => Good_Sensor, UART => Port, Delay_Ms => Mock_Delays.Delay_Ms,
      Halt => Spike_Halt.Halt, On_Measured => On_Measured);
   package Bad_Run is new Spike_Test_Runner
     (Sensor => Bad_Sensor, UART => Port, Delay_Ms => Mock_Delays.Delay_Ms,
      Halt => Spike_Halt.Halt, On_Measured => On_Measured);

   procedure Write_File (Name : String) is
      use Ada.Streams.Stream_IO;
      F : File_Type;
   begin
      Create (F, Out_File, Name);
      for I in 1 .. Mock_Uart.Count loop
         Write (F, (1 => Ada.Streams.Stream_Element
                          (Mock_Uart.Buffer (I))));
      end loop;
      Close (F);
   end Write_File;

begin
   if Ada.Command_Line.Argument_Count /= 2 then
      raise Program_Error with "usage: dump_log_stream <pass> <fail>";
   end if;

   --  PASS stream: one hand-emitted event of each shape first, so the
   --  decoder's table is exercised with real Log_Sink bytes (an unknown
   --  id, an Error-level record, a negative temperature as the runner
   --  sends it: two's complement in 32 bits).
   Mock_Uart.Reset;
   Sink.Emit (Machine.Log.Error, 16#7FFF#, 16#DEADBEEF#);
   On_Measured (Machine.Log.Arg'Mod (-523));
   Good_Run.Run;
   Write_File (Ada.Command_Line.Argument (1));

   Mock_Uart.Reset;
   Bad_Run.Run;
   Write_File (Ada.Command_Line.Argument (2));
end Dump_Log_Stream;
