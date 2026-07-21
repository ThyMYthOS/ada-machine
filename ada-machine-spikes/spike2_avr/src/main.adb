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
with AVR_Board;

procedure Main
  with SPARK_Mode, No_Return  --  the loop below never exits (embedded main)
is

   --  AVR_Board.Env_Sensor is the *instance* of the BME280 generic;
   --  "BME280.Device_Status" etc. would name the un-instantiated
   --  generic template, which has no callable entities. use-visibility
   --  is also needed for "=" on the instance's type (same reason
   --  host_test needed "use type Sensor.Device_Status").
   use type AVR_Board.Env_Sensor.Device_Status;

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
      else
         Status := AVR_Board.Env_Sensor.Ok;  --  §7.1 rule 3: owner resets and retries
      end if;
   end loop;
end Main;
