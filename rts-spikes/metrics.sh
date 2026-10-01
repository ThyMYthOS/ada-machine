#!/bin/sh
#  metrics.sh -- measure the built images, and either compare to or rewrite
#  metrics.golden.   Driven by the Makefile (`make verify`, `make bless`);
#  see the comment above the `verify` target there for the workflow.
#
#  usage: sh metrics.sh verify|bless
#
#  Inputs, all from the environment (the Makefile sets them):
#    RV_SIZE RV_READELF RV_STRINGS     riscv64-elf-* tools (RISC-V applications)
#    ARM_SIZE ARM_READELF ARM_STRINGS  arm-eabi-* tools    (ARM applications)
#    RV_APPS ARM_APPS        space-separated application directory names
#    RV_TC ARM_TC            toolchain bin dirs, used only in the error message
#    GOLDEN                  path of the golden file
#    MEASURED                verify only: where to write this host's measured
#                            rows, in golden format (CI uploads it as an artifact)
#
#  KEYED ON THE COMPILER, NOT THE HOST. Every row carries the `GNAT Version:`
#  string the binder embedded in that image, and a measurement is compared only
#  against the row for the same (app, compiler). Measured on the first CI run:
#  Alire's gnat_riscv64_elf / gnat_arm_elf 15.1.2 is GCC 15.0.1 20250418
#  (prerelease) on macOS/aarch64 but GCC 15.1.0 on Linux/x86_64 -- one crate
#  version, two compilers -- and every image's text differed. CI run 2 traced
#  it exactly: .text (code) is the SAME size on both hosts; only .rodata moves,
#  because the binder embeds "GNAT Version: <compiler>\0" (43 bytes on the Mac,
#  21 on Linux), and the next 4-/8-aligned object turns that into exactly -20
#  bytes on ARM and -24 on RISC-V. The compiler is the variable, so it is the
#  key: a host whose compiler has no baseline FAILS
#  with "no baseline" and prints the rows to seed it, rather than comparing
#  against another compiler's numbers or silently passing. And if Alire ever
#  ships the same build on both hosts, both will check the same rows.
#
#  DESIGN RULES (each one closes a way the old `verify` reported success while
#  checking nothing -- see RTS-PRODUCTION.md A2 and the risk register):
#
#    - A missing image is an ERROR, never a skip.
#    - A missing/unusable tool is an ERROR before anything is measured.
#    - Every field is validated against the shape it must have; an empty or
#      unparseable field is an ERROR, so it can never compare "equal".
#    - The application set is compared, not just the values: an app in the
#      golden file but not measured, or measured but not in the golden file, is
#      a failure.
#    - `bless` refuses to write unless every application measured cleanly, so a
#      half-built tree cannot produce a half-empty golden file.
#    - Exact string match. No tolerances.
#
#  Plain /bin/sh + awk only: this runs on macOS (BSD userland).

set -u

mode=${1:-}
case "$mode" in verify|bless) ;; *) echo "usage: sh metrics.sh verify|bless" >&2; exit 2 ;; esac

: "${GOLDEN:=metrics.golden}"
RV_APPS=${RV_APPS:-}
ARM_APPS=${ARM_APPS:-}

errors=0
err() { printf 'ERROR: %s\n' "$*" >&2; errors=$((errors + 1)); }

tmp=$(mktemp "${TMPDIR:-/tmp}/metrics.XXXXXX") || { echo "ERROR: mktemp failed" >&2; exit 2; }
trap 'rm -f "$tmp" "$tmp.new" "$tmp.kept"' EXIT HUP INT TERM

#  --- toolchain: fail loudly, before measuring anything ----------------------
#  `$(wildcard ...)` that matches nothing leaves TOOLCHAIN empty, so the tool
#  paths degrade to "/riscv64-elf-size". Executing each one proves it exists
#  and runs; a path that merely looks plausible does not pass.
check_tool() {   # path  what  dirvar-name  dirvar-value
  if [ ! -x "$1" ] || ! "$1" --version >/dev/null 2>&1; then
    err "$2 not usable: '$1'"
    printf "       %s is '%s' (empty means the Alire toolchain glob matched nothing).\n" "$3" "$4" >&2
    printf '       Run `make toolchains` (installs the pinned cross compilers through Alire) or pass %s=<bin dir> to make.\n' "$3" >&2
    return 1
  fi
}
tools_ok=1
check_tool "${RV_SIZE:-}"     "RISC-V size"     TOOLCHAIN "${RV_TC:-}"  || tools_ok=0
check_tool "${RV_READELF:-}"  "RISC-V readelf"  TOOLCHAIN "${RV_TC:-}"  || tools_ok=0
check_tool "${RV_STRINGS:-}"  "RISC-V strings"  TOOLCHAIN "${RV_TC:-}"  || tools_ok=0
check_tool "${ARM_SIZE:-}"    "ARM size"        ARM_TC    "${ARM_TC:-}" || tools_ok=0
check_tool "${ARM_READELF:-}" "ARM readelf"     ARM_TC    "${ARM_TC:-}" || tools_ok=0
check_tool "${ARM_STRINGS:-}" "ARM strings"     ARM_TC    "${ARM_TC:-}" || tools_ok=0
if [ "$tools_ok" = 0 ]; then
  echo "FAIL: toolchain missing; nothing was measured" >&2
  exit 1
fi

#  --- measurement ------------------------------------------------------------
#  One TSV row per application:
#    app compiler text data bss entry eflags isa attrs
#  See the header written by `bless` for what each field is and why.
nonblank() { [ -n "$1" ]; }
shape() {   # value regexp  -> 0 if the whole value matches
  printf '%s\n' "$1" | awk -v re="$2" '$0 ~ re { ok = 1 } END { exit ok ? 0 : 1 }'
}

measure() {   # app size readelf strings isatag
  app=$1; size=$2; readelf=$3; strings=$4; isatag=$5
  img="$app/bin/$app"
  if [ ! -f "$img" ]; then
    err "$app: image '$img' not found (run 'make build')"
    return
  fi

  sz=$("$size" "$img") || { err "$app: $size failed on $img"; return; }
  hd=$("$readelf" -h "$img") || { err "$app: $readelf -h failed on $img"; return; }
  at=$("$readelf" -A "$img") || { err "$app: $readelf -A failed on $img"; return; }
  st=$("$strings" -a "$img") || { err "$app: $strings failed on $img"; return; }

  #  The compiler that built THIS image, as the binder recorded it in
  #  __gnat_version -- not whatever happens to be installed. Exactly one distinct
  #  value is required: none means the string was not linked in (the key would
  #  be empty), more than one would mean objects from two compilers.
  compiler=$(printf '%s\n' "$st" | sed -n 's/^GNAT Version: //p' | sort -u)
  ncomp=$(printf '%s' "$compiler" | awk 'END { print NR }')
  if [ "$ncomp" -gt 1 ]; then
    err "$app: $ncomp different 'GNAT Version:' strings in one image: $(printf '%s' "$compiler" | tr '\n' '|')"
    return
  fi

  #  size -B: line 2 is `text data bss dec hex filename`.
  set -- $(printf '%s\n' "$sz" | awk 'NR==2 { print $1, $2, $3 }')
  text=${1:-}; data=${2:-}; bss=${3:-}
  entry=$(printf '%s\n' "$hd" | awk '/Entry point address:/ { print $4 }')
  #  Raw e_flags with readelf's decoding: "0x5, RVC, double-float ABI". This is
  #  the float-ABI authority -- ld refuses to link mixed values.
  eflags=$(printf '%s\n' "$hd" | awk '/^[ \t]*Flags:/ { sub(/^[ \t]*Flags:[ \t]*/, ""); print }')

  #  Every build-attribute tag, verbatim. The ISA tag (the full architecture
  #  string) gets its own column so a diff shows it; everything else, in
  #  readelf's order, is joined as Tag=value;Tag=value. Nothing is summarised.
  parsed=$(printf '%s\n' "$at" | awk -v isatag="$isatag" '
    /^[ \t]*Tag_[A-Za-z0-9_]+:/ {
      line = $0; sub(/^[ \t]+/, "", line)
      i = index(line, ":"); k = substr(line, 1, i - 1); v = substr(line, i + 1)
      sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); gsub(/"/, "", v)
      if (k == isatag) isa = v
      else rest = rest (rest == "" ? "" : ";") k "=" v
    }
    END { printf "%s\t%s\n", isa, rest }')
  isa=${parsed%%	*}
  attrs=${parsed#*	}

  bad=
  nonblank "$compiler" || bad="$bad compiler(no 'GNAT Version:' string in the image)"
  shape "$text"   '^[0-9]+$'    || bad="$bad text"
  shape "$data"   '^[0-9]+$'    || bad="$bad data"
  shape "$bss"    '^[0-9]+$'    || bad="$bad bss"
  shape "$entry"  '^0x[0-9a-f]+$' || bad="$bad entry"
  shape "$eflags" '^0x[0-9a-f]+' || bad="$bad eflags"
  nonblank "$isa"   || bad="$bad isa($isatag)"
  nonblank "$attrs" || bad="$bad attrs"
  if [ -n "$bad" ]; then
    err "$app: could not parse:$bad"
    return
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$app" "$compiler" "$text" "$data" "$bss" "$entry" "$eflags" "$isa" "$attrs" >> "$tmp"
}

for a in $RV_APPS;  do measure "$a" "$RV_SIZE"  "$RV_READELF"  "$RV_STRINGS"  Tag_RISCV_arch; done
for a in $ARM_APPS; do measure "$a" "$ARM_SIZE" "$ARM_READELF" "$ARM_STRINGS" Tag_CPU_arch;   done

#  --- bless ------------------------------------------------------------------
if [ "$mode" = bless ]; then
  if [ "$errors" != 0 ]; then
    echo "FAIL: $errors error(s); $GOLDEN NOT written (a golden file is only blessed from a complete, clean measurement)" >&2
    exit 1
  fi
  if [ ! -s "$tmp" ]; then
    echo "FAIL: no applications measured; $GOLDEN NOT written" >&2
    exit 1
  fi
  #  Rows for OTHER compilers are kept -- they are another host's baseline, which
  #  this host cannot measure -- but only for applications that still exist, so
  #  a removed application does not linger and fail the other host. Rows for
  #  this host's (app, compiler) pairs are replaced. Kept rows come first, in
  #  their existing order, then this host's rows in build order: running bless
  #  twice on an unchanged tree writes an identical file.
  kept="$tmp.kept"
  : > "$kept"
  if [ -f "$GOLDEN" ]; then
    awk -F'\t' -v measured="$tmp" '
      BEGIN { while ((getline l < measured) > 0) { split(l, f, "\t"); M[f[1]] = 1; K[f[1], f[2]] = 1 } }
      /^[ \t]*#/ || /^[ \t]*$/ { next }
      !hdr { hdr = 1; next }
      NF == 9 && ($1 in M) && !(($1, $2) in K)' "$GOLDEN" > "$kept" ||
      { echo "FAIL: could not read existing $GOLDEN; NOT written" >&2; rm -f "$kept"; exit 1; }
  fi
  {
    cat <<'EOF'
# metrics.golden -- the expected size/ABI of every built image.  GENERATED by
# `make bless`; read by `make verify`.  Do not edit by hand.
#
# WORKFLOW.  change code -> `make build verify` fails and shows expected vs.
# actual -> inspect that the change is the one you meant -> `make bless` ->
# commit this file's diff TOGETHER WITH the change that caused it.
#
# KEYED ON (app, compiler). A measurement is compared only with the row for the
# compiler that built it, so each host checks its own rows and `make bless`
# rewrites only those. Measured: Alire's 15.1.2 cross compilers are GCC 15.0.1
# 20250418 (prerelease) on macOS/aarch64 but GCC 15.1.0 on Linux/x86_64. Code
# (.text) is the same size under both; .rodata differs by the embedded
# "GNAT Version:" string plus alignment (-20 bytes ARM, -24 RISC-V). A compiler
# with no rows here fails verify with "no baseline", and prints the rows to add.
# Rows for another host's compiler are seeded from that host's verify output.
#
# One tab-separated row per (application, compiler):
#   app      directory name under rts-spikes/
#   compiler the image's own `GNAT Version:` string (__gnat_version), i.e. the
#            compiler that actually built it, not whatever is installed
#   text    `size` text column: code + rodata (flash footprint, together with data)
#   data    `size` data column: initialised data. Not derivable from text/bss, and
#           not covered by them: a change that only grows .data (what the startup
#           copy loop moves, and the part of the footprint that sits in flash for
#           an XIP image such as hello_envm_mpfs) would otherwise pass unseen
#   bss     `size` bss column
#   entry   ELF entry point (e_entry): where the boot flow jumps
#   eflags  ELF e_flags, raw hex plus readelf's decoding. The float-ABI authority:
#           the linker refuses to mix values, and 'soft'/'hard' is read off this
#   isa     RISC-V: full Tag_RISCV_arch string.  ARM: Tag_CPU_arch.
#           Verbatim -- dropping zicsr, or adding a Z-extension, shows up here
#   attrs   every other build-attribute tag (stack alignment, privileged spec,
#           ARM FP/enum/alignment ABI tags, ...) as Tag=value;Tag=value
# Exact string match; no tolerances.
app	compiler	text	data	bss	entry	eflags	isa	attrs
EOF
    cat "$kept" "$tmp"
  } > "$tmp.new" && mv "$tmp.new" "$GOLDEN" || { echo "FAIL: could not write $GOLDEN" >&2; rm -f "$kept"; exit 1; }
  n=$(wc -l < "$tmp" | tr -d ' ')
  k=$(wc -l < "$kept" | tr -d ' ')
  echo "blessed $n application(s) into $GOLDEN, for: $(cut -f2 "$tmp" | sort -u | tr '\n' '|' | sed 's/|$//')"
  if [ "$k" -gt 0 ]; then
    echo "kept $k row(s) for other compilers, unchecked on this host: $(cut -f2 "$kept" | sort -u | tr '\n' '|' | sed 's/|$//')"
    echo "  (delete any no host builds with any more -- nothing else will)"
  fi
  rm -f "$kept"
  exit 0
fi

#  --- verify -----------------------------------------------------------------
if [ ! -f "$GOLDEN" ]; then
  echo "FAIL: golden file '$GOLDEN' does not exist (run 'make bless' once, and commit it)" >&2
  exit 1
fi

#  This host's measurement, in golden format, for a CI artifact: on a host with
#  no baseline yet these are exactly the rows to review and add.
if [ -n "${MEASURED:-}" ]; then
  cp "$tmp" "$MEASURED" 2>/dev/null || echo "warning: could not write $MEASURED" >&2
fi

#  Say WHERE, and WITH WHAT, this was measured. The compiler line is the key the
#  comparison below uses; the toolchain directory names the exact Alire build.
tcname() { basename "$(dirname "${1:-?}")"; }
printf 'measured on: %s; riscv toolchain %s; arm toolchain %s\n' \
  "$(uname -sm)" "$(tcname "${RV_TC:-}")" "$(tcname "${ARM_TC:-}")"
printf 'compiler(s): %s\n' "$(cut -f2 "$tmp" | sort -u | tr '\n' '|' | sed 's/|$//')"

#  awk reads the golden file, then the measurement. It prints the human table
#  and every mismatch, and exits non-zero on any of: a malformed or empty
#  golden row, a duplicate (app, compiler), an app on one side only, an app
#  built by a compiler with no baseline row, or any differing field. Golden rows
#  for OTHER compilers are another host's baseline and are not compared here.
awk -v golden="$GOLDEN" -v measure_errors="$errors" '
BEGIN {
  FS = "\t"
  nf = split("text data bss entry eflags isa attrs", fname, " ")
  printf "%-18s %-8s %-9s %-11s %s\n", "APP", "TEXT", "BSS", "ENTRY", "FLOAT"
}
function label(isa) {
  if (isa ~ /^rv/) return (isa ~ /_f.*_d/) ? "hard" : "soft"
  return isa
}
FILENAME == golden {
  if ($0 ~ /^[ \t]*#/ || $0 ~ /^[ \t]*$/) next
  if (!seen_hdr) {
    seen_hdr = 1
    if ($1 != "app" || $2 != "compiler") { printf "FAIL: %s: first non-comment line must be the header row (app, compiler, ...)\n", golden; bad++ }
    next
  }
  if (NF != 9) { printf "FAIL: %s: malformed row (%d fields, want 9): %s\n", golden, NF, $0; bad++; next }
  if ($1 == "" || $2 == "") { printf "FAIL: %s: row with empty app or compiler: %s\n", golden, $0; bad++; next }
  if (($1, $2) in G) { printf "FAIL: %s: duplicate row for %s under compiler %s\n", golden, $1, $2; bad++; next }
  for (i = 3; i <= 9; i++)
    if ($i == "") { printf "FAIL: %s: %s (%s) has an empty %s field\n", golden, $1, $2, fname[i - 2]; bad++ }
  G[$1, $2] = 1
  if (!($1 in GA)) gorder[++ng] = $1
  GA[$1] = 1
  comps[$1] = comps[$1] (comps[$1] == "" ? "" : " | ") $2
  for (i = 3; i <= 9; i++) G[$1, $2, i - 2] = $i
  rows++
  next
}
{
  if (NF != 9) { printf "FAIL: internal: malformed measurement row: %s\n", $0; bad++; next }
  app = $1; A[app] = 1; aorder[++na] = app; C[app] = $2; row[app] = $0
  for (i = 3; i <= 9; i++) V[app, i - 2] = $i
}
END {
  if (rows == 0) { printf "FAIL: %s contains no application rows\n", golden; bad++ }
  for (k = 1; k <= na; k++) {
    app = aorder[k]; st = ""
    if (!(app in GA)) st = "FAIL (not in golden file)"
    else if (!((app, C[app]) in G)) st = "FAIL (no baseline for this compiler)"
    else for (i = 1; i <= nf; i++) if (V[app, i] != G[app, C[app], i]) { st = "FAIL"; break }
    printf "%-18s %-8s %-9s %-11s %s%s\n", app, V[app, 1], V[app, 3], V[app, 4], label(V[app, 6]), (st == "" ? "" : "   <-- " st)
  }
  for (k = 1; k <= ng; k++) {
    app = gorder[k]
    if (!(app in A)) printf "%-18s (no measurement)   <-- FAIL\n", app
  }
  print ""
  for (k = 1; k <= na; k++) {
    app = aorder[k]
    if (!(app in GA)) { printf "FAIL %s: built but absent from %s (new application? run make bless)\n", app, golden; bad++; continue }
    if (!((app, C[app]) in G)) {
      printf "FAIL %s: no baseline for the compiler that built it\n    built by:      %s\n    baselines for: %s\n", app, C[app], comps[app]
      bad++; unseeded[++nu] = app; continue
    }
    for (i = 1; i <= nf; i++)
      if (V[app, i] != G[app, C[app], i]) {
        printf "FAIL %s.%s:\n    expected: %s\n    actual:   %s\n", app, fname[i], G[app, C[app], i], V[app, i]; bad++
      }
  }
  for (k = 1; k <= ng; k++) {
    app = gorder[k]
    if (!(app in A)) { printf "FAIL %s: in %s but not measured (image missing, or not in APPS/ARM_APPS)\n", app, golden; bad++ }
  }
  if (nu > 0) {
    printf "\nNo baseline exists yet for the compiler that built %d image(s). These are the rows\n", nu
    printf "measured here, in %s format. Check they are what you expect, then add them --\n", golden
    printf "on this host `make bless` does exactly that and keeps every other compiler'\''s rows:\n"
    printf "----- 8< -----\n"
    for (k = 1; k <= nu; k++) print row[unseeded[k]]
    printf "----- >8 -----\n"
  }
  if (measure_errors > 0) { printf "FAIL: %d measurement error(s) above\n", measure_errors; bad++ }
  if (bad > 0) { printf "verify FAILED (%d problem(s)). If the change is intended: make bless, and commit %s with it.\n", bad, golden; exit 1 }
  printf "verify OK: %d application(s) match %s exactly\n", na, golden
}' "$GOLDEN" "$tmp" || {
  rc=$?
  echo "hint: 'no baseline' means a different compiler built these images (see 'compiler(s):' above) -- seed its rows. A field mismatch under the SAME compiler means the source, the flags or the build changed." >&2
  exit $rc
}
