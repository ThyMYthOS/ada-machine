--  RTS-PRODUCTION.md A4, "Text_IO ... through the selected Console value".
--
--  Built with Console => mmuart3. The program cannot tell which UART its bytes
--  left by, so the verdict is read by the HOST from the serial port the
--  configuration says it should be on (MMUART3 = QEMU's serial 3).
with Test_Report;   use Test_Report;

procedure Console_Mmuart3_Test is
begin
   Start ("console_mmuart3_test");
   Check (True, "this line was written with Console => mmuart3");
   Finish;
end Console_Mmuart3_Test;
