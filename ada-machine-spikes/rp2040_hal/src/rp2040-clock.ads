--  rp2040-clock.ads -- §6.5: L2 exposes reading time, never owning it.
with RP2040_PAC.Timer;

package RP2040.Clock
  with Preelaborate, SPARK_Mode
is
   type Ticks is mod 2**64;             --  the 64-bit TIMER peripheral
   Ticks_Per_Second : constant := 1_000_000;

   function Now return Ticks
     with Inline_Always, Volatile_Function,
          Global => (Input => (RP2040_PAC.Timer.TIMERAWH,
                                RP2040_PAC.Timer.TIMERAWL));
                                --  read-only external state (§6.5: L2
                                --  reads time, never owns it, so this is
                                --  always an Input, never In_Out).
                                --  Volatile_Function: two calls needn't
                                --  agree, it's a running counter (SPARK
                                --  RM 7.1.3(9)).
end RP2040.Clock;
