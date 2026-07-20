--  Register map over an I2C device: address byte, then data.
with Machine.I2C, Machine.Blocking.Generic_I2C_Master,
     Machine.Regmap.Generic_Device;
generic
   with package Bus is new Machine.Blocking.Generic_I2C_Master (<>);
                                    --  blocking transactions on the device's bus
   Device_Address : Machine.I2C.Address_7_Bit;
                                    --  the chip's address on that bus
   Timeout_Ms : Natural := 100;     --  per register access
package Machine.Regmap.Generic_I2C_Binding
  with SPARK_Mode
is
   procedure Write_Reg (Reg : Reg_Address; Value : Byte;
                        Status : in out Access_Status)
     with Post => (if Status'Old /= Ok then Status = Status'Old);  --  §7.1 rule 1

   procedure Read_Regs (Start : Reg_Address; Data : out Byte_Array;
                        Status : in out Access_Status)
     with Post => (if Status'Old /= Ok
                   then Status = Status'Old
                        and then (for all I in Data'Range => Data (I) = 0));

   package As_Device is new Machine.Regmap.Generic_Device
     (Write_Reg => Write_Reg, Read_Regs => Read_Regs);
end Machine.Regmap.Generic_I2C_Binding;
