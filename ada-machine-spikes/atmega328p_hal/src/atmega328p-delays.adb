with ATmega328P_HAL_Config;
with ATmega328P_PAC.Sleep; use ATmega328P_PAC.Sleep;
with System.Machine_Code; use System.Machine_Code;
with Interfaces; use Interfaces;

package body ATmega328P.Delays
  with SPARK_Mode
is

   --  No timer used (§10.1: AVR ZFP owns no tick -- a tick would
   --  confiscate one of the application's few timers). A NOP-count busy
   --  loop, calibrated by F_CPU, mirrors avr-libc's util/delay.h -- an
   --  approximation (4 cycles/iteration is typical for a decrement-and-
   --  branch loop on classic AVR at -O1+), not a cycle-exact clock.
   Cycles_Per_Loop : constant := 4;

   procedure Spin (Iterations : Natural) is
      Count : Natural := Iterations with Volatile;
   begin
      while Count > 0 loop
         Count := Count - 1;
      end loop;
   end Spin;

   procedure Delay_Us (Us : Natural) is
      Cycles : constant Long_Long_Integer :=
        Long_Long_Integer (Us) * ATmega328P_HAL_Config.F_CPU / 1_000_000;
   begin
      Spin (Natural (Cycles / Cycles_Per_Loop));
   end Delay_Us;

   procedure Delay_Ms (Ms : Natural) is
   begin
      for I in 1 .. Ms loop
         Delay_Us (1_000);
      end loop;
   end Delay_Ms;

   procedure Sleep_Idle
     with SPARK_Mode => Off  --  inline asm ("sleep") is outside the SPARK subset
   is
   begin
      SMCR := SMCR_SE;                 --  SM[2:0] = 000 (idle) after reset
      Asm ("sleep", Volatile => True);
      SMCR := SMCR and not SMCR_SE;     --  disarm: SE is a one-shot arm bit
   end Sleep_Idle;

end ATmega328P.Delays;
