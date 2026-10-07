--  Test-mode hook, normal build: nothing. Enabled is a static constant, so
--  `if Test_Run.Enabled then ...` in main.adb folds away and no test code
--  is compiled (see ../../test_support/test_mode.gpr).
package Test_Run
  with SPARK_Mode
is
   Enabled : constant Boolean := False;
   procedure Run_And_Halt is null;
end Test_Run;
