--  atmega328p-clock.ads -- Machine.Generic_Clock over Timer0, needed only
--  because Machine.Blocking.I2C (unlike Generic_Delays) takes a Clock formal
--  for its timeouts. §10.1's "AVR ZFP owns no tick -- a tick would
--  confiscate one of the application's few timers" is why the SPI variant's
--  Delays stays a pure busy-loop instead; I2C's blocking adapter has no
--  such shortcut, so this is the one place on this floor that spends a
--  timer. Ticks is mod 2**32 per README §6.5 ("AVR uses 2**32").
with ATmega328P_HAL_Config;
with ATmega328P_PAC.Timer0;

package ATmega328P.Clock
  with Preelaborate, SPARK_Mode,
       Abstract_State => (State with External => (Async_Readers, Async_Writers)),
       Initializes    => State
is
   type Ticks is mod 2**32;
   Ticks_Per_Second : constant := ATmega328P_HAL_Config.F_CPU / 64 / 256;
                                    --  Timer0 clk/64, 8-bit overflow (/256)

   procedure Enable
     with Global => (Output => (ATmega328P_PAC.Timer0.TCCR0A,
                                 ATmega328P_PAC.Timer0.TCCR0B,
                                 ATmega328P_PAC.Timer0.TIMSK0,
                                 State));

   function  Now return Ticks
     with Inline_Always, Volatile_Function, Global => (Input => State);

   --  Timer0-overflow pump: the application attaches it onto the vector
   --  symbol (D5, same "app owns interrupt attachment" policy as the SPI
   --  variant's SPI_Interrupt/On_Interrupt in avr_board.ads).
   procedure On_Tick
     with Global => (In_Out => State);  --  reads Tick_Count, then increments it
end ATmega328P.Clock;
