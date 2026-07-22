with ATmega328P.GPIO;
with System.GCC_Builtins;
with Machine.GPIO; use Machine.GPIO;

package body AVR_Board
  with SPARK_Mode
is

   procedure SPI_Interrupt is
   begin
      SPI_Async.On_Interrupt;
   end SPI_Interrupt;

   --  CS on PB2 (the hardware /SS pin, repurposed as a plain output in
   --  master mode -- §6.1's own note: chip selects are ordinary GPIOs
   --  owned by the application/binding, never part of the SPI class).
   procedure CS_Set (To : Machine.GPIO.Level) is
   begin
      if To = High then
         ATmega328P.GPIO.Set_High (2);
      else
         ATmega328P.GPIO.Set_Low (2);
      end if;
   end CS_Set;

   procedure Setup is
   begin
      --  CS idle-high before the bus is touched.
      ATmega328P.GPIO.Configure (2, ATmega328P.GPIO.Output);
      ATmega328P.GPIO.Set_High (2);

      ATmega328P.SPI.Enable ((Divisor => ATmega328P.SPI.Div_16, Mode => 0,
                              MSB_First => True));
      ATmega328P.SPI.Enable_Interrupt;
      ATmega328P.USART0.Enable ((Baud_Hz => 9_600));
      System.GCC_Builtins.Sei;  --  global interrupt enable (D5: the
                                --  application's decision, not the
                                --  runtime's, on this ZFP floor) -- the
                                --  GCC intrinsic, not inline asm, so this
                                --  stays in SPARK (§6.6).
   end Setup;

   procedure Log_Event (E : Machine.Log.Event_Id;
                        A : Machine.Log.Arg := Machine.Log.No_Arg) is
   begin
      if Machine.Log.Enabled (Machine.Log.Warning) then
         Sink.Emit (Machine.Log.Warning, E, A);
      end if;
   end Log_Event;

end AVR_Board;
