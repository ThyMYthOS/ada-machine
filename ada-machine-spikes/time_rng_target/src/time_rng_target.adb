package body Time_RNG_Target
  with SPARK_Mode
is
   use type Machine.Byte, Machine.I2C.Bus_Status, Machine.RNG.Rng_Status,
            Rng.Word, Clock.Ticks;

   Reg_Count    : constant := 9;               --  registers 0x00 .. 0x08
   Reg_Epoch_Lo : constant Machine.Byte := 1;   --  first epoch byte's register address

   subtype Reg_Index is Machine.Byte range 0 .. Reg_Count - 1;

   function Snap_Index (R : Reg_Index) return Positive is (Integer (R) + 1);
   --  Byte_Array is Positive-indexed (machine.ads); registers are
   --  0-based, so the snapshot/write buffers below run one past them.

   type Phase is (Idle, Serving_Read, Awaiting_Reg_Addr, Collecting_Write);

   Cur_Phase    : Phase := Idle;
   Reg_Ptr      : Reg_Index := 0;
   Serve_Ptr    : Reg_Index := 0;
   Snapshot     : Machine.Byte_Array (1 .. Reg_Count) := (others => 0);
   Write_Buf    : Machine.Byte_Array (1 .. 4) := (others => 0);
   Write_Filled : Natural range 0 .. 4 := 0;
   Epoch_Base   : Epoch_Seconds := 0;

   --  §6.5: seconds elapsed since Clock was enabled, truncated -- exact
   --  when Clock.Ticks_Per_Second = 1 (STM32G474.Clock's choice), a
   --  sub-second rounding error otherwise. Volatile_Function: reads
   --  Clock.Now (RM 7.1.3(9)); the read is into a local first since a
   --  volatile-function call must be the whole right-hand side, not
   --  combined with "/" (same rule RP2040.I2C0's Check_Abort documents).
   function Elapsed_Seconds return Epoch_Seconds
     with Volatile_Function
   is
      Now_Val : constant Clock.Ticks := Clock.Now;
   begin
      return Epoch_Seconds (Now_Val / Clock.Ticks (Clock.Ticks_Per_Second));
   end Elapsed_Seconds;

   function Current_Epoch_Seconds return Epoch_Seconds is
      Elapsed : constant Epoch_Seconds := Elapsed_Seconds;
   begin
      return Epoch_Base + Elapsed;
   end Current_Epoch_Seconds;

   --  Latch a consistent status/epoch/rng snapshot at the moment a
   --  read-direction transaction starts (see the spec's header comment
   --  on why this must be atomic w.r.t. the multi-byte burst read that
   --  follows). A not-Ok RNG health status still leaves a defined value
   --  (zeros) rather than garbage -- §7.1 rule 1's spirit, even though
   --  this isn't itself a chained operation.
   procedure Latch_Snapshot is
      Epoch  : constant Epoch_Seconds := Current_Epoch_Seconds;
      Word   : Rng.Word := 0;
      Rng_St : Machine.RNG.Rng_Status := Machine.RNG.Ok;
   begin
      Snapshot (Snap_Index (0)) := Version;

      --  Byte-slice via div/mod (not Shift_Right/"and"): predefined for
      --  any modular type, unlike the shift/logical operations, which
      --  Ada only guarantees for Interfaces.Unsigned_* -- Epoch_Seconds
      --  and Rng.Word are both plain user/formal modular types.
      Snapshot (Snap_Index (1)) := Machine.Byte (Epoch / 2 ** 24 mod 256);
      Snapshot (Snap_Index (2)) := Machine.Byte (Epoch / 2 ** 16 mod 256);
      Snapshot (Snap_Index (3)) := Machine.Byte (Epoch / 2 ** 8 mod 256);
      Snapshot (Snap_Index (4)) := Machine.Byte (Epoch mod 256);

      declare
         Rng_Ready : constant Boolean := Rng.Is_Ready;
         --  Read into a local first: a volatile-function call must be
         --  the whole right-hand side, not the condition of an if
         --  (SPARK RM 7.1.3(9)) -- same discipline as RP2040.I2C0's
         --  Check_Abort reading IC_RAW_INTR_STAT before branching on it.
      begin
         if Rng_Ready then
            Rng.Get_Word (Word, Rng_St);
         else
            Rng_St := Machine.RNG.Other_Error;
         end if;
      end;

      if Rng_St = Machine.RNG.Ok then
         Snapshot (Snap_Index (5)) := Machine.Byte (Word / 2 ** 24 mod 256);
         Snapshot (Snap_Index (6)) := Machine.Byte (Word / 2 ** 16 mod 256);
         Snapshot (Snap_Index (7)) := Machine.Byte (Word / 2 ** 8 mod 256);
         Snapshot (Snap_Index (8)) := Machine.Byte (Word mod 256);
      else
         Snapshot (Snap_Index (5) .. Snap_Index (8)) := (0, 0, 0, 0);
      end if;
   end Latch_Snapshot;

   --  Only called with Write_Filled = 4 and Reg_Ptr = Reg_Epoch_Lo (the
   --  one well-formed write this responder acts on -- see the spec's
   --  header comment on why any other write is silently discarded).
   procedure Commit_Epoch is
      Written : Epoch_Seconds := 0;
      Elapsed : Epoch_Seconds;
   begin
      for I in Write_Buf'Range loop
         Written := Written * 256 + Epoch_Seconds (Write_Buf (I));
      end loop;
      Elapsed    := Elapsed_Seconds;
      Epoch_Base := Written - Elapsed;
   end Commit_Epoch;

   --  Every Bus.* formal below is bound to a Volatile_Function or a
   --  procedure touching volatile hardware state; each call is read
   --  into a local first (never combined with another operator or used
   --  directly as an if-condition) -- SPARK RM 7.1.3(9), the same
   --  discipline RP2040.I2C0's Check_Abort documents.
   procedure Poll is
      Addr_Matched : constant Boolean := Bus.Is_Address_Matched;
   begin
      if Addr_Matched then
         Bus.Ack_Address;
         declare
            Read_From_Master : constant Boolean := Bus.Is_Read_From_Master;
         begin
            if Read_From_Master then
               Latch_Snapshot;
               Serve_Ptr := Reg_Ptr;
               Cur_Phase := Serving_Read;
            else
               Write_Filled := 0;
               Cur_Phase := Awaiting_Reg_Addr;
            end if;
         end;
      end if;

      case Cur_Phase is
         when Serving_Read =>
            declare
               Push_Ready : constant Boolean := Bus.Can_Push;
            begin
               if Push_Ready then
                  declare
                     St : Machine.I2C.Bus_Status := Machine.I2C.Ok;
                  begin
                     Bus.Push (Snapshot (Snap_Index (Serve_Ptr)), St);
                     if St = Machine.I2C.Ok and then Serve_Ptr < Reg_Index'Last then
                        Serve_Ptr := Serve_Ptr + 1;
                     end if;
                  end;
               end if;
            end;

         when Awaiting_Reg_Addr =>
            declare
               Pop_Ready : constant Boolean := Bus.Can_Pop;
            begin
               if Pop_Ready then
                  declare
                     Data : Machine.Byte;
                     St   : Machine.I2C.Bus_Status := Machine.I2C.Ok;
                  begin
                     Bus.Pop (Data, St);
                     if St = Machine.I2C.Ok then
                        Reg_Ptr   := (if Data > Reg_Index'Last then Reg_Index'Last
                                      else Reg_Index (Data));
                        Cur_Phase := Collecting_Write;
                     end if;
                  end;
               end if;
            end;

         when Collecting_Write =>
            declare
               Pop_Ready : constant Boolean := Bus.Can_Pop;
            begin
               if Pop_Ready then
                  declare
                     Data : Machine.Byte;
                     St   : Machine.I2C.Bus_Status := Machine.I2C.Ok;
                  begin
                     Bus.Pop (Data, St);
                     if St = Machine.I2C.Ok and then Write_Filled < 4 then
                        Write_Filled := Write_Filled + 1;
                        Write_Buf (Write_Filled) := Data;
                     end if;
                  end;
               end if;
            end;

         when Idle => null;
      end case;

      declare
         Stopped : constant Boolean := Bus.Is_Stop;
      begin
         if Stopped then
            Bus.Clear_Stop;
            if Cur_Phase = Collecting_Write and then Reg_Ptr = Reg_Epoch_Lo
               and then Write_Filled = 4
            then
               Commit_Epoch;
            end if;
            Cur_Phase := Idle;
         end if;
      end;
   end Poll;

end Time_RNG_Target;
