--  board.ads -- spike 3's wiring, same shape as Appendix B.3/C.3: pure
--  declarations reading like the schematic. The novel piece relative to
--  spike 1 (blocking I2C) and spike 2 (interrupt-driven SPI) is the data
--  path: Env_Sensor's SPI transfers ride real GDMA block transfers
--  (ESP32C3.SPI2's Start_Transfer/Cancel_Transfer/Read_Response) awaited
--  through a protected entry (Machine.Tasking.Generic_DMA_SPI), under a
--  tasking runtime rather than a busy-wait or byte-pumped ISR.
with Machine.Generic_Digital_Out;
with Machine.Regmap.Generic_SPI_Binding;
with Machine.Tasking.Delays, Machine.Tasking.Generic_DMA_SPI, BME280;
with ESP32C3.SPI2, ESP32C3.GPIO;

package Board
  with SPARK_Mode
is

   --  CS on GPIO10 (ESP32-C3's default IOMUX FSPICS0 pin) -- an ordinary
   --  GPIO owned by the binding, never part of the SPI class (§6.1).
   procedure CS_Set (High : Boolean);
   package CS is new Machine.Generic_Digital_Out (Set => CS_Set);

   package DMA_SPI is new Machine.Tasking.Generic_DMA_SPI
     (Start_Transfer  => ESP32C3.SPI2.Start_Transfer,
      Cancel_Transfer => ESP32C3.SPI2.Cancel_Transfer,
      Read_Response   => ESP32C3.SPI2.Read_Response);

   package Regs is new Machine.Regmap.Generic_SPI_Binding
     (Bus => DMA_SPI.As_Blocking, CS => CS);

   package Env_Sensor is new BME280
     (Regs => Regs.As_Device,
      Wait => Machine.Tasking.Delays.As_Signature);

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
   --  before first use of Env_Sensor.
end Board;
