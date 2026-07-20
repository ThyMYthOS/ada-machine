--  Portable Bosch BME280 driver. Generic over the bus-neutral register
--  map signature: the same driver serves I2C and SPI wirings. Bus
--  address / chip select live in the binding, where topology is known.
with Machine.Regmap.Generic_Device;
with Machine.Blocking.Generic_Delays;
with Machine.Log;
generic
   with package Regs is new Machine.Regmap.Generic_Device (<>);
                                    --  bus-neutral register access
   with package Wait is new Machine.Blocking.Generic_Delays (<>);
                                    --  waits for conversion/reset times
   with procedure Log_Event (E : Machine.Log.Event_Id;
                             A : Machine.Log.Arg := Machine.Log.No_Arg) is null;
                                    --  optional trace hook; default: no-op
package BME280
  with SPARK_Mode
is

   --  Driver-level chained status: access kinds are mapped, not re-exported.
   type Device_Status is
     (Ok, Wrong_Chip_Id, Bus_Fault, Timed_Out, Not_Initialized);
   function Last_Access_Status return Machine.Regmap.Access_Status;

   type Oversampling is (Skipped, X1, X2, X4, X8, X16);

   --  Compensated readings as decimal fixed point, per datasheet ranges:
   type Celsius     is delta 0.01 range -40.00 .. 85.00    with Small => 0.01;
   type Hectopascal is delta 0.01 range 300.00 .. 1100.00  with Small => 0.01;
   type Percent_RH  is delta 0.01 range 0.00 .. 100.00     with Small => 0.01;
   type Measurement is record
      Temperature : Celsius;
      Pressure    : Hectopascal;
      Humidity    : Percent_RH;
   end record;

   --  Soft-reset, probe chip id (16#60#), load calibration coefficients.
   procedure Initialize (Status : in out Device_Status)
     with Post => (if Status'Old /= Ok then Status = Status'Old);  --  §7.1 rule 1

   procedure Configure
     (Temperature_Oversampling : Oversampling := X2;
      Pressure_Oversampling    : Oversampling := X16;
      Humidity_Oversampling    : Oversampling := X1;
      Status                   : in out Device_Status)
     with Post => (if Status'Old /= Ok then Status = Status'Old);

   --  Forced-mode cycle: trigger, wait, burst-read 16#F7#..16#FE#,
   --  compensate (Bosch integer formulas, datasheet 4.2.3).
   procedure Measure (Result : out Measurement;
                      Status : in out Device_Status)
     with Post => (if Status'Old /= Ok
                   then Status = Status'Old
                        and then Result = (Temperature => 0.0,
                                           Pressure    => 1000.0,
                                           Humidity    => 0.0));

end BME280;
