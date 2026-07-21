--  RNG class vocabulary (new in spike 4 -- not yet in the §6.3 v1 list,
--  proposed here as an 8th signature alongside Digital_Out/In, UART,
--  SPI_Master, I2C_Master, Clock, Delays; one data point so far, same
--  bar Generic_Master was held to before being called proven).
package Machine.RNG
  with Pure, SPARK_Mode
is
   --  Named after real hardware fault modes (STM32 RNG's SEIS/CEIS
   --  health-check flags: the entropy source failed its randomness
   --  self-test, or its dedicated clock is misconfigured/absent) rather
   --  than invented -- same discipline as Machine.I2C.Bus_Status naming
   --  real DW_apb_i2c/STM32 abort reasons.
   type Rng_Status is (Ok, Seed_Error, Clock_Error, Other_Error);
end Machine.RNG;
