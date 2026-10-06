--  ESP32-C3 SYSCON (a.k.a. APB_CTRL), base 0x6002_6000 -- checked against
--  esp-idf's soc/esp32c3 reg_base.h (DR_REG_SYSCON_BASE) and syscon_reg.h
--  (SYSCON_RND_DATA_REG = base + 0x0B0). Curated to the one register
--  esp32c3_hal needs: the hardware RNG's data word. Unlike the other
--  curated PACs this is not a peripheral block of its own -- the RNG has
--  no control, status or ready register at all (see ESP32C3.RNG).
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package ESP32C3_PAC.SYSCON
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#6002_6000#);

   --  RND_DATA_REG (0xB0) -- read-only, bits [31:0]: a fresh random word on
   --  every read, no read side effect to model (nothing is consumed or
   --  cleared), just a value that changes under the reader.
   RND_DATA : Unsigned_32
     with Volatile, Async_Writers, Address => Base + 16#B0#;

end ESP32C3_PAC.SYSCON;
