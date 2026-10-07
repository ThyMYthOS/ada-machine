--  Test-mode hook, test build (ADA_MACHINE_TEST_MODE=on): run the shared
--  test_support runner over this crate's wiring, then halt.
package Test_Run
  with SPARK_Mode
is
   Enabled : constant Boolean := True;
   procedure Run_And_Halt
     with No_Return;         --  never returns (halts)
end Test_Run;
