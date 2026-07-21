with ATmega328P_PAC.Timer0; use ATmega328P_PAC.Timer0;
with System.Machine_Code; use System.Machine_Code;

package body ATmega328P.Clock
  with SPARK_Mode,
       Refined_State => (State => Tick_Count)
is

   Tick_Count : Ticks := 0 with Volatile, Async_Readers, Async_Writers;

   procedure Enable is
   begin
      TCCR0A := 0;                       --  Normal mode (WGM01:0 = 00)
      TCCR0B := TCCR0B_CS0_DIV_64;
      TIMSK0 := TIMSK0_TOIE0;
      Tick_Count := 0;
   end Enable;

   function Now return Ticks
     with SPARK_Mode => Off  --  cli/sei around the read: Ticks is 32 bits,
                              --  four separate byte loads on this 8-bit CPU,
                              --  and On_Tick (the ISR) could otherwise
                              --  interleave a partial update into the
                              --  middle of one -- inline asm is outside the
                              --  SPARK subset. Unconditional cli;...;sei (no
                              --  save/restore of the prior I-bit) is safe on
                              --  this floor because nothing else on the I2C
                              --  variant ever disables interrupts itself;
                              --  same rigor level as the not-yet-closed
                              --  critical-section gap tracked in TODO.md P0
                              --  #2 for machine_async.
   is
      T_Now : Ticks;
   begin
      Asm ("cli", Volatile => True);
      T_Now := Tick_Count;
      Asm ("sei", Volatile => True);
      return T_Now;
   end Now;

   procedure On_Tick is
      T_Now : constant Ticks := Tick_Count;
   begin
      Tick_Count := T_Now + 1;
   end On_Tick;

end ATmega328P.Clock;
