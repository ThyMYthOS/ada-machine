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
--  Verified twice, both by deliberately setting Device => "rp2350" in
--  hello_rp2040/alire.toml during development (then reverting):
--
--   1. As shipped (libgnat-armv8m absent): the build fails BEFORE this
--      pragma ever runs, at Source_Dirs/Source_List_File resolution --
--      "... is not a valid directory" / "source file ... not found" for
--      s-lidosq.adb/s-lisisq.adb. This unit's check is unreachable for
--      that failure, which is fine (the failure is still honest and
--      still names the missing file), but it means the check below is
--      NOT what protects that path.
--   2. With a throwaway stub libgnat-armv8m/ (copies of the armv6m sqrt
--      bodies, just to let Source_Dirs resolve) the build proceeds to
--      compile this unit, and THIS pragma fires with exactly the message
--      below. So the check is live for the case it can actually reach:
--      a partially-populated armv8m overlay that satisfies the source
--      resolver without anyone having updated this guard -- not for the
--      simpler "nothing populated at all" case, which fails one layer
--      earlier for an unrelated reason.

with Pico_Runtime_Config; use Pico_Runtime_Config;

package Pico_Config_Checks is
   pragma Pure;
   pragma Style_Checks (Off);

   Device_Is_Rp2040 : constant Boolean := Device = rp2040;

   pragma Compile_Time_Error
     (not Device_Is_Rp2040,
      "Device => rp2350 has no populated source: " &
      "no ARMv8-M sqrt variant is populated in tier 2 " &
      "(no RP2350 runtime ships in gnat_arm_elf 15.1.2) -- see " &
      "rts_core_cortexm/README.md");

end Pico_Config_Checks;
