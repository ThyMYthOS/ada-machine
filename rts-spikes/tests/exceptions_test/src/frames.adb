package body Frames is

   overriding procedure Finalize (G : in out Guard) is
      pragma Unreferenced (G);
   begin
      Finalized := Finalized + 1;
   end Finalize;

   procedure Raise_Constraint is
   begin
      raise Constraint_Error with Message;
   end Raise_Constraint;

   procedure Raise_Mine is
   begin
      raise My_Error with Message;
   end Raise_Mine;

   procedure Level_2 is
   begin
      Raise_Constraint;
   end Level_2;

   procedure Level_1 is
   begin
      Level_2;
   end Level_1;

   procedure Relay is
   begin
      Raise_Mine;
   exception
      when others =>
         Handler_Count := Handler_Count + 1;
         raise;
   end Relay;

   procedure With_Guard is
      G : Guard;
      pragma Unreferenced (G);
   begin
      Raise_Mine;
   end With_Guard;

   procedure Divide (Numerator, Denominator : Integer; Result : out Integer) is
   begin
      Result := Numerator / Denominator;
   end Divide;

   procedure Index (I : Integer) is
      A : array (1 .. 3) of Integer := (others => 0);
   begin
      A (I) := 1;
      if A (1) + A (2) + A (3) > 3 then   --  keeps A live
         raise Program_Error;
      end if;
   end Index;

end Frames;
