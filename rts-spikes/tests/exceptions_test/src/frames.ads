--  Frames the exceptions test raises through. They live in a package, in
--  separate subprograms, so that a propagating exception really does unwind
--  more than one frame -- a raise and a handler in the same subprogram is
--  compiled to a jump and never touches the runtime's propagation code.
with Ada.Finalization;

package Frames is

   My_Error : exception;

   --  Incremented each time an exception passes through Relay.
   Handler_Count : Natural := 0;

   --  Incremented by Guard's Finalize.
   Finalized : Natural := 0;

   type Guard is new Ada.Finalization.Limited_Controlled with null record;
   overriding procedure Finalize (G : in out Guard);

   Message : constant String := "raised three frames down";

   procedure Raise_Constraint;            --  Constraint_Error with Message
   procedure Raise_Mine;                  --  My_Error with Message
   procedure Level_2;                     --  calls Raise_Constraint, no handler
   procedure Level_1;                     --  calls Level_2, no handler
   procedure Relay;                       --  catches, counts, re-raises (raise;)
   procedure With_Guard;                  --  owns a Guard, then raises
   procedure Divide (Numerator, Denominator : Integer; Result : out Integer);
   procedure Index (I : Integer);         --  indexes a 1 .. 3 array with I

end Frames;
