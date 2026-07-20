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
with Mock_Regmap, Mock_Delays;
with BME280;

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

   --  Generic-instance operators aren't use-visible by just naming the
   --  instance via dot notation (Ada visibility rule, not a mistake in
   --  Regs/Wait above) -- infix "=" on Sensor's types needs this:
   use type Sensor.Device_Status, Sensor.Celsius,
            Sensor.Hectopascal, Sensor.Percent_RH;

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

   if Failed then
      Put_Line ("host_test: FAILED");
      Set_Exit_Status (Failure);
   else
      Put_Line ("host_test: all checks passed");
      Set_Exit_Status (Success);
   end if;
end Main;
