--  ESP32-C3 GP-SPI2, base 0x6002_4000 (DR_REG_SPI2_BASE). Curated to what
--  esp32c3_hal needs for both paths: a polled single-byte data phase
--  (SPI_CMD/SPI_MS_DLEN/SPI_W0, matching Machine.SPI.Generic_Master's
--  Push/Pop shape, §6.2) and a DMA-driven block phase (SPI_DMA_CONF plus
--  the DMA-done status in SPI_DMA_INT_RAW/_CLR) that GDMA channel 0 feeds
--  (ESP32C3_PAC.GDMA). Bit positions below are the ones esp32c3_hal
--  actually programs; SPI_CTRL/_USER1/_USER2/_MISC are exposed as raw
--  registers (address only) since the driver only needs to zero or leave
--  them at reset default for BME280's plain full-duplex mode-0 use.
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package ESP32C3_PAC.SPI2
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#6002_4000#);

   --  SPI_CMD (0x00) -- bit 24 (SPI_USR) starts a user-defined
   --  transaction; the hardware clears it when the transaction ends, so
   --  it doubles as the "transfer in progress" bit polled data phases
   --  read directly (no separate busy/status register needed for that).
   --  Effective_Writes only: writing USR triggers the transaction, but
   --  reading it back is a plain status check with no side effect of
   --  its own (unlike a real read-to-clear register) -- so it stays
   --  readable from a SPARK function (Can_Pop polls this bit), which an
   --  Effective_Reads register could not be (SPARK RM: a function may
   --  not have an Effective_Reads global).
   SPI_CMD : Unsigned_32
     with Volatile, Async_Readers, Async_Writers,
          Effective_Writes => True,
          Address => Base + 16#00#;
   SPI_CMD_USR    : constant := 2#1# * 2**24;
   SPI_CMD_UPDATE : constant := 2#1# * 2**23;

   SPI_ADDR : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#04#;

   --  Raw registers: BME280 over plain full-duplex mode 0 needs these at
   --  their reset defaults (no address phase, no dummy cycles, no QPI) --
   --  exposed for completeness/future widening, not written by this spike.
   SPI_CTRL : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#08#;

   --  SPI_CLOCK (0x0C) -- the four-field divider (datasheet 27.6): actual
   --  SPI clock = APB clock / ((CLKDIV_PRE + 1) * (CLKCNT_N + 1)), with
   --  CLKCNT_H/_L splitting the duty cycle; CLK_EQU_SYSCLK bypasses all of
   --  it (SPI clock = APB clock, bit 31).
   SPI_CLOCK : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#0C#;
   SPI_CLK_EQU_SYSCLK_BIT : constant := 31;
   SPI_CLKDIV_PRE_SHIFT   : constant := 18;  --  4 bits, [21:18]
   SPI_CLKCNT_N_SHIFT     : constant := 12;  --  6 bits, [17:12]
   SPI_CLKCNT_H_SHIFT     : constant := 6;   --  6 bits, [11:6]
   SPI_CLKCNT_L_SHIFT     : constant := 0;   --  6 bits, [5:0]

   --  SPI_USER (0x10) -- DOUTDIN (bit 0) is full-duplex mode (MOSI/MISO
   --  both active, exactly what a byte exchange needs); USR_MOSI/USR_MISO
   --  (bits 27/28) enable the write/read data phases of the user-defined
   --  transaction; CS_SETUP/CS_HOLD (bits 7/6) extend CS around the data
   --  phase, matching the regmap binding's own CS.Set bracketing (the
   --  hardware and the software convention agree here, redundantly but
   --  harmlessly -- BME280's regmap binding still owns CS via a plain
   --  Machine.GPIO.Generic_Digital_Out, per §6.1's "CS is not part of the
   --  SPI class").
   SPI_USER : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#10#;
   SPI_USER_DOUTDIN    : constant := 2#1# * 2**0;
   SPI_USER_CK_OUT_EDGE : constant := 2#1# * 2**9;  --  CPHA (with
                                      --  SPI_MISC_CK_IDLE_EDGE below,
                                      --  conventional mode mapping:
                                      --  mode bit0 -> CK_OUT_EDGE,
                                      --  mode bit1 -> CK_IDLE_EDGE)
   SPI_USER_CS_HOLD    : constant := 2#1# * 2**6;
   SPI_USER_CS_SETUP   : constant := 2#1# * 2**7;
   SPI_USER_USR_MOSI   : constant := 2#1# * 2**27;
   SPI_USER_USR_MISO   : constant := 2#1# * 2**28;

   SPI_USER1 : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#14#;
   SPI_USER2 : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#18#;

   --  SPI_MS_DLEN (0x1C) -- transaction length in BITS minus one,
   --  [17:0], shared by the MOSI and MISO phases (full duplex: same
   --  length both ways).
   SPI_MS_DLEN : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#1C#;

   --  SPI_MISC (0x20) -- CK_IDLE_EDGE (bit 29) is CPOL: idle level of
   --  the clock line.
   SPI_MISC : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#20#;
   SPI_MISC_CK_IDLE_EDGE : constant := 2#1# * 2**29;

   --  SPI_DMA_CONF (0x30) -- bits 27/28 gate the DMA path per direction;
   --  set together for the full-duplex block transfer §8.2/Appendix C
   --  finding 1 talks about (DMA as an <mcu>_hal implementation detail
   --  behind the same portable adapter shape).
   SPI_DMA_CONF : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#30#;
   SPI_DMA_RX_ENA    : constant := 2#1# * 2**27;
   SPI_DMA_TX_ENA    : constant := 2#1# * 2**28;
   SPI_RX_AFIFO_RST  : constant := 2#1# * 2**29;
   SPI_DMA_AFIFO_RST : constant := 2#1# * 2**31;

   --  DMA completion status, mirrored raw/enable/clear (datasheet 27.6):
   --  bit 12 (SPI_TRANS_DONE) is the one esp32c3_hal's DMA path waits on.
   SPI_DMA_INT_RAW : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#3C#;
   SPI_DMA_INT_ENA : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#34#;
   SPI_DMA_INT_CLR : Unsigned_32
     with Volatile, Async_Readers, Effective_Writes => True,
          Address => Base + 16#38#;
   SPI_DMA_INT_ST : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#40#;
   SPI_TRANS_DONE : constant := 2#1# * 2**12;

   --  SPI_W0 (0x98) -- first word of the 16-word (64-byte) data buffer.
   --  The polled byte-at-a-time data phase (Machine.SPI.Generic_Master's
   --  Push/Pop, §6.2) only ever touches this one word: one byte out,
   --  one byte in, per transaction.
   --  Effective_Writes only, same reasoning as SPI_CMD above: no
   --  evidence this data buffer is read-to-clear (unlike AVR's SPDR).
   SPI_W0 : Unsigned_32
     with Volatile, Async_Readers, Async_Writers,
          Effective_Writes => True,
          Address => Base + 16#98#;

end ESP32C3_PAC.SPI2;
