package body Spike_Test_Runner
  with SPARK_Mode
is
   use type Sensor.Device_Status, Sensor.Celsius, Sensor.Hectopascal,
            Sensor.Percent_RH;

   CR : constant Character := Character'Val (13);
   LF : constant Character := Character'Val (10);

   --  Same wait-then-put as Machine.Blocking.Log_Sink.Send; the volatile
   --  function is read into a local first (SPARK RM 7.1.3(9)).
   procedure Put (C : Character) is
      Ready : Boolean;
   begin
      loop
         Ready := UART.Is_Tx_Ready;
         exit when Ready;
      end loop;
      UART.Put_Frame (UART.Frame (Character'Pos (C)));
   end Put;

   procedure Put (S : String) is
   begin
      for I in S'Range loop
         Put (S (I));
      end loop;
   end Put;

   procedure Put_Status (S : Sensor.Device_Status) is
   begin
      case S is
         when Sensor.Ok              => Put ("OK");
         when Sensor.Wrong_Chip_Id   => Put ("WRONG_CHIP_ID");
         when Sensor.Bus_Fault       => Put ("BUS_FAULT");
         when Sensor.Timed_Out       => Put ("TIMED_OUT");
         when Sensor.Not_Initialized => Put ("NOT_INITIALIZED");
      end case;
   end Put_Status;

   type Outcome is (Pass, Init_Failed, Measure_Failed,
                    Temp_Range, Press_Range, Hum_Range);

   --  No String concatenation or functions returning String: on AVR those
   --  pull in the concatenation/secondary-stack runtime and bloat the
   --  flash image. Every byte is written by a plain Put call instead.
   procedure Verdict (O : Outcome; S : Sensor.Device_Status := Sensor.Ok) is
   begin
      Put ("ADA-MACHINE-TEST: ");
      case O is
         when Pass           => Put ("PASS");
         when Init_Failed    =>
            Put ("FAIL INIT-");
            Put_Status (S);
         when Measure_Failed =>
            Put ("FAIL MEASURE-");
            Put_Status (S);
         when Temp_Range     => Put ("FAIL RANGE-TEMP");
         when Press_Range    => Put ("FAIL RANGE-PRESS");
         when Hum_Range      => Put ("FAIL RANGE-HUM");
      end case;
      Put (CR);
      Put (LF);
      Delay_Ms (Drain_Ms);
   end Verdict;

   --  BME280 datasheet 1.1 operating ranges, in the driver's units
   --  (degC, hPa, %RH). The driver's fixed-point types carry the same
   --  bounds, so this is also a guard against a build where they diverge.
   function Judge (M : Sensor.Measurement) return Outcome is
     (if M.Temperature < -40.0 or else M.Temperature > 85.0 then Temp_Range
      elsif M.Pressure < 300.0 or else M.Pressure > 1100.0 then Press_Range
      elsif M.Humidity < 0.0 or else M.Humidity > 100.0 then Hum_Range
      else Pass);

   --  Temperature in hundredths of a degree. Celsius'Small = 0.01, so the
   --  fixed-point type's integer value IS that number: no multiplication
   --  (main.adb's `Integer (T * 100)` multiplies in Celsius itself, whose
   --  range stops at 85.00, so it overflows for every reading above 0.85
   --  degC when checks are on, and wraps on AVR's 16-bit mantissa under
   --  -gnatp). 'Integer_Value is outside the SPARK subset, hence the
   --  SPARK_Mode Off body behind a SPARK-visible declaration.
   function Centi_Degrees (T : Sensor.Celsius) return Integer;

   function Centi_Degrees (T : Sensor.Celsius) return Integer
     with SPARK_Mode => Off
   is
   begin
      return Integer'Integer_Value (T);
   end Centi_Degrees;

   procedure Run is
      Status : Sensor.Device_Status := Sensor.Ok;
      M      : Sensor.Measurement;
      Result : Outcome;
      Centi  : Integer;
   begin
      Sensor.Initialize (Status);
      if Status = Sensor.Ok then
         Sensor.Configure (Status => Status);
      end if;
      if Status /= Sensor.Ok then
         Verdict (Init_Failed, Status);
         return;
      end if;

      for Cycle in 1 .. Cycles loop
         Sensor.Measure (M, Status);
         if Status /= Sensor.Ok then
            Verdict (Measure_Failed, Status);
            return;
         end if;
         Result := Judge (M);
         if Result /= Pass then
            Verdict (Result);
            return;
         end if;
         Centi := Centi_Degrees (M.Temperature);
         On_Measured (Machine.Log.Arg'Mod (Centi));
      end loop;

      Verdict (Pass);
   end Run;

   procedure Run_And_Halt is
   begin
      Run;
      loop
         Halt;
      end loop;
   end Run_And_Halt;

end Spike_Test_Runner;
