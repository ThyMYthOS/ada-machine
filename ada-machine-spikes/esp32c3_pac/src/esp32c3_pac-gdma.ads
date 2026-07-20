--  ESP32-C3 GDMA (general DMA), base 0x6003_F000 (DR_REG_GDMA_BASE).
--  §15.2's synergy point made concrete: Descriptor below is exactly "a
--  representation clause'd record in a statically allocated buffer" that
--  IS the DMA target -- esp32c3_hal declares Descriptor objects and a
--  data buffer as ordinary statically allocated variables and hands the
--  hardware their addresses; no access types cross the Machine.* contract
--  boundary (§6.6), only inside this HAL-private plumbing.
--
--  Curated to channel 0 only (GDMA has several; §9 rule 1 -- widen by
--  regenerating, not by hand-adding channel 1..N here) and to the
--  register subset a one-shot outlink+inlink SPI2 transfer needs.
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package ESP32C3_PAC.GDMA
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#6003_F000#);

   --  The 12-byte DMA descriptor (dma_descriptor_align4_t): one entry
   --  per contiguous buffer, chained via Next (null on the last one).
   --  Size/Length are 12-bit fields, so one descriptor covers at most
   --  4095 bytes -- BME280's longest single transfer (the 25-byte
   --  0x88..0x9F+0xA1 calibration burst plus command byte) fits in one.
   type Owner_Kind is (CPU, DMA_Engine) with Size => 1;
   for Owner_Kind use (CPU => 0, DMA_Engine => 1);

   --  Component defaults (all-zero/CPU-owned, matching a freshly-zeroed
   --  descriptor slot) let an object of this type declare no explicit
   --  initial aggregate of its own -- esp32c3-hal's TX_Desc/RX_Desc carry
   --  a fixed Address clause (they're GDMA-visible SRAM, §15.2), and an
   --  explicit non-scalar aggregate combined with an Address clause hits
   --  a Preelaborate restriction (field-by-field store to a fixed
   --  address needs elaboration code); relying on the type's own
   --  component defaults instead compiles cleanly.
   type Header is record
      Buf_Size : Unsigned_32 range 0 .. 4095 := 0;  --  buffer capacity
      Length   : Unsigned_32 range 0 .. 4095 := 0;  --  valid byte count
      Err_EOF  : Boolean := False;   --  received buffer had an error
      Suc_EOF  : Boolean := True;    --  this is the last descriptor
      Owner    : Owner_Kind := CPU;  --  who may touch the buffer now
   end record
     with Size => 32;
   for Header use record
      Buf_Size at 0 range 0 .. 11;
      Length   at 0 range 12 .. 23;
      --  bits 24..27 reserved
      Err_EOF  at 0 range 28 .. 28;
      --  bit 29 reserved
      Suc_EOF  at 0 range 30 .. 30;
      Owner    at 0 range 31 .. 31;
   end record;

   --  Buffer/Next are plain 32-bit addresses, not System.Address: RV32
   --  (the real target) has a 32-bit address space, but System.Address
   --  is host-width on whatever GNAT compiles this file (64-bit on a
   --  desktop cross-toolchain host) -- Unsigned_32 keeps the descriptor's
   --  12-byte, three-word layout host-checkable and matches how the
   --  hardware actually treats these fields (raw bit patterns, not
   --  pointers with host semantics). esp32c3_hal converts via
   --  System.Storage_Elements.To_Address/To_Integer at the point of use.
   type Descriptor is record
      Dw0    : Header;
      Buffer : Unsigned_32 := 0;
      Next   : Unsigned_32 := 0;   --  0 if this is the last descriptor
   end record
     with Size => 12 * 8;
   for Descriptor use record
      Dw0    at 0 range 0 .. 31;
      Buffer at 4 range 0 .. 31;
      Next   at 8 range 0 .. 31;
   end record;

   --  Interrupt status, channel 0 (mirrored raw/enable/clear).
   GDMA_INT_RAW_CH0 : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#00#;
   GDMA_INT_ENA_CH0 : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#08#;
   GDMA_INT_CLR_CH0 : Unsigned_32
     with Volatile, Async_Readers, Effective_Writes => True,
          Address => Base + 16#0C#;
   GDMA_IN_DONE_CH0    : constant := 2#1# * 2**0;
   GDMA_IN_SUC_EOF_CH0 : constant := 2#1# * 2**1;
   GDMA_OUT_DONE_CH0   : constant := 2#1# * 2**3;
   GDMA_OUT_EOF_CH0    : constant := 2#1# * 2**4;

   --  RX (inlink) channel 0.
   GDMA_IN_CONF0_CH0 : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#70#;

   --  GDMA_IN_LINK_CH0 -- combines the first descriptor's address
   --  (20 LSBs only: ESP32-C3's DMA-capable SRAM sits in a fixed high
   --  region, so only the low 20 bits vary -- esp32c3_hal masks a
   --  Descriptor's 'Address down to that width before writing here) with
   --  the start/stop/restart control bits (§7.1-chained equivalent: the
   --  START bit is "read/write/self-clearing", the hardware clears it
   --  once the link is mounted).
   GDMA_IN_LINK_CH0 : Unsigned_32
     with Volatile, Async_Readers, Async_Writers,
          Effective_Writes => True, Address => Base + 16#80#;
   GDMA_INLINK_ADDR_MASK    : constant := 16#000F_FFFF#;  --  bits [19:0]
   GDMA_INLINK_AUTO_RET_CH0 : constant := 2#1# * 2**20;
   GDMA_INLINK_STOP_CH0     : constant := 2#1# * 2**21;
   GDMA_INLINK_START_CH0    : constant := 2#1# * 2**22;
   GDMA_INLINK_RESTART_CH0  : constant := 2#1# * 2**23;

   --  GDMA_IN_PERI_SEL_CH0 -- which peripheral feeds this RX channel;
   --  0 selects SPI2 (Espressif's peripheral index table).
   GDMA_IN_PERI_SEL_CH0 : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#A0#;
   GDMA_PERI_SEL_SPI2 : constant := 0;

   --  TX (outlink) channel 0 -- same shape as RX, mirrored offsets.
   GDMA_OUT_CONF0_CH0 : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#D0#;
   GDMA_OUT_AUTO_WRBACK_CH0 : constant := 2#1# * 2**2;
   GDMA_OUT_EOF_MODE_CH0    : constant := 2#1# * 2**3;

   GDMA_OUT_LINK_CH0 : Unsigned_32
     with Volatile, Async_Readers, Async_Writers,
          Effective_Writes => True, Address => Base + 16#E0#;
   GDMA_OUTLINK_ADDR_MASK   : constant := 16#000F_FFFF#;  --  bits [19:0]
   GDMA_OUTLINK_STOP_CH0    : constant := 2#1# * 2**20;
   GDMA_OUTLINK_START_CH0   : constant := 2#1# * 2**21;
   GDMA_OUTLINK_RESTART_CH0 : constant := 2#1# * 2**22;

   GDMA_OUT_PERI_SEL_CH0 : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#100#;

end ESP32C3_PAC.GDMA;
