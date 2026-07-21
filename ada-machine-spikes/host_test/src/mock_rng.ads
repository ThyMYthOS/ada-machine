--  Mock_RNG -- host stand-in for Machine.RNG.Generic_Source's formals.
--  Always ready; the test pre-loads the next word Get_Word hands back,
--  so a test can prove Time_RNG_Target's Latch_Snapshot drew the word
--  it saw at latch time and did not re-fetch it mid-transaction.
with Interfaces;
use type Interfaces.Unsigned_32;
with Machine.RNG; use Machine.RNG;

package Mock_RNG
  with SPARK_Mode,
       Abstract_State => State,
       Initializes    => State
is
   procedure Set_Next_Word (W : Interfaces.Unsigned_32)
     with Global => (Output => State);

   function  Is_Ready return Boolean
     with Global => null;
   --  Always True (see the body): genuinely reads no state -- Global =>
   --  null, not Input => State.

   procedure Get_Word (Value : out Interfaces.Unsigned_32;
                       Status : in out Rng_Status)
     with Global => (Input => State),
          Post   => (if Status'Old /= Ok then Status = Status'Old and Value = 0);

end Mock_RNG;
