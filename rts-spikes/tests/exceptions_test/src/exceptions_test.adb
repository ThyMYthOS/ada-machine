--  RTS-PRODUCTION.md A4, "exceptions (embedded)": raise across a subprogram
--  boundary, catch, re-raise / propagate, check the identity, name and message.
with Ada.Exceptions; use Ada.Exceptions;
with Frames;
with Test_Report;    use Test_Report;

procedure Exceptions_Test is

   function Contains (Text, Part : String) return Boolean is
   begin
      for I in Text'First .. Text'Last - Part'Length + 1 loop
         if Text (I .. I + Part'Length - 1) = Part then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   Zero   : Integer := 0;   --  not a constant: the checks below must run
   Result : Integer := 0;
   Caught : Boolean;
   Saved  : Exception_Occurrence;
begin
   Start ("exceptions_test");

   --  1. Two unwound frames, no handler in between; caught by name.
   Caught := False;
   begin
      Frames.Level_1;
      Check (False, "Level_1 returned normally");
   exception
      when E : Constraint_Error =>
         Caught := True;
         Check (Exception_Identity (E) = Constraint_Error'Identity,
                "identity is Constraint_Error");
         Check (Exception_Name (E) = "CONSTRAINT_ERROR",
                "Exception_Name = CONSTRAINT_ERROR");
         Check (Exception_Message (E) = Frames.Message,
                "Exception_Message survives two unwound frames");
   end;
   Check (Caught, "Constraint_Error propagated out of Level_1");

   --  2. A user-defined exception through a re-raising intermediate frame
   --     (raise; keeps identity and message).
   Caught := False;
   begin
      Frames.Relay;
   exception
      when E : Frames.My_Error =>
         Caught := True;
         Check (Exception_Name (E) = "FRAMES.MY_ERROR",
                "user exception name is the expanded name");
         Check (Exception_Message (E) = Frames.Message,
                "message survives 'raise;' in an intermediate handler");
   end;
   Check (Caught, "My_Error propagated out of Relay");
   Check (Frames.Handler_Count = 1,
          "the intermediate handler ran exactly once");

   --  3. Exception_Information mentions the name and the message.
   begin
      Frames.Raise_Constraint;
   exception
      when E : others =>
         declare
            Info : constant String := Exception_Information (E);
         begin
            Check (Contains (Info, "CONSTRAINT_ERROR"),
                   "Exception_Information names the exception");
            Check (Contains (Info, Frames.Message),
                   "Exception_Information carries the message");
         end;
         Save_Occurrence (Saved, E);
   end;

   --  4. A saved occurrence can be re-raised later, from another frame.
   Caught := False;
   begin
      Reraise_Occurrence (Saved);
   exception
      when E : Constraint_Error =>
         Caught := True;
         Check (Exception_Message (E) = Frames.Message,
                "Reraise_Occurrence keeps the message");
   end;
   Check (Caught, "Reraise_Occurrence raised again");

   --  5. Raise_Exception with a message.
   begin
      Raise_Exception (Program_Error'Identity, "from Raise_Exception");
   exception
      when E : Program_Error =>
         Check (Exception_Message (E) = "from Raise_Exception",
                "Raise_Exception message");
   end;

   --  6. Language-defined checks raise the predefined exceptions.
   Caught := False;
   begin
      Frames.Divide (1, Zero, Result);
   exception
      when Constraint_Error => Caught := True;
   end;
   Check (Caught, "division by zero raises Constraint_Error");

   Caught := False;
   begin
      Frames.Index (Zero + 4);              --  index 4 of 1 .. 3
   exception
      when Constraint_Error => Caught := True;
   end;
   Check (Caught, "index out of range raises Constraint_Error");

   --  7. Finalization runs while an exception propagates.
   Caught := False;
   begin
      Frames.With_Guard;
   exception
      when Frames.My_Error => Caught := True;
   end;
   Check (Caught,                 "My_Error propagated out of With_Guard");
   Check (Frames.Finalized = 1,   "the Guard was finalized during propagation");

   --  8. 'others' catches everything, and a handler can be left normally.
   Caught := False;
   begin
      Frames.Level_1;
   exception
      when others => Caught := True;
   end;
   Check (Caught, "'when others' handled and execution continued");

   Finish;
end Exceptions_Test;
