--  RP2040 I2C0 -- DesignWare DW_apb_i2c instance, base 0x4004_4000
--  (I2C1 at 0x4004_8000 is not bound here: spike 1 uses I2C0 only,
--  §9 rule 1 -- curate the data actually needed, regenerate to widen).
--
--  This is a hand-authored stand-in for what a curated-SVD codegen run
--  would produce (§9): one volatile scalar per register, precise
--  Async_Readers/Async_Writers/Effective_Reads/Effective_Writes per
--  register instead of a blanket Volatile (§6.6, §9 rule 2), so that
--  code built over this PAC stays provable.
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package RP2040_PAC.I2C0
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#4004_4000#);

   --  IC_CON (0x00) -- control: master-mode / speed / restart-enable.
   --  Written once at Enable time; not touched by the data phase.
   IC_CON : Unsigned_32
     with Volatile, Async_Readers, Async_Writers,
          Address => Base + 16#00#;
   IC_CON_MASTER_MODE     : constant := 2#1#;             --  bit 0
   IC_CON_SPEED_STANDARD  : constant := 2#01# * 2#10#;    --  bits [2:1] = 01
   IC_CON_SPEED_FAST      : constant := 2#10# * 2#10#;    --  bits [2:1] = 10
   IC_CON_RESTART_EN      : constant := 2#1# * 2**5;      --  bit 5
   IC_CON_SLAVE_DISABLE   : constant := 2#1# * 2**6;      --  bit 6

   --  IC_TAR (0x04) -- target (addressed) slave address, 7-bit unshifted.
   IC_TAR : Unsigned_32
     with Volatile, Async_Readers, Async_Writers,
          Address => Base + 16#04#;

   --  IC_DATA_CMD (0x10) -- the command/data FIFO: writing pushes one
   --  FIFO entry (data byte + CMD/STOP/RESTART flags); reading pops one
   --  received byte. This IS the never-blocking L2 data phase (§6.2).
   IC_DATA_CMD : Unsigned_32
     with Volatile, Async_Readers, Async_Writers,
          Effective_Reads => True, Effective_Writes => True,
          Address => Base + 16#10#;
   IC_DATA_CMD_CMD_READ  : constant := 2#1# * 2**8;   --  bit 8: 1 = read
   IC_DATA_CMD_STOP      : constant := 2#1# * 2**9;   --  bit 9
   IC_DATA_CMD_RESTART   : constant := 2#1# * 2**10;  --  bit 10

   --  IC_FS_SCL_HCNT/LCNT (0x1c/0x20) -- fast-mode SCL high/low counts,
   --  computed from the peripheral clock and the configured baud (D8:
   --  MCU-specific configuration, native, not part of the contract).
   IC_FS_SCL_HCNT : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#1c#;
   IC_FS_SCL_LCNT : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#20#;

   --  IC_CLR_TX_ABRT (0x54) -- read-to-clear: clears TX_ABRT and unlatches
   --  IC_TX_ABRT_SOURCE, required before the next transaction can start.
   --  Effective_Reads requires Async_Writers too (SPARK RM 7.1.2(6)):
   --  reading has an effect (clearing the latch) beyond fetching a
   --  value, which needs something else -- here, the hardware itself --
   --  able to write the object for that combination to be meaningful.
   IC_CLR_TX_ABRT : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Effective_Reads => True,
          Address => Base + 16#54#;

   --  IC_CLR_STOP_DET (0x60) -- read-to-clear STOP_DET.
   IC_CLR_STOP_DET : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Effective_Reads => True,
          Address => Base + 16#60#;

   --  IC_ENABLE (0x6c) -- bit 0 enables the controller.
   IC_ENABLE : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#6c#;
   IC_ENABLE_ENABLE : constant := 2#1#;

   --  IC_RAW_INTR_STAT (0x34) -- level status, read-only, no side effect;
   --  bit 6 = TX_ABRT (NACK / arbitration lost / ...), bit 9 = STOP_DET.
   IC_RAW_INTR_STAT : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#34#;
   RAW_INTR_TX_ABRT  : constant := 2#1# * 2**6;
   RAW_INTR_STOP_DET : constant := 2#1# * 2**9;

   --  IC_STATUS (0x70) -- bit1 TFNF (TX FIFO not full, i.e. Can_Push),
   --  bit3 RFNE (RX FIFO not empty, i.e. Can_Pop).
   IC_STATUS : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#70#;
   STATUS_TFNF : constant := 2#1# * 2**1;
   STATUS_RFNE : constant := 2#1# * 2**3;

   --  IC_TX_ABRT_SOURCE (0x80) -- latched abort reason, read-only until
   --  IC_CLR_TX_ABRT is read. Only the bits the L2 body maps are named.
   IC_TX_ABRT_SOURCE : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#80#;
   ABRT_7B_ADDR_NOACK : constant := 2#1#;             --  bit 0
   ABRT_TXDATA_NOACK  : constant := 2#1# * 2**3;      --  bit 3
   ABRT_ARB_LOST      : constant := 2#1# * 2**12;     --  bit 12

end RP2040_PAC.I2C0;
