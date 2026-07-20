--  I2C class vocabulary. Signatures live beneath as generic children.
package Machine.I2C
  with Pure, SPARK_Mode
is
   type Address_7_Bit is range 0 .. 16#7F#;   --  unshifted, as in datasheets

   --  L2 status: no Timed_Out -- L2 never waits.
   type Bus_Status is
     (Ok, Nack_Address, Nack_Data, Arbitration_Lost, Bus_Error, Other_Error);

   --  Bounded-transaction outcome (blocking calls, async completion).
   type Transaction_Status is
     (Ok, Timed_Out,
      Nack_Address, Nack_Data, Arbitration_Lost, Bus_Error, Other_Error);
end Machine.I2C;
