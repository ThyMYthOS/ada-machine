--  The standardized shape a <mcu>_hal's own <Root>.HAL_Info fills in
--  (§6.1), replacing per-HAL ad-hoc `Has_X : Boolean` stubs with one
--  contract type so the field set is uniform across every HAL. One
--  presence flag per v1 signature class (§6.3). This is the seed: the
--  richer descriptor the console/drain-ownership design (§10.3) and
--  boardgen pin/instance validity (§13) will want grows here, as fields
--  with defaults so existing aggregates keep compiling.
package Machine.HAL_Info
  with Pure, SPARK_Mode
is
   type Descriptor is record
      Has_GPIO   : Boolean := False;   --  Digital_Out/In (Machine.GPIO)
      Has_UART   : Boolean := False;   --  Machine.UART.Generic_Port
      Has_SPI    : Boolean := False;   --  Machine.SPI.Generic_Master
      Has_I2C    : Boolean := False;   --  Machine.I2C.Generic_Master
      Has_Clock  : Boolean := False;   --  Machine.Generic_Clock
      Has_Delays : Boolean := False;   --  native Machine.Blocking.Generic_Delays
   end record;
end Machine.HAL_Info;
