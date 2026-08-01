#!/bin/sh
# Copy the runtime sources named in each crate's list out of the installed
# GNAT RISC-V toolchain. See CONTRACT.md §1 for why they are not committed.
set -e
T=$(ls -d "$HOME"/.local/share/alire/toolchains/gnat_riscv64_elf_15.1.2_*/riscv64-elf/lib/gnat 2>/dev/null | head -1)
[ -n "$T" ] || { echo "error: gnat_riscv64_elf 15.1.2 not installed"; exit 1; }
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

echo "rts_sources_gcc15"
# libgnat.lst now excludes every profile-variant unit (lists/profile-variant.lst),
# so any profile is a valid source for the rest. Search order is still
# widest-first because embedded ships units the narrower profiles omit.
copy "$here/rts_sources_gcc15/libgnat.lst"  "$here/rts_sources_gcc15/libgnat"  "$E/gnat"  "$LT/gnat"  "$L/gnat"
copy "$here/rts_sources_gcc15/libgnarl.lst" "$here/rts_sources_gcc15/libgnarl" "$E/gnarl" "$LT/gnarl"
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
copy "$here/rts_sources_gcc15/libgnarl-light-tasking.lst" "$here/rts_sources_gcc15/libgnarl-light-tasking" "$LT/gnarl"
copy "$here/rts_sources_gcc15/libgnarl-embedded.lst"      "$here/rts_sources_gcc15/libgnarl-embedded"      "$E/gnarl"
echo "rts_core_riscv64"
copy "$here/rts_core_riscv64/src.lst" "$here/rts_core_riscv64/src" "$LT/gnarl" "$E/gnarl" "$L/gnat" "$LT/gnat"
echo "rts_support_mpfs"
copy "$here/rts_support_mpfs/src.lst" "$here/rts_support_mpfs/src" "$L/gnat" "$LT/gnarl" "$E/gnarl"
for f in common-RAM.ld memory-map.ld; do
  [ -f "$L/ld/$f" ] && { mkdir -p "$here/rts_support_mpfs/ld"; cp "$L/ld/$f" "$here/rts_support_mpfs/ld/$f.upstream"; }
done
echo "leaf-owned units"
for p in light:light_mpfs light-tasking:light_tasking_mpfs embedded:embedded_mpfs; do
  prof=${p%%:*}; crate=${p##*:}
  mkdir -p "$here/$crate/src"
  # PRUNE leaf src/ as well, against this profile's own lists plus the
  # keep-list of hand-authored files no list names. This is what makes moving
  # a unit OUT of a leaf and into a tier-1 overlay actually take effect: leaf
  # src/ precedes the overlay in Source_Dirs, so a left-behind copy still WINS
  # and the move would silently do nothing. Same shadowing rule as CONTRACT.md
  # 7.15, one directory level down.
  for existing in "$here/$crate/src"/*; do
    [ -e "$existing" ] || continue
    b=$(basename "$existing"); named=
    for lst in "$here/lists/$prof.gnat.leaf.lst" "$here/lists/$prof.gnarl.leaf.lst" \
               "$here/lists/leaf-keep.lst"; do
      [ -f "$lst" ] && grep -qxF "$b" "$lst" && { named=1; break; }
    done
    [ -n "$named" ] || { echo "  pruned $crate/src/$b"; rm -f "$existing"; }
  done
  for d in gnat gnarl; do
    lst="$here/lists/$prof.$d.leaf.lst"
    [ -f "$lst" ] && while read -r f; do
      # Never clobber a leaf source that has been edited: these files are
      # deliberately modified (s-bbbopa/s-bbpara read MPFS_Runtime_Config).
      # Use FORCE_LEAF_SRC=1 to re-copy pristine upstream copies.
      [ -n "$f" ] && [ -f "$T/$prof-polarfiresoc/$d/$f" ] && \
        { [ -z "${FORCE_LEAF_SRC:-}" ] && [ -f "$here/$crate/src/$f" ] \
          || cp "$T/$prof-polarfiresoc/$d/$f" "$here/$crate/src/$f"; }
    done < "$lst"
  done
  echo "  -> $crate/src: $(ls "$here/$crate/src" | wc -l | tr -d ' ') files"
done

# What remains duplicated between leaves, and why it is not shared:
#   s-parame.ads/.adb, s-bbpara.ads  -- identical in light-tasking and embedded.
# A shared "tasking family" overlay would save three files but cost a whole
# directory, and s-bbpara.ads is HAND-EDITED and committed, so it cannot move
# into rts_sources_gcc15 (that crate is gitignored in full -- the file would
# stop being tracked). Left duplicated, but checked: editing one leaf's copy
# and not the other's now fails here instead of silently diverging.
echo "leaf duplicate check"
dup_bad=0
for f in s-parame.ads s-parame.adb s-bbpara.ads; do
  a=$here/light_tasking_mpfs/src/$f; b=$here/embedded_mpfs/src/$f
  [ -f "$a" ] && [ -f "$b" ] || continue
  cmp -s "$a" "$b" || { echo "  DIVERGED: $f differs between light_tasking_mpfs and embedded_mpfs"; dup_bad=$((dup_bad+1)); }
done
if [ "$dup_bad" -ne 0 ]; then
  echo "error: leaf copies that are meant to be identical have drifted."
  echo "       Reconcile them, or record the divergence in CONTRACT.md 7.16."
  exit 1
fi
echo "  -> light_tasking_mpfs and embedded_mpfs agree on their shared leaf units"
echo "done."
