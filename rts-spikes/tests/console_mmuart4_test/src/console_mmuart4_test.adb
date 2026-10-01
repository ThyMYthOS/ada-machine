--  RTS-PRODUCTION.md A4, "Text_IO ... through the selected Console value".
--
--  Built with Console => mmuart4. The program cannot tell which UART its bytes
--  left by, so the verdict is read by the HOST from the serial port the
--  configuration says it should be on (MMUART4 = QEMU's serial 4).
with Test_Report;   use Test_Report;

procedure Console_Mmuart4_Test is
begin
   Start ("console_mmuart4_test");
   Check (True, "this line was written with Console => mmuart4");
   Finish;
end Console_Mmuart4_Test;
