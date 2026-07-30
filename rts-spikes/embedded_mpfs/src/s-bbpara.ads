------------------------------------------------------------------------------
--                                                                          --
--                  GNAT RUN-TIME LIBRARY (GNARL) COMPONENTS                --
--                                                                          --
--                   S Y S T E M . B B . P A R A M E T E R S                --
--                                                                          --
--                                  S p e c                                 --
--                                                                          --
--        Copyright (C) 1999-2002 Universidad Politecnica de Madrid         --
--             Copyright (C) 2003-2005 The European Space Agency            --
--                     Copyright (C) 2003-2020, AdaCore                     --
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
-- The port of GNARL to bare board targets was initially developed by the   --
-- Real-Time Systems Group at the Technical University of Madrid.           --
--                                                                          --
------------------------------------------------------------------------------

--  This package defines basic parameters used by the low level tasking system

--  embedded_mpfs (CONTRACT.md §3.4): added this with-clause so
--  Max_Number_Of_CPUs below can be derived from MPFS_Runtime_Config.Harts
--  instead of being hardcoded. MPFS_Runtime_Config is the renaming shim of
--  CONTRACT.md §3.3 (gnat_user/mpfs_runtime_config.ads), so this unit does
--  not depend on this leaf's own generated config package by name.
with MPFS_Runtime_Config;

with System.BB.Board_Parameters;

package System.BB.Parameters is
   pragma Pure;

   --------------------
   -- Hardware clock --
   --------------------

   Ticks_Per_Second : constant := Board_Parameters.Clock_Frequency;
   --  Frequency of the system clock

   ----------------
   -- Interrupts --
   ----------------

   --  These definitions are in this package in order to isolate target
   --  dependencies.

   subtype Interrupt_Range is Natural range 1 .. 186;

   ------------
   -- Stacks --
   ------------

   Interrupt_Stack_Size : constant := 8 * 1024;
   --  Size of each of the interrupt stacks in bytes

   Interrupt_Sec_Stack_Size : constant := 1024;
   --  Size of the secondary stack for interrupt handlers

   ----------
   -- CPUS --
   ----------

   --  embedded_mpfs (CONTRACT.md §3.4): Max_Number_Of_CPUs is derived,
   --  statically, from MPFS_Runtime_Config.Harts (a hart-set String, e.g.
   --  "1", "1..4", "2,3" -- RTS-POLARFIRE.md §5.1) rather than hardcoded.
   --
   --  This has to be a genuine static expression: System.Multiprocessors
   --  (rts_sources_gcc15/libgnarl/s-multip.ads) declares
   --  "type CPU_Range is range 0 .. System.BB.Parameters.Max_Number_Of_CPUs;",
   --  and RM 3.5.9 requires both bounds of an integer type definition to
   --  be static. Ada has no static loops, so a general set/range parser is
   --  not legal here -- but PolarFire SoC has exactly five harts (E51 = 0,
   --  U54 #1-4, RTS-POLARFIRE.md §1.1), so every legal Harts value is one
   --  of a small, closed set, enumerable by static string equality (a
   --  predefined operator on static primaries, RM 4.9).
   --
   --  Recognises single harts ("0".."4"), explicit comma sets, and
   --  contiguous ".." ranges (both spellings accepted for the same
   --  contiguous set, e.g. "1,2" and "1..2" both count 2). Multi-hart
   --  values are necessarily U54-only ways (tier-3 rejects Hart_Class =>
   --  e51 with Harts /= "0" -- CONTRACT.md §5).

   Harts_Recognized : constant Boolean :=
     MPFS_Runtime_Config.Harts = "0"
       or else MPFS_Runtime_Config.Harts = "1"
       or else MPFS_Runtime_Config.Harts = "2"
       or else MPFS_Runtime_Config.Harts = "3"
       or else MPFS_Runtime_Config.Harts = "4"
       or else MPFS_Runtime_Config.Harts = "1,2"
       or else MPFS_Runtime_Config.Harts = "1,3"
       or else MPFS_Runtime_Config.Harts = "1,4"
       or else MPFS_Runtime_Config.Harts = "2,3"
       or else MPFS_Runtime_Config.Harts = "2,4"
       or else MPFS_Runtime_Config.Harts = "3,4"
       or else MPFS_Runtime_Config.Harts = "1..2"
       or else MPFS_Runtime_Config.Harts = "2..3"
       or else MPFS_Runtime_Config.Harts = "3..4"
       or else MPFS_Runtime_Config.Harts = "1,2,3"
       or else MPFS_Runtime_Config.Harts = "1,2,4"
       or else MPFS_Runtime_Config.Harts = "1,3,4"
       or else MPFS_Runtime_Config.Harts = "2,3,4"
       or else MPFS_Runtime_Config.Harts = "1..3"
       or else MPFS_Runtime_Config.Harts = "2..4"
       or else MPFS_Runtime_Config.Harts = "1,2,3,4"
       or else MPFS_Runtime_Config.Harts = "1..4";

   pragma Compile_Time_Error
     (not Harts_Recognized,
      "MPFS_Runtime_Config.Harts value not recognized by embedded_mpfs's " &
      "Max_Number_Of_CPUs derivation (src/s-bbpara.ads) -- expected a " &
      "single hart 0-4, a comma set, or a .. range over 1-4");

   Max_Number_Of_CPUs : constant :=
     (if    MPFS_Runtime_Config.Harts = "0" then 1
      elsif MPFS_Runtime_Config.Harts = "1" then 1
      elsif MPFS_Runtime_Config.Harts = "2" then 1
      elsif MPFS_Runtime_Config.Harts = "3" then 1
      elsif MPFS_Runtime_Config.Harts = "4" then 1

      elsif MPFS_Runtime_Config.Harts = "1,2"   then 2
      elsif MPFS_Runtime_Config.Harts = "1,3"   then 2
      elsif MPFS_Runtime_Config.Harts = "1,4"   then 2
      elsif MPFS_Runtime_Config.Harts = "2,3"   then 2
      elsif MPFS_Runtime_Config.Harts = "2,4"   then 2
      elsif MPFS_Runtime_Config.Harts = "3,4"   then 2
      elsif MPFS_Runtime_Config.Harts = "1..2"  then 2
      elsif MPFS_Runtime_Config.Harts = "2..3"  then 2
      elsif MPFS_Runtime_Config.Harts = "3..4"  then 2

      elsif MPFS_Runtime_Config.Harts = "1,2,3" then 3
      elsif MPFS_Runtime_Config.Harts = "1,2,4" then 3
      elsif MPFS_Runtime_Config.Harts = "1,3,4" then 3
      elsif MPFS_Runtime_Config.Harts = "2,3,4" then 3
      elsif MPFS_Runtime_Config.Harts = "1..3"  then 3
      elsif MPFS_Runtime_Config.Harts = "2..4"  then 3

      elsif MPFS_Runtime_Config.Harts = "1,2,3,4" then 4
      elsif MPFS_Runtime_Config.Harts = "1..4"     then 4

      else 1);
   --  Maximum number of CPUs. The "else 1" branch is unreachable for any
   --  Harts value that reaches this point, since Harts_Recognized would
   --  already have failed the Compile_Time_Error above -- it exists only
   --  because the if-expression must be total.

   Multiprocessor : constant Boolean := Max_Number_Of_CPUs /= 1;
   --  Are we on a multiprocessor board?

end System.BB.Parameters;
