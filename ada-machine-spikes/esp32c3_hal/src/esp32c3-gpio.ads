--  esp32c3-gpio.ads -- §6.4's shape, as in RP2040.GPIO, with Global
--  contracts naming the backing PAC registers.
with ESP32C3_PAC.GPIO;

package ESP32C3.GPIO
  with Preelaborate, SPARK_Mode
is
   type Direction is (Input, Output);

   --  In_Out, not Output: any one call only ever writes one of the two
   --  registers (Dir picks which), so Output's "both fully rewritten"
   --  claim would overclaim -- the same lesson as ESP32C3.SPI2's Global
   --  aspects (see that unit's header comment).
   procedure Configure (Pin : Pin_Id; Dir : Direction)
     with Global => (In_Out => (ESP32C3_PAC.GPIO.GPIO_ENABLE_W1TS,
                                ESP32C3_PAC.GPIO.GPIO_ENABLE_W1TC));

   procedure Set_High (Pin : Pin_Id)
     with Inline_Always, Global => (Output => ESP32C3_PAC.GPIO.GPIO_OUT_W1TS);
   procedure Set_Low  (Pin : Pin_Id)
     with Inline_Always, Global => (Output => ESP32C3_PAC.GPIO.GPIO_OUT_W1TC);
   function  Is_High  (Pin : Pin_Id) return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => ESP32C3_PAC.GPIO.GPIO_IN);
                    --  a function reading volatile (hardware) state may
                    --  return differently on identical-looking calls;
                    --  SPARK requires Volatile_Function to say so (RM
                    --  7.1.3(9)) -- RP2040.GPIO.Is_High is missing this
                    --  too (never run through gnatprove either, per
                    --  every "not cross-built" note in this repo).
end ESP32C3.GPIO;
