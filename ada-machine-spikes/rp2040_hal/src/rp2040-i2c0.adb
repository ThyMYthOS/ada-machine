with RP2040_PAC.I2C0;       use RP2040_PAC.I2C0;
with RP2040_PAC.Resets;     use RP2040_PAC.Resets;
with RP2040_PAC.IO_Bank0;   use RP2040_PAC.IO_Bank0;
with RP2040_PAC.Pads_Bank0; use RP2040_PAC.Pads_Bank0;
with Interfaces; use Interfaces;

package body RP2040.I2C0
  with SPARK_Mode
is

   use Machine.I2C;

   --  Simplified: real pico-sdk-style calibration also accounts for
   --  SDA TX hold time and standard/fast-mode minimum period tables;
   --  this spike keeps the 3:5 low:high split that already matches
   --  I2C's asymmetric duty-cycle requirement closely enough to
   --  demonstrate the wiring (D8: bus timing is native configuration,
   --  not part of the portable contract).
   Sys_Clock_Hz : constant := 125_000_000;

   function Route (Address : Machine.I2C.Address_7_Bit) return Unsigned_32 is
     (Unsigned_32 (Address));

   procedure Enable (Cfg : Config := (others => <>)) is
      Period : constant Unsigned_32 := Sys_Clock_Hz / Unsigned_32 (Cfg.Baud_Hz);
      Lcnt   : constant Unsigned_32 := Period * 3 / 5;
      Hcnt   : constant Unsigned_32 := Period - Lcnt;
      Wanted : constant Unsigned_32 :=
        RESET_I2C0 or RESET_IO_BANK0 or RESET_PADS_BANK0;
      Reset_Now : Unsigned_32;
      Done_Now  : Unsigned_32;
   begin
      --  Bring I2C0, IO_BANK0 and PADS_BANK0 out of reset (idempotent).
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

      --  IC_CON must be written while disabled.
      IC_ENABLE := 0;
      IC_CON := IC_CON_MASTER_MODE or IC_CON_SPEED_FAST or
                IC_CON_RESTART_EN or IC_CON_SLAVE_DISABLE;
      IC_FS_SCL_HCNT := Hcnt;
      IC_FS_SCL_LCNT := Lcnt;

      --  Route SDA/SCL pins through the I2C peripheral, Schmitt + weak
      --  pull-up on (I2C is open-drain; RP2040 supplies internal pulls
      --  for bring-up, external pulls are still recommended in prod).
      --  Fully qualified: both IO_Bank0 and Pads_Bank0 are "use"d above
      --  and both declare Pin_Index, so the bare name is ambiguous --
      --  same fix as RP2040.GPIO's Configure.
      Pins (RP2040_PAC.IO_Bank0.Pin_Index (Cfg.SDA_Pin)).Ctrl := FUNCSEL_I2C;
      Pins (RP2040_PAC.IO_Bank0.Pin_Index (Cfg.SCL_Pin)).Ctrl := FUNCSEL_I2C;
      Pads (RP2040_PAC.Pads_Bank0.Pin_Index (Cfg.SDA_Pin)) :=
        PAD_IE or PAD_SCHMITT or PAD_PUE;
      Pads (RP2040_PAC.Pads_Bank0.Pin_Index (Cfg.SCL_Pin)) :=
        PAD_IE or PAD_SCHMITT or PAD_PUE;

      IC_ENABLE := IC_ENABLE_ENABLE;
   end Enable;

   procedure Disable is
   begin
      IC_ENABLE := 0;
   end Disable;

   procedure Set_Target (Address : Machine.I2C.Address_7_Bit) is
   begin
      --  IC_TAR is only writable while the controller is disabled (the
      --  RP2040 build of DW_apb_i2c has no dynamic TAR update); written
      --  while enabled, the write is lost and the bus keeps addressing the
      --  reset target. Same sequence as pico-sdk's i2c_write/read_blocking.
      IC_ENABLE := 0;
      IC_TAR    := Route (Address);
      IC_ENABLE := IC_ENABLE_ENABLE;
   end Set_Target;

   --  A pending, unread abort blocks further FIFO use until cleared
   --  (DW_apb_i2c requires reading IC_CLR_TX_ABRT to resume) -- this is
   --  the "never blocks, detect on the next poll" shape §B.4 finding 5
   --  flags as needing validation against a second controller.
   function Map_Abort (Source : Unsigned_32) return Bus_Status is
     (if (Source and ABRT_7B_ADDR_NOACK) /= 0 then Nack_Address
      elsif (Source and ABRT_TXDATA_NOACK) /= 0 then Nack_Data
      elsif (Source and ABRT_ARB_LOST) /= 0 then Arbitration_Lost
      else Other_Error);

   --  A procedure, not a function: SPARK forbids functions with an
   --  "in out" parameter (a function must be free of side effects on its
   --  parameters), so this reports its result via "Aborted" instead.
   procedure Check_Abort (Status : in out Bus_Status; Aborted : out Boolean)
   is
      Dummy     : Unsigned_32;
      Raw_Intr  : constant Unsigned_32 := IC_RAW_INTR_STAT;
      Abrt_Src  : Unsigned_32;
   begin
      Aborted := False;
      if (Raw_Intr and RAW_INTR_TX_ABRT) /= 0 then
         Abrt_Src := IC_TX_ABRT_SOURCE;     --  read alone (SPARK RM 7.1.3(9))
         Status   := Map_Abort (Abrt_Src);
         Dummy    := IC_CLR_TX_ABRT;        --  read-to-clear, unlatches
         Aborted  := True;
      end if;
   end Check_Abort;

   function Can_Push return Boolean is
      Status_Now : constant Unsigned_32 := IC_STATUS;
   begin
      return (Status_Now and STATUS_TFNF) /= 0;
   end Can_Push;

   procedure Push_Write (Data : Machine.Byte; Stop : Boolean;
                         Status : in out Machine.I2C.Bus_Status)
   is
      Cmd     : Unsigned_32 := Unsigned_32 (Data);
      Aborted : Boolean;
   begin
      if Status /= Ok then
         return;                              --  chained: skip if pending
      end if;
      Check_Abort (Status, Aborted);
      if Aborted then
         return;
      end if;
      if Stop then
         Cmd := Cmd or IC_DATA_CMD_STOP;
      end if;
      IC_DATA_CMD := Cmd;
   end Push_Write;

   procedure Push_Read_Request (Stop : Boolean;
                                Status : in out Machine.I2C.Bus_Status)
   is
      Cmd     : Unsigned_32 := IC_DATA_CMD_CMD_READ;
      Aborted : Boolean;
   begin
      if Status /= Ok then
         return;                              --  chained: skip if pending
      end if;
      Check_Abort (Status, Aborted);
      if Aborted then
         return;
      end if;
      if Stop then
         Cmd := Cmd or IC_DATA_CMD_STOP;
      end if;
      IC_DATA_CMD := Cmd;
   end Push_Read_Request;

   function Can_Pop return Boolean is
      Status_Now : constant Unsigned_32 := IC_STATUS;
   begin
      return (Status_Now and STATUS_RFNE) /= 0;
   end Can_Pop;

   procedure Pop (Data : out Machine.Byte; Status : in out Machine.I2C.Bus_Status)
   is
      Aborted : Boolean;
      Cmd     : Unsigned_32;
   begin
      Data := 0;
      if Status /= Ok then
         return;                              --  chained: skip if pending
      end if;
      Check_Abort (Status, Aborted);
      if Aborted then
         return;
      end if;
      Cmd  := IC_DATA_CMD;
      Data := Machine.Byte (Cmd and 16#FF#);
   end Pop;

end RP2040.I2C0;
