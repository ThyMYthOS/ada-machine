--  atmega328p-i2c_target.ads -- AVR TWI in *target* (slave) mode as
--  Machine.I2C.Generic_Target (TODO.md #11): the second, structurally
--  different target-mode controller, after STM32G474's I2C v2 flag block.
--
--  Where STM32 presents separate, independently clearable flags
--  (ADDR/DIR/RXNE/TXIS/STOPF), TWI presents ONE interrupt flag (TWINT) plus
--  a status *code* in TWSR, and the hardware stretches SCL for as long as
--  TWINT is set. Mapping that onto the signature needs three contortions,
--  each documented rather than hidden:
--    1. Ack_Address cannot always release the stretch. For a read
--       transaction (own SLA+R) TWI starts shifting TWDR out the moment
--       TWINT is cleared, so TWDR must be loaded first: Ack_Address then
--       only records that the address was acknowledged (one bit of state,
--       Acked) and the release happens in the following Push. For a write
--       transaction (own SLA+W) it releases at once. STM32 needs no such
--       state.
--    2. A read transaction's end is the master's NACK (status 0xC0/0xC8),
--       not a STOP event -- TWI reports no 0xA0 after a transmit phase. Is_Stop
--       is true for both, and Clear_Stop returns the hardware to
--       not-addressed listening in both cases.
--    3. Clock stretching is intrinsic: there is no NOSTRETCH option, so
--       there is no overrun/underrun to report; Bus_Error (status 0x00) is
--       the only fault Pop/Push can see.
--  Validation: compiled and flow/proof-checked here, conformance-
--  instantiated in tests/conformance.ads -- not run on silicon and not
--  scripted through a TWI model.
with Machine.I2C;
use type Machine.I2C.Bus_Status;
use type Machine.Byte;
with ATmega328P_PAC.TWI;

package ATmega328P.I2C_Target
  with Preelaborate, SPARK_Mode,
       Abstract_State => (State with External => (Async_Readers, Async_Writers)),
       Initializes    => State
is
   --  Configuration: ATmega-specific (D8) -- own address only; the bus
   --  speed is the master's business in target mode (no TWBR needed).
   type Config is record
      Own_Address : Machine.I2C.Address_7_Bit := 16#42#;
   end record;

   procedure Enable (Cfg : Config := (others => <>))
     with Global => (Output => (ATmega328P_PAC.TWI.TWAR,
                                ATmega328P_PAC.TWI.TWSR,
                                ATmega328P_PAC.TWI.TWCR,
                                State));

   procedure Disable
     with Global => (Output => ATmega328P_PAC.TWI.TWCR);

   --  Never-blocking data phase (§6.2), conforming Machine.I2C.Generic_Target.
   function  Is_Address_Matched return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => (ATmega328P_PAC.TWI.TWCR,
                               ATmega328P_PAC.TWI.TWSR, State));
   function  Is_Read_From_Master return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => ATmega328P_PAC.TWI.TWSR);
   procedure Ack_Address
     with Global => (In_Out => (State, ATmega328P_PAC.TWI.TWCR),
                     Input  => ATmega328P_PAC.TWI.TWSR);

   function  Can_Pop return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => (ATmega328P_PAC.TWI.TWCR,
                               ATmega328P_PAC.TWI.TWSR));
   procedure Pop (Data : out Machine.Byte; Status : in out Machine.I2C.Bus_Status)
     with Global => (In_Out => (ATmega328P_PAC.TWI.TWCR,
                                ATmega328P_PAC.TWI.TWDR),
                     Input  => ATmega328P_PAC.TWI.TWSR),
          Post   => (if Status'Old /= Machine.I2C.Ok
                     then Status = Status'Old and Data = 0);

   function  Can_Push return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => (ATmega328P_PAC.TWI.TWCR,
                               ATmega328P_PAC.TWI.TWSR, State));
   procedure Push (Data : Machine.Byte; Status : in out Machine.I2C.Bus_Status)
     with Global => (In_Out => (State, ATmega328P_PAC.TWI.TWCR,
                                ATmega328P_PAC.TWI.TWDR),
                     Input  => ATmega328P_PAC.TWI.TWSR),
          Post   => (if Status'Old /= Machine.I2C.Ok then Status = Status'Old);

   function  Is_Stop return Boolean
     with Inline_Always, Volatile_Function,
          Global => (Input => (ATmega328P_PAC.TWI.TWCR,
                               ATmega328P_PAC.TWI.TWSR));
   procedure Clear_Stop
     with Global => (Output => (State, ATmega328P_PAC.TWI.TWCR));
end ATmega328P.I2C_Target;
