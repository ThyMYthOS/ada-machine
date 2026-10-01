with Ada.Text_IO;

package body Test_Report is

   Max_Name : constant := 40;

   Name_Buf : String (1 .. Max_Name);
   Name_Len : Natural := 0;
   Checks   : Natural := 0;
   Failures : Natural := 0;

   function Trim (S : String) return String is
     (if S'Length > 0 and then S (S'First) = ' '
      then S (S'First + 1 .. S'Last) else S);

   procedure Start (Name : String) is
      N : constant Natural := Natural'Min (Name'Length, Max_Name);
   begin
      Name_Buf (1 .. N) := Name (Name'First .. Name'First + N - 1);
      Name_Len := N;
      Ada.Text_IO.Put_Line ("TEST " & Name_Buf (1 .. Name_Len) & ": START");
   end Start;

   procedure Check (Condition : Boolean; What : String) is
   begin
      Checks := Checks + 1;
      if Condition then
         Ada.Text_IO.Put_Line ("  ok: " & What);
      else
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("  FAIL: " & What);
      end if;
   end Check;

   procedure Info (What : String; Value : Integer) is
   begin
      Ada.Text_IO.Put_Line ("  info: " & What & " = " & Trim (Integer'Image (Value)));
   end Info;

   procedure Finish is
   begin
      if Checks = 0 then
         Ada.Text_IO.Put_Line ("  FAIL: the test made no checks at all");
         Failures := Failures + 1;
      end if;
      Ada.Text_IO.Put_Line
        ("TEST " & Name_Buf (1 .. Name_Len) & ": "
         & (if Failures = 0 then "PASS" else "FAIL"));
      loop
         null;
      end loop;
   end Finish;

end Test_Report;
