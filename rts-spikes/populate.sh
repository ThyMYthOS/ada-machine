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

L=$T/light-polarfiresoc; LT=$T/light-tasking-polarfiresoc; E=$T/embedded-polarfiresoc

echo "rts_sources_gcc15"
copy "$here/rts_sources_gcc15/libgnat.lst"  "$here/rts_sources_gcc15/libgnat"  "$E/gnat"  "$LT/gnat"  "$L/gnat"
copy "$here/rts_sources_gcc15/libgnarl.lst" "$here/rts_sources_gcc15/libgnarl" "$E/gnarl" "$LT/gnarl"
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
  for d in gnat gnarl; do
    lst="$here/lists/$prof.$d.leaf.lst"
    [ -f "$lst" ] && while read -r f; do
      [ -n "$f" ] && [ -f "$T/$prof-polarfiresoc/$d/$f" ] && cp "$T/$prof-polarfiresoc/$d/$f" "$here/$crate/src/$f"
    done < "$lst"
  done
  echo "  -> $crate/src: $(ls "$here/$crate/src" | wc -l | tr -d ' ') files"
done
echo "done."
