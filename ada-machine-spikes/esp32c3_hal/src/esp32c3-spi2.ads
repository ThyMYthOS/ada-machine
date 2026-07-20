--  esp32c3-spi2.ads -- GP-SPI2, two data-phase shapes over the same
--  hardware (§8.2: DMA stays an <mcu>_hal implementation detail, the
--  portable adapter shape doesn't change):
--
--   1. A polled, byte-at-a-time Machine.SPI.Generic_Master conformance
--      (Can_Push/Push/Can_Pop/Pop) -- the same shape ATmega328P.SPI and
--      RP2040.I2C0 export, one SPI_CMD/USR transaction per byte.
--   2. A block-transfer DMA path (Start_Transfer/Cancel_Transfer/
--      Read_Response/Handle_DMA_Interrupt) matching
--      Machine.Tasking.Generic_DMA_SPI's three formals by construction --
--      this crate does not depend on machine_tasking (L2 stays unaware
--      of L3c; board wiring bridges the two, exactly as avr_board.ads
--      bridges ATmega328P.SPI's ISR to Machine.Async.SPI.On_Interrupt).
--
--  "Busy" bookkeeping for the polled path mirrors ATmega328P.SPI's own
--  reasoning verbatim (Appendix B finding 2: SPI_CMD's USR bit alone
--  doesn't distinguish "never started" from "already collected") -- it
--  is External abstract state, touched by both mainline code and (for
--  the DMA path) the application's attached interrupt handler.
with Machine; use Machine;
with Machine.SPI;
with ESP32C3_PAC.SPI2, ESP32C3_PAC.GDMA;
use type Machine.SPI.Bus_Status, Machine.SPI.Transaction_Status;

package ESP32C3.SPI2
  with Preelaborate, SPARK_Mode,
       Abstract_State => (State with External => (Async_Readers, Async_Writers))
       --  No "Initializes => State": TX_Desc/RX_Desc's real content is
       --  meaningless until Start_Transfer first sets it, and giving
       --  them a non-scalar default aggregate while also carrying an
       --  Address clause hits a Preelaborate restriction (a record
       --  aggregate's field-by-field store to a fixed address needs
       --  elaboration code, which Preelaborate disallows) -- so, unlike
       --  Busy/DMA_Busy (simple Boolean defaults), they are left
       --  genuinely uninitialized until Enable/Start_Transfer runs,
       --  which every caller (Board wiring, main.adb) already does
       --  before touching Env_Sensor.
is

   type Config is record
      Divisor : Positive range 2 .. 64 := 4;  --  SPI clock = APB clock / Divisor
      Mode    : Natural range 0 .. 3 := 0;    --  CPOL/CPHA (BME280: 0 or 3)
   end record;

   --  Native configuration (D8): programs SPI_CLOCK/SPI_USER's clock-edge
   --  bits. GPIO-matrix/IOMUX pin routing for SCLK/MOSI/MISO is a board
   --  property (which physical pins) and is out of this curated subset's
   --  scope -- ESP32-C3's IOMUX default routing for SPI2 (GPIO6=SCLK,
   --  GPIO7=MOSI, GPIO2=MISO) is assumed; a board using different pins
   --  needs the GPIO matrix's FUNCx_OUT_SEL_CFG registers programmed too
   --  (not modeled in esp32c3_pac's curated register subset, §9 rule 1).
   --  In_Out, not Output, throughout this spec: Output would claim the
   --  *entire* named state/register is freshly (re)written with a value
   --  independent of anything before the call. None of these ever touch
   --  every constituent of State in one go (Enable, say, never rewrites
   --  the DMA descriptors), and every PAC register here is itself
   --  External (Async_Readers/Writers) -- both are real, provable
   --  reasons Output overclaims and In_Out is what actually holds.
   procedure Enable  (Cfg : Config := (others => <>))
     with Global => (In_Out => (State, ESP32C3_PAC.SPI2.SPI_CLOCK,
                                ESP32C3_PAC.SPI2.SPI_USER,
                                ESP32C3_PAC.SPI2.SPI_MISC,
                                ESP32C3_PAC.SPI2.SPI_DMA_CONF));
   procedure Disable
     with Global => (In_Out => (State, ESP32C3_PAC.SPI2.SPI_DMA_CONF));

   --  1. Polled data phase (§6.2), one byte per SPI_CMD/USR transaction.
   --  Volatile_Function on both predicates: they read hardware/External
   --  state, so two textually-identical calls need not agree (SPARK RM
   --  7.1.3(9)).
   function  Can_Push return Boolean
     with Inline_Always, Volatile_Function, Global => (Input => State);
   procedure Push (Data : Machine.Byte;
                  Status : in out Machine.SPI.Bus_Status)
     --  No "Pre => Can_Push": a volatile-function call in a contract
     --  expression is itself an interfering context SPARK rejects (RM
     --  7.1.3(9)) -- ATmega328P.SPI's Push has the same Pre and would
     --  hit the same rule if ever gnatproved. Can_Push is the caller's
     --  own check before calling, as Machine.Async.SPI.Start_Exchange
     --  already does ("if Port.Can_Push then Port.Push (...)").
     with Inline_Always,
          Global => (In_Out => (State, ESP32C3_PAC.SPI2.SPI_MS_DLEN,
                                ESP32C3_PAC.SPI2.SPI_W0,
                                ESP32C3_PAC.SPI2.SPI_CMD)),
          Post   => (if Status'Old /= Machine.SPI.Ok
                     then Status = Status'Old);           --  §7.1 rule 1
   function  Can_Pop return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => (State, ESP32C3_PAC.SPI2.SPI_CMD));
   procedure Pop (Data : out Machine.Byte;
                 Status : in out Machine.SPI.Bus_Status)
     with Inline_Always,
          Global => (Input => ESP32C3_PAC.SPI2.SPI_W0, In_Out => State),
          Post   => (if Status'Old /= Machine.SPI.Ok
                     then Status = Status'Old and Data = 0);

   --  2. Block-transfer DMA path (§8.2, §15.2), matching
   --  Machine.Tasking.Generic_DMA_SPI's three formals.
   Max_DMA_Bytes : constant := 32;    --  adapter-owned static buffers, no
                                      --  access types cross this boundary

   procedure Start_Transfer (TX     : Byte_Array;
                             Length : Positive;
                             Status : in out Machine.SPI.Transaction_Status)
     with Global => (In_Out => (State, ESP32C3_PAC.SPI2.SPI_DMA_CONF,
                                ESP32C3_PAC.SPI2.SPI_MS_DLEN,
                                ESP32C3_PAC.SPI2.SPI_CMD,
                                ESP32C3_PAC.SPI2.SPI_DMA_INT_CLR,
                                ESP32C3_PAC.GDMA.GDMA_OUT_LINK_CH0,
                                ESP32C3_PAC.GDMA.GDMA_IN_LINK_CH0)),
          Post   => (if Status'Old /= Machine.SPI.Ok
                     then Status = Status'Old);           --  §7.1 rule 1

   procedure Cancel_Transfer (Status : in out Machine.SPI.Transaction_Status)
     with Global => (In_Out => (State, ESP32C3_PAC.GDMA.GDMA_OUT_LINK_CH0,
                                ESP32C3_PAC.GDMA.GDMA_IN_LINK_CH0,
                                ESP32C3_PAC.SPI2.SPI_DMA_CONF));
                    --  idempotent: safe to call even if nothing is in flight

   procedure Read_Response (Into : out Byte_Array; Last : out Natural)
     with Global => (Input => State);

   --  Call from the application's attached DMA-done handler (D5): acks
   --  the hardware interrupt (clears SPI_DMA_INT_RAW/TRANS_DONE) and
   --  reports the outcome the board wiring passes on to
   --  Machine.Tasking.Generic_DMA_SPI's Signal_Complete.
   procedure Handle_DMA_Interrupt (Status : out Machine.SPI.Transaction_Status)
     with Global => (Input  => ESP32C3_PAC.SPI2.SPI_DMA_INT_RAW,
                    In_Out => (State, ESP32C3_PAC.SPI2.SPI_DMA_CONF,
                               ESP32C3_PAC.SPI2.SPI_DMA_INT_CLR));

end ESP32C3.SPI2;
