--  stm32g474-i2c1.ads -- spike 4's target-mode L2 (Appendix D): the
--  never-blocking data phase conforming Machine.I2C.Generic_Target, over
--  the modern "I2C v2" IP (ADDR/DIR/TXIS/RXNE/ICR) -- deliberately not
--  the legacy F1/F4/L1 peripheral, whose slave-mode errata reputation is
--  exactly why this spike's target board was picked (see README's plan).
--
--  This is the first target/slave-mode L2 in this repo -- spikes 1-3
--  only ever drove the MCU as bus master. Bus-fault detection (BERR/
--  ARLO) is out of scope for this first cut, same footing as the rest
--  of this spike's "logic-only, no real bus" validation.
with Machine.I2C;
use type Machine.Byte, Machine.I2C.Bus_Status;
with STM32G474_PAC.RCC, STM32G474_PAC.GPIOB, STM32G474_PAC.I2C1;

package STM32G474.I2C1
  with Preelaborate, SPARK_Mode
is
   --  Configuration: deliberately STM32G474-specific (D8) -- own address
   --  only. SCL/SDA are fixed to PB6/PB7 (§9 rule 1: no other pin
   --  combination is wired by this spike).
   type Config is record
      Own_Address : Machine.I2C.Address_7_Bit := 16#42#;
   end record;

   procedure Enable (Cfg : Config := (others => <>))
     with Global => (In_Out => (STM32G474_PAC.RCC.APB1ENR1,
                                STM32G474_PAC.RCC.AHB2ENR,
                                STM32G474_PAC.GPIOB.MODER,
                                STM32G474_PAC.GPIOB.OTYPER,
                                STM32G474_PAC.GPIOB.PUPDR,
                                STM32G474_PAC.GPIOB.AFRL),
                     Output => (STM32G474_PAC.I2C1.CR1,
                                STM32G474_PAC.I2C1.TIMINGR,
                                STM32G474_PAC.I2C1.OAR1));
                    --  CR1: Output, not In_Out -- Enable always
                    --  overwrites it outright (disable, then PE at the
                    --  end), never reads the incoming value.
   procedure Disable
     with Global => (Output => STM32G474_PAC.I2C1.CR1);

   --  Never-blocking data phase (§6.2), conforming Machine.I2C.Generic_Target.
   function  Is_Address_Matched return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => STM32G474_PAC.I2C1.ISR);
   function  Is_Read_From_Master return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => STM32G474_PAC.I2C1.ISR);
   procedure Ack_Address
     with Inline_Always, Global => (Output => STM32G474_PAC.I2C1.ICR);

   function  Can_Pop return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => STM32G474_PAC.I2C1.ISR);
   procedure Pop (Data : out Machine.Byte; Status : in out Machine.I2C.Bus_Status)
     with Inline_Always,
          Global => (In_Out => STM32G474_PAC.I2C1.RXDR),
          Post   => (if Status'Old /= Machine.I2C.Ok
                     then Status = Status'Old and Data = 0);

   function  Can_Push return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => STM32G474_PAC.I2C1.ISR);
   procedure Push (Data : Machine.Byte; Status : in out Machine.I2C.Bus_Status)
     with Inline_Always,
          Global => (In_Out => STM32G474_PAC.I2C1.TXDR),
          Post   => (if Status'Old /= Machine.I2C.Ok then Status = Status'Old);

   function  Is_Stop return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => STM32G474_PAC.I2C1.ISR);
   procedure Clear_Stop
     with Inline_Always, Global => (Output => STM32G474_PAC.I2C1.ICR);

end STM32G474.I2C1;
