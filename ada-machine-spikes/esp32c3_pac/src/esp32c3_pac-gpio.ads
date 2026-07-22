--  ESP32-C3 GPIO matrix, base 0x6000_4000 (DR_REG_GPIO_BASE). Unlike
--  RP2040's SIO (one register per operation kind already split by the
--  hardware) this block mixes level and output-enable in the same
--  W1TS/W1TC idiom RP2040 uses for level alone -- curated to exactly the
--  four registers a Machine.GPIO.Generic_Digital_Out CS pin needs:
--  enable it as an output once, then flip its level. GPIO_IN is exposed
--  too (not needed for CS, but any future MISO-as-plain-input use would
--  want it).
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package ESP32C3_PAC.GPIO
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#6000_4000#);

   --  GPIO_ENABLE (0x20) / _W1TS (0x24) / _W1TC (0x28) -- bit n = pin n's
   --  output-enable. Written once at Configure time.
   GPIO_ENABLE : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#20#;
   GPIO_ENABLE_W1TS : Unsigned_32
     with Volatile, Async_Readers, Effective_Writes => True,
          Address => Base + 16#24#;
   GPIO_ENABLE_W1TC : Unsigned_32
     with Volatile, Async_Readers, Effective_Writes => True,
          Address => Base + 16#28#;

   --  GPIO_OUT (0x04) / _W1TS (0x08) / _W1TC (0x0C) -- bit n = pin n's
   --  driven level. The data phase (§6.4): touched on every Set_High/
   --  Set_Low, hence Effective_Writes on the W1TS/W1TC pulse registers.
   GPIO_OUT : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#04#;
   GPIO_OUT_W1TS : Unsigned_32
     with Volatile, Async_Readers, Effective_Writes => True,
          Address => Base + 16#08#;
   GPIO_OUT_W1TC : Unsigned_32
     with Volatile, Async_Readers, Effective_Writes => True,
          Address => Base + 16#0C#;

   --  GPIO_IN (0x3C) -- read-only input level, no side effect.
   GPIO_IN : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#3C#;

end ESP32C3_PAC.GPIO;
