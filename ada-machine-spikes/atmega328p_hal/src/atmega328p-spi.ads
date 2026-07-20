--  atmega328p-spi.ads -- Appendix C.1, plus contracts added beyond the
--  literal excerpt (§6.6/§7.1). "Busy" (the depth-1-FIFO bookkeeping,
--  Appendix C.4 finding 2) is package-private state touched from both
--  mainline code and the SPI_STC interrupt handler (Appendix C.2/C.3),
--  so it is modeled as External abstract state -- an asynchronous
--  reader/writer from this package's point of view, exactly like the
--  hardware registers it sits next to.
with Machine.SPI;
use type Machine.SPI.Bus_Status;  --  for the Post contracts' "="/"/="
use type Machine.Byte;            --  for Pop's postcondition ("Data = 0")
with ATmega328P_PAC.SPI;
with ATmega328P_PAC.Port_B;

package ATmega328P.SPI
  with Preelaborate, SPARK_Mode,
       Abstract_State => (State with External => (Async_Readers, Async_Writers)),
       Initializes    => State  --  Busy's own default (False) at elaboration
is
   --  Configuration: ATmega-specific (D8). Bus pins are fixed (PB3/PB4/PB5);
   --  chip selects are ordinary GPIOs owned by the application/binding.
   type Clock_Divisor is (Div_2, Div_4, Div_8, Div_16, Div_32, Div_64, Div_128);
   type Config is record
      Divisor   : Clock_Divisor := Div_16;      --  SPR1:0 / SPI2X
      Mode      : Natural range 0 .. 3 := 0;    --  CPOL/CPHA (BME280: 0 or 3)
      MSB_First : Boolean := True;              --  DORD
   end record;

   procedure Enable  (Cfg : Config := (others => <>))
     with Global => (In_Out => ATmega328P_PAC.Port_B.DDRB,
                     Output => (ATmega328P_PAC.SPI.SPCR,
                                ATmega328P_PAC.SPI.SPSR,
                                State));
   procedure Disable
     with Global => (Output => (ATmega328P_PAC.SPI.SPCR, State));

   --  Never-blocking full-duplex data phase (§6.2). The SPI has no FIFO:
   --  one byte in flight -- Can_Push/Can_Pop reflect the SPIF/idle state.
   --  Volatile_Function on both: they read hardware/External state, so
   --  two textually-identical calls need not agree (SPARK RM 7.1.3(9));
   --  no "Pre => Can_Push" on Push for the same reason a volatile-
   --  function call in a contract expression is itself an interfering
   --  context SPARK rejects -- Can_Push is the caller's own check.
   function  Can_Push return Boolean
     with Inline_Always, Volatile_Function, Global => (Input => State);

   procedure Push (Data : Machine.Byte;
                   Status : in out Machine.SPI.Bus_Status)
     with Inline_Always,                            --  SPDR := Data
          Global => (Output => (State, ATmega328P_PAC.SPI.SPDR)),
          Post   => (if Status'Old /= Machine.SPI.Ok
                     then Status = Status'Old);    --  §7.1 rule 1

   function  Can_Pop return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => (State, ATmega328P_PAC.SPI.SPSR));

   procedure Pop (Data : out Machine.Byte;
                  Status : in out Machine.SPI.Bus_Status)
     with Inline_Always,                           --  reads SPDR
          Global => (Input  => ATmega328P_PAC.SPI.SPDR,
                     Output => State),
          Post   => (if Status'Old /= Machine.SPI.Ok
                     then Status = Status'Old and Data = 0);

   --  Event plumbing, reduced to the single interrupt the SPI has:
   procedure Enable_Interrupt
     with Inline_Always, Global => (In_Out => ATmega328P_PAC.SPI.SPCR);
   procedure Disable_Interrupt
     with Inline_Always, Global => (In_Out => ATmega328P_PAC.SPI.SPCR);
end ATmega328P.SPI;
