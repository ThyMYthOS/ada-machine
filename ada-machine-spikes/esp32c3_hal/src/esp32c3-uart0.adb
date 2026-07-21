with ESP32C3_PAC.UART0; use ESP32C3_PAC.UART0;
with Interfaces; use Interfaces;

package body ESP32C3.UART0
  with SPARK_Mode
is

   use Machine.UART;

   --  Simplified: assumes UART0's clock source is already running at
   --  APB clock (the ROM bootloader's own default for the console
   --  UART, §9's "native configuration, not part of the portable
   --  contract" -- same simplification as RP2040.UART0's Sys_Clock_Hz).
   Uart_Clk_Hz : constant := 80_000_000;

   procedure Enable (Cfg : Config := (others => <>)) is
      Clkdiv : constant Unsigned_32 :=
        Uart_Clk_Hz / Unsigned_32 (Cfg.Baud_Hz);
   begin
      UART_CLKDIV := Clkdiv;
      UART_CONF0  := UART_CONF0_BIT_NUM_8 or UART_CONF0_STOP_BIT_1
                     or UART_CONF0_RXFIFO_RST or UART_CONF0_TXFIFO_RST;
   end Enable;

   function Is_Tx_Ready return Boolean is
      Status_Now : constant Unsigned_32 := UART_STATUS;
      Tx_Cnt     : constant Unsigned_32 :=
        Shift_Right (Status_Now, UART_STATUS_TXFIFO_CNT_SHIFT)
          and UART_STATUS_TXFIFO_CNT_MASK;
   begin
      return Tx_Cnt < UART_TXFIFO_DEPTH;
   end Is_Tx_Ready;

   procedure Put_Frame (Data : Frame) is
   begin
      UART_FIFO := Unsigned_32 (Data);
   end Put_Frame;

   function Is_Rx_Ready return Boolean is
      Status_Now : constant Unsigned_32 := UART_STATUS;
      Rx_Cnt     : constant Unsigned_32 :=
        Shift_Right (Status_Now, UART_STATUS_RXFIFO_CNT_SHIFT)
          and UART_STATUS_RXFIFO_CNT_MASK;
   begin
      return Rx_Cnt > 0;
   end Is_Rx_Ready;

   function Map_Error (Raw : Unsigned_32) return Machine.UART.Line_Status is
     (if (Raw and UART_INT_FRM_ERR) /= 0 then Framing_Error
      elsif (Raw and UART_INT_PARITY_ERR) /= 0 then Parity_Error
      elsif (Raw and UART_INT_RXFIFO_OVF) /= 0 then Overrun
      else Machine.UART.Ok);

   procedure Get_Frame (Data : out Frame;
                        Status : in out Machine.UART.Line_Status)
   is
      Raw      : Unsigned_32;
      Fifo_Now : Unsigned_32;
   begin
      Data := 0;
      if Status /= Machine.UART.Ok then
         return;                              --  chained: skip if pending
      end if;
      Raw    := UART_INT_RAW;                  --  read alone (SPARK RM 7.1.3(9))
      Status := Map_Error (Raw);
      if Status = Machine.UART.Ok then
         Fifo_Now := UART_FIFO;                --  read alone (SPARK RM 7.1.3(9))
         Data     := Frame (Fifo_Now and 16#FF#);
      else
         UART_INT_CLR := Raw;                  --  ack the latched error bits
      end if;
   end Get_Frame;

end ESP32C3.UART0;
