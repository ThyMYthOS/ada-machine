with ATmega328P.Clock;
with System.GCC_Builtins;

package body AVR_Board
  with SPARK_Mode
is

   procedure Timer0_Interrupt is
   begin
      ATmega328P.Clock.On_Tick;
   end Timer0_Interrupt;

   procedure Setup is
   begin
      ATmega328P.I2C.Enable ((Baud_Hz => 100_000));
      ATmega328P.Clock.Enable;
      System.GCC_Builtins.Sei;  --  global interrupt enable (D5): the
                                --  Timer0-overflow tick needs it, even
                                --  though TWI itself is polled, not
                                --  interrupt-driven, on this floor. The
                                --  GCC intrinsic, not inline asm, so this
                                --  stays in SPARK (§6.6).
   end Setup;

end AVR_Board;
