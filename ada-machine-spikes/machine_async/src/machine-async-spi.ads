--  Interrupt-driven SPI transfers: transfer-oriented, access-free.
--  The adapter owns the buffers (no access types => no caller buffers);
--  the application attaches On_Interrupt to the SPI vector.
--
--  Critical (§14.4) brackets the *mainline* accesses to state
--  On_Interrupt also touches (the kick-off in Start_Exchange, the
--  Got/RX_Buf snapshot in Read_Response, the timeout-abort in
--  Generic_Await.Exchange) -- On_Interrupt itself stays free of
--  Enter/Leave: it already runs with the hardware's own ISR-entry
--  masking, and re-disabling inside it would only cost the hot path
--  for no additional safety.
with Machine.SPI.Generic_Master, Machine.Blocking.Generic_SPI_Master,
     Machine.Generic_Critical_Section;
use type Machine.SPI.Transaction_Status;  --  for the Post contracts' "="/"/="
generic
   with package Port is new Machine.SPI.Generic_Master (<>);
                                    --  never-blocking L2 data phase to pump
   Buffer_Size : Positive := 32;    --  adapter-owned TX/RX buffers
   with package Critical is new Machine.Generic_Critical_Section (<>);
                                    --  §14.4: mutual exclusion vs. On_Interrupt
   with procedure On_Complete (Transferred : Natural;
                               Status : Machine.SPI.Transaction_Status) is null;
                                    --  completion hook; runs in ISR context
package Machine.Async.SPI
  with SPARK_Mode
is

   --  Ghost lock-balance model (§14.4 proof harness). Tracks, purely
   --  for GNATprove's benefit, whether one of Start_Exchange /
   --  Read_Response / Generic_Await.Exchange currently holds the
   --  Critical section: the .adb resets it False as the very first
   --  statement of each of these three, sets it True immediately after
   --  each Critical.Enter, and False immediately before the matching
   --  Critical.Leave. The point is to make "every Enter is followed by
   --  a Leave on every control-flow path" a proof obligation instead of
   --  a hand-checked invariant -- a future edit that adds an early
   --  return, or a new branch, between an Enter and its Leave and
   --  forgets to restore the balance turns into an unproved
   --  postcondition below, not a silent bug: the entry reset only ever
   --  fires once, at the top, so any such bug still leaves In_Critical
   --  True at the offending return, exactly as before.
   --
   --  Because the update is a plain overwrite (True/False), not a
   --  nesting counter, the balance property that is actually meaningful
   --  and provable is "not In_Critical" at exit of each of these three
   --  top-level operations (they are never reentrant against their own
   --  lock) -- stated as a Post below. Deliberately NOT a Pre: an
   --  earlier version of this ghost model also required
   --  "Pre => not In_Critical" plus a "In_Critical = In_Critical'Old"
   --  restatement in Post, which is provable within this package (every
   --  internal call already establishes it) but is NOT provable by an
   --  arbitrary external caller reached only through a generic formal
   --  package chain that has no way to see this ghost global at all
   --  (confirmed: instantiating this package through
   --  Machine.Regmap.Generic_SPI_Binding, e.g. spike2_avr's
   --  avr_board.ads, left two brand-new "precondition might fail"
   --  residuals there that did not exist before this ghost model was
   --  added -- a real collateral proof regression, not a pre-existing
   --  one). Resetting In_Critical to False at the top of each of these
   --  three operations makes their own entry state irrelevant (any
   --  caller may call them from any ghost state) while catching exactly
   --  the same class of bug -- a missing Leave between an Enter and a
   --  return -- with no Pre required and hence no leak to callers.
   --
   --  Honest limitation: this proves the *ghost model* balances (and
   --  therefore that the Enter/Leave bracketing in the body is
   --  structurally sound), not that Critical.Enter/Leave themselves
   --  behave as claimed -- the ghost is wired to the real calls only
   --  by textual adjacency in the .adb. Attaching a contract to
   --  Critical.Enter/Leave directly is out of scope: they are generic
   --  formal subprograms (Machine.Generic_Critical_Section's
   --  signature), and formal subprograms cannot cleanly carry state-
   --  dependent contracts. Ghost + Boolean: zero runtime cost.
   In_Critical : Boolean := False with Ghost;

   --  Initiation: never blocks; chained; rejected while Busy.
   procedure Start_Exchange (TX     : Byte_Array;
                             Status : in out Machine.SPI.Transaction_Status)
     with Post => (if Status'Old /= Machine.SPI.Ok
                   then Status = Status'Old)              --  §7.1 rule 1
                  and then not In_Critical;      --  §14.4 balance: never
                                                  --  returns holding it
   --  Volatile_Function: Busy reads volatile state (Active), so two
   --  textually-identical calls need not agree (SPARK RM 7.1.3(9)).
   function  Busy return Boolean with Inline, Volatile_Function;
   procedure Read_Response (Into : out Byte_Array; Last : out Natural)
     --  copy out after completion
     with Post => not In_Critical;                        --  §14.4 balance

   --  The pump: bounded, never blocks; the APPLICATION attaches it.
   procedure On_Interrupt;

   --  Await: turns the async core into a blocking view -- and thereby
   --  into a Generic_SPI_Master conformance.
   generic
      with procedure Sleep_Until_Interrupt is null;  --  default: spin
   package Generic_Await
     with SPARK_Mode
   is
      procedure Exchange (TX         : Byte_Array;
                          RX         : out Byte_Array;
                          Timeout_Ms : Natural;
                          Status     : in out Machine.SPI.Transaction_Status)
        with Post => (if Status'Old /= Machine.SPI.Ok
                      then Status = Status'Old
                           and then (for all I in RX'Range => RX (I) = 0))
                     and then not In_Critical;             --  §14.4 balance
      package As_Blocking is new Machine.Blocking.Generic_SPI_Master
        (Exchange => Exchange);
   end Generic_Await;

end Machine.Async.SPI;
