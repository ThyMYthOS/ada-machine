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
with Board;

procedure Main
  with SPARK_Mode
is
   use type Board.Env_Sensor.Device_Status;

   Status : Board.Env_Sensor.Device_Status := Board.Env_Sensor.Ok;
   M      : Board.Env_Sensor.Measurement;
begin
   --  CS idle-high before the bus is touched.
   ESP32C3.GPIO.Configure (10, ESP32C3.GPIO.Output);
   ESP32C3.GPIO.Set_High (10);

   ESP32C3.SPI2.Enable ((Divisor => 4, Mode => 0));
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
      if Status = Board.Env_Sensor.Ok then
         Board.Env_Sensor.Measure (M, Status);
      else
         Status := Board.Env_Sensor.Ok;  --  §7.1 rule 3: owner resets and retries
      end if;
   end loop;
end Main;
