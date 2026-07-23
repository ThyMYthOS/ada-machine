------------------------------------------------------------------------------
--                                                                          --
--                       A V R A D A _ R T S   R U N T I M E                --
--                                                                          --
--                          C O N S O L E _ F I F O                         --
--                                                                          --
--                                 S p e c                                  --
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

--  README §10.3: the runtime's diagnostic sink is a single-producer/
--  single-consumer, lock-free, non-blocking RAM ring buffer -- pure
--  Volatile RAM, no peripheral registers, no access types. It is *not*
--  SEGGER-RTT-formatted (AVR has no RTT-capable debug tooling): the
--  buffer is plain, probe-readable / application-drained Volatile RAM.
--
--  The producer (this runtime -- Last_Chance_Handler today; Ada.Text_IO
--  and §14.2 logging are later, separate work) never blocks: on
--  overflow it drops the incoming byte and counts it (Dropped).
--
--  Size is an Alire configuration variable (Avrada_Rts_Config.
--  Console_FIFO_Size), 0 by default. Size 0 is legal and load-bearing:
--  it folds the *entire* FIFO -- buffer bytes *and* bookkeeping (head/
--  tail/dropped) -- to zero bytes of RAM, so the AVR floor and any
--  silent-production build pay nothing for a feature they don't use.
--  See the package body for how that is structured.

with Interfaces;

package Console_FIFO
  with Preelaborate, SPARK_Mode
is
   type Byte_Array is array (Positive range <>) of Interfaces.Unsigned_8;

   ---------------------------------------------------------------------
   --  Consumer side -- non-blocking, bounded-time (L2-rule-conformant,
   --  §10.3): a probe reading memory directly, or application/boardgen
   --  code draining it to any transport. Exactly one consumer at a
   --  time (§10.3) -- which one is a policy decision made outside this
   --  package.
   ---------------------------------------------------------------------

   function Available return Natural
     with Inline_Always, Volatile_Function, Global => null;
   --  Number of unread bytes currently sitting in the FIFO.
   --  Volatile_Function: the body reads the shared ring's Head/Tail,
   --  which the producer/consumer sides mutate between calls, so two
   --  textually-identical calls need not agree (SPARK RM 7.1.3(9)) --
   --  same reasoning as ATmega328P.Critical_Section.Enter. Global =>
   --  null: the body's own SPARK_Mode => Off hides the real Storage
   --  access from analysis (it is an Address overlay, outside the
   --  SPARK subset anyway -- see the body), so this is an explicit,
   --  reviewed assertion, not an inferred fact: Available only reads
   --  shared state and always returns, it does not write anything or
   --  loop forever.

   procedure Read (Into : out Byte_Array; Last : out Natural)
     with Inline_Always;
   --  Never blocks: fills Into (Into'First .. Last) with whatever is
   --  available, up to Into'Length bytes. Last < Into'First means
   --  nothing was read.

   function Dropped return Natural
     with Inline_Always, Volatile_Function, Global => null;
   --  Bytes lost to overflow so far (producer never blocks; it drops
   --  and counts instead). Volatile_Function / Global => null: see
   --  Available.

   ---------------------------------------------------------------------
   --  Producer side -- for the runtime's own internal use (the
   --  Last_Chance_Handler below; Ada.Text_IO's System.Text_IO body and
   --  §14.2 logging are later, separate work per the task that added
   --  this unit). Not part of the L2 consumer contract, but an ordinary
   --  visible procedure: no access types, no callback registration.
   ---------------------------------------------------------------------

   procedure Put (B : Interfaces.Unsigned_8) with Inline_Always;
   --  Never blocks: on overflow, drops B and bumps Dropped.

   procedure Put (S : String) with Inline_Always;
   --  Byte-per-character convenience for producers with a String
   --  message (e.g. Last_Chance_Handler's Msg); same never-blocks,
   --  drop-and-count semantics per character.

end Console_FIFO;
