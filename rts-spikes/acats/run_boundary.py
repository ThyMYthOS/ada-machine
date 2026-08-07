#!/usr/bin/env python3
"""run_boundary.py -- RTS-PRODUCTION.md A0: measure the MPFS profile chain
with ACATS, compile-only.

WHAT THIS MEASURES.  RTS-GUIDE.md 2.2 claims light_mpfs (subset) ⊆
light_tasking_mpfs (subset) ⊆ embedded_mpfs -- i.e. anything that compiles
under `light` also compiles, unchanged, under the other two.  That claim has
never been tested.  This script compiles the same ACATS source files against
all three leaves with `-c -gnatc` (semantic check, no code generation -- no
QEMU, no linking, no Report/ImpDef port needed) and records, per
(test x profile): exit status and a diagnostic bucket.

THE ONE THING THAT MATTERS: a test that compiles under `light` and FAILS
under `light_tasking` or `embedded` is a chain violation -- a layering bug in
OUR design, because the claim says that cannot happen.  A test that fails
under `light` and succeeds higher up is the boundary working as intended
(some unit or construct genuinely is not in the smaller profile).  This
script computes both directions and never conflates them; BOUNDARY.md states
which is which.

USAGE:
    python3 run_boundary.py [options]

    Typical run, from a clean checkout, with ACATS unpacked to /some/path/x:
        python3 run_boundary.py --acats-root /some/path/x

    Defaults assume the layout described in README.md (ACATS_ROOT env var,
    or the exploration scratchpad used to build this harness).

WHAT IT DOES NOT TOUCH: nothing under rts-spikes/ other than reading the
three leaf directories (light_mpfs, light_tasking_mpfs, embedded_mpfs) that
already exist from `make build`.  It writes only under --out-dir (default:
this script's own out/ subdirectory).  It never copies ACATS sources into
the repo -- test files are compiled in place, by absolute path, with the
compiler's working directory set to a scratch dir so `.ali` output does not
land in the ACATS tree either.
"""
import argparse
import collections
import glob
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import select_tests  # noqa: E402  (local module, see select_tests.py)

HERE = os.path.dirname(os.path.abspath(__file__))
RTS_SPIKES_ROOT = os.path.dirname(HERE)  # acats/ is directly under rts-spikes/

# The three MPFS leaves this pilot maps, in chain order (RTS-GUIDE.md 2.2).
PROFILES = ["light_mpfs", "light_tasking_mpfs", "embedded_mpfs"]

# ISA switches, measured from light_mpfs/target_options.gpr's Global_Ada_Switches
# for Hart_Class => "u54" (Harts_Mask = "2"): hard-float, lp64d.  All three
# leaves' already-built adalib directories (from `make build`) are tagged with
# this same u54/hard-float configuration --
#   light_mpfs:         adalib-u54-2-...-lim-
#   light_tasking_mpfs: adalib-u54-2-...-lim-
#   embedded_mpfs:      adalib-u54-2-...-ddr_by_bootloader-
# so this is the one ISA config all three leaves were actually exercised at,
# and the one this harness uses for all three.  -gnatc does not generate code,
# so ISA choice cannot change unit-availability or restriction results here;
# it matters only if a test's legality depends on Float/Address representation.
ISA_SWITCHES = ["-march=rv64imafdc_zicsr_zifencei", "-mabi=lp64d"]

# Global_Ada_Switches in target_options.gpr = ISA_Switches & this one flag --
# it is what reaches every unit in the closure (Builder.Global_Compilation_
# Switches), so it is what an application (or, here, an ACATS test standing
# in for one) is actually compiled with.  -gnatg/-nostdinc are runtime-INTERNAL
# (RTS_ADAFLAGS in runtime_build.gpr) and are deliberately NOT used here.
GLOBAL_ADA_SWITCHES = ["-fno-tree-loop-distribute-patterns"]

# ACATS 4.2 is Ada 2012 (RTS-PRODUCTION.md A0); pin the language version so a
# newer compiler default cannot introduce extra legality noise unrelated to
# the runtime profile boundary being measured.
LANG_SWITCH = ["-gnat2012"]

COMPILE_TIMEOUT_S = 20

UNIT_ABSENT_RE = re.compile(r'"([^"]+)" is not a predefined library unit')
RESTRICTION_RE = re.compile(r'violation of (?:implicit )?restriction "([^"]+)"')
PROFILE_RE = re.compile(r'from profile "([^"]+)"')
CONFIG_RTM_RE = re.compile(r'not allowed in configurable run-time mode')


def find_toolchain_gcc(explicit):
    if explicit:
        return explicit
    pattern = os.path.expanduser(
        "~/.local/share/alire/toolchains/gnat_riscv64_elf_15.1.2_*/bin/riscv64-elf-gcc")
    matches = sorted(glob.glob(pattern))
    if not matches:
        return None
    return matches[0]


LINKER_INPUT_UNUSED_RE = re.compile(r'linker input file unused')


def classify_output(exit_code, output):
    """Return (category, detail) for one compile attempt's result."""
    # Safety net for the -x ada bug this harness hit once already (see
    # compile_one): if gcc ever again treats the file as an unrecognised
    # linker input, it exits 0 having compiled NOTHING.  Never let that
    # silently count as "ok".
    if LINKER_INPUT_UNUSED_RE.search(output):
        return "harness_error", "gcc did not recognize file as Ada source (no -x ada?)"
    if exit_code == 0:
        return "ok", ""
    m = UNIT_ABSENT_RE.search(output)
    if m:
        return "unit_absent", m.group(1)
    m = RESTRICTION_RE.search(output)
    if m:
        detail = m.group(1)
        m2 = PROFILE_RE.search(output)
        if m2:
            detail += f" (profile {m2.group(1)})"
        return "restriction", detail
    if CONFIG_RTM_RE.search(output):
        return "restriction", "configurable run-time mode"
    # Prefer the first actual "error:" line over a "warning:" line (GNAT
    # emits the file/unit-name-mismatch warning ACATS' naming convention
    # always triggers before any real diagnostic, so line 0 is almost never
    # the interesting one).
    lines = [ln for ln in output.strip().splitlines() if ln.strip()]
    error_lines = [ln for ln in lines if re.search(r'\berror:', ln)]
    detail_line = (error_lines or lines or [""])[0]
    return "other_error", detail_line[:160]


def compile_one(gcc, rts_dir, src_path, workdir):
    # -x ada is NOT optional: gcc's extension dispatch recognises .adb/.ads
    # but NOT ACATS' .ADA/.A extensions.  Without it, gcc treats the file as
    # an unrecognised linker input, prints "linker input file unused because
    # linking not done", and EXITS 0 -- a silent no-op that looks exactly
    # like a clean compile.  (Measured: the first full run of this harness,
    # before this flag was added, reported 386/386 "ok" on all three
    # profiles, including files containing deliberately illegal Ada that
    # must be rejected -- see BOUNDARY.md's methodology note.)
    cmd = ([gcc, "-c", "-gnatc", "-x", "ada"] + LANG_SWITCH + ISA_SWITCHES + GLOBAL_ADA_SWITCHES
           + [f"--RTS={rts_dir}", src_path])
    try:
        proc = subprocess.run(cmd, cwd=workdir, capture_output=True, text=True,
                               timeout=COMPILE_TIMEOUT_S)
        return proc.returncode, (proc.stdout + proc.stderr)
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or "") + (e.stderr or "")
        return None, out  # None exit code signals timeout to the caller


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--acats-root", default=os.environ.get("ACATS_ROOT", select_tests.DEFAULT_ACATS_ROOT),
                     help="path to the unpacked ACATS 'x' tree (default: %(default)s, "
                          "overridable via --acats-root or ACATS_ROOT)")
    ap.add_argument("--manifest", default=None,
                     help="pre-generated manifest TSV (area, filename) from select_tests.py; "
                          "if omitted, selection runs inline with --cap")
    ap.add_argument("--cap", type=int, default=30,
                     help="passed to select_tests.py when --manifest is not given (default: %(default)s)")
    ap.add_argument("--gcc", default=None,
                     help="path to riscv64-elf-gcc (default: newest gnat_riscv64_elf_15.1.2_* toolchain found)")
    ap.add_argument("--rts-spikes-root", default=RTS_SPIKES_ROOT,
                     help="path to rts-spikes/ containing the three leaf dirs (default: %(default)s)")
    ap.add_argument("--out-dir", default=os.path.join(HERE, "out"),
                     help="where results.tsv/summary.txt/work/ are written (default: %(default)s)")
    ap.add_argument("--limit", type=int, default=None,
                     help="only process the first N manifest rows (debugging)")
    args = ap.parse_args()

    if not os.path.isdir(args.acats_root):
        print(f"error: ACATS root not found: {args.acats_root}", file=sys.stderr)
        print("       pass --acats-root or set ACATS_ROOT", file=sys.stderr)
        return 1

    gcc = find_toolchain_gcc(args.gcc)
    if not gcc or not os.path.exists(gcc):
        print("error: riscv64-elf-gcc not found (gnat_riscv64_elf_15.1.2 toolchain "
              "not installed under ~/.local/share/alire/toolchains/). "
              "Pass --gcc explicitly.", file=sys.stderr)
        return 1

    leaf_dirs = {}
    for profile in PROFILES:
        d = os.path.join(args.rts_spikes_root, profile)
        if not os.path.isdir(d):
            print(f"error: leaf directory not found: {d}", file=sys.stderr)
            print("       run `cd rts-spikes && make build` first, or pass --rts-spikes-root",
                  file=sys.stderr)
            return 1
        leaf_dirs[profile] = os.path.abspath(d)

    # Selection: either read a saved manifest, or run selection inline.
    manifest_rows = []
    if args.manifest:
        with open(args.manifest) as f:
            next(f)  # header
            for line in f:
                area, fn = line.rstrip("\n").split("\t")
                manifest_rows.append((area, fn))
    else:
        dirs = sorted(d for d in os.listdir(args.acats_root)
                       if select_tests.AREA_RE.match(d) and os.path.isdir(os.path.join(args.acats_root, d)))
        by_area = collections.defaultdict(list)
        for d in dirs:
            dpath = os.path.join(args.acats_root, d)
            for fn in sorted(os.listdir(dpath)):
                stem, ext = os.path.splitext(fn)
                if ext.upper() not in (".ADA", ".A"):
                    continue
                verdict, _ = select_tests.classify(os.path.join(dpath, fn))
                if verdict == "select":
                    by_area[d].append(fn)
        for d in dirs:
            files = by_area.get(d, [])
            if not files:
                continue
            cap = args.cap if d.startswith("B") else len(files)
            for fn in select_tests.strided_sample(files, cap):
                manifest_rows.append((d, fn))

    if args.limit:
        manifest_rows = manifest_rows[:args.limit]

    if not manifest_rows:
        print("error: no tests selected -- nothing to measure", file=sys.stderr)
        return 1

    os.makedirs(args.out_dir, exist_ok=True)
    work_root = os.path.join(args.out_dir, "work")
    for profile in PROFILES:
        os.makedirs(os.path.join(work_root, profile), exist_ok=True)

    # Persist the manifest actually used, for reproducibility of THIS run's
    # evidence (area+filename only -- see select_tests.py for why not the
    # absolute path).
    manifest_path = os.path.join(args.out_dir, "manifest.tsv")
    with open(manifest_path, "w") as f:
        f.write("area\tfilename\n")
        for area, fn in manifest_rows:
            f.write(f"{area}\t{fn}\n")

    results_path = os.path.join(args.out_dir, "results.tsv")
    results_f = open(results_path, "w")
    results_f.write("area\tfilename\tprofile\texit_code\tcategory\tdetail\n")

    t0 = time.time()
    per_test_status = collections.defaultdict(dict)  # (area,fn) -> {profile: category}
    category_counts = collections.defaultdict(collections.Counter)  # profile -> Counter(category)
    n_missing_source = 0

    for i, (area, fn) in enumerate(manifest_rows, 1):
        src_path = os.path.join(args.acats_root, area, fn)
        if not os.path.isfile(src_path):
            n_missing_source += 1
            print(f"warning: source not found, skipping: {src_path}", file=sys.stderr)
            continue
        for profile in PROFILES:
            workdir = os.path.join(work_root, profile)
            exit_code, output = compile_one(gcc, leaf_dirs[profile], src_path, workdir)
            if exit_code is None:
                category, detail = "timeout", f">{COMPILE_TIMEOUT_S}s"
            else:
                category, detail = classify_output(exit_code, output)
            per_test_status[(area, fn)][profile] = category
            category_counts[profile][category] += 1
            results_f.write(f"{area}\t{fn}\t{profile}\t{exit_code}\t{category}\t{detail}\n")
            # Clean up any .ali this compile produced -- keep the work dir
            # from accumulating 386 x 3 stale .ali files across re-runs.
            for stray in glob.glob(os.path.join(workdir, "*.ali")):
                os.remove(stray)
        if i % 50 == 0 or i == len(manifest_rows):
            print(f"  ... {i}/{len(manifest_rows)} tests x 3 profiles "
                  f"({time.time() - t0:.0f}s elapsed)", file=sys.stderr)

    results_f.close()

    # ---- Boundary computation -----------------------------------------
    compiles = {p: set() for p in PROFILES}
    for key, by_profile in per_test_status.items():
        for p in PROFILES:
            if by_profile.get(p) == "ok":
                compiles[p].add(key)

    light, lt, emb = compiles["light_mpfs"], compiles["light_tasking_mpfs"], compiles["embedded_mpfs"]

    # Chain violations: compiles at a lower tier, FAILS at a higher one.
    # This is the assertion RTS-GUIDE.md 2.2 makes and A0 exists to test.
    violation_light_to_lt = light - lt
    violation_lt_to_emb = lt - emb
    violation_light_to_emb = light - emb

    # Expected boundary: fails at the lower tier, compiles at the higher one.
    boundary_light_to_lt = lt - light
    boundary_lt_to_emb = emb - lt
    boundary_light_to_emb = emb - light

    summary_path = os.path.join(args.out_dir, "summary.txt")
    with open(summary_path, "w") as s:
        def w(line=""):
            s.write(line + "\n")

        w("RTS-PRODUCTION.md A0 -- ACATS compile-only profile boundary map")
        w("=" * 70)
        w(f"ACATS root:      {args.acats_root}")
        w(f"Toolchain gcc:   {gcc}")
        w(f"rts-spikes root: {args.rts_spikes_root}")
        w(f"Tests selected:  {len(manifest_rows)} (see manifest.tsv)")
        if n_missing_source:
            w(f"WARNING: {n_missing_source} manifest entries had no source file on disk")
        w()
        w("Compiles cleanly (-c -gnatc exit 0), per profile:")
        for p in PROFILES:
            w(f"  {p:20s} {len(compiles[p]):4d} / {len(manifest_rows)}")
        w()
        w("Diagnostic categories, per profile:")
        for p in PROFILES:
            w(f"  {p}:")
            for cat, n in category_counts[p].most_common():
                w(f"    {cat:15s} {n}")
        w()
        w("-" * 70)
        w("CHAIN VIOLATIONS (compiles at lower tier, FAILS above -- our bug if any)")
        w("-" * 70)
        w(f"  light compiles, light_tasking fails: {len(violation_light_to_lt)}")
        for area, fn in sorted(violation_light_to_lt):
            w(f"    {area}/{fn}  light_tasking={per_test_status[(area, fn)].get('light_tasking_mpfs')}")
        w(f"  light_tasking compiles, embedded fails: {len(violation_lt_to_emb)}")
        for area, fn in sorted(violation_lt_to_emb):
            w(f"    {area}/{fn}  embedded={per_test_status[(area, fn)].get('embedded_mpfs')}")
        w(f"  light compiles, embedded fails (transitive check): {len(violation_light_to_emb)}")
        for area, fn in sorted(violation_light_to_emb):
            w(f"    {area}/{fn}  embedded={per_test_status[(area, fn)].get('embedded_mpfs')}")
        w()
        w("-" * 70)
        w("EXPECTED BOUNDARY (fails at lower tier, compiles above -- the boundary itself)")
        w("-" * 70)
        w(f"  fails light, compiles light_tasking: {len(boundary_light_to_lt)}")
        w(f"  fails light_tasking, compiles embedded: {len(boundary_lt_to_emb)}")
        w(f"  fails light, compiles embedded: {len(boundary_light_to_emb)}")
    print(f"wrote {results_path}", file=sys.stderr)
    print(f"wrote {summary_path}", file=sys.stderr)
    print(f"wrote {manifest_path}", file=sys.stderr)

    # Second pass over results.tsv to tally unit_absent/restriction detail
    # per profile (kept as a separate pass so the file is the single source
    # of truth for both this summary and any later re-analysis).
    unit_tally = {p: collections.Counter() for p in PROFILES}
    restriction_tally = {p: collections.Counter() for p in PROFILES}
    with open(results_path) as f:
        next(f)
        for line in f:
            area, fn, profile, exit_code, category, detail = line.rstrip("\n").split("\t", 5)
            if category == "unit_absent":
                unit_tally[profile][detail] += 1
            elif category == "restriction":
                restriction_tally[profile][detail] += 1
    with open(summary_path, "a") as s:
        def w(line=""):
            s.write(line + "\n")
        w()
        w("-" * 70)
        w("'<unit> is not a predefined library unit' -- by profile, most common first")
        w("-" * 70)
        for p in PROFILES:
            w(f"  {p}:")
            for unit, n in unit_tally[p].most_common(20):
                w(f"    {n:4d}  {unit}")
        w()
        w("-" * 70)
        w("Restriction violations -- by profile, most common first")
        w("-" * 70)
        for p in PROFILES:
            w(f"  {p}:")
            for restr, n in restriction_tally[p].most_common(20):
                w(f"    {n:4d}  {restr}")

    print(f"elapsed: {time.time() - t0:.0f}s", file=sys.stderr)
    print(f"light={len(light)} light_tasking={len(lt)} embedded={len(emb)} "
          f"chain_violations={len(violation_light_to_lt) + len(violation_lt_to_emb)}",
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
