with ATmega328P_PAC.USART0; use ATmega328P_PAC.USART0;
with Interfaces; use Interfaces;

package body ATmega328P.USART0
  with SPARK_Mode
is

   use Machine.UART;

   --  Every volatile (UCSR0A) read below is taken alone into a local
   --  constant first -- SPARK requires a volatile read to be the whole
   --  right-hand side of an assignment/declaration, not combined with
   --  other operators in the same expression (SPARK RM 7.1.3(9)), same
   --  discipline as ATmega328P.SPI's body.

   procedure Enable (Cfg : Config := (others => <>)) is
      --  Normal async mode (U2X0=0): UBRR = F_CPU/(16*Baud) - 1.
      Ubrr : constant Unsigned_16 :=
        Unsigned_16 (ATmega328P_HAL_Config.F_CPU
                     / (16 * Cfg.Baud_Hz) - 1);
   begin
      UCSR0A := 0;
      UBRR0H := Unsigned_8 (Shift_Right (Ubrr, 8) and 16#0F#);
      UBRR0L := Unsigned_8 (Ubrr and 16#FF#);
      UCSR0C := UCSR0C_UCSZ01 or UCSR0C_UCSZ00;   --  8N1, async
      UCSR0B := UCSR0B_TXEN0 or UCSR0B_RXEN0;
   end Enable;

   procedure Disable is
   begin
      UCSR0B := 0;
   end Disable;

   function Is_Tx_Ready return Boolean is
      Ucsr0a_Now : constant Unsigned_8 := UCSR0A;
   begin
      return (Ucsr0a_Now and UCSR0A_UDRE0) /= 0;
   end Is_Tx_Ready;

   procedure Put_Frame (Data : Frame) is
   begin
      UDR0 := Unsigned_8 (Data);
   end Put_Frame;

   function Is_Rx_Ready return Boolean is
      Ucsr0a_Now : constant Unsigned_8 := UCSR0A;
   begin
      return (Ucsr0a_Now and UCSR0A_RXC0) /= 0;
   end Is_Rx_Ready;

   function Map_Error (Flags : Unsigned_8) return Machine.UART.Line_Status is
     (if (Flags and UCSR0A_FE0) /= 0 then Framing_Error
      elsif (Flags and UCSR0A_UPE0) /= 0 then Parity_Error
      elsif (Flags and UCSR0A_DOR0) /= 0 then Overrun
      else Machine.UART.Ok);

   procedure Get_Frame (Data : out Frame;
                        Status : in out Machine.UART.Line_Status)
   is
      Flags : Unsigned_8;
   begin
      Data := 0;
      if Status /= Machine.UART.Ok then
         return;                              --  chained: skip if pending
      end if;
      --  UCSR0A's FE0/DOR0/UPE0 describe the frame still sitting in
      --  UDR0 -- must be read before UDR0 itself (reading UDR0 releases
      --  the receive buffer for the next frame, per the datasheet).
      Flags  := UCSR0A;
      Status := Map_Error (Flags);
      if Status = Machine.UART.Ok then
         Data := Frame (UDR0);
      end if;
   end Get_Frame;

end ATmega328P.USART0;
