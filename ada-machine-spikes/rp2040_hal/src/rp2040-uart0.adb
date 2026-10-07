with RP2040_PAC.UART0;      use RP2040_PAC.UART0;
with RP2040_PAC.Resets;     use RP2040_PAC.Resets;
with RP2040_PAC.IO_Bank0;   use RP2040_PAC.IO_Bank0;
with RP2040_PAC.Pads_Bank0; use RP2040_PAC.Pads_Bank0;
with RP2040_PAC.Clocks;     use RP2040_PAC.Clocks;
with Interfaces; use Interfaces;

package body RP2040.UART0
  with SPARK_Mode
is

   use Machine.UART;

   --  The UART's baud clock is clk_peri, which Enable switches on below
   --  sourced from clk_sys (no divider on RP2040), so it runs at clk_sys:
   --  125 MHz, the frequency the light_rp2040 runtime configures (pinned in
   --  spike1_pico_board/alire.toml). Clock tree setup beyond that is native
   --  configuration (D8), not part of the portable contract.
   Sys_Clock_Hz : constant := 125_000_000;

   procedure Enable (Cfg : Config := (others => <>)) is
      --  pico-sdk's hardware_uart baud divisor formula: IBRD.FBRD is a
      --  22.6 fixed-point ratio of clk_peri/(16*baud); FBRD rounds to
      --  the nearest 1/64th rather than truncating.
      Baud_Rate_Div : constant Unsigned_32 :=
        (8 * Sys_Clock_Hz) / Unsigned_32 (Cfg.Baud_Hz);
      Baud_Ibrd     : constant Unsigned_32 := Shift_Right (Baud_Rate_Div, 7);
      Baud_Fbrd     : constant Unsigned_32 :=
        (if Baud_Ibrd = 0 then 1
         else ((Baud_Rate_Div and 16#7f#) + 1) / 2);
      Wanted    : constant Unsigned_32 :=
        RESET_UART0 or RESET_IO_BANK0 or RESET_PADS_BANK0;
      Reset_Now : Unsigned_32;
      Done_Now  : Unsigned_32;
   begin
      --  clk_peri resets disabled and no runtime enables it: without this
      --  write the UART has no baud clock. AUXSRC = clk_sys is also the
      --  reset value, so a plain write is safe (pico-sdk only needs its
      --  disable-and-wait dance when *changing* the source).
      CLK_PERI_CTRL := CLK_PERI_CTRL_ENABLE or CLK_PERI_CTRL_AUXSRC_CLK_SYS;

      --  Bring UART0, IO_BANK0 and PADS_BANK0 out of reset (idempotent).
      --  RESET/RESET_DONE read alone into a local first: SPARK requires
      --  a volatile read to be the whole right-hand side of an
      --  assignment/declaration, not combined with other operators in
      --  the same expression (SPARK RM 7.1.3(9)).
      Reset_Now := RESET;
      RESET     := Reset_Now and not Wanted;
      loop
         Done_Now := RESET_DONE;
         exit when (Done_Now and Wanted) = Wanted;
      end loop;

      --  UARTIBRD/UARTFBRD/UARTLCR_H must be written while disabled
      --  (PL011 TRM 4.1: LCR_H write latches the baud-rate divisor).
      UARTCR    := 0;
      UARTIBRD  := Baud_Ibrd;
      UARTFBRD  := Baud_Fbrd;
      UARTLCR_H := UARTLCR_H_WLEN_8 or UARTLCR_H_FEN;

      --  Route TX/RX pins through the UART peripheral; RX wants input
      --  enable + Schmitt, TX needs neither (fully qualified: both
      --  IO_Bank0 and Pads_Bank0 are "use"d above and both declare
      --  Pin_Index, same fix as RP2040.I2C0.Enable).
      Pins (RP2040_PAC.IO_Bank0.Pin_Index (Cfg.TX_Pin)).Ctrl := FUNCSEL_UART;
      Pins (RP2040_PAC.IO_Bank0.Pin_Index (Cfg.RX_Pin)).Ctrl := FUNCSEL_UART;
      Pads (RP2040_PAC.Pads_Bank0.Pin_Index (Cfg.RX_Pin)) :=
        PAD_IE or PAD_SCHMITT;

      UARTCR := UARTCR_UARTEN or UARTCR_TXE or UARTCR_RXE;
   end Enable;

   procedure Disable is
   begin
      UARTCR := 0;
   end Disable;

   function Is_Tx_Ready return Boolean is
      Flags_Now : constant Unsigned_32 := UARTFR;
   begin
      return (Flags_Now and UARTFR_TXFF) = 0;
   end Is_Tx_Ready;

   procedure Put_Frame (Data : Frame) is
   begin
      UARTDR := Unsigned_32 (Data);
   end Put_Frame;

   function Is_Rx_Ready return Boolean is
      Flags_Now : constant Unsigned_32 := UARTFR;
   begin
      return (Flags_Now and UARTFR_RXFE) = 0;
   end Is_Rx_Ready;

   function Map_Error (Word : Unsigned_32) return Machine.UART.Line_Status is
     (if (Word and UARTDR_FE) /= 0 then Framing_Error
      elsif (Word and UARTDR_PE) /= 0 then Parity_Error
      elsif (Word and UARTDR_OE) /= 0 then Overrun
      else Machine.UART.Ok);

   procedure Get_Frame (Data : out Frame;
                        Status : in out Machine.UART.Line_Status)
   is
      Word : Unsigned_32;
   begin
      Data := 0;
      if Status /= Machine.UART.Ok then
         return;                              --  chained: skip if pending
      end if;
      Word   := UARTDR;                       --  read alone (SPARK RM 7.1.3(9))
      Status := Map_Error (Word);
      if Status = Machine.UART.Ok then
         Data := Frame (Word and 16#FF#);
      end if;
   end Get_Frame;

end RP2040.UART0;
