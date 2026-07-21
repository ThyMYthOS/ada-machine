--  ESP32-C3 UART0, base 0x6000_0000 (DR_REG_UART_BASE). Curated to what
--  esp32c3_hal needs for a polled byte-at-a-time data phase (§6.2),
--  same curation policy as ESP32C3_PAC.SPI2: only the registers/bits the
--  L2 body actually programs are named, everything else stays at its
--  reset default. Peripheral clock gating (PCR_UART0_CONF_REG on this
--  chip family) is out of this curated subset's scope, same as SPI2's
--  GPIO-matrix pin routing -- UART0's IOMUX-default pins (U0TXD=GPIO21,
--  U0RXD=GPIO20) and clock source are assumed already enabled, as they
--  are out of ROM-bootloader reset (UART0 is the boot-log/console UART).
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package ESP32C3_PAC.UART0
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#6000_0000#);

   --  UART_FIFO_REG (0x00) -- data: write pushes the TX FIFO, read pops
   --  the RX FIFO (bits [7:0]); the never-blocking L2 data phase (§6.2).
   UART_FIFO : Unsigned_32
     with Volatile, Async_Readers, Async_Writers,
          Effective_Reads => True, Effective_Writes => True,
          Address => Base + 16#00#;

   --  UART_CLKDIV_REG (0x14) -- CLKDIV_INT[11:0]; actual baud = UART_CLK
   --  / CLKDIV_INT (the fractional field, [23:20], is left at 0 -- this
   --  curated subset only needs integer-divisor precision).
   UART_CLKDIV : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#14#;

   --  UART_STATUS_REG (0x1C) -- read-only, no side effect: RXFIFO_CNT
   --  [23:16], TXFIFO_CNT [7:0] (Is_Rx_Ready / Is_Tx_Ready, §6.2).
   UART_STATUS : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#1C#;
   UART_STATUS_TXFIFO_CNT_SHIFT : constant := 0;
   UART_STATUS_TXFIFO_CNT_MASK  : constant := 16#FF#;
   UART_STATUS_RXFIFO_CNT_SHIFT : constant := 16;
   UART_STATUS_RXFIFO_CNT_MASK  : constant := 16#FF#;
   UART_TXFIFO_DEPTH            : constant := 128;

   --  UART_CONF0_REG (0x20) -- frame format + FIFO reset pulses.
   --  BIT_NUM[3:2] = 11 -> 8 data bits; STOP_BIT_NUM[5:4] = 01 -> 1 stop
   --  bit; PARITY_EN (bit 1) left clear -> no parity.
   UART_CONF0 : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#20#;
   UART_CONF0_BIT_NUM_8   : constant := 2#11# * 2**2;
   UART_CONF0_STOP_BIT_1  : constant := 2#01# * 2**4;
   UART_CONF0_RXFIFO_RST  : constant := 2#1# * 2**17;
   UART_CONF0_TXFIFO_RST  : constant := 2#1# * 2**18;

   --  RX line-error latch (datasheet 24.4): parity/framing errors raise
   --  the corresponding UART_INT_RAW bit and stay set until cleared via
   --  UART_INT_CLR; there is no per-byte error tag alongside UART_FIFO
   --  the way AVR's UCSR0A/RP2040's UARTDR carry one, so Get_Frame reads
   --  these instead.
   UART_INT_RAW : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#04#;
   UART_INT_CLR : Unsigned_32
     with Volatile, Async_Readers, Effective_Writes => True,
          Address => Base + 16#10#;
   UART_INT_PARITY_ERR : constant := 2#1# * 2**0;
   UART_INT_FRM_ERR    : constant := 2#1# * 2**3;
   UART_INT_RXFIFO_OVF  : constant := 2#1# * 2**4;

end ESP32C3_PAC.UART0;
