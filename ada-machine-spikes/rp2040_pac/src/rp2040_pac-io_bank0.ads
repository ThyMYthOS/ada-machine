--  RP2040 IO_BANK0 -- per-pin function-select registers, base 0x4001_4000.
--  Each pin occupies an 8-byte pair (STATUS then CTRL); FUNCSEL lives in
--  CTRL[4:0]. Only FUNCSEL is named: full IRQ-override / pad-override
--  bits are outside this spike's curated subset (§9 rule 1 -- narrow the
--  data, not the generated shape).
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package RP2040_PAC.IO_Bank0
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#4001_4000#);

   subtype Pin_Index is Natural range 0 .. 29;

   FUNCSEL_UART : constant := 2;   --  F2: UART TX/RX alt function
   FUNCSEL_I2C  : constant := 3;   --  F3: I2C SDA/SCL alt function
   FUNCSEL_SIO  : constant := 5;   --  F5: software-driven GPIO

   --  §9 rule 2 / §6.6: precise flavors, not blanket Volatile (the
   --  conformance defect the review flags). Ordinary MMIO read/write on
   --  both fields -- Status is never read by this HAL (kept only to hold
   --  Ctrl at its real +4 byte offset in the 8-byte-per-pin layout) and
   --  Ctrl is written, never read, so no Effective_Reads/Writes beyond
   --  the volatile defaults are warranted; Async_Readers/Async_Writers
   --  (the hardware itself reads Ctrl to route the pin, and may update
   --  Status asynchronously) is the same "ordinary register" shape as
   --  ESP32C3_PAC.GPIO's GPIO_ENABLE. No Volatile_Full_Access: each field
   --  is a whole 32-bit word at its own offset (no sub-word bit-field
   --  decomposition), so a component store already compiles to one
   --  full-width write -- VFA would add nothing here (contrast
   --  RP2040_PAC.SIO below, where VFA documents a real bus requirement).
   type Pin_Regs is record
      Status : Unsigned_32;
      Ctrl   : Unsigned_32;    --  bits [4:0] = FUNCSEL
   end record
     with Volatile, Async_Readers, Async_Writers;
   for Pin_Regs use record
      Status at 0 range 0 .. 31;
      Ctrl   at 4 range 0 .. 31;
   end record;
   for Pin_Regs'Size use 64;

   type Pin_Regs_Array is array (Pin_Index) of Pin_Regs
     with Volatile, Async_Readers, Async_Writers;

   Pins : Pin_Regs_Array
     with Import, Address => Base;

end RP2040_PAC.IO_Bank0;
