--  Spike 4 main: STM32G474 (Nucleo-G474RE) as an I2C target exposing a
--  settable epoch and hardware RNG words (Appendix D). No runtime
--  console on this floor (§10.3 is a full runtime feature this spike
--  doesn't pull in) -- status is a once-per-second heartbeat blink on
--  the board's user LED (LD2, PA5), unrelated to bus activity: Poll
--  reports no status to react to (its own doc comment explains why),
--  so unlike spike 1's error-counting blink pattern, this one only says
--  "the loop is alive."
with STM32G474.GPIO, STM32G474.Clock, STM32G474.RNG, STM32G474.I2C1;
with Board;

procedure Main
  with SPARK_Mode
is
   use type STM32G474.Clock.Ticks;

   LED : constant STM32G474.GPIO.Pin_Id := 5;

   Next_Toggle : STM32G474.Clock.Ticks := 1;   --  Ticks_Per_Second = 1
   LED_On      : Boolean := False;
begin
   STM32G474.GPIO.Configure_Output (LED);
   STM32G474.Clock.Enable;
   STM32G474.RNG.Enable;
   STM32G474.I2C1.Enable ((Own_Address => 16#42#));

   --  §5: L2 never blocks, so this loop services the bus flat-out --
   --  the heartbeat below only *observes* elapsed time via
   --  STM32G474.Clock.Now directly (Board.Clock_Sig is a conformance
   --  check, not a value to read from, §6.1); it never delays, so it
   --  can never stall Responder.Poll.
   loop
      Board.Responder.Poll;
      declare
         --  A volatile-function call must be the whole right-hand side
         --  (SPARK RM 7.1.3(9), same rule RP2040.I2C0's Check_Abort
         --  documents) -- read once into a local, then compare/compute.
         Ticks_Now : constant STM32G474.Clock.Ticks := STM32G474.Clock.Now;
      begin
         if Ticks_Now >= Next_Toggle then
            LED_On := not LED_On;
            if LED_On then
               STM32G474.GPIO.Set_High (LED);
            else
               STM32G474.GPIO.Set_Low (LED);
            end if;
            Next_Toggle := Ticks_Now + 1;   --  1 tick = 1 second
         end if;
      end;
   end loop;
end Main;
