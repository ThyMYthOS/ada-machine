--  atmega328p-usart0.ads -- the L2 UART of spike 2, mirroring
--  atmega328p-spi.ads (Global/Post contracts beyond the §6.2 literal
--  excerpt for the same reasons as that package and RP2040.UART0).
with Machine, Machine.UART;
use type Machine.UART.Line_Status;  --  for the Post contract's "="/"/="
use type Machine.Byte;               --  for Get_Frame's postcondition
with Interfaces;
with ATmega328P_PAC.USART0;
with ATmega328P_HAL_Config;

package ATmega328P.USART0
  with Preelaborate, SPARK_Mode
is
   type Frame is mod 2**8;

   --  Configuration: ATmega-specific (D8) -- TX/RX pins are fixed
   --  (PD1/PD0), only the baud rate varies. Not part of the portable
   --  contract. Unsigned_32, not Positive: AVR's Standard.Integer is
   --  16 bits, too narrow for the upper end of this range.
   type Config is record
      Baud_Hz : Interfaces.Unsigned_32 range 1 .. 115_200 := 9_600;
   end record;

   procedure Enable  (Cfg : Config := (others => <>))
     with Global => (Output => (ATmega328P_PAC.USART0.UCSR0A,
                                ATmega328P_PAC.USART0.UCSR0B,
                                ATmega328P_PAC.USART0.UCSR0C,
                                ATmega328P_PAC.USART0.UBRR0L,
                                ATmega328P_PAC.USART0.UBRR0H));
   procedure Disable
     with Global => (Output => ATmega328P_PAC.USART0.UCSR0B);

   --  Never-blocking data phase (§6.2). No FIFO: UDR0 is double-buffered
   --  on TX, single-buffered on RX (Appendix B's depth-1-FIFO pattern,
   --  same as ATmega328P.SPI/soon-TWI). Volatile_Function on Is_Tx_Ready/
   --  Is_Rx_Ready for the same reason as ATmega328P.SPI's Can_Push/Can_Pop.
   function  Is_Tx_Ready return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => ATmega328P_PAC.USART0.UCSR0A);

   procedure Put_Frame (Data : Frame)
     with Inline_Always,                             --  UDR0 := Data
          Global => (Output => ATmega328P_PAC.USART0.UDR0);

   function  Is_Rx_Ready return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => ATmega328P_PAC.USART0.UCSR0A);

   procedure Get_Frame (Data : out Frame;
                        Status : in out Machine.UART.Line_Status)
     with Inline_Always,
          Global => (Input => (ATmega328P_PAC.USART0.UCSR0A,
                                ATmega328P_PAC.USART0.UDR0)),
          Post => (if Status'Old /= Machine.UART.Ok
                   then Status = Status'Old and Data = 0);

end ATmega328P.USART0;
