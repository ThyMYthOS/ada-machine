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

   procedure Enable (Cfg : Config := (others => <>)) is
      SPR   : Unsigned_8;
      SPI2X : Unsigned_8;
      Ctrl  : Unsigned_8 := SPCR_SPE or SPCR_MSTR;
   begin
      --  MOSI/SCK/SS as outputs, MISO as input (hardware requirement).
      DDRB := DDRB or Shift_Left (1, PB_SCK) or Shift_Left (1, PB_MOSI)
                    or Shift_Left (1, PB_SS);
      DDRB := DDRB and not Shift_Left (1, PB_MISO);

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

   function Can_Push return Boolean is (not Busy);

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
     (Busy and then (SPSR and SPSR_SPIF) /= 0);

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
   begin
      SPCR := SPCR or SPCR_SPIE;
   end Enable_Interrupt;

   procedure Disable_Interrupt is
   begin
      SPCR := SPCR and not SPCR_SPIE;
   end Disable_Interrupt;

end ATmega328P.SPI;
