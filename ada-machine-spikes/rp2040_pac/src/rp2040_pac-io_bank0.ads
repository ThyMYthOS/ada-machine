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

   FUNCSEL_I2C  : constant := 3;   --  F3: I2C SDA/SCL alt function
   FUNCSEL_SIO  : constant := 5;   --  F5: software-driven GPIO

   type Pin_Regs is record
      Status : Unsigned_32;
      Ctrl   : Unsigned_32;    --  bits [4:0] = FUNCSEL
   end record
     with Volatile;
   for Pin_Regs use record
      Status at 0 range 0 .. 31;
      Ctrl   at 4 range 0 .. 31;
   end record;
   for Pin_Regs'Size use 64;

   type Pin_Regs_Array is array (Pin_Index) of Pin_Regs with Volatile;

   Pins : Pin_Regs_Array
     with Import, Address => Base;

end RP2040_PAC.IO_Bank0;
