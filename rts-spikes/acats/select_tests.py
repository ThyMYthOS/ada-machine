#!/usr/bin/env python3
"""select_tests.py -- pick a compile-only ACATS pilot for RTS-PRODUCTION.md A0.

WHY THIS EXISTS.  ACATS 4.2 has 4,835 tests.  Most need machinery this pilot
deliberately does not build yet: ".TST" macro substitution (token files such
as $DEFAULT_LENGTH), a retargeted Report/ImpDef, and multi-file foundation
code shared between tests.  This script selects the subset that needs NONE
of that -- single ACATS *file*, single Ada compilation unit, no dependency on
another test file -- so `run_boundary.py` can feed each selected file to the
compiler directly and get a signal that is about the RUNTIME PROFILE, not
about a harness gap.

SELECTION RULES, and why each exists:

  1. Extension is .ADA or .A only.  ACATS ships some tests as ".TST" (needing
     token substitution before they are even legal Ada) and some supporting
     material as .AM/.DEP/etc.  gcc's own extension dispatch already proves
     the point: handed a .TST file it says "linker input file unused because
     linking not done" -- it never even recognises the file as Ada source.

  2. No "WITH REPORT" (case-insensitive).  REPORT is ACATS's own reporting
     package (Ada_Auth 5.2.4) -- not a predefined library unit, and not
     ported here.  A test that needs it would fail with "REPORT is not a
     predefined library unit" on EVERY profile, which looks exactly like a
     unit-absence result but means nothing about the runtime boundary.

  3. No WITH clause naming anything outside a small whitelist of predefined
     units (Ada.*, System*, Interfaces*, and the Ada83 unprefixed names:
     Unchecked_Conversion/Deallocation, Calendar, Direct_IO, IO_Exceptions,
     Low_Level_IO, Machine_Code, Sequential_IO, Text_IO, Standard).  Anything
     else is almost always a foundation package shared with other test
     files (SUPPORT/, or an F*.ADA/.A file) -- exactly the "needs other test
     files" case this pilot excludes.

  4. No SEPARATE(...) unit.  A subunit is not compilable on its own; it needs
     its parent compiled first.  ACATS packs several lettered subtests'
     subunits into one file (see C83022G1.ADA, six SEPARATE(C83022G0M)
     bodies) -- these are foundation-shaped even though they carry no WITH.

  5. Exactly one top-level compilation unit.  GNAT (unlike some other Ada
     implementations ACATS was written against) refuses more than one
     compilation unit per file: "end of file expected, file can have only
     one compilation unit".  ACATS' own convention is to indent top-level
     unit keywords (PROCEDURE/PACKAGE/FUNCTION/GENERIC/PRIVATE/SEPARATE) at
     0-1 leading spaces and nested constructs at >=4; a file with more than
     one such keyword (after folding GENERIC/PRIVATE into the unit they
     modify) needs `gnatchop` first.  This pilot does not build gnatchop
     integration (see BOUNDARY.md, "next mechanical blocker") -- it excludes
     these and reports the count instead of silently mis-measuring them.

None of this touches ACATS content: it only reads files to classify them.
The corpus itself is never copied into the repo (see README.md).

USAGE:
    python3 select_tests.py [--acats-root PATH] [--cap N] [--out FILE]

Emits a TSV manifest (area, filename, path, reason) to stdout or --out.
"""
import argparse
import collections
import os
import re
import sys

DEFAULT_ACATS_ROOT = (
    "/private/tmp/claude-502/-Users-manuel-stahl-Repos-ADA-Ada-Machine--"
    "claude-worktrees-uart-logging-facility-680829/822e538d-b569-4561-a995-"
    "8a69c58dd4b3/scratchpad/acats/x"
)

WHITELIST_PREFIXES = ("ADA", "SYSTEM", "INTERFACES")
WHITELIST_EXACT = {
    "UNCHECKED_CONVERSION", "UNCHECKED_DEALLOCATION",
    "CALENDAR", "DIRECT_IO", "IO_EXCEPTIONS", "LOW_LEVEL_IO",
    "MACHINE_CODE", "SEQUENTIAL_IO", "TEXT_IO", "STANDARD",
}
WITH_RE = re.compile(r'\bWITH\b([^;]+);', re.IGNORECASE)
UNIT_KW_RE = re.compile(
    r'^(GENERIC|PRIVATE|PROCEDURE|PACKAGE|FUNCTION|SEPARATE)\b', re.IGNORECASE)
MODIFIERS = {"GENERIC", "PRIVATE"}
UNIT_KW = {"PROCEDURE", "PACKAGE", "FUNCTION"}
MAX_TOP_INDENT = 1  # ACATS convention: top-level unit keywords at col 0-1

# Class B and C chapter subdirectories, per the ACATS 4.2 delivery layout
# (x/B2..x/BXH, x/C2..x/CZ).  A/D/E/L are execution-class or capacity/link
# tests, out of scope for a compile-only pilot (RTS-PRODUCTION.md A0).
AREA_RE = re.compile(r'^(B|C)')


def with_names(text):
    names = set()
    for m in WITH_RE.finditer(text):
        for part in m.group(1).split(','):
            part = part.strip()
            if part:
                names.add((part.split()[0] if part.split() else part).upper())
    return names


def unit_tokens(text):
    toks = []
    for ln in text.splitlines():
        stripped = ln.lstrip(' ')
        indent = len(ln) - len(stripped)
        if indent > MAX_TOP_INDENT:
            continue
        m = UNIT_KW_RE.match(stripped)
        if m:
            toks.append(m.group(1).upper())
    return toks


def merged_unit_count(toks):
    has_separate = "SEPARATE" in toks
    merged = []
    for t in toks:
        if t in MODIFIERS:
            continue  # GENERIC/PRIVATE attach to the unit keyword that follows
        if t == "SEPARATE":
            merged.append("SEPARATE")
            continue
        if t in UNIT_KW:
            merged.append(t)
    return len(merged), has_separate


def classify(path):
    """Return (verdict, detail) where verdict is 'select' or an exclude reason."""
    text = open(path, encoding='latin-1').read()
    names = with_names(text)
    if any(n == "REPORT" for n in names):
        return "needs_report", None
    foreign = [n for n in names if n.split('.')[0] not in WHITELIST_EXACT
               and n.split('.')[0] not in WHITELIST_PREFIXES]
    if foreign:
        return "foreign_with", ",".join(sorted(foreign))
    toks = unit_tokens(text)
    n_units, has_separate = merged_unit_count(toks)
    if has_separate:
        return "subunit", None
    if n_units == 0:
        return "no_recognized_unit", None
    if n_units > 1:
        return "multi_unit", str(n_units)
    return "select", None


def strided_sample(items, cap):
    """Deterministically pick <=cap items spread evenly across a sorted list,
    instead of just the alphabetically-first N -- so the sample still spans
    the numeric range of test IDs (early vs. late Ada features) in a chapter
    with more candidates than the cap."""
    n = len(items)
    if n <= cap:
        return list(items)
    step = n / cap
    picked = []
    seen = set()
    for i in range(cap):
        idx = int(i * step)
        while idx in seen and idx < n - 1:
            idx += 1
        seen.add(idx)
        picked.append(items[idx])
    return picked


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--acats-root", default=os.environ.get("ACATS_ROOT", DEFAULT_ACATS_ROOT),
                     help="path to the unpacked ACATS 'x' tree (default: %(default)s, "
                          "overridable via --acats-root or ACATS_ROOT)")
    ap.add_argument("--cap", type=int, default=30,
                     help="max tests per B-class chapter directory (default: %(default)s); "
                          "C-class directories are never capped (they are already few)")
    ap.add_argument("--out", default="-", help="output TSV path, '-' for stdout")
    ap.add_argument("--stats", action="store_true",
                     help="print exclusion counts to stderr")
    args = ap.parse_args()

    root = args.acats_root
    if not os.path.isdir(root):
        print(f"error: ACATS root not found: {root}", file=sys.stderr)
        print("       pass --acats-root or set ACATS_ROOT", file=sys.stderr)
        return 1

    dirs = sorted(d for d in os.listdir(root)
                   if AREA_RE.match(d) and os.path.isdir(os.path.join(root, d)))

    reasons = collections.Counter()
    total = 0
    by_area = collections.defaultdict(list)
    for d in dirs:
        dpath = os.path.join(root, d)
        for fn in sorted(os.listdir(dpath)):
            stem, ext = os.path.splitext(fn)
            if ext.upper() not in (".ADA", ".A"):
                continue
            total += 1
            verdict, detail = classify(os.path.join(dpath, fn))
            reasons[verdict] += 1
            if verdict == "select":
                by_area[d].append(fn)

    rows = []
    for d in dirs:
        files = by_area.get(d, [])
        if not files:
            continue
        cap = args.cap if d.startswith("B") else len(files)
        for fn in strided_sample(files, cap):
            rows.append((d, fn))

    # NB: the manifest stores area+filename only, not the absolute ACATS
    # path -- the path is scratch-location-specific (this session's
    # /private/tmp/... sandbox) and would not resolve on another machine.
    # run_boundary.py re-resolves path = <acats-root>/<area>/<filename>.
    out = sys.stdout if args.out == "-" else open(args.out, "w")
    out.write("area\tfilename\n")
    for area, fn in rows:
        out.write(f"{area}\t{fn}\n")
    if out is not sys.stdout:
        out.close()

    if args.stats:
        print(f"# ACATS root: {root}", file=sys.stderr)
        print(f"# total .ADA/.A files scanned under B*/C*: {total}", file=sys.stderr)
        for k, v in reasons.most_common():
            print(f"# excluded[{k}]: {v}", file=sys.stderr)
        print(f"# eligible (verdict=select): {reasons['select']}", file=sys.stderr)
        print(f"# sampled (this run, cap={args.cap} per B-dir, C uncapped): {len(rows)}",
              file=sys.stderr)
        per_area = collections.Counter(r[0] for r in rows)
        for d in dirs:
            if per_area[d]:
                print(f"#   {d}: {per_area[d]}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
