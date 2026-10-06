--  Non-shipped conformance unit (§6.1): instantiates every relevant
--  Machine signature against ESP32C3's own packages. If this compiles,
--  the crate conforms -- CI-only, not part of the library sources.
--
--  No Clock_Check here: unlike RP2040/ATmega328P this spike doesn't
--  build a native timer PAC unit -- machine_tasking's own adapters
--  (Delays, Generic_SPI, Generic_DMA_SPI) use Ada.Real_Time.Clock
--  directly rather than a Machine.Generic_Clock instance (see
--  machine_tasking's own handoff notes), so there is nothing here that
--  needs one.
with Machine.SPI.Generic_Master;
with Machine.UART.Generic_Port;
with Machine.RNG.Generic_Source;
with Interfaces;
with Machine.GPIO.Generic_Digital_Out, Machine.GPIO.Generic_Digital_In;
with ESP32C3.SPI2, ESP32C3.GPIO, ESP32C3.UART0, ESP32C3.RNG;

package Conformance
  with SPARK_Mode
is

   package SPI2_Check is new Machine.SPI.Generic_Master
     (Can_Push => ESP32C3.SPI2.Can_Push,
      Push     => ESP32C3.SPI2.Push,
      Can_Pop  => ESP32C3.SPI2.Can_Pop,
      Pop      => ESP32C3.SPI2.Pop);

   --  Only the polled SPI data phase is conformance-checked here. The
   --  block-DMA path (ESP32C3.SPI2.Start_Transfer/Cancel_Transfer/
   --  Read_Response) conforms to Machine.Tasking.Generic_DMA_SPI -- an
   --  L3c *adapter* contract. Instantiating it here would force this L2
   --  HAL to depend on machine_tasking (L3), inverting the layering, so
   --  that conformance is checked at board level instead, where both are
   --  visible: spike3_esp/src/board.ads instantiates Generic_DMA_SPI with
   --  exactly these three ESP32C3.SPI2 procedures (TODO #6: block-transfer
   --  conformance is intentionally board-level, not a hole).

   package UART0_Check is new Machine.UART.Generic_Port
     (Frame       => ESP32C3.UART0.Frame,
      Is_Tx_Ready => ESP32C3.UART0.Is_Tx_Ready,
      Put_Frame   => ESP32C3.UART0.Put_Frame,
      Is_Rx_Ready => ESP32C3.UART0.Is_Rx_Ready,
      Get_Frame   => ESP32C3.UART0.Get_Frame);

   --  The second RNG data point (TODO.md #11): a bare data register with no
   --  ready or health interface, checked against the same signature as
   --  STM32G474's flag-rich RNG.
   package RNG_Check is new Machine.RNG.Generic_Source
     (Word     => Interfaces.Unsigned_32,
      Is_Ready => ESP32C3.RNG.Is_Ready,
      Get_Word => ESP32C3.RNG.Get_Word);

   --  Machine.GPIO.Generic_Digital_Out needs one formal procedure bound to
   --  a fixed pin (§6.4): a real conformance unit wraps ESP32C3.GPIO the
   --  same way board wiring does (spike3_esp's CS_Set pattern).
   procedure GPIO10_Set (To : Machine.GPIO.Level);

   package CS_Check is new Machine.GPIO.Generic_Digital_Out
     (Set => GPIO10_Set);

   --  Machine.GPIO.Generic_Digital_In needs one formal function bound to
   --  a fixed pin, checked against ESP32C3.GPIO.Is_High -- the gap
   --  TODO.md P0 #3 closes: Is_High conformed to nothing before this.
   function GPIO11_Get return Machine.GPIO.Level
     with Volatile_Function;

   package CS_In_Check is new Machine.GPIO.Generic_Digital_In
     (Get => GPIO11_Get);

end Conformance;
