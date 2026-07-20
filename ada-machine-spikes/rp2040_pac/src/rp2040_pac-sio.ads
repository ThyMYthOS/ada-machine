--  RP2040 SIO -- single-cycle IO block: the fast GPIO data path (no APB
--  arbitration), base 0xd000_0000. Atomic SET/CLR/XOR aliases make
--  Set_High/Set_Low/Toggle single-instruction stores (§2 zero-cost goal;
--  §6.4).
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package RP2040_PAC.SIO
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#d000_0000#);

   GPIO_IN      : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#004#;
   GPIO_OUT_SET : Unsigned_32
     with Volatile, Async_Readers, Effective_Reads => False,
          Address => Base + 16#014#;
   GPIO_OUT_CLR : Unsigned_32
     with Volatile, Async_Readers, Effective_Reads => False,
          Address => Base + 16#018#;
   GPIO_OUT_XOR : Unsigned_32
     with Volatile, Async_Readers, Effective_Reads => False,
          Address => Base + 16#01c#;
   GPIO_OE_SET  : Unsigned_32
     with Volatile, Async_Readers, Effective_Reads => False,
          Address => Base + 16#024#;
   GPIO_OE_CLR  : Unsigned_32
     with Volatile, Async_Readers, Effective_Reads => False,
          Address => Base + 16#028#;

end RP2040_PAC.SIO;
