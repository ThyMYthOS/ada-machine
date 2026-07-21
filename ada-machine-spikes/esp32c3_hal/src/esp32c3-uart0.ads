--  esp32c3-uart0.ads -- the L2 UART of spike 3, mirroring
--  esp32c3-spi2.ads's polled data-phase shape (Global/Post contracts
--  beyond the §6.2 literal excerpt for the same reasons as that
--  package). No External abstract state needed here, unlike SPI2's
--  "Busy": UART_STATUS's RXFIFO_CNT/TXFIFO_CNT already distinguish
--  "nothing queued" from "something to drain" directly -- there is no
--  depth-1-FIFO ambiguity to bridge with extra bookkeeping.
with Machine, Machine.UART;
use type Machine.UART.Line_Status;  --  for the Post contract's "="/"/="
use type Machine.Byte;               --  for Get_Frame's postcondition
with ESP32C3_PAC.UART0;

package ESP32C3.UART0
  with Preelaborate, SPARK_Mode
is
   type Frame is mod 2**8;

   --  Configuration: ESP32-C3-specific (D8) -- TX/RX pins are the
   --  IOMUX default (U0TXD=GPIO21, U0RXD=GPIO20, §9 rule 1's curation
   --  note in ESP32C3_PAC.UART0), only the baud rate varies.
   type Config is record
      Baud_Hz : Positive range 1 .. 3_000_000 := 115_200;
   end record;

   procedure Enable  (Cfg : Config := (others => <>))
     with Global => (Output => (ESP32C3_PAC.UART0.UART_CLKDIV,
                                ESP32C3_PAC.UART0.UART_CONF0));

   --  Never-blocking data phase (§6.2). Volatile_Function on Is_Tx_Ready/
   --  Is_Rx_Ready: they read hardware state, so two textually-identical
   --  calls need not agree (SPARK RM 7.1.3(9)); no "Pre => Is_Tx_Ready"
   --  on Put_Frame for the same reason a volatile-function call in a
   --  contract expression is itself an interfering context SPARK
   --  rejects -- Is_Tx_Ready is the caller's own check before calling.
   function  Is_Tx_Ready return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => ESP32C3_PAC.UART0.UART_STATUS);

   procedure Put_Frame (Data : Frame)
     with Inline_Always,                             --  UART_FIFO := Data
          Global => (Output => ESP32C3_PAC.UART0.UART_FIFO);

   function  Is_Rx_Ready return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => ESP32C3_PAC.UART0.UART_STATUS);

   procedure Get_Frame (Data : out Frame;
                        Status : in out Machine.UART.Line_Status)
     with Inline_Always,
          Global => (Input  => (ESP32C3_PAC.UART0.UART_INT_RAW,
                                ESP32C3_PAC.UART0.UART_FIFO),
                     In_Out => ESP32C3_PAC.UART0.UART_INT_CLR),
          Post => (if Status'Old /= Machine.UART.Ok
                   then Status = Status'Old and Data = 0);

end ESP32C3.UART0;
