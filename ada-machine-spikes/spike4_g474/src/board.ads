--  board.ads -- spike 4's wiring (Appendix D): pure declarations; reads
--  like the schematic. First board in this repo where the MCU is wired
--  as an I2C *target* rather than a master.
with Machine.Generic_Clock, Machine.I2C.Generic_Target, Machine.RNG.Generic_Source;
with STM32G474.Clock, STM32G474.I2C1, STM32G474.RNG;
with Time_RNG_Target;
with Interfaces;
package Board
  with SPARK_Mode
is

   package Clock_Sig is new Machine.Generic_Clock
     (Ticks            => STM32G474.Clock.Ticks,
      Ticks_Per_Second => STM32G474.Clock.Ticks_Per_Second,
      Now              => STM32G474.Clock.Now);

   package I2C1_Sig is new Machine.I2C.Generic_Target   --  conformance check
     (Is_Address_Matched  => STM32G474.I2C1.Is_Address_Matched,   --  of STM32G474.I2C1,
      Is_Read_From_Master => STM32G474.I2C1.Is_Read_From_Master,  --  §6.1, for free
      Ack_Address         => STM32G474.I2C1.Ack_Address,
      Can_Pop             => STM32G474.I2C1.Can_Pop,
      Pop                 => STM32G474.I2C1.Pop,
      Can_Push            => STM32G474.I2C1.Can_Push,
      Push                => STM32G474.I2C1.Push,
      Is_Stop             => STM32G474.I2C1.Is_Stop,
      Clear_Stop          => STM32G474.I2C1.Clear_Stop);

   package RNG_Sig is new Machine.RNG.Generic_Source    --  conformance check
     (Word     => Interfaces.Unsigned_32,                --  of STM32G474.RNG
      Is_Ready => STM32G474.RNG.Is_Ready,
      Get_Word => STM32G474.RNG.Get_Word);

   package Responder is new Time_RNG_Target
     (Bus => I2C1_Sig, Rng => RNG_Sig, Clock => Clock_Sig);

   --  Native configuration stays native (D8): main calls
   --    STM32G474.Clock.Enable;
   --    STM32G474.RNG.Enable;
   --    STM32G474.I2C1.Enable ((Own_Address => 16#42#));
   --  before first use of Responder.Poll.
   --
   --  No Machine.Blocking adapter is wired here on purpose: a target
   --  device must stay continuously responsive to the bus, so nothing
   --  in this spike's main loop may block (unlike spike 1's master-side
   --  main.adb, which is free to block between its own measurement
   --  cycles). main.adb reads STM32G474.Clock.Now directly for its
   --  heartbeat pacing instead of a busy-wait delay.
end Board;
