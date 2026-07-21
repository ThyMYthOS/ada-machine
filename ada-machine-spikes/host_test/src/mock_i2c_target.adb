package body Mock_I2C_Target
  with SPARK_Mode,
       Refined_State => (State => (Addr_Pending, Read_Dir, Stop_Pending,
                                    Rx_Queue, Rx_Count, Rx_Pos,
                                    Tx_Log, Tx_Count, Acks))
is
   Addr_Pending : Boolean := False;
   Read_Dir     : Boolean := False;
   Stop_Pending : Boolean := False;

   Rx_Queue : array (1 .. Max_Rx) of Byte := (others => 0);
   Rx_Count : Natural range 0 .. Max_Rx := 0;
   Rx_Pos   : Natural range 0 .. Max_Rx := 0;

   Tx_Log   : array (1 .. Max_Tx) of Byte := (others => 0);
   Tx_Count : Natural range 0 .. Max_Tx := 0;

   Acks : Natural := 0;

   procedure Reset is
   begin
      Addr_Pending := False;
      Read_Dir     := False;
      Stop_Pending := False;
      Rx_Queue     := (others => 0);
      Rx_Count     := 0;
      Rx_Pos       := 0;
      Tx_Log       := (others => 0);
      Tx_Count     := 0;
      Acks         := 0;
   end Reset;

   procedure Begin_Transaction (Read_Direction : Boolean) is
   begin
      Addr_Pending := True;
      Read_Dir     := Read_Direction;
      Rx_Count     := 0;
      Rx_Pos       := 0;
   end Begin_Transaction;

   procedure Feed_Byte (Data : Byte) is
   begin
      if Rx_Count < Max_Rx then
         Rx_Count := Rx_Count + 1;
         Rx_Queue (Rx_Count) := Data;
      end if;
   end Feed_Byte;

   procedure Simulate_Stop is
   begin
      Stop_Pending := True;
   end Simulate_Stop;

   function Pushed_Count return Natural is (Tx_Count);
   function Pushed_Byte (I : Positive) return Byte is (Tx_Log (I));
   function Ack_Count return Natural is (Acks);

   function Is_Address_Matched return Boolean is (Addr_Pending);
   function Is_Read_From_Master return Boolean is (Read_Dir);

   procedure Ack_Address is
   begin
      Addr_Pending := False;
      Acks := Acks + 1;
   end Ack_Address;

   function Can_Pop return Boolean is (Rx_Pos < Rx_Count);

   procedure Pop (Data : out Byte; Status : in out Bus_Status) is
   begin
      Data := 0;
      if Status /= Ok then
         return;                              --  chained: skip if pending
      end if;
      if Rx_Pos < Rx_Count then
         Rx_Pos := Rx_Pos + 1;
         Data   := Rx_Queue (Rx_Pos);
      end if;
   end Pop;

   --  Always ready: the mock's "master" never withholds a read clock,
   --  so nothing beyond the responder's own Cur_Phase gates whether
   --  Push is meaningfully called.
   function Can_Push return Boolean is (True);

   procedure Push (Data : Byte; Status : in out Bus_Status) is
   begin
      if Status /= Ok then
         return;                              --  chained: skip if pending
      end if;
      if Tx_Count < Max_Tx then
         Tx_Count := Tx_Count + 1;
         Tx_Log (Tx_Count) := Data;
      end if;
   end Push;

   function Is_Stop return Boolean is (Stop_Pending);

   procedure Clear_Stop is
   begin
      Stop_Pending := False;
   end Clear_Stop;

end Mock_I2C_Target;
