# ACATS compile-only profile boundary map (RTS-PRODUCTION.md A0)

This is the measured result of running `run_boundary.py` against the three
MPFS leaves. It exists to test one claim, stated in RTS-GUIDE.md §2.2 and
never previously tested: **`light_mpfs` ⊆ `light_tasking_mpfs` ⊆
`embedded_mpfs`** — that anything that compiles under `light` compiles
unchanged under the other two.

Everything below is **measured** (a command was run, its output is quoted or
tabulated) unless a paragraph is explicitly marked **INFERRED** or
**manual probe** (see §5).

## 0. Reproduce this

```
cd rts-spikes && make build          # builds the three leaves this depends on
cd acats
python3 run_boundary.py --acats-root /path/to/unpacked/ACATS/x
```

`--acats-root` defaults to the scratchpad path this measurement was taken
from; override it (or set `ACATS_ROOT`) to point at wherever ACATS 4.2 is
unpacked. Output lands in `acats/out/`: `manifest.tsv` (which tests),
`results.tsv` (per test × profile: exit code, diagnostic category, detail),
`summary.txt` (the tables reproduced below).

This run: toolchain `riscv64-elf-gcc (GCC) 15.0.1 20250418 (prerelease)`,
ACATS 4.2, 386 tests × 3 profiles = 1,158 compiles, 61s wall time.

## 1. Selection: 386 tests, and what was excluded

`select_tests.py` scanned every `.ADA`/`.A` file under ACATS' `B2`..`BXH` and
`C2`..`CZ` directories (4,453 files) and kept only tests that are:

- a single ACATS file (`.TST` macro-substitution files excluded outright —
  gcc's extension dispatch does not even recognize them as Ada);
- self-contained: no `WITH REPORT` (ACATS's own reporting package — not
  ported here, and not a predefined unit) and no `WITH` of anything outside
  a small predefined-unit whitelist (`Ada.*`, `System*`, `Interfaces*`, and
  the Ada83 unprefixed names: `Unchecked_Conversion`/`Deallocation`,
  `Calendar`, `Direct_IO`, `Sequential_IO`, `Text_IO`, `IO_Exceptions`,
  `Low_Level_IO`, `Machine_Code`, `Standard`) — anything else is almost
  always a foundation package shared with other test files;
- not a subunit (`SEPARATE(...)`) — needs its parent compiled first;
- exactly one top-level compilation unit — GNAT refuses more than one per
  file ("file can have only one compilation unit"); ACATS packs several
  spec+body+main units into some files, which needs `gnatchop` first (not
  built here — see §6).

| Stage | Count |
|---|---:|
| `.ADA`/`.A` files under B*/C* | 4,453 |
| excluded: needs `REPORT` | 1,896 |
| excluded: other foreign `WITH` (foundation code) | 1,558 |
| excluded: subunit (`SEPARATE`) | 57 |
| excluded: multiple compilation units in one file | 30 |
| excluded: no recognized top-level unit (e.g. bare `TASK` as a "library unit", itself the illegality under test) | 3 |
| **eligible** | **909** |
| **sampled for this run** (capped at 30/B-chapter-dir, C uncapped) | **386** |

Sampling took every eligible test where the pool fit under the cap, and an
evenly-strided subset (not just the alphabetically-first N) where it didn't,
so the sample still spans each chapter's numeric range. Spread across 24
chapter-area directories:

B2:30 B3:30 B4:30 B5:30 B6:28 B7:30 B8:30 B9:30 BA:30 BB:5 BC:30 BD:30 BE:12
BXA:2 BXE:1 · C3:4 C4:2 C5:2 C7:1 C8:9 C9:1 CA:14 CC:2 CD:3

**Deliberately excluded from this pilot, and why it matters:** the 1,896
`REPORT`-dependent files are almost the entire Class C corpus (2,437 of
2,580 C-class tests use `REPORT`). That means this run's C-class sample (38
tests) is a small, atypical residual — mostly program-unit/generic-legality
checks (chapter "CA": renaming, instantiation) — not the library-usage tests
(containers, `Unbounded_Strings`, exception propagation) that would most
directly probe the `light_tasking`→`embedded` boundary. See §5 and §6.

## 2. Boundary table: compiles per profile

| Profile | Compiles clean (`-c -gnatc` exit 0) | / 386 |
|---|---:|---:|
| `light_mpfs` | 39 | 39 |
| `light_tasking_mpfs` | 39 | 39 |
| `embedded_mpfs` | 39 | 39 |

Diagnostic categories per profile (`other_error` is everything that isn't
one of the other three — genuine Ada legality errors, mostly the B-class
tests correctly being rejected for the illegality they were written to
exercise):

| Category | light | light_tasking | embedded |
|---|---:|---:|---:|
| ok | 39 | 39 | 39 |
| other_error | 301 | 304 | 306 |
| restriction | 40 | 37 | 36 |
| unit_absent | 6 | 6 | 5 |

**The 39 tests that compile are the *same 39 tests* under all three
profiles** (verified as a set equality, not just a count match — see §4).

## 3. Set differences

### 3a. `light` compiles, higher tier FAILS — chain violations

**None found**, in either direction, in this 386-test sample:

- `light` compiles ∧ `light_tasking` fails: **0**
- `light_tasking` compiles ∧ `embedded` fails: **0**
- `light` compiles ∧ `embedded` fails (transitive check): **0**

### 3b. Higher tier compiles, `light` (or `light_tasking`) FAILS — the expected boundary

- fails `light`, compiles `light_tasking`: **0** *(within this sample — see §5 for why, and for two manual probes outside the sample that do show this direction)*
- fails `light_tasking`, compiles `embedded`: **0** *(same caveat)*
- fails `light`, compiles `embedded`: **0**

At the level of "does the whole file compile clean", this sample happens to
show a flat boundary: the 39 tests that pass, pass everywhere; the 347 that
fail, fail everywhere. §5 explains why (sample composition), and shows —
via diagnostics that change even where the overall verdict doesn't — that
the boundary mechanism is very much alive underneath.

### 3c. How much this sample can actually prove

State the power plainly, because "0 violations" invites over-reading:

| | |
|---|---:|
| tests selected | 386 |
| of which **Class B — *must be rejected* to meet their own objective** | **348** |
| Class C | 38 |
| of the 39 that compile clean, Class B | 29 |

For a Class B test, "compiles clean" is not success — it is the *test*
failing. So roughly **nine tenths of this sample cannot contribute a
meaningful "compiles" signal by construction**, and the 39 that do compile
are mostly B tests whose intended illegality is presumably diagnosed at a
stage `-gnatc` does not reach.

That makes the result **real but weak**: zero chain violations is a genuine
measurement — nothing gets *stricter* going up, verified across all
386 × 3 compilations, and the monotone restriction counts (40 → 37 → 36)
and `unit_absent` counts (6 → 6 → 5) point the same way — but it is far from
the strong evidence the chain claim eventually needs.

**The strong version needs Class C**, which is where library-level
availability differences live, and Class C needs the `Report` retarget
(§6). Until then, treat this as "the harness works and found no
counter-example", not as "the chain is verified".

## 4. Chain violations: none found

**Explicit answer: no chain violations were found in this run.** The 39
tests that compile under `light_mpfs` are exactly the 39 tests that compile
under `light_tasking_mpfs`, which are exactly the 39 that compile under
`embedded_mpfs` (checked as Python set equality on the (area, filename)
key, not inferred from matching counts).

This is a narrow but real result, and its scope should not be oversold: at
386 tests concentrated in representation-clause and program-unit legality
(see §5), it does not yet exercise the parts of the runtime most likely to
disagree (containers, finalization, `Ada.Strings.Unbounded`, exception
propagation across scopes). §6 says what closes that gap.

**A methodology note, because a wrong-but-plausible result already happened
once during this work and is worth recording:** the first full run of this
harness reported 386/386 "ok" on *all three* profiles, including files
containing deliberately-illegal Ada. The cause: `gcc`'s extension dispatch
does not recognize ACATS' `.ADA`/`.A` extensions, so without `-x ada` it
silently treats the file as an unrecognized linker input ("linker input
file unused because linking not done") and **exits 0 having compiled
nothing**. Fixed by adding `-x ada` to every invocation, plus a permanent
safety net in `classify_output()` that treats that exact message as
`harness_error` regardless of exit code, so this cannot recur silently.
This is exactly the "stale object / uncompiled unit" failure mode this
project has been burned by before — recorded here because a "0 chain
violations" result is only meaningful once you've confirmed the compiler
was actually invoked.

## 5. Units and features that mark each boundary

### Absent from every profile (not a chain distinction — a target limitation)

| Unit | light | light_tasking | embedded |
|---|---:|---:|---:|
| `SEQUENTIAL_IO` (generic) | 3 | 3 | 3 |
| `ADA.DIRECT_IO` | 1 | 1 | 1 |
| `ADA.STREAMS.STREAM_IO` | — | — | 1 |

File-based I/O is absent from **all three** MPFS profiles — there is no
filesystem on this target, so this is a board/target property, not a
profile-chain distinction. Not evidence for or against the chain claim.

### The `light` → `light_tasking` boundary: tasking arrives

`light_mpfs` rejects tasking outright:

```
error: violation of restriction "NO_TASKING" at system.ads:52
error: construct not allowed in configurable run-time mode
```

35 of the 40 `light` restriction violations in this sample are
`NO_TASKING`. Once tasking is available (`light_tasking_mpfs`,
`embedded_mpfs`), the *same* task-hierarchy/Ravenscar-style restrictions
apply to both — this sample never distinguishes them:

```
error: violation of restriction "NO_TASK_HIERARCHY"
error: violation of restriction "MAX_TASK_ENTRIES = 0"
error: violation of restriction "No_Local_Protected_Objects" (profile Jorvik)
```

**Interesting secondary finding:** three tests (`B33201C.ADA`,
`B74101A.ADA`, `B83008A.ADA` — chapters on types, packages, visibility, not
tasking) declare a task type merely as a vehicle for the actual construct
under test. Under `light` they fail immediately on `NO_TASKING`; under
`light_tasking`/`embedded`, tasking is legal, so the compiler proceeds
*past* that and hits the test's real, intended, non-tasking illegality
(e.g. `"D1" conflicts with declaration at line 42`). Same final verdict
(rejected) at every tier, but the *diagnostic* changes exactly where the
profile chain says it should — this is the mechanism working, even though
the test's summary bucket (`restriction` vs `other_error`) makes it invisible
in the headline count.

### The `light_tasking` → `embedded` boundary: two features, from a thin sample

- **`Storage_Size` aspect on access types.** `BD2B02A.ADA` hits
  `"configurable run-time mode"` under both `light` and `light_tasking`, but
  under `embedded` that restriction is gone and the compiler proceeds to the
  test's real (unrelated) illegality — `aspect "STORAGE_SIZE" for
  "ACCESS_TYPE" previously given at line 36`. `embedded` permits an access
  type's `Storage_Size` aspect; `light_tasking` does not.
- **`Ada.Streams`.** `BXE2008.A` (an Annex E / Remote_Types test) gets
  `"Ada.Streams" is not a predefined library unit` under `light` and
  `light_tasking`, but compiles past that point under `embedded` — although
  it still fails there, on a genuine Remote_Types legality error unrelated
  to Streams. `Ada.Streams` itself is present starting at `embedded`; its
  child `Ada.Streams.Stream_IO` remains absent everywhere (no filesystem,
  per above).

Both are real, but neither flips a whole test to "compiles clean" — this
sample is too thin on library-usage tests to produce a full pass/fail
crossing at this tier. See the manual probes below for confirmation that
such crossings exist; §6 explains what it takes to reach them from ACATS
itself.

### Manual probes (NOT ACATS, NOT part of the 386-test measurement)

Run directly against the leaves while developing this harness, kept here
because they show the light_tasking→embedded boundary concretely and
because the mechanism producing them is identical to `run_boundary.py`'s:

```
$ riscv64-elf-gcc -c -gnatc -gnat2012 -march=rv64imafdc_zicsr_zifencei \
    -mabi=lp64d -fno-tree-loop-distribute-patterns --RTS=<leaf> t5.adb
```
where `t5.adb` is `with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
... S : Unbounded_String := To_Unbounded_String ("hi"); ...`:

| Profile | Result |
|---|---|
| `light_mpfs` | `error: "Ada.Strings.Unbounded" is not a predefined library unit` |
| `light_tasking_mpfs` | `error: "Ada.Strings.Unbounded" is not a predefined library unit` |
| `embedded_mpfs` | compiles clean |

These are hand-written, not from the corpus, and are called out separately
per the instruction to keep MEASURED (the 386-test run) and supplementary
evidence distinct. They are consistent with, and reinforce, §5's ACATS-
derived findings — but they are not ACATS results and are not counted in
any table above.

## 6. Scaling to the full suite: the next mechanical blockers

In priority order (each unlocks a specific, named gap above):

1. **`gnatchop` integration** (30 excluded files, plus needed for any
   multi-unit foundation-code test in general). Mechanical: split each
   multi-unit file, compile the parts in file order, keep the resulting
   `.ali`s visible to later parts in the same test. This is the most
   direct way to grow coverage without changing what's measured.
2. **Foundation code** (1,558 excluded files here, most of the corpus).
   Needs `Source_Dirs`-style resolution: a test's `WITH` of an `F*` unit (or
   another test acting as a foundation) has to resolve to a real file
   compiled first. Foundation files live in `SUPPORT/` or alongside the
   test; both would need indexing by unit name.
3. **`Report` retarget** (1,896 excluded files — most of Class C). ACATS
   User's Guide §5.2.4 sanctions exactly this: one context clause, 18 I/O
   call sites, ~591 lines, targeting a `light`-class `Text_IO`-alike. This
   is the highest-value next step for the *specific* question this
   exercise cares about — §5 shows the current sample is thin on
   library-usage tests precisely because they are almost all `Report`-gated
   Class C tests, and those are exactly the ones most likely to show
   (or refute) further `light_tasking`↔`embedded` boundary claims (and, per
   RTS-PRODUCTION.md A4, doubles as the basis for an executable test suite
   later).
4. **`.TST` macro substitution** (63 files total in ACATS, a much smaller
   gap than the above) — token files like `$DEFAULT_LENGTH` need
   preprocessing before they are legal Ada at all.

None of the above changes what this pilot already answered: the compile-only
mechanism works end to end, needs nothing beyond a compiler, and the chain
claim survives 386 real, independently-authored tests with zero violations.
