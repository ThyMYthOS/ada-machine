------------------------------------------------------------------------------
--                                                                          --
--                         GNAT COMPILER COMPONENTS                         --
--                                                                          --
--                       A D A . E X C E P T I O N S                        --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--          Copyright (C) 1992-2011, Free Software Foundation, Inc.         --
--          Copyright (C) 2012, 2022 Rolf Ebert                             --
--                                                                          --
-- GNAT is free software;  you can  redistribute it  and/or modify it under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  GNAT is distributed in the hope that it will be useful, but WITH- --
-- OUT ANY WARRANTY;  without even the  implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE.                                     --
--                                                                          --
-- As a special exception under Section 7 of GPL version 3, you are granted --
-- additional permissions described in the GCC Runtime Library Exception,   --
-- version 3.1, as published by the Free Software Foundation.               --
--                                                                          --
-- You should have received a copy of the GNU General Public License and    --
-- a copy of the GCC Runtime Library Exception along with this program;     --
-- see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see    --
-- <http://www.gnu.org/licenses/>.                                          --
--                                                                          --
-- GNAT was originally developed  by the GNAT team at  New York University. --
-- Extensive contributions were provided by Ada Core Technologies Inc.      --
--                                                                          --
------------------------------------------------------------------------------

--  README §14.3: fault reports are written through the same §10.3
--  diagnostic sink every other producer uses (Console_FIFO), then the
--  handler parks -- see Park below for why that replaced the old
--  unconditional Reset.
with Ada.Unchecked_Conversion;
with Console_FIFO;
with Interfaces;
with System; use System;
with System.Machine_Code;
with System.Storage_Elements; use System.Storage_Elements;

package body Ada.Exceptions is

   procedure Reset;
   pragma Import (Ada, Reset);
   for Reset'Address use System.Null_Address;
   pragma No_Return (Reset);

   procedure Park with No_Return;
   --  README §14.3/§10.3: disable interrupts and halt in place, rather
   --  than reset. A reset re-runs startup, which zeroes .bss -- wiping
   --  the fault message this handler just wrote into Console_FIFO and
   --  defeating "the message sits in RAM for a post-mortem probe read"
   --  (§10.3). Parking keeps the crashed image's RAM intact for a
   --  debug probe (or, on size 0, is simply the only honest option --
   --  there is nothing to preserve, and no sink to hand control back
   --  to). Weak_External below still lets an application override this
   --  policy (e.g. back to Reset) at link time.

   --  (No SPARK_Mode on Park: this whole unit is outside SPARK's scope --
   --  a-except.ads carries no SPARK_Mode either -- so the inline asm
   --  below needs no special marking here, unlike Console_FIFO's own
   --  body, which does live under a SPARK_Mode spec.)
   procedure Park is
      use System.Machine_Code;
   begin
      Asm ("cli", Volatile => True);  --  interrupts stay off: nothing
                                       --  must run after a fault.
      loop
         Asm ("sleep", Volatile => True);
      end loop;
   end Park;

   procedure Default_Handler (Msg : System.Address; Line : Integer);
   pragma Export (C, Default_Handler, "__gnat_last_chance_handler");
   pragma Weak_External (Default_Handler);
   pragma No_Return (Default_Handler);

   procedure Default_Handler (Msg : System.Address; Line : Integer) is
   begin
      --  Best-effort: record the fault in the diagnostic sink (§10.3)
      --  before parking. When the FIFO is compiled out (size 0) these
      --  calls are no-ops (Console_FIFO.Put drops silently) -- nothing
      --  to record, so we just park (§10.3's "the honest cost of the
      --  zero-footprint setting").
      if Msg /= System.Null_Address then
         declare
            --  Msg points at a (conventionally null-terminated, per
            --  Ada.Exceptions' spec comment) message string; without a
            --  known length we can only forward it byte-by-byte until
            --  we hit the terminator.
            type Char_Ptr is access all Character;
            function To_Char_Ptr is new Ada.Unchecked_Conversion
              (System.Address, Char_Ptr);
            P : Char_Ptr := To_Char_Ptr (Msg);
         begin
            while P.all /= ASCII.NUL loop
               Console_FIFO.Put
                 (Interfaces.Unsigned_8 (Character'Pos (P.all)));
               P := To_Char_Ptr (P.all'Address + Storage_Offset'(1));
            end loop;
         end;
      end if;
      Console_FIFO.Put (" (line ");
      --  Line as decimal digits, no Ada.Text_IO / secondary stack.
      declare
         V : Natural := (if Line >= 0 then Line else 0);
         Digits_Buf : String (1 .. 10);
         Pos : Positive := Digits_Buf'Last + 1;
      begin
         loop
            Pos := Pos - 1;
            Digits_Buf (Pos) := Character'Val (Character'Pos ('0') + V mod 10);
            V := V / 10;
            exit when V = 0 or Pos = Digits_Buf'First;
         end loop;
         Console_FIFO.Put (Digits_Buf (Pos .. Digits_Buf'Last));
      end;
      Console_FIFO.Put (")" & ASCII.LF);
      Park;
   end Default_Handler;

   procedure Last_Chance_Handler (Msg : System.Address; Line : Integer);
   pragma Import (C, Last_Chance_Handler, "__gnat_last_chance_handler");
   pragma No_Return (Last_Chance_Handler);

   procedure Raise_Exception (E : Exception_Id; Message : String := "") is
      pragma Unreferenced (E);
   begin
      Last_Chance_Handler (Message'Address, 0);
   end Raise_Exception;

end Ada.Exceptions;
