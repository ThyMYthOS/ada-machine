--  avr_board.ads -- Appendix C.3, verbatim: pure declarations plus the
--  one exported vector symbol.
with Machine.SPI.Generic_Master, Machine.Generic_Digital_Out,
     Machine.Blocking.Generic_Delays, Machine.Async.SPI,
     Machine.Regmap.Generic_SPI_Binding;
with ATmega328P.SPI, ATmega328P.Delays;
with ATmega328P_PAC.Port_B;
with BME280;
package AVR_Board
  with SPARK_Mode
is

   package SPI_Sig is new Machine.SPI.Generic_Master   --  SPI conformance,
     (Can_Push => ATmega328P.SPI.Can_Push,             --  checked for free
      Push     => ATmega328P.SPI.Push,
      Can_Pop  => ATmega328P.SPI.Can_Pop,
      Pop      => ATmega328P.SPI.Pop);

   package SPI_Async is new Machine.Async.SPI
     (Port => SPI_Sig, Buffer_Size => 32);     --  27-byte calibration burst fits

   --  Interrupt attachment is the application's decision (D5). ZFP-AVR has
   --  no Attach_Handler: export onto the vector symbol, with the AVR ISR
   --  calling convention:
   procedure SPI_Interrupt
     with Export, External_Name => "__vector_17";       --  ATmega328P SPI_STC_vect
        --  No explicit Global here: it calls into SPI_Async's instantiated
        --  On_Interrupt, whose adapter-owned buffers/flags are body-private
        --  state of a generic package with no Abstract_State of its own
        --  (§7.1's postconditions were added there instead, see
        --  Machine.Async.SPI) -- GNATprove still derives the concrete
        --  effect through the instantiation; nothing forces it to be
        --  spelled out by hand here.
   pragma Machine_Attribute (SPI_Interrupt, "signal");  --  ISR prologue/epilogue
   --  (body: SPI_Async.On_Interrupt;)

   package Await is new SPI_Async.Generic_Await
     (Sleep_Until_Interrupt => ATmega328P.Delays.Sleep_Idle);

   procedure CS_Set (High : Boolean)            --  (body: drive PB2; §6.4 pattern)
     with Global => (In_Out => ATmega328P_PAC.Port_B.PORTB);
   package CS is new Machine.Generic_Digital_Out (Set => CS_Set);

   package Regs is new Machine.Regmap.Generic_SPI_Binding
     (Bus => Await.As_Blocking, CS => CS);

   package Delays_Sig is new Machine.Blocking.Generic_Delays
     (Delay_Us => ATmega328P.Delays.Delay_Us,
      Delay_Ms => ATmega328P.Delays.Delay_Ms);

   --  Byte-for-byte the same driver as spike 1 (Appendix A.3):
   package Env_Sensor is new BME280
     (Regs => Regs.As_Device,
      Wait => Delays_Sig);
end AVR_Board;
