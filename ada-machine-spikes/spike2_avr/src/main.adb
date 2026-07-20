--  Spike 2 main: ATmega328P, BME280 over SPI, interrupt-driven (Appendix B).
--  No status LED wired for this port (PORTB's only spare pin doubles as
--  SCK/MOSI/SS); the last Device_Status is simply held in a volatile for
--  debugger/probe inspection.
with System.Machine_Code; use System.Machine_Code;
with ATmega328P.SPI;
with ATmega328P.GPIO;
with AVR_Board;

procedure Main
  with SPARK_Mode => Off  --  inline asm ("sei") is outside the SPARK subset
is

   --  AVR_Board.Env_Sensor is the *instance* of the BME280 generic;
   --  "BME280.Device_Status" etc. would name the un-instantiated
   --  generic template, which has no callable entities. use-visibility
   --  is also needed for "=" on the instance's type (same reason
   --  host_test needed "use type Sensor.Device_Status").
   use type AVR_Board.Env_Sensor.Device_Status;

   Status : AVR_Board.Env_Sensor.Device_Status := AVR_Board.Env_Sensor.Ok
     with Volatile;
   M      : AVR_Board.Env_Sensor.Measurement;
begin
   --  CS idle-high before the bus is touched.
   ATmega328P.GPIO.Configure (2, ATmega328P.GPIO.Output);
   ATmega328P.GPIO.Set_High (2);

   ATmega328P.SPI.Enable ((Divisor => ATmega328P.SPI.Div_16, Mode => 0,
                           MSB_First => True));
   ATmega328P.SPI.Enable_Interrupt;
   Asm ("sei", Volatile => True);    --  global interrupt enable (D5: the
                                     --  application's decision, not the
                                     --  runtime's, on this ZFP floor)

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
