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
--  for the Hart_Class/Memory_Profile equality tests below.
with MPFS_Runtime_Config; use MPFS_Runtime_Config;

package MPFS_Config_Checks is

   ---------------------------------------------------------------------
   --  1. Hart_Class = e51 with a hard-float ABI -> error (no FPU)
   ---------------------------------------------------------------------
   --  NOT IMPLEMENTED AS A PRAGMA -- reported, not faked. CONTRACT.md
   --  S3.2's finalised variable table has no separate Float_ABI (or
   --  similar) knob: Hart_Class is the sole determinant, and the
   --  ISA/ABI pairing (RTS-POLARFIRE.md S1.1, S3.6's MPFS_ARCH/MPFS_ABI
   --  `external()`s) is a `runtime.xml`/GPR-level concern the leaf's
   --  `MPFS_Runtime_Config` package does not carry -- there is no
   --  MPFS_Runtime_Config field this spec could put on the other side of
   --  `and then`. Writing `Hart_Class = E51 and then <nothing available>`
   --  would either not compile or -- worse -- compile as a condition
   --  that can never be true, which is exactly the silently-useless
   --  check this file's own header warns against. Flagged in the task
   --  report as a CONTRACT.md/RTS-POLARFIRE.md S5.3 mismatch instead.

   ---------------------------------------------------------------------
   --  2. Hart_Class = e51 -> Harts must be "0" (the E51 is hart 0)
   ---------------------------------------------------------------------
   pragma Compile_Time_Error
     (Hart_Class = E51 and then Harts /= "0",
      "Hart_Class => E51 is hart 0; Harts must be ""0""");

   ---------------------------------------------------------------------
   --  3. Hart_Class = u54 -> hart 0 (the E51) must not be in the set
   ---------------------------------------------------------------------
   --  Standalone mode is single-hart only (RTS-POLARFIRE.md S5, P1), so
   --  Harts is exactly one digit; this is an exact-match, not a
   --  substring search (pragma Compile_Time_Error's condition cannot
   --  call Ada.Strings.Fixed.Index -- a general multi-hart "is 0 in the
   --  set" test is not expressible this way; see check 8 below for the
   --  'Length-based technique this file uses instead where it can).
   pragma Compile_Time_Error
     (Hart_Class = U54 and then Harts = "0",
      "hart 0 is the E51 and cannot be part of a U54 Harts set");

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
   --  7. DTIM is E51-only (RTS-POLARFIRE.md S1.4)
   ---------------------------------------------------------------------
   pragma Compile_Time_Error
     (DTIM_Ways /= 0 and then Hart_Class /= E51,
      "only the E51 has a configurable DTIM");

   ---------------------------------------------------------------------
   --  8. ITIM is per-hart private: no multi-hart image may use it
   ---------------------------------------------------------------------
   --  Every single-hart Harts value ("0".."4") is exactly one character;
   --  every multi-hart value ("1..4", "2,3", ...) is necessarily longer.
   --  'Length is an attribute of the whole Harts object, not an indexed
   --  component, so (unlike Harts(Harts'First)) it remains usable here.
   pragma Compile_Time_Error
     (ITIM_Ways /= 0 and then Harts'Length > 1,
      "ITIM is per-hart private; a multi-hart image has no single ITIM");

   ---------------------------------------------------------------------
   --  9. A Memory_Profile that needs DDR requires DDR_Present
   ---------------------------------------------------------------------
   --  Of the six Memory_Profile values, only Ddr_By_Bootloader names DDR
   --  outright. System_Partition is derived-mode data (RTS-POLARFIRE.md
   --  S4.4); its own DDR window is range-checked in the generated
   --  MPFS.System_Map, not here, by design (S4.3's "range-check every
   --  window" applies to the generator, which is the only actor that can
   --  see the MSS XML this spec cannot).
   pragma Compile_Time_Error
     (Memory_Profile = Ddr_By_Bootloader and then not DDR_Present,
      "Memory_Profile => Ddr_By_Bootloader needs DDR_Present => True");

end MPFS_Config_Checks;
