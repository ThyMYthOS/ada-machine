with ATmega328P_PAC.TWI; use ATmega328P_PAC.TWI;
with Interfaces; use Interfaces;

package body ATmega328P.I2C_Target
  with SPARK_Mode,
       Refined_State => (State => Acked)
is

   use Machine.I2C;

   --  The one bit of state this hardware needs beyond its registers: the
   --  own-SLA+R match has been acknowledged by Ack_Address but TWINT is
   --  deliberately still set (TWDR is not loaded yet, see the .ads), so
   --  Is_Address_Matched must stop reporting it and Can_Push may start.
   Acked : Boolean := False
     with Volatile, Async_Readers, Async_Writers;

   --  Release the stretch and keep listening/ACKing: the common TWCR
   --  value for every "carry on" step of a slave transaction.
   Release : constant Unsigned_8 := TWCR_TWINT or TWCR_TWEA or TWCR_TWEN;

   --  Every volatile read is taken alone into a local first (SPARK RM
   --  7.1.3(9)), as in ATmega328P.I2C.

   function Status_Code return Unsigned_8
     with Volatile_Function, Global => (Input => TWSR)
   is
      Sr_Raw : constant Unsigned_8 := TWSR;
   begin
      return Sr_Raw and TWSR_STATUS_MASK;
   end Status_Code;

   function Flag_Set return Boolean
     with Volatile_Function, Global => (Input => TWCR)
   is
      Cr_Now : constant Unsigned_8 := TWCR;
   begin
      return (Cr_Now and TWCR_TWINT) /= 0;
   end Flag_Set;

   function Is_Write_Match (Code : Unsigned_8) return Boolean is
     (Code = TW_SR_SLA_ACK or else Code = TW_SR_ARB_LOST_SLA_ACK);

   function Is_Read_Match (Code : Unsigned_8) return Boolean is
     (Code = TW_ST_SLA_ACK or else Code = TW_ST_ARB_LOST_SLA_ACK);

   procedure Enable (Cfg : Config := (others => <>)) is
   begin
      TWAR  := Shift_Left (Unsigned_8 (Cfg.Own_Address), 1);   --  TWGCE = 0
      TWSR  := 0;                                              --  prescaler off
      Acked := False;
      TWCR  := Release;           --  clear TWINT, enable, ACK own address
   end Enable;

   procedure Disable is
   begin
      TWCR := 0;
   end Disable;

   function Is_Address_Matched return Boolean is
      Ack_Now : constant Boolean := Acked;
      Set_Now : constant Boolean := Flag_Set;
      Code    : constant Unsigned_8 := Status_Code;
   begin
      return Set_Now and then not Ack_Now
        and then (Is_Write_Match (Code) or else Is_Read_Match (Code));
   end Is_Address_Matched;

   function Is_Read_From_Master return Boolean is
      Code : constant Unsigned_8 := Status_Code;
   begin
      return Code = TW_ST_SLA_ACK or else Code = TW_ST_ARB_LOST_SLA_ACK
        or else Code = TW_ST_DATA_ACK or else Code = TW_ST_DATA_NACK
        or else Code = TW_ST_LAST_DATA;
   end Is_Read_From_Master;

   procedure Ack_Address is
      Code : constant Unsigned_8 := Status_Code;
   begin
      if Is_Write_Match (Code) then
         TWCR  := Release;        --  receive: the next TWINT is a data byte
         Acked := False;
      elsif Is_Read_Match (Code) then
         Acked := True;           --  transmit: TWDR first (Push), then release
      end if;
   end Ack_Address;

   function Can_Pop return Boolean is
      Set_Now : constant Boolean := Flag_Set;
      Code    : constant Unsigned_8 := Status_Code;
   begin
      return Set_Now and then Code = TW_SR_DATA_ACK;
   end Can_Pop;

   procedure Pop (Data : out Machine.Byte; Status : in out Machine.I2C.Bus_Status) is
      Code : Unsigned_8;
      Dr   : Unsigned_8;
   begin
      Data := 0;
      if Status /= Ok then
         return;                              --  chained: skip if pending
      end if;
      Code := Status_Code;
      if Code = TW_BUS_ERROR then
         --  Illegal START/STOP: recover by releasing the bus (TWSTO), the
         --  datasheet's reset idiom; fail clean (§7.1 rule 2).
         Status := Bus_Error;
         TWCR   := TWCR_TWINT or TWCR_TWSTO or TWCR_TWEA or TWCR_TWEN;
      elsif Code = TW_SR_DATA_ACK then
         Dr   := TWDR;
         Data := Machine.Byte (Dr);
         TWCR := Release;         --  next byte (or STOP) raises TWINT again
      end if;
   end Pop;

   function Can_Push return Boolean is
      Ack_Now : constant Boolean := Acked;
      Set_Now : constant Boolean := Flag_Set;
      Code    : constant Unsigned_8 := Status_Code;
   begin
      return Set_Now
        and then ((Ack_Now and then Is_Read_Match (Code))
                  or else Code = TW_ST_DATA_ACK);
   end Can_Push;

   procedure Push (Data : Machine.Byte; Status : in out Machine.I2C.Bus_Status) is
      Code : Unsigned_8;
   begin
      if Status /= Ok then
         return;                              --  chained: skip if pending
      end if;
      Code := Status_Code;
      if Code = TW_BUS_ERROR then
         Status := Bus_Error;
         TWCR   := TWCR_TWINT or TWCR_TWSTO or TWCR_TWEA or TWCR_TWEN;
         Acked  := False;
      else
         TWDR  := Unsigned_8 (Data);
         TWCR  := Release;        --  starts shifting TWDR out; master's
         Acked := False;          --  (N)ACK decides what comes next
      end if;
   end Push;

   function Is_Stop return Boolean is
      Set_Now : constant Boolean := Flag_Set;
      Code    : constant Unsigned_8 := Status_Code;
   begin
      return Set_Now
        and then (Code = TW_SR_STOP or else Code = TW_ST_DATA_NACK
                  or else Code = TW_ST_LAST_DATA);
   end Is_Stop;

   procedure Clear_Stop is
   begin
      TWCR  := Release;           --  back to not-addressed listening
      Acked := False;
   end Clear_Stop;

end ATmega328P.I2C_Target;
