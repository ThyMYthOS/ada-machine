--  The standardized shape a <mcu>_hal's own <Root>.HAL_Info fills in
--  (§6.1), replacing per-HAL ad-hoc `Has_X : Boolean` stubs with one
--  contract type so the field set is uniform across every HAL. One
--  presence flag per v1 signature class (§6.3; Has_I2C_Target and
--  Has_RNG joined with those two signatures' promotion, TODO.md #11). This is the seed: the
--  richer descriptor the console/drain-ownership design (§10.3) and
--  boardgen pin/instance validity (§13) will want grows here, as fields
--  with defaults; aggregates name what they provide and close with
--  `others => False`, so a new field never breaks an existing HAL.
package Machine.HAL_Info
  with Pure, SPARK_Mode
is
   type Descriptor is record
      Has_GPIO       : Boolean := False;  --  Digital_Out/In (Machine.GPIO)
      Has_UART       : Boolean := False;  --  Machine.UART.Generic_Port
      Has_SPI        : Boolean := False;  --  Machine.SPI.Generic_Master
      Has_I2C        : Boolean := False;  --  Machine.I2C.Generic_Master
      Has_Clock      : Boolean := False;  --  Machine.Generic_Clock
      Has_Delays     : Boolean := False;  --  native Machine.Blocking.Generic_Delays
      Has_I2C_Target : Boolean := False;  --  Machine.I2C.Generic_Target
      Has_RNG        : Boolean := False;  --  Machine.RNG.Generic_Source
   end record;
end Machine.HAL_Info;
