--  RP2040 UART0 -- ARM PL011 instance, base 0x4003_4000 (UART1 at
--  0x4003_8000 is not bound here: §9 rule 1, curate the data actually
--  needed, regenerate to widen).
--
--  Hand-authored stand-in for what a curated-SVD codegen run would
--  produce (§9), like RP2040_PAC.I2C0: one volatile scalar per
--  register, precise Async_Readers/Async_Writers/Effective_Reads/
--  Effective_Writes per register instead of a blanket Volatile.
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package RP2040_PAC.UART0
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#4003_4000#);

   --  UARTDR (0x00) -- data register: writing pushes the TX FIFO;
   --  reading pops the RX FIFO. Bits [11:8] carry OE/BE/PE/FE for the
   --  byte just read (16550-style "error follows the data").
   UARTDR : Unsigned_32
     with Volatile, Async_Readers, Async_Writers,
          Effective_Reads => True, Effective_Writes => True,
          Address => Base + 16#00#;
   UARTDR_FE : constant := 2#1# * 2**8;    --  framing error
   UARTDR_PE : constant := 2#1# * 2**9;    --  parity error
   UARTDR_BE : constant := 2#1# * 2**10;   --  break error
   UARTDR_OE : constant := 2#1# * 2**11;   --  overrun error

   --  UARTFR (0x18) -- flag register, read-only, no side effect.
   UARTFR : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#18#;
   UARTFR_BUSY : constant := 2#1# * 2**3;
   UARTFR_RXFE : constant := 2#1# * 2**4;  --  RX FIFO empty
   UARTFR_TXFF : constant := 2#1# * 2**5;  --  TX FIFO full

   --  UARTIBRD/UARTFBRD (0x24/0x28) -- integer/fractional baud divisor,
   --  written once at Enable time; not touched by the data phase.
   UARTIBRD : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#24#;
   UARTFBRD : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#28#;

   --  UARTLCR_H (0x2c) -- line control: word length, FIFO enable.
   UARTLCR_H : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#2c#;
   UARTLCR_H_FEN  : constant := 2#1# * 2**4;         --  enable FIFOs
   UARTLCR_H_WLEN_8 : constant := 2#11# * 2**5;      --  8 data bits

   --  UARTCR (0x30) -- control: enable UART / transmitter / receiver.
   UARTCR : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#30#;
   UARTCR_UARTEN : constant := 2#1#;
   UARTCR_TXE    : constant := 2#1# * 2**8;
   UARTCR_RXE    : constant := 2#1# * 2**9;

   --  UARTIMSC/UARTRIS/UARTICR (0x38/0x3c/0x44) -- event plumbing for
   --  L3b (§6.2), unused by the blocking spikes.
   UARTIMSC : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#38#;
   UARTRIS  : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#3c#;
   UARTICR  : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#44#;
   UARTIMSC_RXIM : constant := 2#1# * 2**4;
   UARTIMSC_TXIM : constant := 2#1# * 2**5;
   UARTMIS_RXMIS : constant := 2#1# * 2**4;
   UARTMIS_TXMIS : constant := 2#1# * 2**5;
   UARTICR_RXIC  : constant := 2#1# * 2**4;
   UARTICR_TXIC  : constant := 2#1# * 2**5;

end RP2040_PAC.UART0;
