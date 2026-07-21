--  stm32g474-clock.ads -- §6.5: L2 exposes reading time, never owning an
--  interrupt. Driven by TIM2 as a free-running counter, no timekeeping
--  interrupt at all (unlike RP2040.Clock's always-on hardware TIMER,
--  this one needs an explicit Enable to start it, §6.5's "runtime owns
--  the tick" doesn't apply -- there is no runtime here, this spike is a
--  native-host stand-in, §10).
with STM32G474_PAC.RCC, STM32G474_PAC.TIM2;

package STM32G474.Clock
  with Preelaborate, SPARK_Mode
is
   type Ticks is mod 2 ** 32;

   --  Coarse on purpose: the only consumer in this spike (Time_RNG_Target's
   --  settable-epoch feature) needs second granularity, not microsecond
   --  delays -- unlike RP2040.Clock (Ticks_Per_Second = 1_000_000, feeding
   --  Machine.Blocking.Generic_Delays.Delay_Us), nothing here needs finer
   --  resolution, and at 1 Hz a 32-bit counter doesn't wrap for ~136 years.
   Ticks_Per_Second : constant := 1;

   procedure Enable
     with Global => (In_Out => STM32G474_PAC.RCC.APB1ENR1,
                     Output => (STM32G474_PAC.TIM2.CR1,
                                STM32G474_PAC.TIM2.PSC,
                                STM32G474_PAC.TIM2.ARR));
                    --  CR1/PSC/ARR: Output, not In_Out -- Enable always
                    --  overwrites them outright, never reads the
                    --  incoming value (unlike APB1ENR1's read-modify-write).

   function Now return Ticks
     with Inline_Always, Volatile_Function,
          Global => (Input => STM32G474_PAC.TIM2.CNT);
end STM32G474.Clock;
