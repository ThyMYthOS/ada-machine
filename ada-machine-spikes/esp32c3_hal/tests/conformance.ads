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
with Machine.Generic_Digital_Out;
with ESP32C3.SPI2, ESP32C3.GPIO;

package Conformance
  with SPARK_Mode
is

   package SPI2_Check is new Machine.SPI.Generic_Master
     (Can_Push => ESP32C3.SPI2.Can_Push,
      Push     => ESP32C3.SPI2.Push,
      Can_Pop  => ESP32C3.SPI2.Can_Pop,
      Pop      => ESP32C3.SPI2.Pop);

   --  Machine.Generic_Digital_Out needs one formal procedure bound to a
   --  fixed pin (§6.4): a real conformance unit wraps ESP32C3.GPIO the
   --  same way board wiring does (spike3_esp's CS_Set pattern).
   procedure GPIO10_Set (High : Boolean);

   package CS_Check is new Machine.Generic_Digital_Out (Set => GPIO10_Set);

end Conformance;
