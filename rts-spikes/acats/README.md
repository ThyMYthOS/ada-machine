# acats/ -- RTS-PRODUCTION.md A0: map the profile boundary with ACATS

Tests, compile-only, whether `light_mpfs` ⊆ `light_tasking_mpfs` ⊆
`embedded_mpfs` really holds (RTS-GUIDE.md §2.2), using the ACATS test
suite as an independent corpus instead of hand-written checks. See
[`BOUNDARY.md`](BOUNDARY.md) for the measured result.

## Get ACATS

The corpus is **not vendored** in this repo (5,264 files; licensing permits
it — see RTS-PRODUCTION.md A0 — but there is no reason to carry the bytes).
Fetch and unpack it yourself:

```
curl -O http://www.ada-auth.org/acats-files/2.6/ACATS42.ZIP   # or wherever
mkdir -p /some/path/acats && cd /some/path/acats
unzip ACATS42.ZIP -d x
```

(The exact download location moves around; search "ACATS 4.2" if the URL
above is stale. What matters is ending up with an `x/` directory containing
`B2/`, `B3/`, ..., `C2/`, ..., `SUPPORT/`, `DOCS/` etc.)

## Run it

```
cd rts-spikes && make build          # builds light_mpfs, light_tasking_mpfs,
                                      # embedded_mpfs (among others) -- this
                                      # harness compiles against those, so
                                      # they must already exist on disk.
cd acats
python3 run_boundary.py --acats-root /some/path/acats/x
```

Override the ACATS location with `--acats-root` or the `ACATS_ROOT`
environment variable; override the toolchain with `--gcc` if it isn't under
`~/.local/share/alire/toolchains/gnat_riscv64_elf_15.1.2_*/bin/`.

Output goes to `acats/out/` (gitignored except the specific files this repo
commits as evidence for a given run -- see below):

- `manifest.tsv` -- which tests this run selected (area, filename)
- `results.tsv` -- per (test, profile): exit code, diagnostic category, detail
- `summary.txt` -- the tables `BOUNDARY.md` is built from
- `work/<profile>/` -- scratch compile directories (`.ali` output only,
  cleaned after each test); never touches the ACATS tree or the leaves

Re-running is safe: `results.tsv`/`summary.txt`/`manifest.tsv` are
overwritten, and stray `.ali` files are removed after each compile.

## What it does and does not do

`select_tests.py` picks a **pilot**, not the full 4,835-test suite: single
ACATS file, single Ada compilation unit, no `Report` dependency, no
foundation code, no `.TST` macro substitution. See `BOUNDARY.md` §1/§6 for
exactly what that excludes and why, and what closes the gap. Read
`select_tests.py`'s module docstring for the mechanical reasons each rule
exists (each one was found by an actual failure while building this, not
guessed in advance).

`run_boundary.py` compiles each selected file against each of the three
already-built leaves with `-c -gnatc -x ada` (semantic check only, no code
generation, no linking) plus the ISA switches
(`-march=rv64imafdc_zicsr_zifencei -mabi=lp64d`, matching the u54/hard-float
configuration all three leaves were actually built at) and the one global
switch every unit in the closure gets
(`-fno-tree-loop-distribute-patterns`, from `target_options.gpr`). It does
**not** pass `-gnatg`/`-nostdinc` -- those are runtime-internal switches,
not application-facing ones (see `runtime_build.gpr`'s own comment on this).

It writes nothing under `rts-spikes/` other than `acats/out/`. It never
copies ACATS source into the repo -- files are compiled in place, by
absolute path, from wherever `--acats-root` points.

## Files

| File | Purpose |
|---|---|
| `select_tests.py` | Selection policy (see its docstring for the "why" of each rule) |
| `run_boundary.py` | The harness: compile, classify, tabulate, write `out/` |
| `BOUNDARY.md` | The measured result: counts, set differences, chain-violation check, named boundary features |
| `out/` | This run's output (gitignored working files; committed evidence files, if any, are named explicitly in a commit) |
