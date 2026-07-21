--  avr_board.ads -- spike 2's I2C wiring variant (Appendix B, TODO.md P0
--  #1): the same Machine.Blocking.I2C + bme280 spike 1 uses over RP2040's
--  command FIFO, here driven by ATmega328P.I2C's TWI state machine instead
--  -- unmodified, validating that the push/pop shape survives a second,
--  structurally different I2C controller. Blocking/polled, like spike 1
--  (not interrupt-driven like this crate's SPI variant): no ISR for TWI
--  itself, only for ATmega328P.Clock's Timer0 tick (needed because
--  Machine.Blocking.I2C, unlike SPI's Generic_Delays, takes a Clock formal).
with Machine.Generic_Clock, Machine.I2C.Generic_Master;
with Machine.Blocking.Delays, Machine.Blocking.I2C;
with Machine.Regmap.Generic_I2C_Binding;
with Machine.UART.Generic_Port, Machine.Blocking.Log_Sink, Machine.Log;
with ATmega328P.I2C, ATmega328P.Clock, ATmega328P.USART0;
with ATmega328P_PAC.TWI, ATmega328P_PAC.Timer0, ATmega328P_PAC.USART0;
with BME280;

package AVR_Board
  with SPARK_Mode
is

   package Clock_Sig is new Machine.Generic_Clock
     (Ticks            => ATmega328P.Clock.Ticks,
      Ticks_Per_Second => ATmega328P.Clock.Ticks_Per_Second,
      Now              => ATmega328P.Clock.Now);

   package I2C_Sig is new Machine.I2C.Generic_Master     --  I2C conformance,
     (Set_Target        => ATmega328P.I2C.Set_Target,    --  checked for free
      Can_Push          => ATmega328P.I2C.Can_Push,
      Push_Write        => ATmega328P.I2C.Push_Write,
      Push_Read_Request => ATmega328P.I2C.Push_Read_Request,
      Can_Pop           => ATmega328P.I2C.Can_Pop,
      Pop               => ATmega328P.I2C.Pop);

   --  Timer0-overflow pump: interrupt attachment is the application's
   --  decision (D5), same policy as the SPI variant's SPI_Interrupt.
   procedure Timer0_Interrupt
     with Export, External_Name => "__vector_16";  --  ATmega328P TIMER0_OVF_vect
   pragma Machine_Attribute (Timer0_Interrupt, "signal");
   --  (body: ATmega328P.Clock.On_Tick;)

   package Delays is new Machine.Blocking.Delays (Clock => Clock_Sig);
   package I2C    is new Machine.Blocking.I2C (Port => I2C_Sig, Clock => Clock_Sig);

   package Regs is new Machine.Regmap.Generic_I2C_Binding
     (Bus => I2C.As_Signature, Device_Address => 16#76#);

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

   --  Byte-for-byte the same driver as spike 1 and this crate's SPI variant
   --  (the shared bme280 crate, §11):
   package Env_Sensor is new BME280
     (Regs      => Regs.As_Device,
      Wait      => Delays.As_Signature,
      Log_Event => Log_Event);

   --  Bus-specific bring-up (D8): I2C + the Timer0 tick it needs for
   --  timeouts, USART0 enabled, global interrupts on. The one shared
   --  main.adb (src/main.adb) calls this and the SPI variant's
   --  counterpart identically.
   procedure Setup
     with Global => (In_Out => ATmega328P_PAC.TWI.TWCR,
                     Output => (ATmega328P_PAC.TWI.TWBR,
                                ATmega328P_PAC.TWI.TWSR,
                                ATmega328P_PAC.Timer0.TCCR0A,
                                ATmega328P_PAC.Timer0.TCCR0B,
                                ATmega328P_PAC.Timer0.TIMSK0,
                                ATmega328P.I2C.State,
                                ATmega328P.Clock.State,
                                ATmega328P_PAC.USART0.UCSR0A,
                                ATmega328P_PAC.USART0.UCSR0B,
                                ATmega328P_PAC.USART0.UCSR0C,
                                ATmega328P_PAC.USART0.UBRR0L,
                                ATmega328P_PAC.USART0.UBRR0H));
end AVR_Board;
