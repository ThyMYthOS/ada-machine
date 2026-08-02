#!/bin/sh
# Copy the runtime sources named in each crate's list out of the installed
# GNAT ARM toolchain. See rts_sources_gcc15_arm/README.md and
# rts-spikes/CONTRACT.md §1 for why they are not committed.
#
# Single source runtime: light-tasking-rpi-pico. There is no plain
# "light-rpi-pico" in this toolchain (only light-tasking-rpi-pico,
# light-tasking-rpi-pico-smp, embedded-rpi-pico, embedded-rpi-pico-smp are
# installed) -- see the top-level README.md "Blockers" section. Every list
# below was derived by diffing light-tasking-rpi-pico against embedded-rpi-pico
# (tier 1 provenance) and against the generic light-cortex-m0p (tier 2/3
# boundary), so light-tasking-rpi-pico alone is a sufficient and correct
# single source for all of them.
set -e
T=$(ls -d "$HOME"/.local/share/alire/toolchains/gnat_arm_elf_15.1.2_*/arm-eabi/lib/gnat 2>/dev/null | head -1)
[ -n "$T" ] || { echo "error: gnat_arm_elf 15.1.2 not installed"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
LT="$T/light-tasking-rpi-pico"
[ -d "$LT" ] || { echo "error: light-tasking-rpi-pico runtime not found under $T"; exit 1; }

copy() {   # copy <list> <dest> <src-dir>...
  list=$1; dest=$2; shift 2
  mkdir -p "$dest"
  # PRUNE: a file left behind from an earlier layout is a WRONG-VARIANT file
  # sitting where the right one belongs (rts-spikes/CONTRACT.md §7.15/7.16).
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

#  Tier 1 is SHARED with the PolarFire spike (CONTRACT.md 7.19): one crate,
#  ../../rts-spikes/rts_sources_gcc15, serving arm-eabi and riscv64-elf. Its
#  populate script copies both targets' halves and asserts they still agree, so
#  there is nothing to do here. There is no rts_sources_gcc15_arm any more.
echo "tier 1: shared -- run ../rts-spikes/populate.sh"
sh "$here/../rts-spikes/populate.sh" >/dev/null 2>&1 \
  || echo "  note: shared tier-1 populate reported a problem; run it directly to see why"
# libgnat-armv8m is intentionally NOT populated: no RP2350 runtime ships in
# this toolchain (README.md "Device axis").

#  Tier 2, tier 3 and this leaf are OWNED, not populated (CONTRACT.md §1).
#  rts_core_cortexm and rts_support_pico live in ../rts-spikes and are
#  committed there, including src-rp2350/ -- whose sources came from the
#  published light_tasking_rp2350 crate, since no RP2350 runtime ships in the
#  toolchain. Owning them is what makes that provenance acceptable: there is
#  no second copy to drift from.
echo "tier 2/3 and the leaf: owned, not populated"
echo "done."
