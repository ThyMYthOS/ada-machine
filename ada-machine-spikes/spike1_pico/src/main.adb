--  Spike 1 main: RP2040 (Pico), BME280 over I2C0, blocking (Appendix A).
--  No runtime console on this floor (§10.3 is a full runtime feature
--  this spike doesn't pull in) -- status is a GP25 (onboard LED) blink
--  pattern: one long pulse per successful Measure, short pulses counting
--  Device_Status'Pos on failure.
with RP2040.GPIO;
with RP2040.I2C0;
with RP2040.UART0;
with Machine.Log;
with Board;
with Test_Run;

procedure Main
  with SPARK_Mode
is
   LED : constant RP2040.GPIO.Pin_Id := 25;

   --  Board.Env_Sensor is the *instance* of the BME280 generic; its
   --  Device_Status/Ok/Measurement only exist through that instance --
   --  "BME280.Device_Status" etc. would name the un-instantiated
   --  generic template, which has no callable entities. The "=" and
   --  'Pos below also need this to be use-visible (same reason
   --  host_test needed "use type Sensor.Device_Status": naming an
   --  instance's type via dot notation doesn't make its predefined
   --  operators directly visible).
   use type Board.Env_Sensor.Device_Status, Board.Env_Sensor.Celsius;

   procedure Blink (Times : Natural; Ms : Natural) is
   begin
      for I in 1 .. Times loop
         RP2040.GPIO.Set_High (LED);
         Board.Delays.Delay_Ms (Ms);
         RP2040.GPIO.Set_Low (LED);
         Board.Delays.Delay_Ms (Ms);
      end loop;
   end Blink;

   Status : Board.Env_Sensor.Device_Status := Board.Env_Sensor.Ok;
   M      : Board.Env_Sensor.Measurement;
begin
   RP2040.GPIO.Configure (LED, RP2040.GPIO.Output);
   RP2040.I2C0.Enable ((Baud_Hz => 400_000, SDA_Pin => 4, SCL_Pin => 5));
   RP2040.UART0.Enable ((Baud_Hz => 115_200, TX_Pin => 0, RX_Pin => 1));

   --  Test mode (ADA_MACHINE_TEST_MODE=on): run the measurement cycles,
   --  write the ADA-MACHINE-TEST verdict line and halt. Enabled is a static
   --  constant, so in a normal build this folds away.
   if Test_Run.Enabled then
      Test_Run.Run_And_Halt;
   end if;

   Board.Env_Sensor.Initialize (Status);
   if Status = Board.Env_Sensor.Ok then
      Board.Env_Sensor.Configure (Status => Status);
   end if;

   loop
      if Status = Board.Env_Sensor.Ok then
         Board.Env_Sensor.Measure (M, Status);
      end if;
      case Status is
         when Board.Env_Sensor.Ok =>
            --  Per-measurement Info trace (§14.2): a decision/state
            --  transition, not a per-byte data phase, so it belongs
            --  here and not inside the driver's L2/L3 primitives.
            if Machine.Log.Enabled (Machine.Log.Info) then
               Board.Sink.Emit
                 (Machine.Log.Info, Board.Ev_Measured,
                  --  Hundredths of a degree: dividing by the type's own Small
                  --  stays exact and in range (multiplying by 100 inside
                  --  Celsius overflowed its 85.00 bound above 0.85 degC);
                  --  'Mod because Arg is modular and readings may be negative.
                  Machine.Log.Arg'Mod
                    (Integer (M.Temperature / Board.Env_Sensor.Celsius'(0.01))));
            end if;
            Blink (Times => 1, Ms => 500);       --  one long-ish pulse: OK
         when others =>
            Blink (Times => Board.Env_Sensor.Device_Status'Pos (Status) + 1,
                   Ms => 150);
            Status := Board.Env_Sensor.Ok;        --  §7.1 rule 3: owner resets
      end case;
   end loop;
end Main;
