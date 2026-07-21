--  Mock_I2C_Target -- host stand-in for Machine.I2C.Generic_Target's
--  formals (§15.4-style mock, spike 4's Appendix D). Scripted one bus
--  event at a time by the test driver (Begin_Transaction/Feed_Byte/
--  Simulate_Stop), mirroring what real target-mode hardware presents:
--  an edge-triggered address-match flag that persists until Ack_Address,
--  a byte queue for the write direction, and a log of served bytes for
--  the read direction.
with Machine;    use Machine;
with Machine.I2C; use Machine.I2C;

package Mock_I2C_Target
  with SPARK_Mode,
       Abstract_State => State,
       Initializes    => State
is
   Max_Rx : constant := 8;
   Max_Tx : constant := 32;

   --  Test-driver controls.
   procedure Reset
     with Global => (Output => State);

   procedure Begin_Transaction (Read_Direction : Boolean)
     with Global => (In_Out => State);
   --  Simulates a fresh address match (repeated-START if called again
   --  before Simulate_Stop, exactly as real hardware allows) and clears
   --  the RX queue for the phase that follows.

   procedure Feed_Byte (Data : Byte)
     with Global => (In_Out => State);
   --  Queues one byte the "master" has written, available to Pop on the
   --  responder's next poll. A no-op past Max_Rx bytes (test scripts
   --  stay within that).

   procedure Simulate_Stop
     with Global => (In_Out => State);

   --  Inspection for assertions.
   function Pushed_Count return Natural
     with Global => (Input => State);
   function Pushed_Byte (I : Positive) return Byte
     with Global => (Input => State), Pre => I <= Pushed_Count;
   function Ack_Count return Natural
     with Global => (Input => State);

   --  The Machine.I2C.Generic_Target formal shape (§6.1: instantiating
   --  this against it in host_test/src/main.adb *is* the conformance
   --  check for a mock, same as any real HAL's).
   function  Is_Address_Matched return Boolean
     with Global => (Input => State);
   function  Is_Read_From_Master return Boolean
     with Global => (Input => State);
   procedure Ack_Address
     with Global => (In_Out => State);
   function  Can_Pop return Boolean
     with Global => (Input => State);
   procedure Pop (Data : out Byte; Status : in out Bus_Status)
     with Global => (In_Out => State),
          Post   => (if Status'Old /= Ok then Status = Status'Old and Data = 0);
   function  Can_Push return Boolean
     with Global => null;
   --  Always True (see the body): the mock's "master" never withholds a
   --  read clock, so this genuinely reads no state -- Global => null,
   --  not Input => State.
   procedure Push (Data : Byte; Status : in out Bus_Status)
     with Global => (In_Out => State),
          Post   => (if Status'Old /= Ok then Status = Status'Old);
   function  Is_Stop return Boolean
     with Global => (Input => State);
   procedure Clear_Stop
     with Global => (In_Out => State);

end Mock_I2C_Target;
