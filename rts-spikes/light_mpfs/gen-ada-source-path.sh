#!/bin/sh
#  gen-ada-source-path.sh -- write ada_source_path from ada_source_path.in.
#
#  Run by Alire as this crate's `post-fetch` AND `pre-build` action
#  (alire.toml [[actions]]); the working directory is the crate root, which is
#  the runtime directory (`for Runtime ("Ada") use Project'Project_Dir`).
#  RTS-PRODUCTION.md B1 has the measurements behind every choice below.
#
#  WHY GENERATED. ada_source_path lists directories that belong to OTHER
#  crates (tiers 1-3). Their location is known only after Alire has resolved
#  and deployed the dependency closure: a fetched crate lands under
#  <cache>/builds/<crate>_<version>_<id>/<hash>/, a path-pinned one at its pin,
#  and no relative path is right for both. Alire exports the root of every
#  crate in the solution as <CRATE>_ALIRE_PREFIX (measured, in post-fetch,
#  pre-build and post-build alike); this script substitutes them.
#
#  TEMPLATE. One directory per line, in search order (ORDER IS LOAD-BEARING:
#  board shadows core shadows shared, CONTRACT.md 3.4).
#    a plain line      a directory inside THIS crate, written relative to it
#    @crate@/subdir    a directory inside dependency <crate>
#  Blank lines and lines starting with '#' are dropped. The template MUST
#  list exactly the leaf's Source_Dirs (plus its own gnat_config/ and src/);
#  GNAT reads this file at bind time and for subunits at compile time
#  (RTS-GUIDE.md 1.1), and treats a missing entry as an error and a stale one
#  as nothing at all -- so this script is strict where GNAT is not: a directory
#  that does not exist stops the build, naming the directory.
#
#  Idempotent, and leaves the file untouched (timestamp too) when the content
#  is unchanged, so it is safe to run on every build.
set -eu

tpl=ada_source_path.in
out=ada_source_path
me=gen-ada-source-path

[ -f "$tpl" ] || { echo "$me: $PWD/$tpl not found (the working directory must be the crate root)" >&2; exit 1; }

tmp=$out.tmp.$$
trap 'rm -f "$tmp"' EXIT
: > "$tmp"
bad=0

while IFS= read -r line || [ -n "$line" ]; do
  case $line in
    '' | '#'*) continue ;;
    @*@*)
      name=${line#@}
      name=${name%%@*}
      rest=${line#@"$name"@}
      var=$(printf '%s' "$name" | tr 'a-z-' 'A-Z_')_ALIRE_PREFIX
      case $var in
        *[!A-Z0-9_]*) echo "$me: bad crate name '$name' in $tpl" >&2; bad=1; continue ;;
      esac
      eval "prefix=\${$var:-}"
      if [ -z "$prefix" ]; then
        echo "$me: $var is not set -- is '$name' in this crate's dependency closure, and is this running under alr?" >&2
        bad=1; continue
      fi
      path=$prefix$rest ;;
    *) path=$line ;;
  esac
  if [ ! -d "$path" ]; then
    echo "$me: '$path' (from '$line') is not a directory -- did 'make populate' run?" >&2
    bad=1; continue
  fi
  printf '%s\n' "$path" >> "$tmp"
done < "$tpl"

[ "$bad" -eq 0 ] || exit 1
[ -s "$tmp" ] || { echo "$me: $tpl lists no directories" >&2; exit 1; }

if [ -f "$out" ] && cmp -s "$tmp" "$out"; then
  :
else
  mv "$tmp" "$out"
fi
