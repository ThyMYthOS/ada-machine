--  Spike 3 main: ESP32-C3, BME280 over SPI, DMA-driven under a tasking
--  runtime. No status LED wired for this port. Spike 2's main.adb holds
--  its last Device_Status in a local "with Volatile" for debugger/probe
--  inspection -- legal there only because that unit is SPARK_Mode => Off
--  (inline "sei" forces that). This one stays fully in SPARK (no inline
--  asm needed, see below), and SPARK requires effectively volatile
--  objects to be at library level, not local to a subprogram -- so
--  Status is a plain local here; hoisting it to a library-level volatile
--  (in Board, say) is the option if probe visibility is wanted later.
with ESP32C3.SPI2;
with ESP32C3.GPIO;
with ESP32C3.UART0;
with Machine.Log;
with Machine.Tasking.Delays;
with Board;
with Test_Run;

procedure Main
  with SPARK_Mode
is
   use type Board.Env_Sensor.Device_Status, Board.Env_Sensor.Celsius;

   Status : Board.Env_Sensor.Device_Status := Board.Env_Sensor.Ok;
   M      : Board.Env_Sensor.Measurement;
begin
   --  CS idle-high before the bus is touched.
   ESP32C3.GPIO.Configure (10, ESP32C3.GPIO.Output);
   ESP32C3.GPIO.Set_High (10);

   ESP32C3.SPI2.Enable ((Divisor => 4, Mode => 0));
   ESP32C3.UART0.Enable ((Baud_Hz => 115_200));

   --  Test mode (ADA_MACHINE_TEST_MODE=on): run the measurement cycles,
   --  write the ADA-MACHINE-TEST verdict line and halt. Enabled is a static
   --  constant, so in a normal build this folds away.
   if Test_Run.Enabled then
      Test_Run.Run_And_Halt;
   end if;
   --  Global interrupt enable and the DMA-done interrupt's actual
   --  attachment are runtime-owned on a light-tasking profile (unlike
   --  spike 2's ZFP floor, which needed inline "sei" here) -- no inline
   --  asm, so this stays in SPARK, D5's application-attaches rule taken
   --  as far as the missing ESP32-C3 runtime (see Board.DMA_Handler's
   --  own note) lets it go in this repo.

   Board.Env_Sensor.Initialize (Status);
   if Status = Board.Env_Sensor.Ok then
      Board.Env_Sensor.Configure (Status => Status);
   end if;

   loop
      --  Guard against spinning Measure on a device that never came up:
      --  a prior failure (Initialize itself, or a since-failed Measure)
      --  is retried through Initialize/Configure again before the next
      --  Measure is attempted, never straight into Measure on a device
      --  whose state we don't actually know (§7.1 rule 3: owner resets
      --  and retries, applied at the point where the retry actually
      --  re-establishes a known-good state).
      if Status /= Board.Env_Sensor.Ok then
         Board.Env_Sensor.Initialize (Status);
         if Status = Board.Env_Sensor.Ok then
            Board.Env_Sensor.Configure (Status => Status);
         end if;
      end if;

      if Status = Board.Env_Sensor.Ok then
         Board.Env_Sensor.Measure (M, Status);
         if Status = Board.Env_Sensor.Ok then
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
         end if;
      end if;

      --  Pace the loop: the tasking runtime's own delay facility
      --  (Machine.Tasking.Delays, already wired into Env_Sensor's own
      --  Wait formal above) rather than a tight unpaced retry -- 500 ms
      --  between measurements whether the last one succeeded or not,
      --  matching spike1_pico's measurement cadence.
      Machine.Tasking.Delays.Delay_Ms (500);
   end loop;
end Main;
