--  RTS-PRODUCTION.md A4, "Text_IO ... through the selected Console value".
--
--  Built with Console => mmuart1. The program cannot tell which UART its bytes
--  left by, so the verdict is read by the HOST from the serial port the
--  configuration says it should be on (MMUART1 = QEMU's second -serial).
with Test_Report;   use Test_Report;

procedure Console_Test is
begin
   Start ("console_test");
   Check (True, "this line was written with Console => mmuart1");
   Finish;
end Console_Test;
