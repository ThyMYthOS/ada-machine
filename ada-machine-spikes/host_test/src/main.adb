--  host_test main: instantiates the portable BME280 driver (the bme280 crate, §11)
--  over Mock_Regmap/Mock_Delays and checks its output against the
--  well-known Bosch reference vector (dig_T1=27504 ... adc_T=519888 ->
--  25.08 degC / 1006.53 hPa / 20.78 %RH), independently cross-checked
--  against the datasheet's double-precision reference formula before
--  being hardcoded as the expectation below.
with Ada.Text_IO;         use Ada.Text_IO;
with Ada.Command_Line;    use Ada.Command_Line;

with Machine.Regmap.Generic_Device;
with Machine.Blocking.Generic_Delays;
with Machine.Log;
with Mock_Regmap, Mock_Delays, Mock_Regmap_Bad_Id, Recording_Log_Sink;
with BME280;

--  Spike 4 (Appendix D): Time_RNG_Target over mocks for all three of its
--  formals -- the first target-mode I2C exercise in this repo, and the
--  first RNG one. Instantiating Machine.I2C.Generic_Target/
--  Machine.RNG.Generic_Source/Machine.Generic_Clock against Mock_*
--  below is the same "conformance check for free" idiom board.ads uses
--  for real HALs (§6.1), just applied to a mock.
with Interfaces;
with Machine.I2C.Generic_Target, Machine.RNG.Generic_Source, Machine.Generic_Clock;
with Mock_I2C_Target, Mock_RNG, Mock_Clock;
with Time_RNG_Target;

procedure Main
  with SPARK_Mode
is

   package Regs is new Machine.Regmap.Generic_Device
     (Write_Reg => Mock_Regmap.Write_Reg,
      Read_Regs => Mock_Regmap.Read_Regs);

   package Wait is new Machine.Blocking.Generic_Delays
     (Delay_Us => Mock_Delays.Delay_Us,
      Delay_Ms => Mock_Delays.Delay_Ms);

   package Sensor is new BME280 (Regs => Regs, Wait => Wait);

   --  A second instantiation over a register file that never answers
   --  the chip-id probe with 0x60, so BME280's Wrong_Chip_Id path runs
   --  and Recording_Log_Sink.Log_Event has something to record -- the
   --  logging formals double as test probes (§14.5).
   package Bad_Regs is new Machine.Regmap.Generic_Device
     (Write_Reg => Mock_Regmap_Bad_Id.Write_Reg,
      Read_Regs => Mock_Regmap_Bad_Id.Read_Regs);

   package Bad_Sensor is new BME280
     (Regs      => Bad_Regs,
      Wait      => Wait,
      Log_Event => Recording_Log_Sink.Log_Event);

   package Mock_I2C_Sig is new Machine.I2C.Generic_Target
     (Is_Address_Matched  => Mock_I2C_Target.Is_Address_Matched,
      Is_Read_From_Master => Mock_I2C_Target.Is_Read_From_Master,
      Ack_Address         => Mock_I2C_Target.Ack_Address,
      Can_Pop             => Mock_I2C_Target.Can_Pop,
      Pop                 => Mock_I2C_Target.Pop,
      Can_Push            => Mock_I2C_Target.Can_Push,
      Push                => Mock_I2C_Target.Push,
      Is_Stop             => Mock_I2C_Target.Is_Stop,
      Clear_Stop          => Mock_I2C_Target.Clear_Stop);

   package Mock_Rng_Sig is new Machine.RNG.Generic_Source
     (Word     => Interfaces.Unsigned_32,
      Is_Ready => Mock_RNG.Is_Ready,
      Get_Word => Mock_RNG.Get_Word);

   package Mock_Clock_Sig is new Machine.Generic_Clock
     (Ticks            => Mock_Clock.Ticks,
      Ticks_Per_Second => Mock_Clock.Ticks_Per_Second,
      Now              => Mock_Clock.Now);

   package Responder is new Time_RNG_Target
     (Bus => Mock_I2C_Sig, Rng => Mock_Rng_Sig, Clock => Mock_Clock_Sig);

   --  Generic-instance operators aren't use-visible by just naming the
   --  instance via dot notation (Ada visibility rule, not a mistake in
   --  Regs/Wait above) -- infix "=" on Sensor's types needs this:
   use type Sensor.Device_Status, Sensor.Celsius,
            Sensor.Hectopascal, Sensor.Percent_RH;
   use type Responder.Epoch_Seconds, Machine.Byte;

   Status : Sensor.Device_Status := Sensor.Ok;
   M      : Sensor.Measurement;
   Failed : Boolean := False;

   procedure Check (Name : String; Got, Want : String; Ok : Boolean) is
   begin
      Put_Line ((if Ok then "PASS  " else "FAIL  ") & Name &
                ": got " & Got & ", want " & Want);
      if not Ok then
         Failed := True;
      end if;
   end Check;

begin
   Sensor.Initialize (Status);
   Check ("Initialize", Status'Image, "OK", Status = Sensor.Ok);

   if Status = Sensor.Ok then
      Sensor.Configure (Status => Status);
      Check ("Configure", Status'Image, "OK", Status = Sensor.Ok);
   end if;

   if Status = Sensor.Ok then
      Sensor.Measure (M, Status);
      Check ("Measure", Status'Image, "OK", Status = Sensor.Ok);
   end if;

   if Status = Sensor.Ok then
      Check ("Temperature", M.Temperature'Image, "25.08",
             M.Temperature = 25.08);
      Check ("Pressure", M.Pressure'Image, "1006.53",
             M.Pressure = 1006.53);
      Check ("Humidity", M.Humidity'Image, "20.78",
             M.Humidity = 20.78);
   end if;

   Check ("Register writes observed", Mock_Regmap.Write_Count'Image,
          "> 0", Mock_Regmap.Write_Count > 0);

   --  Recording_Log_Sink as a test probe (§14.5): the Wrong_Chip_Id path
   --  must emit exactly one event, id 0x0001 (bme280.adb's Ev_Wrong_Id --
   --  not exported by the driver's spec, so this couples to that
   --  documented convention rather than a re-exported constant), with
   --  Arg = 0 (the bogus chip id Mock_Regmap_Bad_Id reads back).
   declare
      Bad_Status : Bad_Sensor.Device_Status := Bad_Sensor.Ok;
      use type Bad_Sensor.Device_Status,
               Machine.Log.Event_Id, Machine.Log.Arg;
   begin
      Bad_Sensor.Initialize (Bad_Status);
      Check ("Wrong_Chip_Id path taken", Bad_Status'Image, "WRONG_CHIP_ID",
             Bad_Status = Bad_Sensor.Wrong_Chip_Id);
      Check ("Log event recorded", Recording_Log_Sink.Count'Image, "1",
             Recording_Log_Sink.Count = 1);
      if Recording_Log_Sink.Count >= 1 then
         Check ("Log event id", Recording_Log_Sink.Event (1)'Image, "1",
                Recording_Log_Sink.Event (1) = 1);
         Check ("Log event arg", Recording_Log_Sink.Arg_At (1)'Image, "0",
                Recording_Log_Sink.Arg_At (1) = 0);
      end if;
   end;

   --  Time_RNG_Target (Appendix D): the register-file responder that
   --  makes the MCU an I2C *target* instead of a master -- the part of
   --  spike 4 with real risk, so it gets real scenarios instead of a
   --  smoke test. One shared Responder instance; each scenario ends
   --  with Simulate_Stop + one more Poll so the next one starts Idle.

   --  Scenario A: latch-on-read-start consistency. Change both the RNG
   --  word and the clock strictly *after* the transaction's first Poll
   --  call (the one that latches) and confirm every byte served in
   --  this transaction still reflects the pre-change snapshot -- the
   --  property the spec's header comment calls out as the reason to
   --  latch at all (a multi-byte burst read must not straddle a
   --  rollover or hand out two different random words mid-transfer).
   Mock_Clock.Set_Now (1000);
   Mock_RNG.Set_Next_Word (16#1122_3344#);
   Mock_I2C_Target.Reset;
   Mock_I2C_Target.Begin_Transaction (Read_Direction => True);
   Responder.Poll;                            --  address match + latch + byte 1
   Mock_RNG.Set_Next_Word (16#5566_7788#);     --  changed after the latch
   Mock_Clock.Set_Now (2000);                  --  changed after the latch
   for I in 2 .. 9 loop
      Responder.Poll;
   end loop;
   Check ("Latch: bytes served", Mock_I2C_Target.Pushed_Count'Image, "9",
          Mock_I2C_Target.Pushed_Count = 9);
   if Mock_I2C_Target.Pushed_Count = 9 then
      Check ("Latch: version byte", Mock_I2C_Target.Pushed_Byte (1)'Image, "1",
             Mock_I2C_Target.Pushed_Byte (1) = 1);
      Check ("Latch: epoch reflects pre-change 1000, not 2000 (byte 2)",
             Mock_I2C_Target.Pushed_Byte (4)'Image, "3",
             Mock_I2C_Target.Pushed_Byte (4) = 3);
      Check ("Latch: epoch reflects pre-change 1000, not 2000 (byte 3)",
             Mock_I2C_Target.Pushed_Byte (5)'Image, "232",
             Mock_I2C_Target.Pushed_Byte (5) = 232);
      Check ("Latch: RNG is the pre-change word, not the new one (byte 0)",
             Mock_I2C_Target.Pushed_Byte (6)'Image, "17",
             Mock_I2C_Target.Pushed_Byte (6) = 16#11#);
      Check ("Latch: RNG is the pre-change word, not the new one (byte 3)",
             Mock_I2C_Target.Pushed_Byte (9)'Image, "68",
             Mock_I2C_Target.Pushed_Byte (9) = 16#44#);
   end if;
   Mock_I2C_Target.Simulate_Stop;
   Responder.Poll;

   --  Scenario B: a write-then-repeated-START read uses the register
   --  pointer the write phase set, not register 0 -- the classic
   --  "write the address, repeated-START, read" idiom every I2C
   --  sensor uses, now exercised from the *device* side.
   Mock_RNG.Set_Next_Word (16#AABB_CCDD#);
   Mock_I2C_Target.Reset;
   Mock_I2C_Target.Begin_Transaction (Read_Direction => False);
   Responder.Poll;                            --  address match (write), ack
   Mock_I2C_Target.Feed_Byte (5);              --  register pointer = 0x05 (RNG)
   Responder.Poll;                            --  pops it: Reg_Ptr := 5
   Mock_I2C_Target.Begin_Transaction (Read_Direction => True);  --  repeated START
   Responder.Poll;                            --  latches, serves from reg 5
   Check ("Repeated-START: one byte served from the written pointer",
          Mock_I2C_Target.Pushed_Count'Image, "1",
          Mock_I2C_Target.Pushed_Count = 1);
   if Mock_I2C_Target.Pushed_Count = 1 then
      Check ("Repeated-START: byte is reg 0x05 (RNG), not reg 0x00 (status)",
             Mock_I2C_Target.Pushed_Byte (1)'Image, "170",
             Mock_I2C_Target.Pushed_Byte (1) = 16#AA#);
   end if;
   Mock_I2C_Target.Simulate_Stop;
   Responder.Poll;

   --  Scenario C: a well-formed 4-byte write at 0x01 sets the epoch --
   --  the "settable epoch" design (§6.5): write once, then free-run.
   Mock_Clock.Set_Now (500);
   Mock_I2C_Target.Reset;
   Mock_I2C_Target.Begin_Transaction (Read_Direction => False);
   Responder.Poll;                            --  address match (write), ack
   Mock_I2C_Target.Feed_Byte (1);              --  register pointer = 0x01 (epoch)
   Responder.Poll;                            --  pops it: Reg_Ptr := 1
   Mock_I2C_Target.Feed_Byte (0);
   Mock_I2C_Target.Feed_Byte (0);
   Mock_I2C_Target.Feed_Byte (16#27#);
   Mock_I2C_Target.Feed_Byte (16#10#);         --  0x00_00_27_10 = 10_000
   for I in 1 .. 4 loop
      Responder.Poll;                          --  pops one byte per call
   end loop;
   Mock_I2C_Target.Simulate_Stop;
   Responder.Poll;                            --  Is_Stop -> Commit_Epoch
   Mock_Clock.Set_Now (600);                   --  100 ticks later
   declare
      --  Read once into a local: a volatile-function call must be the
      --  whole right-hand side (SPARK RM 7.1.3(9)) -- calling it twice
      --  more (for 'Image and for "=") would also each need isolating.
      Got : constant Responder.Epoch_Seconds := Responder.Current_Epoch_Seconds;
   begin
      Check ("Settable epoch: advances from the written value (10000 -> 10100)",
             Got'Image, "10100", Got = 10_100);
   end;

   if Failed then
      Put_Line ("host_test: FAILED");
      Set_Exit_Status (Failure);
   else
      Put_Line ("host_test: all checks passed");
      Set_Exit_Status (Success);
   end if;
end Main;
