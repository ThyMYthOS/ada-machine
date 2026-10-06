--  RNG class vocabulary (new in spike 4; promoted to the §6.3 v1 list in
--  TODO.md #11 once a second, structurally different source -- the bare
--  ESP32-C3 data register, no ready/health flags -- instantiated it
--  unchanged, the same bar Generic_Master had to clear).
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
