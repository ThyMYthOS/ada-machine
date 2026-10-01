--  RTS-PRODUCTION.md A4, "Text_IO ... through the selected Console value".
--
--  Built with Console => mmuart2. The program cannot tell which UART its bytes
--  left by, so the verdict is read by the HOST from the serial port the
--  configuration says it should be on (MMUART2 = QEMU's serial 2).
with Test_Report;   use Test_Report;

procedure Console_Mmuart2_Test is
begin
   Start ("console_mmuart2_test");
   Check (True, "this line was written with Console => mmuart2");
   Finish;
end Console_Mmuart2_Test;
