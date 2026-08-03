--  Validates the Device configuration value against what is actually
--  populated (mirrors rts-spikes/CONTRACT.md §5's mpfs_config_checks.ads,
--  and its two hard-won lessons):
--
--   * pragma Compile_Time_Error needs a FLAT, independent named scalar
--     constant -- not an indexed/selected non-static expression, which
--     silently never fires (CONTRACT.md §7.4).
--   * a hand-authored unit must be named in the leaf's Source_List_File
--     (light_tasking_pico/runtime.gnat.lst) or it is never compiled and
--     every check in it is dead code that looks like assurance
--     (CONTRACT.md §7.12).
--
--  WHY THIS GUARD STILL EXISTS, AND WHY ITS REASON CHANGED.
--
--  It originally rejected rp2350 because no ARMv8-M sqrt overlay was
--  populated, so the build would have failed at Source_Dirs resolution
--  anyway. That reason is gone: s-lisisq.adb and s-lidosq.adb are now
--  single merged bodies in rts_sources_gcc15/libgnat-patched/ selecting
--  on RTS_Capabilities in the body (RTS.md 5.5), and tier 3 carries a
--  full src-rp2350/ overlay. Nothing about the SOURCES blocks rp2350.
--
--  The guard is kept because three other things do, and each would
--  produce a plausible-looking image rather than an error:
--
--   1. rts_support_pico/ld/ has only the RP2040 script pair. The RP2350
--      scripts differ (six files versus five upstream) and have not been
--      compared, so a link would silently use the wrong memory map.
--   2. target_options.gpr maps rp2350 to -mfloat-abi=soft, while the
--      published light_tasking_rp2350 crate uses hard. Wrong ABI, and
--      one that links.
--   3. This leaf's rts_capabilities.ads says no hardware square root of
--      either precision. The M33 FPU has single but not double, so an
--      rp2350 leaf needs its own (see that file's header).
--
--  So the message below names those three rather than the source
--  overlay. Anyone removing this pragma should have fixed all three --
--  the failure mode is no longer a missing file but a built image with
--  the wrong ABI and the wrong memory map.
--
--  Two mechanical lessons this file was written to remember
--  (../CONTRACT.md 5, and mpfs_config_checks.ads next door):
--
--   * pragma Compile_Time_Error needs a FLAT, independent named scalar
--     constant -- not an indexed/selected non-static expression, which
--     silently never fires (CONTRACT.md 7.4).
--   * a hand-authored unit must be named in the leaf's Source_List_File
--     (light_tasking_pico/runtime.gnat.lst) or it is never compiled and
--     every check in it is dead code that looks like assurance
--     (CONTRACT.md 7.12).
--
--  Verified by setting Device => "rp2350" in hello_rp2040/alire.toml and
--  reverting. Note WHAT changed: this pragma is now the FIRST thing to
--  fail. Before the sqrt merge and the src-rp2350 overlay, the build died
--  earlier at Source_Dirs/Source_List_File resolution ("... is not a valid
--  directory") and this check was unreachable for the case it names. It
--  now fires on its own, which is both the confirmation that no source is
--  missing any more and the reason the message had to be rewritten.

with Pico_Runtime_Config; use Pico_Runtime_Config;

package Pico_Config_Checks is
   pragma Pure;
   pragma Style_Checks (Off);

   Device_Is_Rp2040 : constant Boolean := Device = rp2040;

   pragma Compile_Time_Error
     (not Device_Is_Rp2040,
      "Device => rp2350 is not buildable yet. Tier 3 HAS the src-rp2350 " &
      "overlay; what is missing is an RP2350 linker script pair in " &
      "rts_support_pico/ld, -mfloat-abi=hard in target_options.gpr, and a " &
      "single-precision-only rts_capabilities.ads in this leaf. Fix all " &
      "three together -- see rts_support_pico/README.md, " &
      """What is still missing""");

end Pico_Config_Checks;
