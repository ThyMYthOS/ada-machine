------------------------------------------------------------------------------
--                                                                          --
--                  GNAT RUN-TIME LIBRARY (GNARL) COMPONENTS                --
--                                                                          --
--            S Y S T E M . B B . B O A R D _ P A R A M E T E R S           --
--                                                                          --
--                                  S p e c                                 --
--                                                                          --
--                    Copyright (C) 2012-2020, AdaCore                      --
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

--  This package defines board parameters for the PolarFire SOC

------------------------------------------------------------------------------
--  rts-spikes / rts_support_mpfs local changes -- CONTRACT.md task 4;
--  cross-reference RTS-POLARFIRE.md S8 items 1 and 8.
--
--  1. `with MPFS_Runtime_Config` (the CONTRACT.md S3.3 renaming shim), so
--     board parameters come from the leaf's configuration instead of
--     being constants frozen for one hart.
--  2. CLINT_Mtimecmp_Offset no longer hardcodes "mtimecmp for hart 1"
--     (upstream: `16#4008# = 0x4000 + 8*1`). It is now a fixed base
--     (CLINT_Mtimecmp_Base_Offset) plus a per-hart stride
--     (CLINT_Mtimecmp_Stride) times the configured hart, parsed from
--     MPFS_Runtime_Config.Harts.
--  3. PLIC_Hart_Id is derived from that same configured hart instead of
--     the literal 1. This is only the hart-id half of RTS-POLARFIRE S8
--     item 1: MPFS gives the E51 an M-mode PLIC context and each U54
--     both M- and S-mode contexts, so "context" and "hart id" are
--     different numbers in general (RTS-POLARFIRE S11 risk 5). That
--     per-mode context derivation is still open, deferred with S-mode
--     support to P5, and NOT attempted here.
--  4. UART_Base_Address follows MPFS_Runtime_Config.Console instead of
--     being frozen to MMUART0 (RTS-POLARFIRE S8 item 8).
--
--  Standalone mode (RTS-POLARFIRE S5) is single-hart per image (P1), so
--  Harts is one decimal digit; every derivation below reads only its
--  first character.
--
--  CONTRACT.md S7.3 (resolved blocker, applied here as directed): upstream
--  `pragma No_Elaboration_Code_All` propagates transitively -- every unit
--  this package `with`s must carry it too -- and the S3.3 renaming shim
--  cannot carry it (`pragma ... not allowed for renamed package`). `Pure`
--  is not the problem (Alire already generates `pragma Pure` on its config
--  package); `No_Elaboration_Code_All` is. Fixed below by using the
--  non-transitive `pragma Restrictions (No_Elaboration_Code);` instead,
--  keeping `pragma Pure` -- same as damaki's shipped `rp2040` crate.
--
--  REMAINING RISK, partly UNVERIFIED end-to-end / CONFIRMED in isolation:
--  past the S7.3 fix, Ada legality rules still make it impossible to
--  fully honour this from Board_Parameters alone.
--  MPFS_Runtime_Config.Harts is pinned as
--  `String` (CONTRACT.md S3.2). Indexing into it, or a case/if
--  expression built from it, is accepted as *this* package's own,
--  first-use declaration (GNAT folds it; no elaboration code results,
--  confirmed with a scratch reproduction against this toolchain) but is
--  REJECTED -- "not a static constant (RM 4.9(5))" -- the instant
--  another preelaborated unit's own library-level constant combines it
--  further (also confirmed). That is exactly the shape of three
--  consumers this crate cannot edit or fully verify against (no leaf's
--  generated config exists yet in this workspace to link against --
--  UNVERIFIED end-to-end, CONFIRMED in isolation):
--    - s-bbsuti.adb (System.BB.Board_Support.Time, tier 1) computes
--      `System'To_Address (Mtimecmp_Base_Address + 4)`;
--    - s-bbripl.adb (System.BB.RISCV_PLIC, this crate) computes
--      `Use_Hart_0 : constant Boolean := PLIC_Hart_Id = 0;`;
--    - s-textio.adb (System.Text_IO, this crate) computes
--      `Base_Address : constant System.Address := ...UART_Base_Address;`.
--  All three are library-level constants of Preelaborate units, which
--  Ada requires to be static; a value parsed out of a String never is.
--  Fully resolving this needs either a run-time mhartid read in the
--  tier-1 consumer -- which is what RTS-POLARFIRE S8 item 1 actually
--  asks for ("computed at run time") -- or a differently-typed
--  configuration channel CONTRACT.md does not currently provide. Each
--  constant below is therefore declared as its own one-shot expression
--  (never referencing another Harts-derived constant by name), which is
--  enough to keep *this* unit compiling; it does not by itself prove the
--  three consumers above still compile.
------------------------------------------------------------------------------

--  Configuration pragma: must precede the compilation unit, not sit inside
--  the spec. Not `No_Elaboration_Code_All` -- that propagates transitively
--  onto the renamed MPFS_Runtime_Config, which cannot carry it (CONTRACT 7.3).

with Interfaces;
with MPFS_Runtime_Config;

package System.BB.Board_Parameters is
   pragma Pure;

   --------------------
   -- Hardware clock --
   --------------------

   Clock_Scale     : constant := 1;
   --  Scaling factor for clock frequency. This is used to provide a clock
   --  frequency that results in a definition of Time_Unit less than 20
   --  microseconds (as Ada RM D.8 (30) requires).

   Decrementer_Frequency : constant Positive := 1_000_000;
   --  Frequency of the system clock for the decrementer timer

   Clock_Frequency : constant Positive := Decrementer_Frequency * Clock_Scale;
   --  Scaled clock frequency

   CLINT_Base_Address    : constant := 16#0200_0000#;
   CLINT_Mtime_Offset    : constant := 16#BFF8#;

   CLINT_Mtimecmp_Base_Offset : constant := 16#4000#;
   CLINT_Mtimecmp_Stride      : constant := 8;
   --  mtimecmp lives at CLINT_Base_Address + 0x4000 + 8 * hart
   --  (RTS-POLARFIRE.md S1.2).

   CLINT_Mtimecmp_Offset : constant Natural :=
     CLINT_Mtimecmp_Base_Offset + CLINT_Mtimecmp_Stride *
       (Character'Pos (MPFS_Runtime_Config.Harts
                          (MPFS_Runtime_Config.Harts'First))
          - Character'Pos ('0'));
   --  Base plus per-hart stride, no longer "hart 1" always (see the
   --  header comment for what this does and does not verify).

   Mtime_Base_Address : constant :=
     CLINT_Base_Address + CLINT_Mtime_Offset;
   --  Address of the memory mapped mtime register. One per system, not
   --  per-hart (RTS-POLARFIRE.md S1.2), so this needs none of the above
   --  and is unchanged from upstream.

   Mtimecmp_Base_Address : constant Natural :=
     CLINT_Base_Address + CLINT_Mtimecmp_Base_Offset + CLINT_Mtimecmp_Stride *
       (Character'Pos (MPFS_Runtime_Config.Harts
                          (MPFS_Runtime_Config.Harts'First))
          - Character'Pos ('0'));
   --  Deliberately NOT "CLINT_Base_Address + CLINT_Mtimecmp_Offset":
   --  reusing a Harts-derived constant inside a further constant
   --  expression is exactly the pattern the header's REMAINING RISK note
   --  describes (confirmed to fail even within this same package).
   --  Recomputing independently at least keeps this unit compiling.

   --  Console UART. Mmuart0's address is the one value CONTRACT.md /
   --  RTS-POLARFIRE.md actually give (S2: UART_Base_Address =
   --  16#2000_0000#). Mmuart1..4 below come from general PolarFire SoC
   --  familiarity, NOT from the MSS TRM or the MSS Configurator XML --
   --  neither was available while writing this.
   --  UNVERIFIED: confirm against the TRM / `mss_io`+`apb_split` before
   --  relying on these for real hardware; the real per-board values
   --  belong in `mpfs_system`, read from the XML, once P4 exists
   --  (RTS-POLARFIRE.md S4.3).
   UART_Mmuart0_Address : constant := 16#2000_0000#;
   UART_Mmuart1_Address : constant := 16#2010_0000#;
   UART_Mmuart2_Address : constant := 16#2011_0000#;
   UART_Mmuart3_Address : constant := 16#2012_0000#;
   UART_Mmuart4_Address : constant := 16#2013_0000#;

   --  "MPFS_Runtime_Config."="(...)" (prefixed call), not infix "=":
   --  CONTRACT.md S3.3 says tier-3 sources "with MPFS_Runtime_Config and
   --  nothing else", which this reads as ruling out an added
   --  "use MPFS_Runtime_Config;" too. A prefixed operator call needs no
   --  "use" and does not depend on knowing the Console enumeration
   --  type's actual (Alire-generated) name -- only CONTRACT.md S3.2's
   --  pinned value names, which this crate can rely on.
   UART_Base_Address : constant :=
     (if    MPFS_Runtime_Config."=" (MPFS_Runtime_Config.Console,
                                      MPFS_Runtime_Config.mmuart0) then
        UART_Mmuart0_Address
      elsif MPFS_Runtime_Config."=" (MPFS_Runtime_Config.Console,
                                      MPFS_Runtime_Config.mmuart1) then
        UART_Mmuart1_Address
      elsif MPFS_Runtime_Config."=" (MPFS_Runtime_Config.Console,
                                      MPFS_Runtime_Config.mmuart2) then
        UART_Mmuart2_Address
      elsif MPFS_Runtime_Config."=" (MPFS_Runtime_Config.Console,
                                      MPFS_Runtime_Config.mmuart3) then
        UART_Mmuart3_Address
      elsif MPFS_Runtime_Config."=" (MPFS_Runtime_Config.Console,
                                      MPFS_Runtime_Config.mmuart4) then
        UART_Mmuart4_Address
      else
        UART_Mmuart0_Address);
   --  Console => Ram_Fifo or Console => None still resolve to *some*
   --  MMUART address here, because s-textio.adb, as populated, is
   --  unconditionally an MMUART driver. RTS-POLARFIRE S8 item 8's
   --  "better" fix -- use the RAM-FIFO console so the runtime owns no
   --  peripheral at all -- needs a different System.Text_IO body
   --  selected by the leaf's source list; a Board_Parameters value
   --  cannot make that swap by itself.

   --  Platform Level Interrupt Controller
   PLIC_Base_Address     : constant := 16#0C00_0000#;
   PLIC_Nbr_Of_Harts     : constant := 5;
   PLIC_Nbr_Of_Sources   : constant := 185;
   PLIC_Nbr_Of_Mask_Regs : constant := 6;
   PLIC_Priority_Bits    : constant := 3;

   PLIC_Hart_Id : constant Natural :=
     Character'Pos (MPFS_Runtime_Config.Harts
                       (MPFS_Runtime_Config.Harts'First))
       - Character'Pos ('0');
   --  The configured hart, not the literal 1 (see header comment 3 for
   --  what this does not yet do: PLIC *context* derivation).

   GDB_First_CPU_Id : constant Interfaces.Unsigned_32 :=
     Interfaces.Unsigned_32
       (Character'Pos (MPFS_Runtime_Config.Harts
                          (MPFS_Runtime_Config.Harts'First))
          - Character'Pos ('0'));
   pragma Export (C, GDB_First_CPU_Id, "__gnat_gdb_cpu_first_id");
   --  This value is used by GDB to know the hardware id of the first CPU
   --  used by the run-time: the configured hart (recomputed rather than
   --  referencing PLIC_Hart_Id by name, for the same reason
   --  Mtimecmp_Base_Address recomputes rather than reuses
   --  CLINT_Mtimecmp_Offset -- see above).

end System.BB.Board_Parameters;
