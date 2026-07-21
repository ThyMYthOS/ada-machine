--  stm32g474-rng.ads -- the never-blocking L2 data phase over STM32G474's
--  hardware RNG (RM0440 ch. 26), conforming Machine.RNG.Generic_Source.
--  Health-check faults (seed/clock error) map to Rng_Status directly
--  from SR's SECS/CECS bits (§7 "per-class error kinds", extended to the
--  new RNG class).
with STM32G474_PAC.RCC, STM32G474_PAC.RNG;
with Interfaces;
use type Interfaces.Unsigned_32;
with Machine.RNG;
use type Machine.RNG.Rng_Status;

package STM32G474.RNG
  with Preelaborate, SPARK_Mode
is
   procedure Enable
     with Global => (In_Out => STM32G474_PAC.RCC.AHB2ENR,
                     Output => STM32G474_PAC.RNG.CR);
                    --  CR: Output, not In_Out -- Enable always overwrites
                    --  it outright, never reads the incoming value.

   function Is_Ready return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => STM32G474_PAC.RNG.SR);

   procedure Get_Word (Value  : out Interfaces.Unsigned_32;
                       Status : in out Machine.RNG.Rng_Status)
     with Inline_Always,
          Global => (Input => STM32G474_PAC.RNG.SR, In_Out => STM32G474_PAC.RNG.DR),
          Post   => (if Status'Old /= Machine.RNG.Ok
                     then Status = Status'Old and Value = 0);
end STM32G474.RNG;
