with ATmega328P.GPIO;

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
   procedure CS_Set (High : Boolean) is
   begin
      if High then
         ATmega328P.GPIO.Set_High (2);
      else
         ATmega328P.GPIO.Set_Low (2);
      end if;
   end CS_Set;

end AVR_Board;
