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

   ------------------------------------------------------------------
   --  CHANGED from upstream's `Max_Number_Of_CPUs : constant := 1;`.
   --  Derived from MPFS_Runtime_Config.Harts_Mask, an Integer bitmask, so
   --  the popcount below is STATIC -- which it must be, because
   --  System.Multiprocessors declares
   --    type CPU_Range is range 0 .. System.BB.Parameters.Max_Number_Of_CPUs;
   --  and a scalar range bound is required to be static (RM 3.5.4).
   --  The earlier String form could not satisfy that: indexing a string
   --  constant is never static (RM 4.9), and length arithmetic could not
   --  distinguish which harts were selected, only how many characters.
   ------------------------------------------------------------------

   Mask : constant := MPFS_Runtime_Config.Harts_Mask;

   Max_Number_Of_CPUs : constant :=
     (if (Mask / 1)  mod 2 = 1 then 1 else 0)
   + (if (Mask / 2)  mod 2 = 1 then 1 else 0)
   + (if (Mask / 4)  mod 2 = 1 then 1 else 0)
   + (if (Mask / 8)  mod 2 = 1 then 1 else 0)
   + (if (Mask / 16) mod 2 = 1 then 1 else 0);

   pragma Compile_Time_Error
     (MPFS_Runtime_Config.Harts_Mask not in 1 .. 31,
      "Harts_Mask must select from harts 0 .. 4");
   --  Maximum number of CPUs. The "else 1" branch is unreachable for any
   --  Harts value that reaches this point, since Harts_Recognized would
   --  already have failed the Compile_Time_Error above -- it exists only
   --  because the if-expression must be total.

   Multiprocessor : constant Boolean := Max_Number_Of_CPUs /= 1;
   --  Are we on a multiprocessor board?

end System.BB.Parameters;
