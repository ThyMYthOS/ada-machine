--  board.ads -- spike 3's wiring (Appendix C), same shape as spikes 1 & 2
--  (Appendices A & B): pure
--  declarations reading like the schematic. The novel piece relative to
--  spike 1 (blocking I2C) and spike 2 (interrupt-driven SPI) is the data
--  path: Env_Sensor's SPI transfers ride real GDMA block transfers
--  (ESP32C3.SPI2's Start_Transfer/Cancel_Transfer/Read_Response) awaited
--  through a protected entry (Machine.Tasking.Generic_DMA_SPI), under a
--  tasking runtime rather than a busy-wait or byte-pumped ISR.
with Machine.GPIO.Generic_Digital_Out;
with Machine.Regmap.Generic_SPI_Binding;
with Machine.Tasking.Delays, Machine.Tasking.Generic_DMA_SPI, BME280;
with Machine.UART.Generic_Port, Machine.Blocking.Log_Sink, Machine.Log;
with ESP32C3.SPI2, ESP32C3.GPIO, ESP32C3.UART0;

package Board
  with SPARK_Mode
is

   --  CS on GPIO10 (ESP32-C3's default IOMUX FSPICS0 pin) -- an ordinary
   --  GPIO owned by the binding, never part of the SPI class (§6.1).
   procedure CS_Set (To : Machine.GPIO.Level);
   package CS is new Machine.GPIO.Generic_Digital_Out (Set => CS_Set);

   package DMA_SPI is new Machine.Tasking.Generic_DMA_SPI
     (Start_Transfer  => ESP32C3.SPI2.Start_Transfer,
      Cancel_Transfer => ESP32C3.SPI2.Cancel_Transfer,
      Read_Response   => ESP32C3.SPI2.Read_Response);

   package Regs is new Machine.Regmap.Generic_SPI_Binding
     (Bus => DMA_SPI.As_Blocking, CS => CS);

   package UART0_Sig is new Machine.UART.Generic_Port  --  conformance check
     (Frame       => ESP32C3.UART0.Frame,               --  of ESP32C3.UART0
      Is_Tx_Ready => ESP32C3.UART0.Is_Tx_Ready,
      Put_Frame   => ESP32C3.UART0.Put_Frame,
      Is_Rx_Ready => ESP32C3.UART0.Is_Rx_Ready,
      Get_Frame   => ESP32C3.UART0.Get_Frame);

   --  The UART-backed log sink (§10.3/§14.2): a direct blocking drain
   --  over UART0, same choice as spike1_pico/spike2_avr (no runtime
   --  FIFO here either).
   package Sink is new Machine.Blocking.Log_Sink (UART => UART0_Sig);

   --  BME280's Log_Event formal predates the Level vocabulary (it takes
   --  only Event_Id + Arg), so board wiring assigns every driver-observed
   --  event (Wrong_Chip_Id/Bus_Fault/Timed_Out) the same severity here,
   --  same as spike1_pico/spike2_avr's board wiring.
   procedure Log_Event (E : Machine.Log.Event_Id;
                        A : Machine.Log.Arg := Machine.Log.No_Arg);

   --  A per-measurement trace line, emitted directly by main.adb (not
   --  through the driver's Log_Event, which only reports faults): Info
   --  severity, Arg = Temperature in hundredths of a degree Celsius.
   Ev_Measured : constant Machine.Log.Event_Id := 16#1000#;

   package Env_Sensor is new BME280
     (Regs      => Regs.As_Device,
      Wait      => Machine.Tasking.Delays.As_Signature,
      Log_Event => Log_Event);

   --  DMA-done interrupt: the application attaches it (D5) and bridges
   --  ESP32C3.SPI2's L2-native acknowledgement to DMA_SPI's completion
   --  signal -- the tasking-runtime, block-transfer counterpart of
   --  avr_board.ads's SPI_Interrupt (which bridges ATmega328P.SPI's ISR
   --  to Machine.Async.SPI.On_Interrupt the same way).
   --
   --  Left unattached here (no pragma Attach_Handler): doing so for real
   --  needs an Ada.Interrupts.Interrupt_ID for ESP32-C3's SPI2 DMA-done
   --  source, which in turn needs the interrupt matrix programmed
   --  (ETS_SPI2_INTR_SOURCE / ETS_DMA_CH0_INTR_SOURCE routed onto a CPU
   --  interrupt line, per esp32c3_hal's own research notes) by a
   --  light-tasking runtime for ESP32-C3 that does not exist anywhere in
   --  this repo or its dependencies (§10's runtime-compatibility gate --
   --  see esp32c3_hal/alire.toml). This protected object is the
   --  documentation/wiring artifact for where that attachment goes, same
   --  spirit as spike1_pico/spike2_avr never performing an actual cross
   --  build.
   protected DMA_Handler is
      procedure On_Interrupt;
   end DMA_Handler;

   --  Native configuration stays native (D8): main calls
   --    ESP32C3.SPI2.Enable ((Divisor => 4, Mode => 0));
   --    ESP32C3.UART0.Enable ((Baud_Hz => 115_200));
   --  before first use of Env_Sensor / Sink.
end Board;
