with Machine; use Machine;
with Machine.SPI;
with ESP32C3_PAC.SPI2; use ESP32C3_PAC.SPI2;
with ESP32C3_PAC.GDMA; use ESP32C3_PAC.GDMA;
with Interfaces; use Interfaces;
with System.Storage_Elements;

use type Machine.SPI.Bus_Status, Machine.SPI.Transaction_Status;

package body ESP32C3.SPI2
  with SPARK_Mode,
       Refined_State => (State => (Busy, DMA_Busy, TX_Buf, RX_Buf,
                                   TX_Desc, RX_Desc, DMA_Length))
is

   --  No explicit Refined_Global anywhere below: GNAT auto-derives a
   --  precise, minimal one per subprogram from its body. A hand-written
   --  Refined_Global must instead enumerate *every* constituent of any
   --  state it touches (even ones the body doesn't actually use) --
   --  Mock_Regmap (host_test) relies on the same auto-derivation and
   --  proves cleanly; hand-writing it here fought that rule for no
   --  benefit, so it was dropped in favor of just fixing the *visible*
   --  Global aspects (below, in the spec) to name the real PAC registers
   --  each subprogram touches, alongside the abstract State.
   --
   --  Constituents of State (Refined_State above already associates
   --  each of these with it by name -- Part_Of would be redundant here;
   --  it is only for constituents declared in a package's private part,
   --  not its body, SPARK RM 7.2.6(5)). Each needs Async_Readers/
   --  Async_Writers named explicitly: bare Volatile defaults to *all
   --  four* external properties, which would silently also claim
   --  Effective_Reads/Effective_Writes that State's own External
   --  declaration (Async_Readers, Async_Writers only) doesn't have.
   --
   --  Polled path: no FIFO depth beyond one byte -- same depth-1
   --  bookkeeping ATmega328P.SPI keeps (Appendix B finding 2).
   Busy : Boolean := False
     with Volatile, Async_Readers, Async_Writers;

   --  DMA path: adapter-owned static buffers/descriptors (§6.6, §15.2),
   --  pinned at fixed addresses in ESP32-C3's internal DRAM (SOC_DRAM_LOW
   --  0x3FC8_0000 .. SOC_DRAM_HIGH 0x3FCE_0000) rather than left to the
   --  linker: GDMA descriptors must live in DMA-capable internal SRAM
   --  (the LINK registers below only carry the low 20 bits of a
   --  descriptor's address -- esp32c3_pac-gdma.ads), and SPARK does not
   --  allow reading 'Address as a plain expression outside an attribute
   --  *definition* clause (only assigning INTO one, which is what these
   --  four declarations do) -- so this is also the SPARK-legal way to
   --  get these buffers' addresses at all, not just the DMA-legal one.
   --  A real BSP would reserve this range via the linker script instead
   --  of a hardcoded literal; this is a spike placeholder for that.
   DMA_Scratch_Base : constant := 16#3FC8_0000#;
   TX_Buf_Addr      : constant := DMA_Scratch_Base;
   RX_Buf_Addr      : constant := DMA_Scratch_Base + 16#20#;  --  +32
   TX_Desc_Addr     : constant := DMA_Scratch_Base + 16#40#;  --  +64
   RX_Desc_Addr     : constant := DMA_Scratch_Base + 16#4C#;  --  +76

   TX_Buf : Byte_Array (1 .. Max_DMA_Bytes) := (others => 0)
     with Volatile, Async_Readers, Async_Writers,
          Address => System.Storage_Elements.To_Address (TX_Buf_Addr);
   RX_Buf : Byte_Array (1 .. Max_DMA_Bytes) := (others => 0)
     with Volatile, Async_Readers, Async_Writers,
          Address => System.Storage_Elements.To_Address (RX_Buf_Addr);
   --  No default value here (see the spec's note by the Abstract_State
   --  aspect): Start_Transfer fully overwrites both before every real
   --  transfer, so their pre-Enable content is genuinely irrelevant.
   TX_Desc : ESP32C3_PAC.GDMA.Descriptor
     with Volatile, Async_Readers, Async_Writers,
          Address => System.Storage_Elements.To_Address (TX_Desc_Addr);
   RX_Desc : ESP32C3_PAC.GDMA.Descriptor
     with Volatile, Async_Readers, Async_Writers,
          Address => System.Storage_Elements.To_Address (RX_Desc_Addr);
   DMA_Busy : Boolean := False
     with Volatile, Async_Readers, Async_Writers;
   DMA_Length : Natural := 0
     with Volatile, Async_Readers, Async_Writers;

   ----------------------------------------------------------------------

   procedure Enable (Cfg : Config := (others => <>)) is
      N    : constant Unsigned_32 := Unsigned_32 (Cfg.Divisor - 1);
      H    : constant Unsigned_32 := N / 2;
      User : Unsigned_32 :=
        SPI_USER_DOUTDIN or SPI_USER_USR_MOSI or SPI_USER_USR_MISO;
   begin
      SPI_CLOCK := Shift_Left (N, SPI_CLKCNT_N_SHIFT)
                 or Shift_Left (H, SPI_CLKCNT_H_SHIFT)
                 or Shift_Left (N, SPI_CLKCNT_L_SHIFT);
      if Cfg.Mode = 1 or Cfg.Mode = 3 then
         User := User or SPI_USER_CK_OUT_EDGE;    --  CPHA
      end if;
      SPI_USER := User;
      SPI_MISC := (if Cfg.Mode = 2 or Cfg.Mode = 3
                   then SPI_MISC_CK_IDLE_EDGE else 0);  --  CPOL
      SPI_DMA_CONF := 0;
      Busy       := False;
      DMA_Busy   := False;
      DMA_Length := 0;
   end Enable;

   procedure Disable is
   begin
      SPI_DMA_CONF := 0;
      Busy     := False;
      DMA_Busy := False;
   end Disable;

   ----------------------------------------------------------------------
   --  1. Polled byte-at-a-time data phase.
   --
   --  Every function/procedure below that touches a volatile (External)
   --  object reads it alone into a local constant first, then computes
   --  with that ordinary local -- SPARK requires a volatile read to be
   --  the whole right-hand side of an assignment/declaration, not
   --  combined with other operators in the same expression (SPARK RM
   --  7.1.3(9)); ATmega328P.SPI's Can_Pop/Pop combine such reads
   --  directly and would hit the same rule if ever run through
   --  gnatprove (which, per every "not cross-built" note in this repo,
   --  it never has been).

   function Can_Push return Boolean is
      B : constant Boolean := Busy;
   begin
      return not B;
   end Can_Push;

   procedure Push (Data : Machine.Byte;
                   Status : in out Machine.SPI.Bus_Status) is
   begin
      if Status /= Machine.SPI.Ok then
         return;                              --  chained: skip if pending
      end if;
      Busy        := True;
      SPI_MS_DLEN := 7;                        --  8 bits - 1
      SPI_W0      := Unsigned_32 (Data);
      SPI_CMD     := SPI_CMD_USR;              --  starts the transaction
   end Push;

   function Can_Pop return Boolean is
      B   : constant Boolean := Busy;
      Cmd : constant Unsigned_32 := SPI_CMD;
   begin
      return B and then (Cmd and SPI_CMD_USR) = 0;
   end Can_Pop;

   procedure Pop (Data : out Machine.Byte;
                  Status : in out Machine.SPI.Bus_Status) is
      W0 : Unsigned_32;
   begin
      Data := 0;
      if Status /= Machine.SPI.Ok then
         return;                              --  chained: skip if pending
      end if;
      W0   := SPI_W0;
      Data := Machine.Byte (W0 and 16#FF#);
      Busy := False;
   end Pop;

   ----------------------------------------------------------------------
   --  2. Block-transfer DMA path.

   procedure Start_Transfer (TX     : Byte_Array;
                             Length : Positive;
                             Status : in out Machine.SPI.Transaction_Status)
   is
      Conf     : Unsigned_32;
      Busy_Now : constant Boolean := DMA_Busy;
   begin
      if Status /= Machine.SPI.Ok then
         return;                              --  chained: skip if pending
      end if;
      if Busy_Now or else Length > Max_DMA_Bytes
        or else Length > TX'Length
      then
         Status := Machine.SPI.Other_Error;
         return;
      end if;

      TX_Buf (1 .. Length) := TX (TX'First .. TX'First + Length - 1);
      RX_Buf     := (others => 0);
      DMA_Length := Length;

      TX_Desc := (Dw0    => (Buf_Size => Unsigned_32 (Length),
                            Length   => Unsigned_32 (Length),
                            Err_EOF  => False, Suc_EOF => True,
                            Owner    => DMA_Engine),
                 Buffer => Unsigned_32 (TX_Buf_Addr),
                 Next   => 0);
      RX_Desc := (Dw0    => (Buf_Size => Unsigned_32 (Max_DMA_Bytes),
                            Length   => 0,
                            Err_EOF  => False, Suc_EOF => True,
                            Owner    => DMA_Engine),
                 Buffer => Unsigned_32 (RX_Buf_Addr),
                 Next   => 0);

      SPI_MS_DLEN := Unsigned_32 (Length * 8 - 1);
      Conf        := SPI_DMA_CONF;
      SPI_DMA_CONF := Conf or SPI_DMA_TX_ENA or SPI_DMA_RX_ENA;

      GDMA_OUT_LINK_CH0 :=
        (Unsigned_32 (TX_Desc_Addr) and GDMA_OUTLINK_ADDR_MASK)
          or GDMA_OUTLINK_START_CH0;
      GDMA_IN_LINK_CH0  :=
        (Unsigned_32 (RX_Desc_Addr) and GDMA_INLINK_ADDR_MASK)
          or GDMA_INLINK_START_CH0;

      SPI_DMA_INT_CLR := SPI_TRANS_DONE;        --  clear any stale status
      SPI_CMD         := SPI_CMD_USR;           --  kick the transaction

      DMA_Busy := True;
   end Start_Transfer;

   procedure Cancel_Transfer (Status : in out Machine.SPI.Transaction_Status)
   is
      pragma Unreferenced (Status);   --  never fails in this curated subset
      Conf : constant Unsigned_32 := SPI_DMA_CONF;
   begin
      GDMA_OUT_LINK_CH0 := GDMA_OUTLINK_STOP_CH0;
      GDMA_IN_LINK_CH0  := GDMA_INLINK_STOP_CH0;
      SPI_DMA_CONF := Conf and not (SPI_DMA_TX_ENA or SPI_DMA_RX_ENA);
      DMA_Busy := False;
   end Cancel_Transfer;

   procedure Read_Response (Into : out Byte_Array; Last : out Natural) is
      Length_Now : constant Natural := DMA_Length;
      N          : constant Natural := Natural'Min (Into'Length, Length_Now);
   begin
      Into := (others => 0);
      for I in 1 .. N loop
         Into (Into'First + I - 1) := RX_Buf (I);
      end loop;
      Last := Into'First + N - 1;
   end Read_Response;

   procedure Handle_DMA_Interrupt (Status : out Machine.SPI.Transaction_Status)
   is
      Raw : constant Unsigned_32 := SPI_DMA_INT_RAW;
   begin
      if (Raw and SPI_TRANS_DONE) /= 0 then
         declare
            Conf : constant Unsigned_32 := SPI_DMA_CONF;
         begin
            SPI_DMA_INT_CLR := SPI_TRANS_DONE;
            SPI_DMA_CONF := Conf and not (SPI_DMA_TX_ENA or SPI_DMA_RX_ENA);
         end;
         DMA_Busy := False;
         Status   := Machine.SPI.Ok;
      else
         Status := Machine.SPI.Other_Error;   --  spurious call: nothing to ack
      end if;
   end Handle_DMA_Interrupt;

end ESP32C3.SPI2;
