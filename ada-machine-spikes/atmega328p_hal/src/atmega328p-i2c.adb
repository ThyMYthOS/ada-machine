with ATmega328P_PAC.TWI; use ATmega328P_PAC.TWI;
with ATmega328P_HAL_Config;
with Interfaces; use Interfaces;

package body ATmega328P.I2C
  with SPARK_Mode,
       Refined_State => (State => (Target, Addressed_Dir, Read_Pending,
                                    Stop_Pending))
is

   use Machine.I2C;

   type Direction is (None, Write, Read);

   --  Bookkeeping this depth-1, no-FIFO hardware needs beyond the raw
   --  registers: which address a transaction targets, whether (and in
   --  which direction) START+address has already been sent for it, and
   --  whether a read result is outstanding / should be followed by STOP
   --  once collected. Touched from mainline code only (no ISR on this
   --  floor -- I2C here is blocking/polled, unlike the SPI variant's
   --  interrupt-driven pump), but still Volatile: External per the .ads
   --  Abstract_State, for the same reason ATmega328P.SPI's Busy is.
   Target        : Unsigned_8 := 0
     with Volatile, Async_Readers, Async_Writers;
   Addressed_Dir : Direction := None
     with Volatile, Async_Readers, Async_Writers;
   Read_Pending  : Boolean := False
     with Volatile, Async_Readers, Async_Writers;
   Stop_Pending  : Boolean := False
     with Volatile, Async_Readers, Async_Writers;

   --  Every volatile (TWCR/TWSR/TWDR/Target/Addressed_Dir/Read_Pending/
   --  Stop_Pending) read below is taken alone into a local first, then
   --  combined with other operators via that ordinary local -- SPARK
   --  requires a volatile read to be the whole right-hand side of an
   --  assignment/declaration, not combined with anything else in the same
   --  expression (SPARK RM 7.1.3(9)).

   procedure Await_TWINT
     with Global => (Input => TWCR)
   is
   begin
      loop
         declare
            Cr_Now : constant Unsigned_8 := TWCR;
         begin
            exit when (Cr_Now and TWCR_TWINT) /= 0;
         end;
      end loop;
   end Await_TWINT;

   function Status_Code return Unsigned_8
     with Volatile_Function, Global => (Input => TWSR)
   is
      Sr_Raw : constant Unsigned_8 := TWSR;
   begin
      return Sr_Raw and TWSR_STATUS_MASK;
   end Status_Code;

   procedure Enable (Cfg : Config := (others => <>)) is
      --  Long_Integer throughout: F_CPU (16_000_000) alone overflows
      --  AVR's 16-bit Integer, and the division must happen before the
      --  result (a small, TWBR-sized value) is narrowed.
      Divisor : constant Long_Integer :=
        Long_Integer (ATmega328P_HAL_Config.F_CPU) / Cfg.Baud_Hz;
   begin
      TWBR := Unsigned_8 ((Divisor - 16) / 2);   --  prescaler = 1 (TWPS = 00)
      TWSR := 0;
      Target        := 0;
      Addressed_Dir := None;
      Read_Pending  := False;
      Stop_Pending  := False;
      --  Prime TWINT: issue a benign STOP (no transaction pending) so
      --  Can_Push's "TWINT set = ready" invariant holds from the very
      --  first real push -- TWINT's reset value is 0, and nothing else
      --  ever sets it without a hardware action being triggered first.
      TWCR := TWCR_TWINT or TWCR_TWSTO or TWCR_TWEN;
      Await_TWINT;
   end Enable;

   procedure Set_Target (Address : Machine.I2C.Address_7_Bit) is
   begin
      Target        := Unsigned_8 (Address);
      Addressed_Dir := None;
      --  Reset, not just Addressed_Dir: a caller starting a new
      --  transaction without popping a previous transaction's last read
      --  result would otherwise leave Read_Pending stuck True, wrongly
      --  blocking Can_Push for the new transaction forever.
      Read_Pending  := False;
      Stop_Pending  := False;
   end Set_Target;

   function Can_Push return Boolean is
      Cr_Now : constant Unsigned_8 := TWCR;
      Rp_Now : constant Boolean := Read_Pending;
   begin
      return not Rp_Now and then (Cr_Now and TWCR_TWINT) /= 0;
   end Can_Push;

   procedure Push_Write (Data : Machine.Byte; Stop : Boolean;
                         Status : in out Machine.I2C.Bus_Status)
   is
      Sr_Now  : Unsigned_8;
      Dir_Now : constant Direction := Addressed_Dir;
      Tgt_Now : Unsigned_8;
   begin
      if Status /= Ok then
         return;                              --  chained: skip if pending
      end if;

      if Dir_Now = Write then
         --  Check the previous data byte's ack (Can_Push already
         --  confirmed TWINT is set, so TWSR reflects that completed
         --  action).
         Sr_Now := Status_Code;
         if Sr_Now /= TW_MT_DATA_ACK then
            Status        := Nack_Data;
            Addressed_Dir := None;             --  transaction aborted
            return;
         end if;
      else
         --  First byte of this transaction, or a direction change:
         --  (repeated) START + address+W.
         TWCR := TWCR_TWINT or TWCR_TWSTA or TWCR_TWEN;
         Await_TWINT;
         Sr_Now := Status_Code;
         if Sr_Now /= TW_START and then Sr_Now /= TW_REP_START then
            Status        := Bus_Error;
            Addressed_Dir := None;
            return;
         end if;

         Tgt_Now := Target;
         TWDR := Shift_Left (Tgt_Now, 1);       --  address<<1 | 0 (write)
         TWCR := TWCR_TWINT or TWCR_TWEN;
         Await_TWINT;
         Sr_Now := Status_Code;
         if Sr_Now = TW_MT_SLA_NACK then
            Status        := Nack_Address;
            Addressed_Dir := None;
            return;
         elsif Sr_Now /= TW_MT_SLA_ACK then
            Status        := Arbitration_Lost;
            Addressed_Dir := None;
            return;
         end if;
         Addressed_Dir := Write;
      end if;

      --  Kick the data byte (async: gated by Can_Push on the next call).
      TWDR := Unsigned_8 (Data);
      if Stop then
         --  Last byte of the transaction: nothing else will ever poll
         --  for its ack, so wait for it here and issue STOP synchronously.
         TWCR := TWCR_TWINT or TWCR_TWEN;
         Await_TWINT;
         Sr_Now := Status_Code;
         if Sr_Now /= TW_MT_DATA_ACK then
            Status := Nack_Data;
         end if;
         TWCR := TWCR_TWINT or TWCR_TWSTO or TWCR_TWEN;
         Addressed_Dir := None;                 --  transaction closed
      else
         TWCR := TWCR_TWINT or TWCR_TWEN;        --  kick, don't wait
      end if;
   end Push_Write;

   procedure Push_Read_Request (Stop : Boolean;
                                Status : in out Machine.I2C.Bus_Status)
   is
      Sr_Now  : Unsigned_8;
      Dir_Now : constant Direction := Addressed_Dir;
      Tgt_Now : Unsigned_8;
   begin
      if Status /= Ok then
         return;                              --  chained: skip if pending
      end if;

      if Dir_Now /= Read then
         --  First read of this transaction, or a direction change (the
         --  write-then-read shape of Write_Read, §7.1): (repeated) START
         --  + address+R.
         TWCR := TWCR_TWINT or TWCR_TWSTA or TWCR_TWEN;
         Await_TWINT;
         Sr_Now := Status_Code;
         if Sr_Now /= TW_START and then Sr_Now /= TW_REP_START then
            Status        := Bus_Error;
            Addressed_Dir := None;
            return;
         end if;

         Tgt_Now := Target;
         TWDR := Shift_Left (Tgt_Now, 1) or 1;   --  address<<1 | 1 (read)
         TWCR := TWCR_TWINT or TWCR_TWEN;
         Await_TWINT;
         Sr_Now := Status_Code;
         if Sr_Now = TW_MR_SLA_NACK then
            Status        := Nack_Address;
            Addressed_Dir := None;
            return;
         elsif Sr_Now /= TW_MR_SLA_ACK then
            Status        := Arbitration_Lost;
            Addressed_Dir := None;
            return;
         end if;
         Addressed_Dir := Read;
      end if;

      --  Kick the incoming byte (async): ACK it (more bytes expected)
      --  unless this is the last one requested, in which case NACK it --
      --  the standard TWI idiom for telling the slave to stop sending.
      --  STOP itself is deferred to Pop, once this byte has actually
      --  arrived (Stop_Pending).
      if Stop then
         TWCR := TWCR_TWINT or TWCR_TWEN;              --  TWEA = 0: NACK
      else
         TWCR := TWCR_TWINT or TWCR_TWEA or TWCR_TWEN;  --  TWEA = 1: ACK
      end if;
      Read_Pending := True;
      Stop_Pending := Stop;
   end Push_Read_Request;

   function Can_Pop return Boolean is
      Cr_Now : constant Unsigned_8 := TWCR;
      Rp_Now : constant Boolean := Read_Pending;
   begin
      return Rp_Now and then (Cr_Now and TWCR_TWINT) /= 0;
   end Can_Pop;

   procedure Pop (Data : out Machine.Byte;
                  Status : in out Machine.I2C.Bus_Status)
   is
      Sr_Now : Unsigned_8;
      Dr_Now : Unsigned_8;
      Sp_Now : constant Boolean := Stop_Pending;
   begin
      Data := 0;
      if Status /= Ok then
         return;                              --  chained: skip if pending
      end if;
      Sr_Now := Status_Code;
      Dr_Now := TWDR;
      Read_Pending := False;
      if Sr_Now /= TW_MR_DATA_ACK and then Sr_Now /= TW_MR_DATA_NACK then
         Status        := Bus_Error;
         Addressed_Dir := None;
         return;
      end if;
      Data := Machine.Byte (Dr_Now);
      if Sp_Now then
         TWCR          := TWCR_TWINT or TWCR_TWSTO or TWCR_TWEN;
         Addressed_Dir := None;
      end if;
   end Pop;

end ATmega328P.I2C;
