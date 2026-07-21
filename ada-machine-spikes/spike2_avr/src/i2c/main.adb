--  Spike 2 main, I2C variant: ATmega328P, BME280 over TWI, blocking
--  (Appendix B, TODO.md P0 #1). No status LED wired for this port (matches
--  the SPI variant's own choice, for consistency between the two); the
--  last Device_Status is held in a volatile for debugger/probe inspection.
with System.Machine_Code; use System.Machine_Code;
with ATmega328P.I2C;
with ATmega328P.Clock;
with AVR_Board;

procedure Main
  with SPARK_Mode => Off  --  inline asm ("sei") is outside the SPARK subset
is

   --  AVR_Board.Env_Sensor is the *instance* of the BME280 generic; see
   --  the SPI variant's main.adb for why "use type" is needed here.
   use type AVR_Board.Env_Sensor.Device_Status;

   Status : AVR_Board.Env_Sensor.Device_Status := AVR_Board.Env_Sensor.Ok
     with Volatile;
   M      : AVR_Board.Env_Sensor.Measurement;
begin
   ATmega328P.I2C.Enable ((Baud_Hz => 100_000));
   ATmega328P.Clock.Enable;
   Asm ("sei", Volatile => True);    --  global interrupt enable (D5): the
                                     --  Timer0-overflow tick needs it, even
                                     --  though TWI itself is polled, not
                                     --  interrupt-driven, on this floor.

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
