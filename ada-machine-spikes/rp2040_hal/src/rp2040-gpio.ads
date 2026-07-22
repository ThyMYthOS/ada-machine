--  rp2040-gpio.ads -- §6.4's shape (shown verbatim in the architecture
--  doc), with Global contracts added naming the backing PAC registers
--  (an addition beyond the literal §6.4 excerpt, in the spirit of §6.6).
with RP2040_PAC.SIO, RP2040_PAC.IO_Bank0, RP2040_PAC.Pads_Bank0;

package RP2040.GPIO
  with Preelaborate, SPARK_Mode
is
   subtype Pin_Id is RP2040.Pin_Id;
   type Direction is (Input, Output);
   type Pull is (Floating, Pull_Up, Pull_Down);

   --  All four In_Out, not Output: GPIO_OE_SET/GPIO_OE_CLR because any
   --  one call only ever writes one of the two (Dir picks which), and
   --  Pads/Pins (TODO #8) because they are whole-array Globals but this
   --  call only writes the one element at index Pin -- either way,
   --  Output's "the whole object is (re)written" claim would overclaim
   --  (same lesson as ESP32C3.SPI2/GPIO's own Global aspects).
   procedure Configure (Pin : Pin_Id; Dir : Direction; P : Pull := Floating)
     with Global => (In_Out => (RP2040_PAC.Pads_Bank0.Pads,
                                RP2040_PAC.IO_Bank0.Pins,
                                RP2040_PAC.SIO.GPIO_OE_SET,
                                RP2040_PAC.SIO.GPIO_OE_CLR));

   procedure Set_High (Pin : Pin_Id)
     with Inline_Always, Global => (Output => RP2040_PAC.SIO.GPIO_OUT_SET);
   procedure Set_Low  (Pin : Pin_Id)
     with Inline_Always, Global => (Output => RP2040_PAC.SIO.GPIO_OUT_CLR);
   procedure Toggle   (Pin : Pin_Id)
     with Inline_Always, Global => (Output => RP2040_PAC.SIO.GPIO_OUT_XOR);
   function  Is_High  (Pin : Pin_Id) return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => RP2040_PAC.SIO.GPIO_IN);
                    --  a function reading volatile (hardware) state may
                    --  return differently on identical-looking calls;
                    --  SPARK requires Volatile_Function to say so (RM
                    --  7.1.3(9)).
end RP2040.GPIO;
