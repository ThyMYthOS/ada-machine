#!/bin/sh
#  tests/negative/run_negative.sh -- builds that MUST fail, with the diagnostic
#  asserted.   Driven by `make test` (run from rts-spikes/); RTS-PRODUCTION.md A4.
#
#  usage: sh tests/negative/run_negative.sh [case-id ...]    (default: every case)
#
#    NEG_LIST   the case list (default tests/negative/cases.list)
#    RV_GCC     riscv64-elf-gcc of the pinned toolchain (kind `unit` only; the
#               Makefile passes it)
#
#  WHAT IT PROVES. CONTRACT.md 7.4 and 7.12 record the configuration checks in
#  rts_support_mpfs/src/mpfs_config_checks.ads having been silently dead twice
#  (a non-static condition; a unit missing from the membership list) -- the
#  failure mode is "a build that should fail, succeeds". A build that fails is
#  also not enough: it must fail for THE reason. So every case names the
#  diagnostic that must appear on an error line of the build output, and the
#  case fails -- it is not skipped -- if the build succeeds, if it fails with a
#  different message, or if a binary appears anyway.
#
#  HOW BAD VALUES ARE DRIVEN WITHOUT TOUCHING A COMMITTED FILE. The whole
#  working tree is copied (rsync, build products excluded) to a scratch
#  directory (one per leaf group, see below), and every case gets its own
#  application directory there, derived
#  from one of the real applications (hello_mpfs = light, tasking_mpfs =
#  light-tasking, embedded_app = embedded) with its [configuration.values]
#  overridden (kind `config`) or its sources replaced by a fixture from
#  tests/negative/fixtures/ (kind `source`). Nothing under rts-spikes/ is
#  written; the scratch tree is removed on exit. It is a real Alire build all
#  the way down: configuration values -> generated config package -> the
#  MPFS_Runtime_Config shim -> the membership list -> the compiler.
#
#  KIND `unit`. Some checks cannot be reached through a build at all: gprbuild's
#  typed strings (Hart_Mask_Kind, U54_Mask_Kind) reject the value before any Ada
#  is compiled. Those are driven at the unit: mpfs_config_checks.ads compiled
#  alone against the leaf's own generated configuration package with one
#  constant patched. The unmodified unit is compiled first and must succeed, so
#  a failure after the patch is the patch's doing.
#
#  THE CONTROL. Each leaf's group starts with a `control` case: the unmodified
#  application, which must BUILD. It proves the scratch tree is healthy (so the
#  failures after it are caused by the overrides), that the checks do not fire
#  on a valid configuration, and -- because it compiles first, into the same
#  leaf directory -- it would expose a stale object masking a check (7.11).
#
#  The three leaf groups run concurrently (each leaf directory is built by one
#  group only); cases within a group are sequential.
#
#  POSIX sh only: this runs under dash (Ubuntu's /bin/sh) and macOS's bash-as-sh.

set -u

NEG_LIST=${NEG_LIST:-tests/negative/cases.list}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

command -v rsync >/dev/null 2>&1 || fail "rsync not found (needed to copy the tree to a scratch directory)"
command -v alr   >/dev/null 2>&1 || fail "alr not found"
[ -d tests/negative ] || fail "run from rts-spikes/ (tests/negative not found)"
[ -f "$NEG_LIST" ] || fail "case list '$NEG_LIST' does not exist"

tmpd=$(mktemp -d "${TMPDIR:-/tmp}/rts-neg.XXXXXX") || fail "mktemp -d failed"
cleanup() {
  jobs_pids=$(jobs -p 2>/dev/null)
  [ -n "$jobs_pids" ] && kill $jobs_pids 2>/dev/null
  rm -rf "$tmpd"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

#  --- the list ----------------------------------------------------------------
rows="$tmpd/rows"
awk -F'\t' '
  /^[ \t]*#/ || /^[ \t]*$/ { next }
  !hdr { hdr = 1
         if (NF != 6 || $1 != "id" || $2 != "kind" || $3 != "leaf" || $4 != "arg" || $5 != "diagnostic" || $6 != "why") {
           print "BADHEADER" > "/dev/stderr"; bad = 1 }
         next }
  NF != 6 || $1 == "" || $4 == "" || $5 == "" || $6 == "" ||
  ($2 != "control" && $2 != "config" && $2 != "source" && $2 != "unit") ||
  ($3 != "light" && $3 != "light_tasking" && $3 != "embedded") ||
  ($2 != "control" && $5 == "-") ||
  ($2 == "control" && $5 != "-") { printf "BADROW\t%s\n", $0; bad = 1; next }
  { print }
  END { exit bad ? 1 : 0 }
' "$NEG_LIST" > "$rows" 2> "$tmpd/awk.err"
if [ $? -ne 0 ]; then
  cat "$tmpd/awk.err" >&2
  grep '^BADROW' "$rows" | while IFS= read -r l; do printf '  %s\n' "$l" >&2; done
  fail "$NEG_LIST is malformed: header 'id kind leaf arg diagnostic why' (TAB-separated), kind control|config|source|unit, leaf light|light_tasking|embedded; every non-control row needs a diagnostic, a control row must have '-'"
fi
[ -s "$rows" ] || fail "$NEG_LIST lists no cases; an empty list would make this pass vacuously"

if [ $# -gt 0 ]; then
  for n in "$@"; do
    awk -F'\t' -v n="$n" '$1 == n { f = 1 } END { exit f ? 0 : 1 }' "$rows" || fail "'$n' is not in $NEG_LIST"
  done
  want=" $* "
else
  want=
fi

#  --- the scratch trees ---------------------------------------------------------
#  ONE PER LEAF GROUP, not one shared. The three leaves path-pin the same
#  source-only crates (rts_sources_gcc15, rts_core_riscv64, rts_support_mpfs),
#  and concurrent `alr build`s in one tree race on those crates' alire/
#  directories ("copy of .../alire/build_hash_inputs failed", "post-fetch ...
#  failed" -- measured, and it failed the controls). 16 MB each is cheap.
[ -d rts_sources_gcc15/libgnat ] || fail "tier 1 is not populated (run make populate): rts_sources_gcc15/libgnat is missing"

make_ws() {   #  $1 = leaf; sets ws
  ws="$tmpd/ws_$1"
  rsync -a \
    --exclude='/acats/' --exclude='/tests/' \
    --exclude='/*/obj/' --exclude='/*/obj-*/' --exclude='/*/adalib/' --exclude='/*/adalib-*/' \
    --exclude='/*/bin/' --exclude='/*/alire/' --exclude='/*/config/' \
    --exclude='/*/gnat_config/*_config.*' --exclude='*.ali' --exclude='*.o' \
    ./ "$ws/"
}

base_app() {   #  leaf -> the real application a case is derived from
  case "$1" in light) echo hello_mpfs ;; light_tasking) echo tasking_mpfs ;; embedded) echo embedded_app ;; esac
}
leaf_crate() { case "$1" in light) echo light_mpfs ;; light_tasking) echo light_tasking_mpfs ;; embedded) echo embedded_mpfs ;; esac; }

#  Every ";"-separated diagnostic must appear on an error line: one containing
#  "error", or a project-file diagnostic (file.gpr:line:col:). The echoed
#  "ERROR: Command [...]" line does not count (it holds paths, not messages).
#  Prints a problem description, or nothing.
diag_problem() {   #  log diag rc
  _out=
  oldifs=$IFS; IFS=';'
  for d in $2; do
    IFS=$oldifs
    if ! awk -v d="$d" 'index($0, d) && !/^ERROR: Command/ && (/error/ || /[.]gpr:[0-9]+:[0-9]+:/) { f = 1 } END { exit f ? 0 : 1 }' "$1"; then
      _out="the build failed (exit $3) but no error line contains: $d"
    fi
    IFS=';'
  done
  IFS=$oldifs
  printf '%s' "$_out"
}

#  Prints the verdict for the current case (id kind diag why problem log).
verdict_line() {
  if [ -n "$problem" ]; then
    printf 'FAIL %s: %s\n' "$id" "$problem"
    printf '     (%s)\n' "$why"
    printf '     output, last 15 lines:\n'
    tail -n 15 "$log" | cut -c1-240 | sed 's/^/       | /'
    return 1
  fi
  if [ "$kind" = control ]; then
    printf 'ok   %s: builds clean (%s)\n' "$id" "$why"
  else
    printf 'ok   %s: failed as required with "%s" (%s)\n' "$id" "$diag" "$why"
  fi
  return 0
}

#  kind `unit` (see the header).
run_unit_case() {
  problem=
  if [ -z "${RV_GCC:-}" ] || [ ! -x "$RV_GCC" ]; then
    problem="RV_GCC is not set to the riscv64-elf-gcc of the pinned toolchain (the Makefile passes it)"
    verdict_line; return $?
  fi
  cfg="$ws/$crate/gnat_config/${crate}_config.ads"
  if [ ! -f "$cfg" ]; then
    problem="$cfg was not generated (the control case must run first, and succeed)"
    verdict_line; return $?
  fi
  ud="$ws/unit_$id"; rm -rf "$ud"; mkdir "$ud"
  cp "$cfg" "$ud/" && cp "$ws/$crate/src/mpfs_runtime_config.ads" "$ws/rts_support_mpfs/src/mpfs_config_checks.ads" "$ud/"
  ( cd "$ud" && "$RV_GCC" --RTS="$ws/$crate" -c -gnatc -I"$ud" mpfs_config_checks.ads ) > "$log" 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    problem="the check unit does not compile against the UNMODIFIED generated configuration (exit $rc): the unit harness is unhealthy"
  else
    for tok in $arg; do
      key=${tok%%=*}; val=${tok#*=}
      sed -E "s/^( *$key : constant [A-Za-z_]* *:= *)[^;]*;/\\1$val;/" "$ud/${crate}_config.ads" > "$ud/new" && mv "$ud/new" "$ud/${crate}_config.ads"
      grep -Eq "^ *$key : constant [A-Za-z_]* *:= *$val;" "$ud/${crate}_config.ads" || problem="could not patch $key in the generated configuration"
    done
    if [ -z "$problem" ]; then
      ( cd "$ud" && "$RV_GCC" --RTS="$ws/$crate" -c -gnatc -I"$ud" mpfs_config_checks.ads ) > "$log" 2>&1
      rc=$?
      if [ "$rc" -eq 0 ]; then
        problem="the check unit COMPILED against the patched configuration ($arg); it was required to fail with: $diag"
      else
        problem=$(diag_problem "$log" "$diag" "$rc")
      fi
    fi
  fi
  verdict_line
}

#  --- one case ----------------------------------------------------------------------
#  Prints exactly one verdict (+ detail on failure) to stdout.
run_case() {
  id=$1; kind=$2; leaf=$3; arg=$4; diag=$5; why=$6
  app=$(base_app "$leaf"); crate=$(leaf_crate "$leaf")
  log="$tmpd/$id.log"

  if [ "$kind" = unit ]; then
    run_unit_case; return $?
  fi

  dir="$ws/neg_$id"
  rm -rf "$dir"; mkdir "$dir"
  ( cd "$ws/$app" && tar -cf - alire.toml ./*.gpr src $( [ -d ld ] && echo ld ) ) | ( cd "$dir" && tar -xf - )

  if [ "$kind" = config ]; then
    for tok in $arg; do
      key=${tok%%=*}; val=${tok#*=}
      awk -v pat="^${crate}[.]${key}[ \t]*=" '$0 !~ pat' "$dir/alire.toml" > "$dir/alire.toml.new"
      printf '%s.%s = %s\n' "$crate" "$key" "$val" >> "$dir/alire.toml.new"
      mv "$dir/alire.toml.new" "$dir/alire.toml"
    done
  elif [ "$kind" = source ]; then
    fx="$PWD/tests/negative/fixtures/$arg/src"
    if [ ! -d "$fx" ]; then
      problem="fixture $fx not found"; verdict_line; return $?
    fi
    rm -rf "$dir/src"; cp -R "$fx" "$dir/src"
    gpr=$(ls "$dir"/*.gpr)
    sed 's/for Main use ("[A-Za-z_0-9]*[.]adb")/for Main use ("neg_main.adb")/' "$gpr" > "$gpr.new" && mv "$gpr.new" "$gpr"
  fi

  ( cd "$dir" && alr -n build ) > "$log" 2>&1
  rc=$?
  produced=0
  if [ -f "$dir/bin/$app" ] || [ -f "$dir/bin/neg_main" ]; then produced=1; fi

  problem=
  if [ "$kind" = control ]; then
    [ "$rc" -eq 0 ] || problem="the unmodified application did not build (exit $rc): the scratch tree is unhealthy, so no failure below it means anything"
    [ -n "$problem" ] || [ "$produced" -eq 1 ] || problem="no binary was produced by the control build"
  elif [ "$rc" -eq 0 ]; then
    problem="the build SUCCEEDED (exit 0); it was required to fail with: $diag"
  elif [ "$produced" -eq 1 ]; then
    problem="the build failed (exit $rc) but a binary exists anyway"
  else
    problem=$(diag_problem "$log" "$diag" "$rc")
  fi
  verdict_line
}

run_group() {   #  $1 = leaf: its cases in file order
  grc=0
  make_ws "$1" || { printf 'FAIL %s: rsync to the scratch tree failed\n' "$1"; return 1; }
  for id in $(awk -F'\t' -v l="$1" '$3 == l { print $1 }' "$rows"); do
    case "$want" in ''|*" $id "*) ;; *) continue ;; esac
    line=$(awk -F'\t' -v i="$id" '$1 == i { print }' "$rows")
    kind=$(printf '%s' "$line" | cut -f2); arg=$(printf '%s' "$line" | cut -f4)
    diag=$(printf '%s' "$line" | cut -f5); why=$(printf '%s' "$line" | cut -f6)
    run_case "$id" "$kind" "$1" "$arg" "$diag" "$why" || grc=1
  done
  return $grc
}

for leaf in light light_tasking embedded; do
  ( run_group "$leaf" > "$tmpd/group.$leaf" 2>&1; echo $? > "$tmpd/group.$leaf.rc" ) &
done
wait

total=0; bad=0
for leaf in light light_tasking embedded; do
  [ -s "$tmpd/group.$leaf" ] || continue
  printf '== %s\n' "$leaf"
  cat "$tmpd/group.$leaf"
  total=$((total + $(grep -c '^\(ok\|FAIL\) ' "$tmpd/group.$leaf")))
  nfail=$(grep -c '^FAIL ' "$tmpd/group.$leaf")
  bad=$((bad + nfail))
  if [ "$nfail" -eq 0 ] && [ "$(cat "$tmpd/group.$leaf.rc")" != 0 ]; then bad=$((bad + 1)); fi
done

[ "$total" -gt 0 ] || fail "no negative case ran; zero cases must not mean zero failures"
if [ "$bad" -ne 0 ]; then
  printf 'negative builds FAILED: %d of %d case(s) did not behave as required\n' "$bad" "$total" >&2
  exit 1
fi
printf 'negative builds OK: %d case(s) (controls built; every other build failed with its required diagnostic)\n' "$total"
