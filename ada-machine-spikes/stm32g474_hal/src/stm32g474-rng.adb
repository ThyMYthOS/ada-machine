with Interfaces; use Interfaces;

package body STM32G474.RNG
  with SPARK_Mode
is
   use STM32G474_PAC.RCC;
   use STM32G474_PAC.RNG;

   procedure Enable is
      En_Now : constant Unsigned_32 := AHB2ENR;
   begin
      --  The RNG kernel clock is CCIPR.CLK48SEL, which resets to HSI48
      --  (that reset default is relied on, not rewritten) -- but HSI48
      --  itself is off after reset, so start it here. No wait for
      --  HSI48RDY: L2 never waits (§5), and the RNG reports Is_Ready
      --  only once clock and seed are good (DRDY), so a caller polling
      --  Is_Ready already waits for exactly this.
      CRRCR := CRRCR_HSI48ON;   --  other bits (RDY, CAL) are read-only: a
                                --  plain write, no read-modify-write
      AHB2ENR := En_Now or AHB2ENR_RNGEN;
      CR := CR_RNGEN;
   end Enable;

   function Is_Ready return Boolean is
      Status_Now : constant Unsigned_32 := SR;
   begin
      return (Status_Now and SR_DRDY) /= 0;
   end Is_Ready;

   procedure Get_Word (Value  : out Unsigned_32;
                       Status : in out Machine.RNG.Rng_Status)
   is
      Status_Now : Unsigned_32;
   begin
      Value := 0;
      if Status /= Machine.RNG.Ok then
         return;                              --  chained: skip if pending
      end if;
      Status_Now := SR;
      if (Status_Now and SR_SECS) /= 0 then
         Status := Machine.RNG.Seed_Error;
      elsif (Status_Now and SR_CECS) /= 0 then
         Status := Machine.RNG.Clock_Error;
      else
         Value := DR;
      end if;
   end Get_Word;

end STM32G474.RNG;
