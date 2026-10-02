#!/bin/sh
# Populate TIER 1 ONLY.
#
# Tier 1 is a snapshot of the compiler's own sources, so it is copied from the
# installed toolchains and asserted against both. Tier 2, tier 3 and every leaf
# src/ are OURS: committed, hand-editable, never overwritten (CONTRACT.md §1).
#
# That is why there is no prune here any more beyond tier 1's own. The leaf
# prune deleted a correctly-listed hand-authored file three times; owning the
# files removes the mechanism rather than adding a fourth guard to it.
set -e
#  The Makefile passes both; the defaults make `sh populate.sh` work on its own.
#  On a fresh machine the toolchains below do not exist yet: `make populate`
#  installs them first (toolchains.sh); running this script directly does not.
GNAT_VERSION=${GNAT_VERSION:-15.3.1}
ALIRE_TC_DIR=${ALIRE_TC_DIR:-$HOME/.local/share/alire/toolchains}
T=$(ls -d "$ALIRE_TC_DIR"/gnat_riscv64_elf_"$GNAT_VERSION"_*/riscv64-elf/lib/gnat 2>/dev/null | head -1)
[ -n "$T" ] || { echo "error: gnat_riscv64_elf $GNAT_VERSION not installed under $ALIRE_TC_DIR (run 'make toolchains', or 'make populate', which does)"; exit 1; }
#  Tier 1 serves both targets now (CONTRACT.md 7.19), so populating it in full
#  needs BOTH toolchains. The ARM half is optional: without it the RISC-V leaves
#  still build, because 122 of the 136 units only one target uses are 128-bit
#  and packed-array support that no 32-bit list names anyway. A published crate
#  would vendor the merged result and need neither toolchain.
TA=$(ls -d "$ALIRE_TC_DIR"/gnat_arm_elf_"$GNAT_VERSION"_*/arm-eabi/lib/gnat 2>/dev/null | head -1)
[ -n "$TA" ] || echo "note: gnat_arm_elf $GNAT_VERSION not installed -- ARM-only tier-1 units will be reported MISSING"
here=$(cd "$(dirname "$0")" && pwd)

copy() {   # copy <list> <dest> <src-dir>...
  list=$1; dest=$2; shift 2
  mkdir -p "$dest"
  # PRUNE, but only the tier-1 copies. A file left from an earlier layout is a
  # WRONG-VARIANT file sitting where the right one belongs: 18 units differ in
  # content between profiles, Source_Dirs order silently prefers whichever comes
  # first, and no diagnostic is issued (CONTRACT.md 7.15). Copying alone is
  # therefore not idempotent.
  # Leaf and tier-3 src/ dirs are NOT pruned: they hold hand-authored files
  # (mpfs_config_checks.ads, the edited s-bbbopa) that no list names.
  case "$dest" in
    */libgnat|*/libgnat-*|*/libgnarl|*/libgnarl-*)
      for existing in "$dest"/*; do
        [ -e "$existing" ] || continue
        grep -qxF "$(basename "$existing")" "$list" || rm -f "$existing"
      done ;;
  esac
  n=0; miss=0
  while read -r f; do
    [ -n "$f" ] || continue
    found=
    for d in "$@"; do
      if [ -f "$d/$f" ]; then cp "$d/$f" "$dest/$f"; found=1; n=$((n+1)); break; fi
    done
    [ -n "$found" ] || { echo "  MISSING: $f"; miss=$((miss+1)); }
  done < "$list"
  echo "  -> $dest: $n copied${miss:+, $miss missing}"
}

assert_identical() {   # assert_identical <list> <dir-a> <dir-b> <label-a> <label-b>
  # A SHARED overlay is only sound while the profiles mounting it agree on
  # every byte. This turns that assumption into a checked invariant: without
  # it, a toolchain update that makes light and light-tasking diverge would
  # silently give one of them the other's variant of a unit it compiles into
  # libgnat -- undetectable until something misbehaves on hardware.
  list=$1; a=$2; b=$3; la=$4; lb=$5; bad=0
  while read -r f; do
    [ -n "$f" ] || continue
    [ -f "$a/$f" ] && [ -f "$b/$f" ] || continue
    cmp -s "$a/$f" "$b/$f" || { echo "  DIVERGED: $f differs between $la and $lb"; bad=$((bad+1)); }
  done < "$list"
  if [ "$bad" -ne 0 ]; then
    echo "error: the shared $la/$lb overlay is not valid for this toolchain."
    echo "       Split libgnat-light back into per-profile overlays and restore"
    echo "       Gnat_Light_Tasking_Dir (CONTRACT.md 7.16)."
    exit 1
  fi
  echo "  -> verified: $la and $lb agree on every file in $(basename "$list")"
}

L=$T/light-polarfiresoc; LT=$T/light-tasking-polarfiresoc; E=$T/embedded-polarfiresoc

# Migration: libgnat-light-tasking was merged into libgnat-light (CONTRACT.md
# 7.16). Remove it rather than leaving it behind -- a stale overlay directory is
# the exact hazard CONTRACT.md 7.15 describes if anything ever puts it back on a
# source path.
rm -rf "$here/rts_sources_gcc15/libgnat-light-tasking"
rm -rf "$here/rts_sources_gcc15/libgnarl-light-tasking"

#  libgnat-patched is COMMITTED, not populated: those bodies are ours
#  (rts_sources_gcc15.gpr). Nothing here copies into it.
echo "rts_sources_gcc15"
# libgnat.lst now excludes every profile-variant unit (lists/profile-variant.lst),
# so any profile is a valid source for the rest. Search order is still
# widest-first because embedded ships units the narrower profiles omit.
#  The ARM runtimes are searched LAST for the common directories: where both
#  targets ship a unit the copies are byte-identical (measured), so order is
#  immaterial there, and the ARM trees are what supply the units only arm-eabi
#  has. AP/AE are the ARM sources; see the note above if they are absent.
AP=${TA:+$TA/light-tasking-rpi-pico}; AE=${TA:+$TA/embedded-rpi-pico}
copy "$here/rts_sources_gcc15/libgnat.lst"  "$here/rts_sources_gcc15/libgnat"  "$E/gnat"  "$LT/gnat"  "$L/gnat"  ${AE:+"$AE/gnat"} ${AP:+"$AP/gnat"}
copy "$here/rts_sources_gcc15/libgnarl.lst" "$here/rts_sources_gcc15/libgnarl" "$E/gnarl" "$LT/gnarl" ${AE:+"$AE/gnarl"} ${AP:+"$AP/gnarl"}

#  Content-disagreement overlay pairs (CONTRACT.md 7.19). A leaf mounts exactly
#  one member of each pair, so the shared basenames between them are safe.
copy "$here/rts_sources_gcc15/libgnat-64.lst"          "$here/rts_sources_gcc15/libgnat-64"          "$LT/gnat"
copy "$here/rts_sources_gcc15/libgnat-textio.lst"      "$here/rts_sources_gcc15/libgnat-textio"      "$LT/gnat"
copy "$here/rts_sources_gcc15/libgnarl-sp.lst"         "$here/rts_sources_gcc15/libgnarl-sp"         "$LT/gnarl"
if [ -n "$TA" ]; then
  copy "$here/rts_sources_gcc15/libgnat-32.lst"          "$here/rts_sources_gcc15/libgnat-32"          "$AP/gnat"
  copy "$here/rts_sources_gcc15/libgnat-semihosting.lst" "$here/rts_sources_gcc15/libgnat-semihosting" "$AP/gnat"
  copy "$here/rts_sources_gcc15/libgnarl-smp.lst"        "$here/rts_sources_gcc15/libgnarl-smp"        "$AP/gnarl"
  assert_identical "$here/rts_sources_gcc15/libgnat.lst" "$LT/gnat" "$AP/gnat" riscv64 arm-eabi
  #  The gnarl half needs the same guard. Omitting it let three board-support
  #  units (a-intnam.ads, s-bbbosu.adb/.ads) sit in the common directory, so an
  #  ARM build compiled PolarFire's Board_Support and failed on
  #  "System.Bb.Riscv_Plic is not a predefined library unit".
  assert_identical "$here/rts_sources_gcc15/libgnarl.lst" "$LT/gnarl" "$AP/gnarl" riscv64-gnarl arm-eabi-gnarl
fi
# CONTRACT.md 7.15: tier 1 is NOT a flat union. GNAT's configurable-runtime
# logic keys off which units are VISIBLE on the source path, so a light-profile
# build must not see embedded's units. Common set plus per-profile overlays.
#
# libgnat-light is SHARED by the light and light-tasking leaves: measured on
# this toolchain, every unit both profiles vary is byte-identical between them,
# so two directories held two copies of one snapshot for no content reason
# (CONTRACT.md 7.16). One directory, plus the assertion below that the sharing
# is still true. There is deliberately no libgnat-light-tasking any more.
copy "$here/rts_sources_gcc15/libgnat-light.lst"          "$here/rts_sources_gcc15/libgnat-light"          "$L/gnat"
assert_identical "$here/rts_sources_gcc15/libgnat-light.lst" "$L/gnat" "$LT/gnat" light light-tasking
copy "$here/rts_sources_gcc15/libgnat-embedded.lst"       "$here/rts_sources_gcc15/libgnat-embedded"       "$E/gnat"
copy "$here/rts_sources_gcc15/libgnarl-embedded.lst"      "$here/rts_sources_gcc15/libgnarl-embedded"      "$E/gnarl"
# Units whose owning LIBRARY varies by profile, not their content: gnarl-side
# for light-tasking, gnat-side for embedded, byte-identical either way. One
# directory serves both; the assertion keeps that true (CONTRACT.md 7.17).
copy "$here/rts_sources_gcc15/librestrictions.lst"        "$here/rts_sources_gcc15/librestrictions"        "$LT/gnarl"
assert_identical "$here/rts_sources_gcc15/librestrictions.lst" "$LT/gnarl" "$E/gnat" light-tasking-gnarl embedded-gnat

#  Tier 2, tier 3 and the leaves are owned, not populated. Nothing follows.
echo "tier 2/3 and leaves: owned, not populated"
echo "done."
