with Machine.SPI;

package body Board
  with SPARK_Mode
is

   procedure CS_Set (High : Boolean) is
   begin
      if High then
         ESP32C3.GPIO.Set_High (10);
      else
         ESP32C3.GPIO.Set_Low (10);
      end if;
   end CS_Set;

   protected body DMA_Handler is
      procedure On_Interrupt is
         Status : Machine.SPI.Transaction_Status;
      begin
         ESP32C3.SPI2.Handle_DMA_Interrupt (Status);
         DMA_SPI.Signal_Complete (Status);
      end On_Interrupt;
   end DMA_Handler;

end Board;
