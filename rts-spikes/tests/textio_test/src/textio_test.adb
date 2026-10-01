--  RTS-PRODUCTION.md A4, "Text_IO": output through the selected Console, and a
--  round trip through the same serial port.
--
--  Two different checkers are involved, on purpose:
--    - OUTPUT is asserted by the HOST. A program cannot verify that its own
--      bytes reached the wire, so tests/run_tests.sh compares what appeared on
--      the serial port with textio_test/console.expected.
--    - INPUT is asserted by the PROGRAM: the runner feeds console.in to the
--      port, Ada.Text_IO.Get reads it (polling Is_Rx_Ready on the MMUART's LSR)
--      and Check compares it with the text that was sent.
with Ada.Text_IO;
with Test_Report;   use Test_Report;

procedure Textio_Test is

   Line : String (1 .. 64);
   Last : Natural := 0;
   C    : Character;
begin
   Start ("textio_test");

   Ada.Text_IO.Put_Line ("TEXTIO: Put_Line works");
   Ada.Text_IO.Put ("TEXTIO: Put of a string, ");
   Ada.Text_IO.Put ('o');
   Ada.Text_IO.Put ('f');
   Ada.Text_IO.Put (' ');
   Ada.Text_IO.Put ("characters");
   Ada.Text_IO.New_Line;
   Ada.Text_IO.Put_Line ("TEXTIO: punctuation !""#$%&'()*+,-./:;<=>?@[\]^_`{|}~");

   --  Round trip: tell the host we are ready, then read a line it has queued.
   Ada.Text_IO.Put_Line ("TEXTIO: awaiting a line on the console");
   loop
      Ada.Text_IO.Get (C);
      exit when C = ASCII.LF or else C = ASCII.CR;
      if Last < Line'Last then
         Last := Last + 1;
         Line (Last) := C;
      end if;
   end loop;
   Ada.Text_IO.Put_Line ("TEXTIO: echo [" & Line (1 .. Last) & "]");

   Check (Last > 0, "a line arrived on the console input");
   Check (Line (1 .. Last) = "round trip 12345",
          "Ada.Text_IO.Get returned exactly the bytes the host sent");

   Finish;
end Textio_Test;
