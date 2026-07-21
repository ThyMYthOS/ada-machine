with Interfaces; use Interfaces;

package body STM32G474.Clock
  with SPARK_Mode
is
   use STM32G474_PAC.RCC;
   use STM32G474_PAC.TIM2;

   --  Assumes the default post-reset HSI16 clock (16 MHz, undivided to
   --  APB1 -- D8, native config: no PLL/clock-tree setup in this spike).
   Core_Clock_Hz : constant := 16_000_000;

   procedure Enable is
      En_Now : constant Unsigned_32 := APB1ENR1;
   begin
      APB1ENR1 := En_Now or APB1ENR1_TIM2EN;

      CR1 := 0;                            --  stop while reconfiguring
      PSC := Core_Clock_Hz - 1;            --  prescale to a 1 Hz count rate
      ARR := 16#FFFF_FFFF#;                --  free-run, no artificial wrap
      CR1 := CR1_CEN;
   end Enable;

   function Now return Ticks is (Ticks (CNT));

end STM32G474.Clock;
