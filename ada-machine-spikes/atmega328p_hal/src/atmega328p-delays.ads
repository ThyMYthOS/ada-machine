--  atmega328p-delays.ads -- Appendix C.1, verbatim: calibrated busy-wait;
--  F_CPU is an Alire crate configuration variable, folded at compile time.
--  Global contracts added beyond the literal excerpt (§6.6).
with ATmega328P_PAC.Sleep;

package ATmega328P.Delays
  with Preelaborate, SPARK_Mode
is
   procedure Delay_Us (Us : Natural)
     with Global => null;      --  a pure busy-loop on a local counter
   procedure Delay_Ms (Ms : Natural)
     with Global => null;
   procedure Sleep_Idle
     with Inline_Always,       --  SLEEP (idle); wakes on any IRQ
          Global => (In_Out => ATmega328P_PAC.Sleep.SMCR);
end ATmega328P.Delays;
