--  RP2040 SIO -- single-cycle IO block: the fast GPIO data path (no APB
--  arbitration), base 0xd000_0000. Atomic SET/CLR/XOR aliases make
--  Set_High/Set_Low/Toggle single-instruction stores (§2 zero-cost goal;
--  §6.4).
--
--  §9 rule 2 / TODO #8: one encoding for write-1/pulse registers across
--  all PACs -- SET/CLR/XOR/OE_SET/OE_CLR each pulse the underlying
--  set-or-clear hardware on every write (the RP2040 datasheet's atomic
--  register aliasing), so each write is individually significant, same
--  as ESP32C3_PAC.GPIO's W1TS/W1TC: Async_Readers, Effective_Writes =>
--  True -- not RP2040's previous Effective_Reads => False (a different,
--  narrower claim: only that reading these back has no side effect,
--  silent on whether repeated writes matter, which they do here).
--
--  Volatile_Full_Access + Size => 32 on every register in this
--  block: the RP2040 datasheet documents SIO as accessible only via
--  single-cycle, full 32-bit reads/writes (it bypasses the usual APB
--  bus precisely to give the processor single-instruction GPIO access;
--  sub-word accesses are not defined for it). Every register here is
--  already a whole Unsigned_32 scalar with no sub-word bit-field
--  decomposition, so GNAT would not otherwise split an access -- VFA
--  makes that bus requirement an explicit, checked contract instead of
--  an implicit fact about today's access patterns.
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package RP2040_PAC.SIO
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#d000_0000#);

   GPIO_IN      : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Volatile_Full_Access, Size => 32,
          Address => Base + 16#004#;
   GPIO_OUT_SET : Unsigned_32
     with Volatile, Async_Readers, Effective_Writes => True,
          Volatile_Full_Access, Size => 32,
          Address => Base + 16#014#;
   GPIO_OUT_CLR : Unsigned_32
     with Volatile, Async_Readers, Effective_Writes => True,
          Volatile_Full_Access, Size => 32,
          Address => Base + 16#018#;
   GPIO_OUT_XOR : Unsigned_32
     with Volatile, Async_Readers, Effective_Writes => True,
          Volatile_Full_Access, Size => 32,
          Address => Base + 16#01c#;
   GPIO_OE_SET  : Unsigned_32
     with Volatile, Async_Readers, Effective_Writes => True,
          Volatile_Full_Access, Size => 32,
          Address => Base + 16#024#;
   GPIO_OE_CLR  : Unsigned_32
     with Volatile, Async_Readers, Effective_Writes => True,
          Volatile_Full_Access, Size => 32,
          Address => Base + 16#028#;

end RP2040_PAC.SIO;
