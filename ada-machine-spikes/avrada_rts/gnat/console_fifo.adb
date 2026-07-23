------------------------------------------------------------------------------
--                                                                          --
--                       A V R A D A _ R T S   R U N T I M E                --
--                                                                          --
--                          C O N S O L E _ F I F O                         --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                    Copyright (C) 2026 Ada Machine project                --
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
------------------------------------------------------------------------------

with Avrada_Rts_Config;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces;              use Interfaces;

package body Console_FIFO
  with SPARK_Mode => Off
  --  Byte-level Address overlays onto the raw ring buffer are outside
  --  the SPARK subset (aliasing) -- same reasoning as
  --  ATmega328P.Critical_Section's inline asm or ATmega328P.Delays.
  --  Sleep_Idle's "sleep": the trick that makes Console_FIFO_Size => 0
  --  fold to *zero bytes of RAM* needs raw memory access that SPARK
  --  cannot see through. The public spec stays SPARK_Mode (the default,
  --  inherited) since none of that is visible from outside.
is

   Capacity : constant Natural := Avrada_Rts_Config.Console_FIFO_Size;
   --  0 (the default) or a power of two, in bytes -- checked below.

   Enabled : constant Boolean := Capacity > 0;

   pragma Compile_Time_Error
     (Capacity /= 0
        and then (Unsigned_16 (Capacity) and Unsigned_16 (Capacity - 1)) /= 0,
      "Console_FIFO_Size must be 0 or a power of two");

   --  One flat Volatile byte array holds *everything*: bytes
   --  [0 .. Capacity - 1] are the ring's data, followed -- only when
   --  Enabled -- by 6 bookkeeping bytes (Head, Tail, Dropped: two bytes
   --  each, mod-2**16 indices/counter). Storage_Offset is signed, so
   --  "0 .. Total_Bytes - 1" is a genuine null range (not an
   --  out-of-bounds index) when Total_Bytes = 0 -- Capacity = 0 folds
   --  buffer *and* bookkeeping to zero bytes in this one declaration;
   --  there is no separate scalar Head/Tail/Dropped variable anywhere
   --  in this unit that a Size = 0 build could forget to disable.
   Bookkeeping_Bytes : constant Storage_Offset := (if Enabled then 6 else 0);
   Total_Bytes       : constant Storage_Offset :=
     Storage_Offset (Capacity) + Bookkeeping_Bytes;

   type Storage_Bytes is array (Storage_Offset range <>) of Unsigned_8;

   Storage : Storage_Bytes (0 .. Total_Bytes - 1)
     with Volatile, Async_Readers, Async_Writers,
          Effective_Writes => True, Effective_Reads => False;
   --  Async_Writers/Readers: both producer (Put) and consumer (Read)
   --  sides of this single unit mutate Storage, so from any one
   --  subprogram's point of view it can change between calls -- same
   --  shape as ATmega328P.Critical_Section's External State.
   --  Effective_Reads => False / Effective_Writes => True: reading
   --  Storage (Get_U16) never itself alters anything -- only Put_U16
   --  does -- which is what lets Available/Dropped stay ordinary SPARK
   --  functions (ada functions may only have Input-mode globals; an
   --  Effective_Reads => True volatile object would force them to look
   --  like they have an output, which they don't).
   --  Total_Bytes = 0 when Capacity = 0 ⇒ Storage'Length = 0, so this
   --  declaration alone folds *both* the buffer and every bookkeeping
   --  counter to zero -- no separate Head/Tail/Dropped variable exists
   --  anywhere in this unit for a Size = 0 build to forget to disable.
   --  It is still a well-defined object (its 'Address is always legal
   --  to compute), which is all the helpers below need -- they never
   --  index it when Capacity = 0 (every call site is guarded by "if
   --  Enabled"), only compute addresses from it.
   --
   --  Honest residual: a zero-length array object still needs a
   --  distinct, addressable storage location, so GNAT/avr-gcc gives it
   --  the ABI minimum of *one* byte in .bss even at Capacity = 0 (see
   --  `avr-nm --size-sort -S obj/console_fifo.o`) -- not a forgotten
   --  counter, just the floor cost of an addressable object. In every
   --  linked application measured for this change (`spike2_avr`,
   --  README §10.3/task verification), that single byte -- along with
   --  the rest of this compilation unit -- is removed entirely by the
   --  linker's --gc-sections + -fdata-sections/-ffunction-sections
   --  (already in avrada_rts.gpr) whenever nothing actually calls into
   --  Console_FIFO, which is why the measured .data+.bss of a linked
   --  Capacity = 0 binary matches its pre-Console_FIFO baseline
   --  exactly, byte for byte.

   Head_Off    : constant Storage_Offset := Storage_Offset (Capacity);
   Tail_Off    : constant Storage_Offset := Head_Off + 2;
   Dropped_Off : constant Storage_Offset := Head_Off + 4;
   --  Byte offsets of the three 16-bit bookkeeping words within
   --  Storage. Meaningless (never used) when not Enabled.

   Capacity_U16 : constant Unsigned_16 := Unsigned_16 (if Enabled
                                                         then Capacity
                                                         else 1);
   --  Capacity as a divisor/modulus, never literally 0: Capacity = 0
   --  only ever occurs with Enabled = False, and every use of
   --  Capacity_U16 below is itself inside an "if Enabled" guard, so
   --  the substitute value 1 is never actually reached -- it only
   --  keeps the front end from flagging "mod 0" as a certain
   --  Constraint_Error in that unreachable branch.

   -----------------------------------------------------------------
   --  Get_U16/Put_U16 (16-bit bookkeeping words) and Get_U8/Put_U8
   --  (ring data bytes): local, non-persistent overlays -- a bare
   --  "Address => ..., Import" view onto existing Storage memory
   --  declared *inside* a subprogram never allocates storage of its
   --  own (the same idiom this repo's PAC register overlays use
   --  throughout); calling these costs nothing extra when Enabled is
   --  False, and every call site is behind an "if Enabled" guard, so
   --  they are never actually invoked in that configuration. Address
   --  arithmetic (not array indexing) is deliberate throughout: an
   --  index into Storage would be checked against its bounds, which
   --  are legitimately empty when Capacity = 0, and even inside a
   --  dead "if Enabled" branch a *statically* out-of-range index is
   --  flagged by the front end -- computing a raw address instead
   --  sidesteps that entirely.
   -----------------------------------------------------------------

   function Get_U16 (Off : Storage_Offset) return Unsigned_16;
   procedure Put_U16 (Off : Storage_Offset; V : Unsigned_16);
   function Get_U8 (Off : Storage_Offset) return Unsigned_8;
   procedure Put_U8 (Off : Storage_Offset; V : Unsigned_8);

   function Get_U16 (Off : Storage_Offset) return Unsigned_16 is
      Value : Unsigned_16 with Address => Storage'Address + Off,
                                Import, Volatile;
   begin
      return Value;
   end Get_U16;

   procedure Put_U16 (Off : Storage_Offset; V : Unsigned_16) is
      Value : Unsigned_16 with Address => Storage'Address + Off,
                                Import, Volatile;
   begin
      Value := V;
   end Put_U16;

   function Get_U8 (Off : Storage_Offset) return Unsigned_8 is
      Value : Unsigned_8 with Address => Storage'Address + Off,
                               Import, Volatile;
   begin
      return Value;
   end Get_U8;

   procedure Put_U8 (Off : Storage_Offset; V : Unsigned_8) is
      Value : Unsigned_8 with Address => Storage'Address + Off,
                               Import, Volatile;
   begin
      Value := V;
   end Put_U8;

   --  One ring slot is always kept empty (the classic head/tail
   --  ring-buffer trick) so "Head = Tail" unambiguously means empty and
   --  "(Head + 1) mod Capacity = Tail" unambiguously means full; usable
   --  capacity is therefore Capacity - 1 bytes.

   function Available return Natural is
   begin
      if not Enabled then
         return 0;
      end if;
      declare
         H : constant Unsigned_16 := Get_U16 (Head_Off);
         T : constant Unsigned_16 := Get_U16 (Tail_Off);
      begin
         --  Unsigned_16 subtraction wraps modulo 2**16, giving the
         --  right forward distance even when H < T; reducing mod
         --  Capacity (a power of two) then yields the logical count.
         return Natural ((H - T) mod Capacity_U16);
      end;
   end Available;

   function Dropped return Natural is
   begin
      if not Enabled then
         return 0;
      end if;
      return Natural (Get_U16 (Dropped_Off));
   end Dropped;

   procedure Read (Into : out Byte_Array; Last : out Natural) is
      Idx : Natural := Into'First - 1;
   begin
      if not Enabled then
         Last := Idx;
         return;
      end if;
      for I in Into'Range loop
         declare
            H : constant Unsigned_16 := Get_U16 (Head_Off);
            T : constant Unsigned_16 := Get_U16 (Tail_Off);
         begin
            exit when H = T;  --  empty
            Into (I) := Get_U8 (Storage_Offset (T));
            Put_U16 (Tail_Off, (T + 1) mod Capacity_U16);
            Idx := I;
         end;
      end loop;
      Last := Idx;
   end Read;

   procedure Put (B : Unsigned_8) is
   begin
      if not Enabled then
         return;
      end if;
      declare
         H      : constant Unsigned_16 := Get_U16 (Head_Off);
         T      : constant Unsigned_16 := Get_U16 (Tail_Off);
         Next_H : constant Unsigned_16 := (H + 1) mod Capacity_U16;
      begin
         if Next_H = T then
            --  Full: never block/overwrite unread data -- drop and
            --  count instead (§10.3's "producer never waits").
            Put_U16 (Dropped_Off, Get_U16 (Dropped_Off) + 1);
         else
            Put_U8 (Storage_Offset (H), B);
            Put_U16 (Head_Off, Next_H);
         end if;
      end;
   end Put;

   procedure Put (S : String) is
   begin
      for C of S loop
         Put (Unsigned_8 (Character'Pos (C)));
      end loop;
   end Put;

end Console_FIFO;
