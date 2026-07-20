--  Mock_Regmap -- an in-memory stand-in for a real I2C/SPI regmap
--  binding (§15.4), implementing exactly the Machine.Regmap.Generic_Device
--  formal shape so BME280 (the shared bme280 crate, §11) instantiates over it unchanged.
--  Seeded with the widely-cited BME280 reference calibration/raw-ADC
--  vector so Measure's output can be checked against a known value
--  without any real bus or hardware.
with Machine;         use Machine;
with Machine.Regmap;  use Machine.Regmap;

package Mock_Regmap
  with SPARK_Mode,
       Abstract_State => State,    --  the in-memory register file + write count
       Initializes    => State     --  set up by this package's own elaboration
                                    --  (the begin...end block in the body)
is

   procedure Write_Reg (Reg : Reg_Address; Value : Byte;
                        Status : in out Access_Status)
     with Global => (In_Out => State),
          Post   => (if Status'Old /= Ok then Status = Status'Old);  --  §7.1 rule 1

   procedure Read_Regs (Start : Reg_Address; Data : out Byte_Array;
                        Status : in out Access_Status)
     with Global => (Input => State),
          Post   => (if Status'Old /= Ok
                     then Status = Status'Old
                          and then (for all I in Data'Range => Data (I) = 0));

   --  Test hook: how many register writes were observed (sanity check
   --  that Initialize/Configure/Measure actually touched the device).
   function Write_Count return Natural
     with Global => (Input => State);

end Mock_Regmap;
