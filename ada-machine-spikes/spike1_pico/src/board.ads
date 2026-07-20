--  board.ads -- spike 1's wiring (Appendix A): pure declarations; reads
--  like the schematic.
with Machine.Generic_Clock, Machine.I2C.Generic_Master, Machine.UART.Generic_Port;
with Machine.Regmap.Generic_I2C_Binding;
with RP2040.Clock, RP2040.I2C0, RP2040.UART0;
with Machine.Blocking.Delays, Machine.Blocking.I2C, Machine.Blocking.Log_Sink;
with Machine.Log;
with BME280;
package Board
  with SPARK_Mode
is

   package Clock_Sig is new Machine.Generic_Clock
     (Ticks            => RP2040.Clock.Ticks,
      Ticks_Per_Second => RP2040.Clock.Ticks_Per_Second,
      Now              => RP2040.Clock.Now);

   package I2C0_Sig is new Machine.I2C.Generic_Master   --  conformance check
     (Set_Target        => RP2040.I2C0.Set_Target,     --  of RP2040.I2C0,
      Can_Push          => RP2040.I2C0.Can_Push,       --  §6.1, for free
      Push_Write        => RP2040.I2C0.Push_Write,
      Push_Read_Request => RP2040.I2C0.Push_Read_Request,
      Can_Pop           => RP2040.I2C0.Can_Pop,
      Pop               => RP2040.I2C0.Pop);

   package UART0_Sig is new Machine.UART.Generic_Port  --  conformance check
     (Frame       => RP2040.UART0.Frame,                --  of RP2040.UART0
      Is_Tx_Ready => RP2040.UART0.Is_Tx_Ready,
      Put_Frame   => RP2040.UART0.Put_Frame,
      Is_Rx_Ready => RP2040.UART0.Is_Rx_Ready,
      Get_Frame   => RP2040.UART0.Get_Frame);

   package Delays is new Machine.Blocking.Delays (Clock => Clock_Sig);
   package I2C    is new Machine.Blocking.I2C (Port => I2C0_Sig, Clock => Clock_Sig);

   package Regs is new Machine.Regmap.Generic_I2C_Binding
     (Bus => I2C.As_Signature, Device_Address => 16#76#);

   --  The UART-backed log sink (§10.3/§14.2): a direct blocking drain
   --  over UART0, since these spikes have no runtime FIFO to reuse.
   package Sink is new Machine.Blocking.Log_Sink (UART => UART0_Sig);

   --  BME280's Log_Event formal predates the Level vocabulary (it takes
   --  only Event_Id + Arg), so board wiring assigns every driver-observed
   --  event (Wrong_Chip_Id/Bus_Fault/Timed_Out) the same severity here.
   procedure Log_Event (E : Machine.Log.Event_Id;
                        A : Machine.Log.Arg := Machine.Log.No_Arg);

   --  A per-measurement trace line, emitted directly by main.adb (not
   --  through the driver's Log_Event, which only reports faults): Info
   --  severity, Arg = Temperature in hundredths of a degree Celsius.
   Ev_Measured : constant Machine.Log.Event_Id := 16#1000#;

   package Env_Sensor is new BME280
     (Regs      => Regs.As_Device,
      Wait      => Delays.As_Signature,
      Log_Event => Log_Event);

   --  Native configuration stays native (D8): main calls
   --    RP2040.I2C0.Enable ((Baud_Hz => 400_000, SDA_Pin => 4, SCL_Pin => 5));
   --    RP2040.UART0.Enable ((Baud_Hz => 115_200, TX_Pin => 0, RX_Pin => 1));
   --  before first use of Env_Sensor / Sink.
end Board;
