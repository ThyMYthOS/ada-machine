--  ATmega328P USART0 -- UCSR0A/B/C, UBRR0L/H, UDR0, data-space addresses
--  per the datasheet register summary (same direct-address style as
--  ATmega328P_PAC.SPI/TWI). No FIFO: UDR0 is double-buffered on the TX
--  side and single-buffered on RX (Appendix B's "depth-1 FIFO" data
--  point, same as SPI/TWI).
with System;
with Interfaces; use Interfaces;

package ATmega328P_PAC.USART0
  with Preelaborate, SPARK_Mode
is
   UCSR0A : Unsigned_8       --  status: RXC0, TXC0, UDRE0, FE0, DOR0, UPE0, U2X0
     with Volatile, Async_Readers, Async_Writers,
          Address => System'To_Address (16#C0#);
   UCSR0B : Unsigned_8       --  control: RXCIE0, TXCIE0, UDRIE0, RXEN0, TXEN0
     with Volatile, Async_Readers, Async_Writers,
          Address => System'To_Address (16#C1#);
   UCSR0C : Unsigned_8       --  frame format: UMSEL01:0, UPM01:0, USBS0, UCSZ01:0
     with Volatile, Async_Readers, Async_Writers,
          Address => System'To_Address (16#C2#);
   UBRR0L : Unsigned_8       --  baud divisor, low byte
     with Volatile, Async_Readers, Async_Writers,
          Address => System'To_Address (16#C4#);
   UBRR0H : Unsigned_8       --  baud divisor, high nibble (bits 11:8)
     with Volatile, Async_Readers, Async_Writers,
          Address => System'To_Address (16#C5#);
   UDR0   : Unsigned_8       --  data: write starts TX, read fetches RX
     with Volatile, Async_Readers, Async_Writers,
          Effective_Reads => True, Effective_Writes => True,
          Address => System'To_Address (16#C6#);

   UCSR0A_UPE0  : constant := 2#1# * 2**2;   --  bit 2: parity error
   UCSR0A_DOR0  : constant := 2#1# * 2**3;   --  bit 3: data overrun
   UCSR0A_FE0   : constant := 2#1# * 2**4;   --  bit 4: framing error
   UCSR0A_UDRE0 : constant := 2#1# * 2**5;   --  bit 5: UDR0 empty (Is_Tx_Ready)
   UCSR0A_RXC0  : constant := 2#1# * 2**7;   --  bit 7: RX complete (Is_Rx_Ready)

   UCSR0B_TXEN0 : constant := 2#1# * 2**3;   --  bit 3: transmitter enable
   UCSR0B_RXEN0 : constant := 2#1# * 2**4;   --  bit 4: receiver enable

   UCSR0C_UCSZ00   : constant := 2#1# * 2**1;  --  bit 1: char size bit 0
   UCSR0C_UCSZ01   : constant := 2#1# * 2**2;  --  bit 2: char size bit 1
                                                --  (UCSZ01:00 = 11 -> 8 data bits)
end ATmega328P_PAC.USART0;
