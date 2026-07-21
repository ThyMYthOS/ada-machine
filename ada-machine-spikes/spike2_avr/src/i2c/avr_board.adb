with ATmega328P.Clock;

package body AVR_Board
  with SPARK_Mode
is

   procedure Timer0_Interrupt is
   begin
      ATmega328P.Clock.On_Tick;
   end Timer0_Interrupt;

end AVR_Board;
