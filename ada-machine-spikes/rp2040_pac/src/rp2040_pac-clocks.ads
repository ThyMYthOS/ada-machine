--  RP2040 CLOCKS -- base 0x4000_8000 (pico-sdk addressmap.h CLOCKS_BASE).
--  Curated to the one register spike 1 needs: CLK_PERI_CTRL (offset 0x48),
--  the clock generator feeding UART0/1 and SPI0/1. Offsets and bits checked
--  against pico-sdk's hardware/regs/clocks.h. Its reset value is 0: the
--  generator is *disabled* until someone sets ENABLE, and neither the
--  light_rp2040 runtime's clock setup nor anything else does.
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package RP2040_PAC.Clocks
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#4000_8000#);

   --  CLK_PERI_CTRL: ENABLE bit 11; AUXSRC [7:5], 0 = clk_sys.
   CLK_PERI_CTRL : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#48#;
   CLK_PERI_CTRL_ENABLE        : constant := 2#1# * 2**11;
   CLK_PERI_CTRL_AUXSRC_CLK_SYS : constant := 0;     --  AUXSRC field value 0

end RP2040_PAC.Clocks;
