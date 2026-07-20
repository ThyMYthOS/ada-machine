with ATmega328P_PAC.SPI;    use ATmega328P_PAC.SPI;
with ATmega328P_PAC.Port_B; use ATmega328P_PAC.Port_B;
with Interfaces; use Interfaces;

package body ATmega328P.SPI
  with SPARK_Mode,
       Refined_State => (State => Busy)
is

   use Machine.SPI;

   --  No FIFO on this hardware: one byte in flight. The HAL keeps the
   --  "is a transfer outstanding" bit itself, since SPDR/SPSR alone
   --  don't distinguish "never started" from "already collected"
   --  (Appendix C.4 finding 2: a depth-1 FIFO). Touched from both
   --  mainline code and the SPI_STC interrupt handler (Appendix C.2/C.3
   --  calls Push/Pop from On_Interrupt) -- Volatile for correctness
   --  under that. No "Part_Of => State": Refined_State above already
   --  associates Busy with State by name, and Part_Of would be
   --  redundant/illegal alongside that for a body-declared constituent
   --  (SPARK RM 7.2.6(5); Part_Of is only for constituents declared in a
   --  package's private part, not its body).
   Busy : Boolean := False
     with Volatile, Async_Readers, Async_Writers;

   --  PB5=SCK, PB4=MISO (input, left as Hi-Z/input by DDRB), PB3=MOSI,
   --  PB2=/SS (must be output in master mode or the hardware can force
   --  a mode fault on input-low).
   PB_SCK  : constant := 5;
   PB_MISO : constant := 4;
   PB_MOSI : constant := 3;
   PB_SS   : constant := 2;

   --  Every volatile (DDRB/SPCR) read below is taken alone into a local
   --  constant first, then combined with other operators via that
   --  ordinary local -- SPARK requires a volatile read to be the whole
   --  right-hand side of an assignment/declaration, not combined with
   --  other operators in the same expression (SPARK RM 7.1.3(9)).

   procedure Enable (Cfg : Config := (others => <>)) is
      SPR      : Unsigned_8;
      SPI2X    : Unsigned_8;
      Ctrl     : Unsigned_8 := SPCR_SPE or SPCR_MSTR;
      Ddrb_Now : Unsigned_8;
   begin
      --  MOSI/SCK/SS as outputs, MISO as input (hardware requirement).
      Ddrb_Now := DDRB;
      DDRB := Ddrb_Now or Shift_Left (1, PB_SCK) or Shift_Left (1, PB_MOSI)
                        or Shift_Left (1, PB_SS);
      Ddrb_Now := DDRB;
      DDRB := Ddrb_Now and not Shift_Left (1, PB_MISO);

      case Cfg.Divisor is
         when Div_2   => SPI2X := 1; SPR := 2#00#;
         when Div_4   => SPI2X := 0; SPR := 2#00#;
         when Div_8   => SPI2X := 1; SPR := 2#01#;
         when Div_16  => SPI2X := 0; SPR := 2#01#;
         when Div_32  => SPI2X := 1; SPR := 2#10#;
         when Div_64  => SPI2X := 0; SPR := 2#10#;
         when Div_128 => SPI2X := 0; SPR := 2#11#;
      end case;

      if Cfg.Mode = 2 or Cfg.Mode = 3 then Ctrl := Ctrl or SPCR_CPOL; end if;
      if Cfg.Mode = 1 or Cfg.Mode = 3 then Ctrl := Ctrl or SPCR_CPHA; end if;
      if not Cfg.MSB_First then Ctrl := Ctrl or SPCR_DORD; end if;
      Ctrl := Ctrl or Shift_Left (Unsigned_8 (SPR), 0);

      SPSR := SPI2X;              --  SPI2X is bit 0 of SPSR
      SPCR := Ctrl;
      Busy := False;
   end Enable;

   procedure Disable is
   begin
      SPCR := 0;
      Busy := False;
   end Disable;

   function Can_Push return Boolean is
      B : constant Boolean := Busy;
   begin
      return not B;
   end Can_Push;

   procedure Push (Data : Machine.Byte;
                   Status : in out Machine.SPI.Bus_Status)
   is
   begin
      if Status /= Ok then
         return;                              --  chained: skip if pending
      end if;
      Busy := True;
      SPDR := Unsigned_8 (Data);               --  starts the transfer
   end Push;

   function Can_Pop return Boolean is
      B    : constant Boolean := Busy;
      Spsr_Now : constant Unsigned_8 := SPSR;
   begin
      return B and then (Spsr_Now and SPSR_SPIF) /= 0;
   end Can_Pop;

   procedure Pop (Data : out Machine.Byte;
                  Status : in out Machine.SPI.Bus_Status)
   is
   begin
      Data := 0;
      if Status /= Ok then
         return;                              --  chained: skip if pending
      end if;
      Data := Machine.Byte (SPDR);             --  clears SPIF as a side effect
      Busy := False;
   end Pop;

   procedure Enable_Interrupt is
      Spcr_Now : constant Unsigned_8 := SPCR;
   begin
      SPCR := Spcr_Now or SPCR_SPIE;
   end Enable_Interrupt;

   procedure Disable_Interrupt is
      Spcr_Now : constant Unsigned_8 := SPCR;
   begin
      SPCR := Spcr_Now and not SPCR_SPIE;
   end Disable_Interrupt;

end ATmega328P.SPI;
