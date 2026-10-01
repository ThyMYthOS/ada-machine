--  MPFS_Config_Checks -- standalone-mode configuration validation
--  (CONTRACT.md S5). Project-owned (not FSF/AdaCore), part of
--  rts_support_mpfs (tier 3).
--
--  NAMING NOTE (deviation from the literal instruction, reported rather
--  than silently duplicated): the task that produced this crate asked
--  for `src/mpfs-config_checks.ads`, i.e. a child unit `MPFS.Config_Checks`.
--  That parent, `MPFS`, already exists -- as an empty, `pragma Pure` root
--  -- in `mpfs_system/src/mpfs.ads` (tier 7, generated, derived-mode-only,
--  RTS-POLARFIRE.md S4.4). Making this spec a child of it would either
--  (a) redeclare `mpfs.ads` here too, which conflicts the moment a leaf
--  uses both crates (derived mode), or (b) not redeclare it, leaving this
--  unit's parent missing for every STANDALONE build (light_mpfs and
--  friends with no `MPFS_PARTITION` set) -- which is this crate's primary,
--  always-present use, unlike mpfs_system. Both are worse than a
--  self-contained unit, so this is `MPFS_Config_Checks` (flat), not
--  `MPFS.Config_Checks`. See this crate's README.md and the task report.
--
--  Every quantity a check reaches must be a flat, independent named
--  scalar/string constant read directly off MPFS_Runtime_Config --
--  never a component selected out of an array or record. GNAT does not
--  diagnose a `pragma Compile_Time_Error` whose condition fails to be a
--  static expression: the pragma is simply never triggered, silently,
--  even when the condition is in fact true (confirmed against this
--  toolchain; see the task report). A check that cannot fire is worse
--  than no check. Every condition below was deliberately triggered at
--  least once against a stand-in config and confirmed to report its own
--  message (task report has the transcript); this is not a paper
--  exercise.

--  "with ... and nothing else" (CONTRACT.md S3.3) is read here as "no
--  other dependency", not as "no use clause" -- the `use` below only
--  brings this one, already-with'ed package's names into scope, needed
--  for the Memory_Profile equality tests below.
with MPFS_Runtime_Config; use MPFS_Runtime_Config;

package MPFS_Config_Checks is

   pragma Pure;
   --  NOT decoration -- this is what MAKES the checks below enforceable
   --  (CONTRACT.md 7.4). A `pragma Compile_Time_Error` whose condition is
   --  not static is silently discarded: no error, no warning, under any
   --  switch. `Pure` closes that hole, because preelaboration legality
   --  rejects the same non-static expression outright.
   --
   --  Measured in this exact context -- tier-3 unit, reached through the
   --  MPFS_Runtime_Config renaming shim, compiled with -gnatg -- by adding
   --  a deliberately non-static condition (a selected component of a
   --  constant array of records) and building hello_mpfs:
   --
   --    mpfs_config_checks.ads:47:07: warning: non-static constant in
   --                                  preelaborated unit [enabled by default]
   --    compilation of mpfs_config_checks.ads failed
   --
   --  Note it FAILED on warnings alone: -gnatg promotes them, so no
   --  -gnatwe is needed here. Without `Pure` the same condition compiles
   --  clean and the check silently does not exist.
   --
   --  So the flat-named-scalar rule in the header below is now enforced by
   --  the compiler rather than by discipline. Do not remove this pragma to
   --  make something compile -- a condition it rejects is a check that
   --  would not have worked.

   ---------------------------------------------------------------------
   --  1. (not implementable) e51 with a hard-float ABI
   ---------------------------------------------------------------------
   --  NOT IMPLEMENTED AS A PRAGMA -- reported, not faked. CONTRACT.md
   --  S3.2's finalised variable table has no separate Float_ABI (or
   --  similar) knob: the mask is the sole determinant, and the
   --  ISA/ABI pairing (RTS-POLARFIRE.md S1.1, S3.6's MPFS_ARCH/MPFS_ABI
   --  `external()`s) is a `runtime.xml`/GPR-level concern the leaf's
   --  `MPFS_Runtime_Config` package does not carry -- there is no
   --  MPFS_Runtime_Config field this spec could put on the other side of
   --  `and then`. Writing `<e51 test> and then <nothing available>`
   --  would either not compile or -- worse -- compile as a condition
   --  that can never be true, which is exactly the silently-useless
   --  check this file's own header warns against. Flagged in the task
   --  report as a CONTRACT.md/RTS-POLARFIRE.md S5.3 mismatch instead.

   ---------------------------------------------------------------------
   --  2. The mask must not mix the E51 with the U54s
   ---------------------------------------------------------------------
   --  Hart_Class is DERIVED from Harts_Mask in runtime_build.gpr (bit 0 is
   --  the E51), so "Hart_Class disagrees with the mask" is no longer
   --  representable and needs no check. What remains is that hart 0 is
   --  soft-float lp64 while harts 1..4 are hard-float lp64d: one image
   --  cannot serve both.
   pragma Compile_Time_Error
     ((Harts_Mask mod 2) = 1 and then Harts_Mask /= 1,
      "the soft-float E51 (hart 0) cannot share a mask with the U54s");

   --  With the Integer bitmask these are ordinary static scalar
   --  comparisons; the earlier String form could not be checked this way
   --  (RM 4.9: indexing a string constant is never static).

   ---------------------------------------------------------------------
   --  4-6. L2 way partition (RTS-POLARFIRE.md S1.2.1)
   ---------------------------------------------------------------------
   pragma Compile_Time_Error
     (L2_Cache_Ways + L2_LIM_Ways + L2_Scratchpad_Ways /= 16,
      "L2_Cache_Ways + L2_LIM_Ways + L2_Scratchpad_Ways must be 16");

   pragma Compile_Time_Error
     (L2_LIM_Ways > 15,
      "L2_LIM_Ways > 15: way 0 cannot be LIM, max LIM is 1920 KB " &
      "(15 ways)");

   pragma Compile_Time_Error
     (L2_Cache_Ways < 1,
      "L2_Cache_Ways < 1: at least one way must remain a real cache");

   ---------------------------------------------------------------------
   --  7. DTIM is e51-only (RTS-POLARFIRE.md S1.4)
   ---------------------------------------------------------------------
   pragma Compile_Time_Error
     (DTIM_Ways /= 0 and then Harts_Mask /= 1,
      "only the e51 (Harts_Mask => 1) has a configurable DTIM");

   ---------------------------------------------------------------------
   --  8. ITIM is per-hart private: no multi-hart image may use it
   ---------------------------------------------------------------------
   pragma Compile_Time_Error
     (ITIM_Ways /= 0
        and then Harts_Mask not in 1 | 2 | 4 | 8 | 16,
      --  "more than one bit set", i.e. not a single-hart mask. A plain
      --  "> 1" would be wrong: mask 2 is the single hart 1.
      "ITIM is per-hart private; a multi-hart image has no single ITIM");

   ---------------------------------------------------------------------
   --  9. A Memory_Profile that needs DDR requires DDR_Present
   ---------------------------------------------------------------------
   --  Of the six Memory_Profile values, only ddr_by_bootloader names DDR
   --  outright. System_Partition is derived-mode data (RTS-POLARFIRE.md
   --  S4.4); its own DDR window is range-checked in the generated
   --  MPFS.System_Map, not here, by design (S4.3's "range-check every
   --  window" applies to the generator, which is the only actor that can
   --  see the MSS XML this spec cannot).
   pragma Compile_Time_Error
     (Memory_Profile = ddr_by_bootloader and then not DDR_Present,
      "Memory_Profile => ddr_by_bootloader needs DDR_Present => True");

   ---------------------------------------------------------------------
   --  10. Console => ram_fifo is declared but not implemented
   ---------------------------------------------------------------------
   --  RTS-PRODUCTION.md A4 (CONSOLE_DEAD): the Console value used to select
   --  nothing, and ram_fifo is still a name without a driver. Accepting it
   --  would reintroduce exactly that defect for one value -- the image would
   --  build and print nowhere -- so it is refused until a RAM FIFO console
   --  exists. (mmuart0 .. mmuart4 select a UART; none discards output.)
   pragma Compile_Time_Error
     (Console = ram_fifo,
      "Console => ram_fifo is not implemented (use mmuart0..mmuart4 or none)");

end MPFS_Config_Checks;
