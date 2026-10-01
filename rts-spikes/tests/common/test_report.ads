--  Test_Report -- the one reporting convention every test application shares,
--  so tests/run_tests.sh has exactly one thing to look for (RTS-PRODUCTION.md A4).
--
--  Console protocol (everything goes through Ada.Text_IO, i.e. through the
--  runtime's own System.Text_IO, which is part of what is being tested):
--
--    TEST <name>: START          printed by Start
--      ok: <what>                one line per Check that held
--      FAIL: <what>              one line per Check that did not
--      info: <what> = <value>    measurements, never asserted by the runner
--    TEST <name>: PASS           printed by Finish, only if every Check held
--    TEST <name>: FAIL           printed by Finish otherwise
--
--  Finish prints FAIL as well when NO check was made at all: a test that
--  asserts nothing must not be able to report success (the project's recurring
--  failure mode -- RTS-PRODUCTION.md risk register). It never returns: a bare-
--  board main must not fall off its end, and the runner stops QEMU as soon as
--  it sees a final line.
--
--  Not task-safe: call it from the environment task only. Tasks under test
--  record their observations in protected objects and main reports them.

package Test_Report is

   procedure Start (Name : String);

   procedure Check (Condition : Boolean; What : String);

   procedure Info (What : String; Value : Integer);

   procedure Finish;
   pragma No_Return (Finish);

end Test_Report;
