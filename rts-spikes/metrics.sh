#!/bin/sh
#  metrics.sh -- measure the built images, and either compare to or rewrite
#  metrics.golden.   Driven by the Makefile (`make verify`, `make bless`);
#  see the comment above the `verify` target there for the workflow.
#
#  usage: sh metrics.sh verify|bless
#
#  Inputs, all from the environment (the Makefile sets them):
#    RV_SIZE RV_READELF      riscv64-elf-size / -readelf   (RISC-V applications)
#    ARM_SIZE ARM_READELF    arm-eabi-size / -readelf      (ARM applications)
#    RV_APPS ARM_APPS        space-separated application directory names
#    RV_TC ARM_TC            toolchain bin dirs, used only in the error message
#    GOLDEN                  path of the golden file
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
trap 'rm -f "$tmp" "$tmp.new"' EXIT HUP INT TERM

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
check_tool "${ARM_SIZE:-}"    "ARM size"        ARM_TC    "${ARM_TC:-}" || tools_ok=0
check_tool "${ARM_READELF:-}" "ARM readelf"     ARM_TC    "${ARM_TC:-}" || tools_ok=0
if [ "$tools_ok" = 0 ]; then
  echo "FAIL: toolchain missing; nothing was measured" >&2
  exit 1
fi

#  --- measurement ------------------------------------------------------------
#  One TSV row per application:
#    app text data bss entry eflags isa attrs
#  See the header written by `bless` for what each field is and why.
nonblank() { [ -n "$1" ]; }
shape() {   # value regexp  -> 0 if the whole value matches
  printf '%s\n' "$1" | awk -v re="$2" '$0 ~ re { ok = 1 } END { exit ok ? 0 : 1 }'
}

measure() {   # app size readelf isatag
  app=$1; size=$2; readelf=$3; isatag=$4
  img="$app/bin/$app"
  if [ ! -f "$img" ]; then
    err "$app: image '$img' not found (run 'make build')"
    return
  fi

  sz=$("$size" "$img") || { err "$app: $size failed on $img"; return; }
  hd=$("$readelf" -h "$img") || { err "$app: $readelf -h failed on $img"; return; }
  at=$("$readelf" -A "$img") || { err "$app: $readelf -A failed on $img"; return; }

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
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$app" "$text" "$data" "$bss" "$entry" "$eflags" "$isa" "$attrs" >> "$tmp"
}

for a in $RV_APPS;  do measure "$a" "$RV_SIZE"  "$RV_READELF"  Tag_RISCV_arch; done
for a in $ARM_APPS; do measure "$a" "$ARM_SIZE" "$ARM_READELF" Tag_CPU_arch;   done

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
  {
    cat <<'EOF'
# metrics.golden -- the expected size/ABI of every built image.  GENERATED by
# `make bless`; read by `make verify`.  Do not edit by hand.
#
# WORKFLOW.  change code -> `make build verify` fails and shows expected vs.
# actual -> inspect that the change is the one you meant -> `make bless` ->
# commit this file's diff TOGETHER WITH the change that caused it.
#
# One tab-separated row per application:
#   app     directory name under rts-spikes/
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
app	text	data	bss	entry	eflags	isa	attrs
EOF
    cat "$tmp"
  } > "$tmp.new" && mv "$tmp.new" "$GOLDEN" || { echo "FAIL: could not write $GOLDEN" >&2; exit 1; }
  n=$(wc -l < "$tmp" | tr -d ' ')
  echo "blessed $n application(s) into $GOLDEN"
  exit 0
fi

#  --- verify -----------------------------------------------------------------
if [ ! -f "$GOLDEN" ]; then
  echo "FAIL: golden file '$GOLDEN' does not exist (run 'make bless' once, and commit it)" >&2
  exit 1
fi

#  Say WHERE this measurement was taken. metrics.golden was blessed on
#  macOS/aarch64; whether the same 15.1.2 cross compiler built for Linux/x86_64
#  produces byte-identical text/data/bss/attributes had never been checked
#  (RTS-PRODUCTION.md A3). If a CI run differs from the golden file while the
#  same commit passes on the Mac, this line and the expected/actual pairs below
#  are the whole diagnosis: they name the host and the exact compiler build.
tcname() { basename "$(dirname "${1:-?}")"; }
printf 'measured on: %s; riscv toolchain %s; arm toolchain %s\n' \
  "$(uname -sm)" "$(tcname "${RV_TC:-}")" "$(tcname "${ARM_TC:-}")"

#  awk reads the golden file, then the measurement. It prints the human table
#  and every mismatch, and exits non-zero on any of: a malformed or empty
#  golden row, a duplicate app, an app on one side only, or any differing field.
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
    if ($1 != "app") { printf "FAIL: %s: first non-comment line must be the header row\n", golden; bad++ }
    next
  }
  if (NF != 8) { printf "FAIL: %s: malformed row (%d fields, want 8): %s\n", golden, NF, $0; bad++; next }
  if ($1 == "") { printf "FAIL: %s: row with empty app name\n", golden; bad++; next }
  if ($1 in G) { printf "FAIL: %s: duplicate row for %s\n", golden, $1; bad++; next }
  for (i = 2; i <= 8; i++)
    if ($i == "") { printf "FAIL: %s: %s has an empty %s field\n", golden, $1, fname[i - 1]; bad++ }
  gorder[++ng] = $1
  for (i = 2; i <= 8; i++) G[$1, i - 1] = $i
  G[$1] = 1
  next
}
{
  if (NF != 8) { printf "FAIL: internal: malformed measurement row: %s\n", $0; bad++; next }
  app = $1; A[app] = 1; aorder[++na] = app
  for (i = 2; i <= 8; i++) V[app, i - 1] = $i
}
END {
  if (ng == 0) { printf "FAIL: %s contains no application rows\n", golden; bad++ }
  #  table: measured apps first, then golden-only apps as explicit failures
  for (k = 1; k <= na; k++) {
    app = aorder[k]; st = ""
    if (!(app in G)) st = "FAIL (not in golden file)"
    else for (i = 1; i <= nf; i++) if (V[app, i] != G[app, i]) { st = "FAIL"; break }
    printf "%-18s %-8s %-9s %-11s %s%s\n", app, V[app, 1], V[app, 3], V[app, 4], label(V[app, 6]), (st == "" ? "" : "   <-- " st)
  }
  for (k = 1; k <= ng; k++) {
    app = gorder[k]
    if (!(app in A)) printf "%-18s (no measurement)   <-- FAIL\n", app
  }
  print ""
  for (k = 1; k <= na; k++) {
    app = aorder[k]
    if (!(app in G)) { printf "FAIL %s: built but absent from %s (new application? run make bless)\n", app, golden; bad++; continue }
    for (i = 1; i <= nf; i++)
      if (V[app, i] != G[app, i]) {
        printf "FAIL %s.%s:\n    expected: %s\n    actual:   %s\n", app, fname[i], G[app, i], V[app, i]; bad++
      }
  }
  for (k = 1; k <= ng; k++) {
    app = gorder[k]
    if (!(app in A)) { printf "FAIL %s: in %s but not measured (image missing, or not in APPS/ARM_APPS)\n", app, golden; bad++ }
  }
  if (measure_errors > 0) { printf "FAIL: %d measurement error(s) above\n", measure_errors; bad++ }
  if (bad > 0) { printf "verify FAILED (%d problem(s)). If the change is intended: make bless, and commit %s with it.\n", bad, golden; exit 1 }
  printf "verify OK: %d application(s) match %s exactly\n", na, golden
}' "$GOLDEN" "$tmp" || {
  rc=$?
  echo "hint: if EVERY application differs (or the same commit passes on another host), suspect the compiler build or host, not the source -- compare 'measured on' above with the host metrics.golden was blessed on (macOS/aarch64)." >&2
  exit $rc
}
