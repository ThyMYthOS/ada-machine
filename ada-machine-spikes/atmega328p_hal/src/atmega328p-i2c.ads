--  atmega328p-i2c.ads -- AVR TWI as Machine.I2C.Generic_Master (TODO.md P0
--  #1: validating the never-blocking push/pop shape against a register-event
--  state machine, not RP2040's DW_apb_i2c command FIFO). TWI has no FIFO and
--  no auto-start-on-write: a full byte transfer needs up to three chained
--  hardware actions the first time in a transaction (START, address+R/W,
--  data) but only one (data) after that, each gated by the single TWINT
--  flag. Push_Write/Push_Read_Request hide the START/address sub-steps
--  behind a bounded busy-spin -- §6.2 permits "completes in bounded short
--  time", not only "returns immediately"; each sub-step is one hardware
--  action, the same order of magnitude as the register writes Enable
--  already does synchronously elsewhere in this HAL. Only the data byte
--  itself -- the repeated, hot-path operation -- stays fully async, gated by
--  Can_Push/Can_Pop reading TWINT directly, the same depth-1 shape as
--  ATmega328P.SPI's Busy.
with Machine.I2C;
use type Machine.I2C.Bus_Status;
use type Machine.Byte;
with ATmega328P_PAC.TWI;

package ATmega328P.I2C
  with Preelaborate, SPARK_Mode,
       Abstract_State => (State with External => (Async_Readers, Async_Writers)),
       Initializes    => State
is
   --  Configuration: ATmega-specific (D8), like ATmega328P.SPI.Config.
   --  Long_Integer, not Positive/Integer: AVR's Integer is 16 bits (max
   --  32_767), too narrow for a 100_000..400_000 Hz baud rate.
   type Config is record
      Baud_Hz : Long_Integer range 1 .. 400_000 := 100_000;
   end record;

   procedure Enable (Cfg : Config := (others => <>))
     with Global => (Output => (ATmega328P_PAC.TWI.TWBR,
                                 ATmega328P_PAC.TWI.TWSR,
                                 State),
                     In_Out => ATmega328P_PAC.TWI.TWCR);

   procedure Set_Target (Address : Machine.I2C.Address_7_Bit)
     with Global => (Output => State);

   --  Volatile_Function on both: they read hardware/External state, so two
   --  textually-identical calls need not agree (SPARK RM 7.1.3(9)) -- same
   --  reasoning as ATmega328P.SPI's Can_Push/Can_Pop.
   function  Can_Push return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => (ATmega328P_PAC.TWI.TWCR, State));

   --  TWDR is In_Out, not Output, on all three of these -- like TWCR, it
   --  has Effective_Reads/Writes (ATmega328P_PAC.TWI), and GNATprove's
   --  auto-derived Global for a subprogram touching such an object
   --  classifies it In_Out regardless of whether the body itself ever
   --  reads it back.
   procedure Push_Write (Data : Machine.Byte; Stop : Boolean;
                         Status : in out Machine.I2C.Bus_Status)
     with Global => (In_Out => (State, ATmega328P_PAC.TWI.TWCR,
                                 ATmega328P_PAC.TWI.TWDR),
                     Input  => ATmega328P_PAC.TWI.TWSR),
          Post   => (if Status'Old /= Machine.I2C.Ok
                     then Status = Status'Old);      --  §7.1 rule 1

   procedure Push_Read_Request (Stop : Boolean;
                                Status : in out Machine.I2C.Bus_Status)
     with Global => (In_Out => (State, ATmega328P_PAC.TWI.TWCR,
                                 ATmega328P_PAC.TWI.TWDR),
                     Input  => ATmega328P_PAC.TWI.TWSR),
          Post   => (if Status'Old /= Machine.I2C.Ok
                     then Status = Status'Old);

   function  Can_Pop return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => (ATmega328P_PAC.TWI.TWCR, State));

   procedure Pop (Data : out Machine.Byte;
                  Status : in out Machine.I2C.Bus_Status)
     with Global => (In_Out => (State, ATmega328P_PAC.TWI.TWCR,
                                 ATmega328P_PAC.TWI.TWDR),
                     Input  => ATmega328P_PAC.TWI.TWSR),
          Post   => (if Status'Old /= Machine.I2C.Ok
                     then Status = Status'Old and Data = 0);
end ATmega328P.I2C;
