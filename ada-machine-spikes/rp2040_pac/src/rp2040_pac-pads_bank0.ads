--  RP2040 PADS_BANK0 -- per-pin pad control (pull up/down, input enable,
--  schmitt, drive strength, output disable), base 0x4001_c000. Word 0 is
--  VOLTAGE_SELECT (not a pin register); GPIO0's word starts at +0x04.
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package RP2040_PAC.Pads_Bank0
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#4001_c000#);

   subtype Pin_Index is Natural range 0 .. 29;

   PAD_SCHMITT : constant := 2#1# * 2**1;  --  bit 1: Schmitt trigger enable
   PAD_PDE     : constant := 2#1# * 2**2;  --  bit 2: pull-down enable
   PAD_PUE     : constant := 2#1# * 2**3;  --  bit 3: pull-up enable
   PAD_IE      : constant := 2#1# * 2**6;  --  bit 6: input enable
   PAD_OD      : constant := 2#1# * 2**7;  --  bit 7: output disable

   --  §9 rule 2 / §6.6: precise flavors, not blanket Volatile. Ordinary
   --  MMIO read/write (no register here is read-to-clear or a
   --  write-1-pulse) -- Async_Readers/Async_Writers matches
   --  ESP32C3_PAC.GPIO's plain registers; no Volatile_Full_Access, each
   --  element is a whole 32-bit word with no sub-word bit-field
   --  decomposition (RP2040.GPIO/.I2C0/.UART0 always write the full
   --  pad word in one store), so VFA would add nothing here.
   type Pad_Array is array (Pin_Index) of Unsigned_32
     with Volatile, Async_Readers, Async_Writers;

   Pads : Pad_Array
     with Import, Address => Base + 16#04#;

end RP2040_PAC.Pads_Bank0;
