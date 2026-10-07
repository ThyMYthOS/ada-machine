--  rp2040-i2c0.ads -- the L2 I2C of spike 1 (Appendix A), plus Global/Post contracts added
--  beyond the literal excerpt (§6.6/§7.1: the chained skip-semantics
--  postcondition is the one contract worth stating uniformly at every
--  layer, and Global documents exactly which registers each operation
--  touches).
with Machine, Machine.I2C;
use type Machine.I2C.Bus_Status;  --  for the Post contracts' "="/"/="
use type Machine.Byte;            --  for Pop's postcondition ("Data = 0")
with RP2040_PAC.I2C0, RP2040_PAC.Resets, RP2040_PAC.IO_Bank0, RP2040_PAC.Pads_Bank0;

package RP2040.I2C0
  with Preelaborate, SPARK_Mode
is
   --  Configuration: deliberately RP2040-specific (D8) -- pins, pad
   --  options, bus speed. Not part of the portable contract.
   type Config is record
      Baud_Hz : Positive range 1 .. 1_000_000 := 100_000;
      SDA_Pin : Pin_Id := 4;
      SCL_Pin : Pin_Id := 5;
      --  ... pull-ups, slew, RP2040 pad controls
   end record;

   --  Pins/Pads: In_Out, not Output (TODO #8) -- they are whole-array
   --  Globals but Enable only writes the two elements at SDA_Pin/SCL_Pin,
   --  so Output's "the whole array is (re)written" claim would overclaim.
   procedure Enable  (Cfg : Config := (others => <>))
     with Global => (In_Out => (RP2040_PAC.Resets.RESET,
                                RP2040_PAC.IO_Bank0.Pins,
                                RP2040_PAC.Pads_Bank0.Pads),
                     Input  => RP2040_PAC.Resets.RESET_DONE,
                     Output => (RP2040_PAC.I2C0.IC_ENABLE,
                                RP2040_PAC.I2C0.IC_CON,
                                RP2040_PAC.I2C0.IC_FS_SCL_HCNT,
                                RP2040_PAC.I2C0.IC_FS_SCL_LCNT));
   procedure Disable
     with Global => (Output => RP2040_PAC.I2C0.IC_ENABLE);
   --  Writes IC_ENABLE too: DW_apb_i2c only accepts IC_TAR while the
   --  controller is disabled, so Set_Target disables, writes, re-enables.
   procedure Set_Target (Address : Machine.I2C.Address_7_Bit)
     with Global => (Output => (RP2040_PAC.I2C0.IC_TAR,
                                RP2040_PAC.I2C0.IC_ENABLE));

   --  Never-blocking data phase over the DW_apb_i2c command FIFO;
   --  Stop => True sets the STOP bit on that FIFO entry. Volatile_Function
   --  on Can_Push/Can_Pop: they read hardware state, so two textually-
   --  identical calls need not agree (SPARK RM 7.1.3(9)); no
   --  "Pre => Can_Push" on the procedures below for the same reason a
   --  volatile-function call in a contract expression is itself an
   --  interfering context SPARK rejects -- Can_Push is the caller's own
   --  check before calling.
   function  Can_Push return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => RP2040_PAC.I2C0.IC_STATUS);

   procedure Push_Write (Data : Machine.Byte; Stop : Boolean;
                         Status : in out Machine.I2C.Bus_Status)
     with Inline_Always,
          Global => (Input  => (RP2040_PAC.I2C0.IC_RAW_INTR_STAT,
                                RP2040_PAC.I2C0.IC_TX_ABRT_SOURCE,
                                RP2040_PAC.I2C0.IC_CLR_TX_ABRT),
                     In_Out => RP2040_PAC.I2C0.IC_DATA_CMD),
                    --  In_Out, not Output: the write is skipped on the
                    --  chained/aborted early-return paths.
          Post => (if Status'Old /= Machine.I2C.Ok
                   then Status = Status'Old);      --  §7.1 rule 1: skip if pending

   procedure Push_Read_Request (Stop : Boolean;
                                Status : in out Machine.I2C.Bus_Status)
     with Inline_Always,
          Global => (Input  => (RP2040_PAC.I2C0.IC_RAW_INTR_STAT,
                                RP2040_PAC.I2C0.IC_TX_ABRT_SOURCE,
                                RP2040_PAC.I2C0.IC_CLR_TX_ABRT),
                     In_Out => RP2040_PAC.I2C0.IC_DATA_CMD),
                    --  In_Out, not Output: the write is skipped on the
                    --  chained/aborted early-return paths.
          Post => (if Status'Old /= Machine.I2C.Ok
                   then Status = Status'Old);

   function  Can_Pop return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => RP2040_PAC.I2C0.IC_STATUS);

   procedure Pop (Data : out Machine.Byte; Status : in out Machine.I2C.Bus_Status)
     with Inline_Always,
          Global => (Input => (RP2040_PAC.I2C0.IC_RAW_INTR_STAT,
                                RP2040_PAC.I2C0.IC_TX_ABRT_SOURCE,
                                RP2040_PAC.I2C0.IC_CLR_TX_ABRT,
                                RP2040_PAC.I2C0.IC_DATA_CMD)),
          Post => (if Status'Old /= Machine.I2C.Ok
                   then Status = Status'Old and Data = 0);

   --  Event plumbing for L3b (§6.2), unused in this blocking spike:
   --  Enable_Event / Disable_Event / Pending_Event / Clear_Event ...
end RP2040.I2C0;
