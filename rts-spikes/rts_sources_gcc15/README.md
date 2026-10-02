# rts_sources_gcc15

Tier 1 of the rts-spikes crate hierarchy (see [../CONTRACT.md](../CONTRACT.md) §2
and [../../RTS.md](../../RTS.md) §6–§7): the `libgnat`/`libgnarl` source
snapshot shared by every leaf runtime in this spike.

## What this crate is

`rts_sources_gcc15` holds the ~1049 units (963 `libgnat` + 86 `libgnarl`,
per `libgnat.lst`/`libgnarl.lst`) that make up GNAT's run-time library
sources, unmodified. It is **source-only and is never built by Alire**:
these units require `-gnatg -nostdinc`, the cross compiler, and no
runtime to compile against — a bootstrap cycle that only a leaf's
`runtime_build.gpr`/`ravenscar_build.gpr` (which supply exactly those
switches) can resolve. `rts_sources_gcc15.gpr` is therefore an `abstract`
project with `Source_Dirs => ()`: it contributes no compilation of its
own, only two path variables — `Gnat_Dir` and `Gnarl_Dir` — that a leaf's
library project reads via `Project'Project_Dir` and lists directly in its
own `Source_Dirs` (RTS.md §6, "Assembling the directory").

Every leaf in this spike (`light_mpfs`, `light_tasking_mpfs`,
`embedded_mpfs`) depends on this one crate for its shared-source layer
rather than vendoring its own copy, which is the whole point of pulling
tier 1 out as its own crate (RTS.md §7: "Tier 1 pays clearly").

## Populated, not vendored

**The `libgnat/` and `libgnarl/` directories are not committed.** Tier 1
alone is ~6 MB of FSF/AdaCore code across 1049 files, and vendoring it
into every crate that needed it (as a published crate would) is exactly
the duplication this spike's tier-1 boundary exists to remove
(CONTRACT.md §1; RTS.md §7). Instead:

- `libgnat.lst` and `libgnarl.lst` — committed, one relative filename per
  line — are the reviewable manifest of which units belong to this
  snapshot. They play the role RTS.md §2.1 gives `Source_List_File`:
  membership is a listed fact, not something inferred from whatever
  happens to be sitting in a directory.
- `../populate.sh` copies each named file out of the installed
  `gnat_riscv64_elf` toolchain (falling back across the `embedded` /
  `light-tasking` / `light` PolarFire SoC runtimes it ships, in that
  order) into `libgnat/` and `libgnarl/` respectively. `.gitignore`
  excludes both directories.
- Consequently **`make populate` is a prerequisite for any build** — a
  fresh clone of this repository does not build until it has run. This
  is a spike-only shortcut a published crate would not take (CONTRACT.md
  §1 says so explicitly); it exists here to avoid re-vendoring the same
  ~1049 files into `rts_sources_gcc15` when the toolchain installation
  already has an authoritative, licence-clean copy on disk.

Do not edit `libgnat.lst` or `libgnarl.lst` by hand outside of the
tooling that generated them, and do not commit anything under
`libgnat/` or `libgnarl/`.

## Version

This snapshot corresponds to the **`gnat_riscv64_elf` / `gnat_arm_elf`
15.3.1** Alire toolchains (the source of `populate.sh`'s copies), whose
compiler identifies itself as GCC 15.3.0 (`GNAT Version: 15.3.0`). The
previous pin, 15.1.2, was a GCC 15.0.1 20250418 prerelease on macOS and
GCC 15.1.0 on Linux under one release number; its tier-1 sources are
byte-identical to 15.3.1's (RTS-PRODUCTION.md C3), so the move changed
no file here. The Alire release number, not the GCC version, is what
this crate is versioned against. A GCC/toolchain upgrade means re-running `populate.sh`
against the new installation and bumping this crate's version — the
version-test boundary RTS.md §3 and §7 argue for.

## Licence

`licenses = "GPL-3.0-or-later WITH GCC-exception-3.1"` in `alire.toml`,
matching every file's own header: GNU GPL v3-or-later, plus the GCC
Runtime Library Exception v3.1 that permits linking non-GPL application
code against the compiled runtime. Copyright is Free Software Foundation
/ AdaCore, per each file's banner comment.

**Do not alter the FSF/AdaCore header comments in any populated file.**
They are the license grant for that specific file and are reproduced
verbatim by `populate.sh`; this crate's own `alire.toml` licence field
describes the aggregate, it does not replace the per-file notices.
