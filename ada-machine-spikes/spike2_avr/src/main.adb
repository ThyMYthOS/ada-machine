--  Spike 2 main (Appendix B): shared between the SPI and I2C bus
--  variants (spike2_avr.gpr's BME280_BUS switch) -- AVR_Board.Setup does
--  each variant's own bus-specific bring-up, so this stays bus-agnostic
--  and fully in SPARK (both variants' Setup no longer need inline asm --
--  System.GCC_Builtins.Sei replaces it). No status LED wired for either
--  port; Status isn't Volatile any more either (SPARK forbids an
--  effectively volatile object that isn't at library level, same
--  restriction that already keeps Delays.Spin's local counter out of
--  SPARK) -- it was only ever a debugger/probe-visibility aid, not a
--  correctness requirement: Status is read every loop iteration by
--  ordinary code regardless.
with Machine.Log;
with AVR_Board;

procedure Main
  with SPARK_Mode, No_Return  --  the loop below never exits (embedded main)
is

   --  AVR_Board.Env_Sensor is the *instance* of the BME280 generic;
   --  "BME280.Device_Status" etc. would name the un-instantiated
   --  generic template, which has no callable entities. use-visibility
   --  is also needed for "=" on the instance's type (same reason
   --  host_test needed "use type Sensor.Device_Status").
   use type AVR_Board.Env_Sensor.Device_Status, AVR_Board.Env_Sensor.Celsius;

   Status : AVR_Board.Env_Sensor.Device_Status := AVR_Board.Env_Sensor.Ok;
   M      : AVR_Board.Env_Sensor.Measurement;
begin
   AVR_Board.Setup;

   AVR_Board.Env_Sensor.Initialize (Status);
   if Status = AVR_Board.Env_Sensor.Ok then
      AVR_Board.Env_Sensor.Configure (Status => Status);
   end if;

   loop
      if Status = AVR_Board.Env_Sensor.Ok then
         AVR_Board.Env_Sensor.Measure (M, Status);
         if Status = AVR_Board.Env_Sensor.Ok then
            --  Per-measurement Info trace (§14.2): a decision/state
            --  transition, not a per-byte data phase, so it belongs
            --  here and not inside the driver's L2/L3 primitives.
            if Machine.Log.Enabled (Machine.Log.Info) then
               AVR_Board.Sink.Emit
                 (Machine.Log.Info, AVR_Board.Ev_Measured,
                  Machine.Log.Arg (Integer (M.Temperature * 100)));
            end if;
         end if;
      else
         Status := AVR_Board.Env_Sensor.Ok;  --  §7.1 rule 3: owner resets and retries
      end if;
   end loop;
end Main;
