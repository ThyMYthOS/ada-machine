--  RP2040 RESETS -- base 0x4000_c000. Bits Appendix A's I2C0/GPIO/UART0
--  paths need to bring themselves out of reset: I2C0, IO_BANK0,
--  PADS_BANK0, UART0 (bit numbers per the RP2040 datasheet's
--  RESETS_RESET field, alphabetical peripheral order).
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package RP2040_PAC.Resets
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#4000_c000#);

   RESET_I2C0       : constant := 2#1# * 2**3;
   RESET_IO_BANK0   : constant := 2#1# * 2**5;
   RESET_PADS_BANK0 : constant := 2#1# * 2**8;
   RESET_UART0      : constant := 2#1# * 2**22;

   RESET      : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#00#;
   RESET_DONE : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#08#;

end RP2040_PAC.Resets;
