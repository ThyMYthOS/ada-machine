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

with System.BB.Board_Parameters;
with MPFS_Runtime_Config;

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

   --  MPFS SPIKE CHANGE (rts-spikes/light_tasking_mpfs, CONTRACT.md §3.4):
   --  upstream hardcodes Max_Number_Of_CPUs to 1 even for light-tasking
   --  (RTS-POLARFIRE.md §2) -- no SMP is built. Here it is derived from
   --  MPFS_Runtime_Config.Harts (a comma-separated list of single-digit
   --  hart numbers, e.g. "1" or "2,3") instead.
   --
   --  Harts is parsed by LENGTH alone, not by content: Ada's static
   --  expression rules (RM 4.9) never allow an indexed_component to be
   --  static -- confirmed against this exact compiler by attempting it
   --  (error: "indexed component is never static (RM 4.9)") -- and this
   --  package's caller in tier 1, System.Multiprocessors
   --  (rts_sources_gcc15/libgnarl/s-multip.ads), declares
   --  "type CPU_Range is range 0 .. System.BB.Parameters.
   --  Max_Number_Of_CPUs;", whose bounds are a signed_integer_type_
   --  definition and therefore syntactically required to be static
   --  (RM 3.5.4). So Max_Number_Of_CPUs must stay derivable without ever
   --  inspecting an individual character of Harts.
   --
   --  A comma-separated list of N single-digit harts is always exactly
   --  2N-1 characters (N digits, N-1 commas), so the count is a pure
   --  function of Harts'Length -- itself confirmed static here (unlike
   --  indexing or whole-string equality, which were also tried and
   --  rejected by this compiler as non-static in a number declaration).
   --  This deliberately does NOT accept the "a..b" range shorthand shown
   --  as an example in RTS-POLARFIRE.md §5.1 ("1..4"): a range's hart
   --  count depends on the two endpoint digits, which cannot be read
   --  back out of the string in a static expression by any mechanism
   --  found -- so a range write out its members instead, e.g. "1,2,3,4".
   --  pragma Compile_Time_Error rejects any other shape outright, rather
   --  than silently computing a wrong count (RTS.md §5.2/A.15).

   pragma Compile_Time_Error
     (MPFS_Runtime_Config.Harts'Length not in 1 | 3 | 5 | 7 | 9,
      "MPFS_Runtime_Config.Harts must be a single hart digit (e.g. ""2"")"
      & " or a comma-separated list of digits (e.g. ""2,3"");"
      & " the ""a..b"" range shorthand is not accepted here -- write out"
      & " its members instead (e.g. ""1,2,3,4"" for ""1..4"")");

   Max_Number_Of_CPUs : constant :=
     (MPFS_Runtime_Config.Harts'Length + 1) / 2;
   --  Maximum number of CPUs, derived from Harts (see above)

   Multiprocessor : constant Boolean := Max_Number_Of_CPUs /= 1;
   --  Are we on a multiprocessor board?

end System.BB.Parameters;
