--  MUST NOT COMPILE on the `light` profile: a task declaration.
--  (tests/negative/cases.list: light_task.) Never built by `make build`.
procedure Neg_Main is

   task T;

   task body T is
   begin
      null;
   end T;

begin
   null;
end Neg_Main;
