--  avr_board.ads -- spike 2's wiring (Appendix B): declarations, the one
--  exported vector symbol, and the bus-specific setup main.adb (shared
--  with the I2C variant) calls before using Env_Sensor.
with Machine.SPI.Generic_Master, Machine.GPIO.Generic_Digital_Out,
     Machine.Blocking.Generic_Delays, Machine.Async.SPI,
     Machine.Regmap.Generic_SPI_Binding, Machine.Generic_Critical_Section;
with Machine.UART.Generic_Port, Machine.Blocking.Log_Sink, Machine.Log;
with ATmega328P.SPI, ATmega328P.Delays, ATmega328P.GPIO, ATmega328P.USART0,
     ATmega328P.Critical_Section;
with ATmega328P_PAC.Port_B, ATmega328P_PAC.SPI, ATmega328P_PAC.USART0;
with BME280;
package AVR_Board
  with SPARK_Mode
is

   package SPI_Sig is new Machine.SPI.Generic_Master   --  SPI conformance,
     (Can_Push => ATmega328P.SPI.Can_Push,             --  checked for free
      Push     => ATmega328P.SPI.Push,
      Can_Pop  => ATmega328P.SPI.Can_Pop,
      Pop      => ATmega328P.SPI.Pop);

   --  §14.4's critical section, for real: the I-bit in SREG (D8's own
   --  ATmega-specific answer, same category as the fixed SPI pins).
   package CS_Section is new Machine.Generic_Critical_Section
     (Mask_State => ATmega328P.Critical_Section.Mask_State,
      Enter      => ATmega328P.Critical_Section.Enter,
      Leave      => ATmega328P.Critical_Section.Leave);

   package SPI_Async is new Machine.Async.SPI
     (Port => SPI_Sig, Buffer_Size => 32,      --  27-byte calibration burst fits
      Critical => CS_Section);

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

   procedure CS_Set (To : Machine.GPIO.Level)    --  (body: PB2; §6.4 pattern)
     with Global => (In_Out => ATmega328P_PAC.Port_B.PORTB);
   package CS is new Machine.GPIO.Generic_Digital_Out (Set => CS_Set);

   package Regs is new Machine.Regmap.Generic_SPI_Binding
     (Bus => Await.As_Blocking, CS => CS);

   package Delays_Sig is new Machine.Blocking.Generic_Delays
     (Delay_Us => ATmega328P.Delays.Delay_Us,
      Delay_Ms => ATmega328P.Delays.Delay_Ms);

   package UART0_Sig is new Machine.UART.Generic_Port  --  conformance check
     (Frame       => ATmega328P.USART0.Frame,           --  of ATmega328P.USART0
      Is_Tx_Ready => ATmega328P.USART0.Is_Tx_Ready,
      Put_Frame   => ATmega328P.USART0.Put_Frame,
      Is_Rx_Ready => ATmega328P.USART0.Is_Rx_Ready,
      Get_Frame   => ATmega328P.USART0.Get_Frame);

   --  The UART-backed log sink (§10.3/§14.2): a direct blocking drain
   --  over USART0, same choice as spike1_pico (no runtime FIFO here).
   package Sink is new Machine.Blocking.Log_Sink (UART => UART0_Sig);

   --  BME280's Log_Event formal predates the Level vocabulary (it takes
   --  only Event_Id + Arg), so board wiring assigns every driver-observed
   --  event (Wrong_Chip_Id/Bus_Fault/Timed_Out) the same severity here,
   --  same as spike1_pico's board wiring.
   procedure Log_Event (E : Machine.Log.Event_Id;
                        A : Machine.Log.Arg := Machine.Log.No_Arg);

   --  A per-measurement trace line, emitted directly by main.adb (not
   --  through the driver's Log_Event, which only reports faults): Info
   --  severity, Arg = Temperature in hundredths of a degree Celsius.
   Ev_Measured : constant Machine.Log.Event_Id := 16#1000#;

   --  Byte-for-byte the same driver as spike 1 (the shared bme280 crate, §11):
   package Env_Sensor is new BME280
     (Regs      => Regs.As_Device,
      Wait      => Delays_Sig,
      Log_Event => Log_Event);

   --  Bus-specific bring-up (D8): CS idle-high, SPI enabled + its
   --  interrupt, USART0 enabled, global interrupts on. The one shared
   --  main.adb (src/main.adb) calls this and its I2C-variant counterpart
   --  identically.
   procedure Setup
     with Global => (In_Out => (ATmega328P_PAC.Port_B.DDRB,
                                 ATmega328P_PAC.Port_B.PORTB,
                                 ATmega328P_PAC.SPI.SPCR),
                     Output => (ATmega328P_PAC.SPI.SPSR, ATmega328P.SPI.State,
                                ATmega328P_PAC.USART0.UCSR0A,
                                ATmega328P_PAC.USART0.UCSR0B,
                                ATmega328P_PAC.USART0.UCSR0C,
                                ATmega328P_PAC.USART0.UBRR0L,
                                ATmega328P_PAC.USART0.UBRR0H));
end AVR_Board;
