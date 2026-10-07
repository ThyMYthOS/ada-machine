--  rp2040-uart0.ads -- the L2 UART of spike 1, mirroring rp2040-i2c0.ads
--  (Global/Post contracts beyond the §6.2 literal excerpt for the same
--  reasons: the chained skip-semantics postcondition is the one contract
--  worth stating uniformly at every layer, and Global documents exactly
--  which registers each operation touches).
with Machine, Machine.UART;
use type Machine.UART.Line_Status;  --  for the Post contract's "="/"/="
use type Machine.Byte;               --  for Get_Frame's postcondition
with RP2040_PAC.UART0, RP2040_PAC.Resets, RP2040_PAC.IO_Bank0,
     RP2040_PAC.Pads_Bank0, RP2040_PAC.Clocks;

package RP2040.UART0
  with Preelaborate, SPARK_Mode
is
   type Frame is mod 2**8;

   --  Configuration: deliberately RP2040-specific (D8) -- pins, baud.
   --  Not part of the portable contract.
   type Config is record
      Baud_Hz : Positive range 1 .. 3_000_000 := 115_200;
      TX_Pin  : Pin_Id := 0;
      RX_Pin  : Pin_Id := 1;
   end record;

   --  Pins/Pads: In_Out, not Output (TODO #8) -- they are whole-array
   --  Globals but Enable only writes the elements at TX_Pin/RX_Pin, so
   --  Output's "the whole array is (re)written" claim would overclaim.
   procedure Enable  (Cfg : Config := (others => <>))
     with Global => (In_Out => (RP2040_PAC.Resets.RESET,
                                RP2040_PAC.IO_Bank0.Pins,
                                RP2040_PAC.Pads_Bank0.Pads),
                     Input  => RP2040_PAC.Resets.RESET_DONE,
                     Output => (RP2040_PAC.Clocks.CLK_PERI_CTRL,
                                RP2040_PAC.UART0.UARTCR,
                                RP2040_PAC.UART0.UARTLCR_H,
                                RP2040_PAC.UART0.UARTIBRD,
                                RP2040_PAC.UART0.UARTFBRD));
   procedure Disable
     with Global => (Output => RP2040_PAC.UART0.UARTCR);

   --  Never-blocking data phase over the PL011 TX/RX FIFOs (§6.2).
   --  Volatile_Function on Is_Tx_Ready/Is_Rx_Ready: they read hardware
   --  state, so two textually-identical calls need not agree (SPARK RM
   --  7.1.3(9)); no "Pre => Is_Tx_Ready" on Put_Frame for the same
   --  reason a volatile-function call in a contract expression is
   --  itself an interfering context SPARK rejects -- Is_Tx_Ready is the
   --  caller's own check before calling.
   function  Is_Tx_Ready return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => RP2040_PAC.UART0.UARTFR);

   procedure Put_Frame (Data : Frame)
     with Inline_Always,
          Global => (Output => RP2040_PAC.UART0.UARTDR);

   function  Is_Rx_Ready return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => RP2040_PAC.UART0.UARTFR);

   procedure Get_Frame (Data : out Frame;
                        Status : in out Machine.UART.Line_Status)
     with Inline_Always,
          Global => (Input => RP2040_PAC.UART0.UARTDR),
          Post => (if Status'Old /= Machine.UART.Ok
                   then Status = Status'Old and Data = 0);

   --  Event plumbing for L3b (§6.2), unused in this blocking spike:
   --  Enable_Event / Disable_Event / Pending_Event / Clear_Event ...
end RP2040.UART0;
