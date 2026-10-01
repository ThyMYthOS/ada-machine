--  MUST NOT COMPILE on the `light` profile: a protected object.
--  (tests/negative/cases.list: light_protected.) Never built by `make build`.
procedure Neg_Main is

   protected P is
      procedure Bump;
   private
      N : Natural := 0;
   end P;

   protected body P is
      procedure Bump is
      begin
         N := N + 1;
      end Bump;
   end P;

begin
   P.Bump;
end Neg_Main;
