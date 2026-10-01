#!/bin/sh
#  smoke.sh -- boot every console-producing image under QEMU and ASSERT that it
#  printed what smoke.expected says it must.   Driven by `make smoke`.
#
#  usage: sh smoke.sh        (configuration is all environment, set by the Makefile)
#
#    QEMU            qemu-system-riscv64 binary (name on PATH, or a path)
#    QEMU_MACHINE    microchip-icicle-kit
#    QEMU_MIN        oldest acceptable QEMU, "major.minor"; "0" disables the check
#    SMOKE_EXPECTED  the expectation file (default smoke.expected)
#    SMOKE_TIMEOUT   seconds a boot may take before it is killed (default 20)
#
#  WHY THIS EXISTS. `make qemu` shows output and exits 0 whatever it saw, which
#  is the flaw A2 removed from `verify`: a check that reports success while
#  testing nothing (RTS-PRODUCTION.md A3). Each rule below closes one way this
#  script could pass without the image having run:
#
#    - QEMU missing, unusable, too old, or without the machine is a FAILURE with
#      the reason, never a skip.
#    - A missing image is a FAILURE, never a skip.
#    - The strings are searched on the GUEST CONSOLE only. The serial port is
#      routed to a file (-serial file:...), so QEMU's own stderr -- including its
#      unconditional "does not generate a device tree" warning -- can never
#      satisfy an expectation, and neither can a shell echo of ours.
#    - An empty console fails (and says it was empty).
#    - An empty or unparseable expectation file, or a row with an empty field, is
#      a FAILURE: zero expectations must not mean zero failures.
#    - A boot is bounded. Success ends it early, so a passing run is fast and the
#      timeout only costs anything when something is wrong.
#
#  The run is bounded by a watchdog, not `timeout`: there is no `timeout` on
#  macOS, and alarm()-based substitutes do not work against QEMU (see the comment
#  above the `qemu` target in the Makefile).
#
#  POSIX sh only: this runs under dash (Ubuntu's /bin/sh) and macOS's bash-as-sh.

set -u

QEMU=${QEMU:-qemu-system-riscv64}
QEMU_MACHINE=${QEMU_MACHINE:-microchip-icicle-kit}
QEMU_MIN=${QEMU_MIN:-10.1}
SMOKE_EXPECTED=${SMOKE_EXPECTED:-smoke.expected}
SMOKE_TIMEOUT=${SMOKE_TIMEOUT:-20}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

case "$SMOKE_TIMEOUT" in
  ''|*[!0-9]*) fail "SMOKE_TIMEOUT must be a whole number of seconds, got '$SMOKE_TIMEOUT'" ;;
esac

tab=$(printf '\t')
tmpd=$(mktemp -d "${TMPDIR:-/tmp}/smoke.XXXXXX") || fail "mktemp -d failed"
qpid=
wdog=
cleanup() {
  [ -n "$wdog" ] && kill "$wdog" 2>/dev/null
  [ -n "$qpid" ] && kill -9 "$qpid" 2>/dev/null
  rm -rf "$tmpd"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

#  --- the expectation file ---------------------------------------------------
[ -f "$SMOKE_EXPECTED" ] || fail "expectation file '$SMOKE_EXPECTED' does not exist"

#  Normalised rows: "app<TAB>string", comments, blanks and the header dropped.
#  awk, not a shell read loop, so a string with a backslash or leading space
#  survives untouched.
rows="$tmpd/rows"
awk -F'\t' '
  /^[ \t]*#/ || /^[ \t]*$/ { next }
  !hdr { hdr = 1; if ($1 != "app") { print "BADHEADER" > "/dev/stderr"; bad = 1 } ; next }
  NF != 2 || $1 == "" || $2 == "" { printf "BADROW\t%s\n", $0; bad = 1; next }
  { print }
  END { exit bad ? 1 : 0 }
' "$SMOKE_EXPECTED" > "$rows" 2> "$tmpd/awk.err"
if [ $? -ne 0 ]; then
  cat "$tmpd/awk.err" >&2
  grep '^BADROW' "$rows" | while IFS= read -r l; do printf '  %s\n' "$l" >&2; done
  fail "$SMOKE_EXPECTED is malformed: the first non-comment line must be the 'app<TAB>string' header, and every row needs both fields, TAB-separated"
fi
[ -s "$rows" ] || fail "$SMOKE_EXPECTED contains no expectations; an empty file would make this test pass vacuously"

apps=$(awk -F'\t' '!seen[$1]++ { print $1 }' "$rows")

#  --- QEMU: loud preconditions ----------------------------------------------
command -v "$QEMU" >/dev/null 2>&1 \
  || fail "QEMU not found: '$QEMU'. Install qemu-system-riscv64 (Ubuntu 26.04: apt install qemu-system-riscv; macOS: brew install qemu), or pass QEMU=<path>. Nothing was booted."

qver=$("$QEMU" --version 2>&1 | head -n 1)
[ -n "$qver" ] || fail "'$QEMU --version' printed nothing; this is not a usable QEMU"
printf 'QEMU:    %s\n' "$qver"
printf 'host:    %s\n' "$(uname -sm)"

#  Version floor. Measured on 11.0.1/11.1.1; read from QEMU's source, the
#  `-kernel` without `-dtb` path (what `-bios none` relies on) first appears in
#  10.1.0 -- 10.0.0 and earlier only boot a kernel that comes with a device tree
#  and otherwise load HSS, so on those NOTHING of ours would run. Failing here
#  turns "mysteriously silent" into a sentence.
if [ "$QEMU_MIN" != 0 ]; then
  have=$(printf '%s\n' "$qver" | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+/) { split($i, v, "."); print v[1] " " v[2]; exit } }')
  if [ -z "$have" ]; then
    printf 'WARNING: could not read a version out of "%s"; the %s floor was not checked\n' "$qver" "$QEMU_MIN" >&2
  else
    set -- $have
    hmaj=$1; hmin=$2
    mmaj=${QEMU_MIN%%.*}; mmin=${QEMU_MIN#*.}
    if [ "$hmaj" -lt "$mmaj" ] || { [ "$hmaj" -eq "$mmaj" ] && [ "$hmin" -lt "$mmin" ]; }; then
      fail "QEMU $hmaj.$hmin is older than $QEMU_MIN. Before 10.1 the microchip-icicle-kit machine boots '-kernel' only together with '-dtb' and otherwise loads HSS, so '-bios none -kernel' starts nothing of ours (hw/riscv/microchip_pfsoc.c, v10.0.0 vs v10.1.0). Use a newer QEMU, or QEMU_MIN=0 to try anyway."
    fi
  fi
fi

machines=$("$QEMU" -M help 2>&1)
printf '%s\n' "$machines" | grep -q "^$QEMU_MACHINE[[:space:]]" \
  || fail "this QEMU has no machine '$QEMU_MACHINE' (qemu -M help | grep -i microchip found nothing)"

#  --- boot each image --------------------------------------------------------
#  Does every expected string for $1 occur in console file $2?  Prints nothing.
all_present() {
  awk -F'\t' -v a="$1" '$1 == a { print $2 }' "$rows" | {
    while IFS= read -r needle; do
      grep -qF -- "$needle" "$2" || exit 1
    done
  }
}

failures=0
passed=0
for app in $apps; do
  img="$app/bin/$app"
  printf '==> %s\n' "$app"
  if [ ! -f "$img" ]; then
    printf 'FAIL %s: image %s not found (run make build)\n' "$app" "$img" >&2
    failures=$((failures + 1)); continue
  fi

  con="$tmpd/$app.console"; err="$tmpd/$app.stderr"
  : > "$con"
  #  QEMU parses the value after "file:" as a comma-separated option list, so a
  #  comma in the path has to be doubled.
  qcon=$(printf '%s' "$con" | sed 's/,/,,/g')
  "$QEMU" -M "$QEMU_MACHINE" -m 2G -display none -monitor none \
      -serial "file:$qcon" -bios none -kernel "$img" -no-reboot \
      </dev/null >"$err" 2>&1 &
  qpid=$!
  #  Poll for success so a passing boot ends in about a second; kill on expiry.
  (
    i=0
    while [ "$i" -lt "$SMOKE_TIMEOUT" ]; do
      all_present "$app" "$con" && break
      sleep 1
      i=$((i + 1))
    done
    kill -9 "$qpid" 2>/dev/null
  ) &
  wdog=$!
  wait "$qpid" 2>/dev/null
  qstatus=$?
  kill "$wdog" 2>/dev/null
  wait "$wdog" 2>/dev/null
  qpid=; wdog=

  missing=0
  while IFS= read -r needle; do
    if grep -qF -- "$needle" "$con"; then
      printf '    ok:      "%s"\n' "$needle"
    else
      printf '    MISSING: "%s"\n' "$needle" >&2
      missing=$((missing + 1))
    fi
  done <<EOF
$(awk -F'\t' -v a="$app" '$1 == a { print $2 }' "$rows")
EOF

  if [ "$missing" -ne 0 ]; then
    failures=$((failures + 1))
    printf 'FAIL %s: %d expected string(s) absent from the guest console (QEMU exit status %s; 137 = killed by the %ss watchdog)\n' \
      "$app" "$missing" "$qstatus" "$SMOKE_TIMEOUT" >&2
    nbytes=$(wc -c < "$con" | tr -d ' ')
    if [ "$nbytes" = 0 ]; then
      echo "  guest console: EMPTY -- the image booted (or failed to) and wrote nothing to MMUART0" >&2
    else
      echo "  guest console ($nbytes bytes), first 20 lines:" >&2
      head -n 20 "$con" | while IFS= read -r l; do printf '    | %s\n' "$l" >&2; done
    fi
    if [ -s "$err" ]; then
      echo "  QEMU stderr:" >&2
      head -n 20 "$err" | while IFS= read -r l; do printf '    | %s\n' "$l" >&2; done
    fi
  else
    passed=$((passed + 1))
  fi
done

if [ "$failures" -ne 0 ]; then
  printf 'smoke FAILED: %d of %d image(s) did not print what %s expects\n' \
    "$failures" "$((failures + passed))" "$SMOKE_EXPECTED" >&2
  exit 1
fi
printf 'smoke OK: %d image(s) printed every string %s expects\n' "$passed" "$SMOKE_EXPECTED"
