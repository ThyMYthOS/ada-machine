# rts_core_riscv64

Tier 2 of the rts-spikes crate hierarchy (see [../CONTRACT.md](../CONTRACT.md) §2,
[../../RTS-POLARFIRE.md](../../RTS-POLARFIRE.md) §3, and
[../../RTS.md](../../RTS.md) §6–§7): the RISC-V architecture core, i.e. the
CPU-specific layer of `System.BB` that the run-time's tasking kernel sits on.

## What this crate is

`rts_core_riscv64` holds the units named in `src.lst` — the RISC-V
implementation of `System.BB`'s CPU seam — copied out of the installed
`gnat_riscv64_elf` toolchain. Like tier 1 and tier 3, it is **source-only
and is never built by Alire**: these units require `-gnatg -nostdinc`, the
cross compiler, and no runtime to compile against — a bootstrap cycle
that only a leaf's `runtime_build.gpr`/`ravenscar_build.gpr` (which
supply exactly those switches) can resolve. `rts_core_riscv64.gpr` is
therefore an `abstract` project with `Source_Dirs => ()`: it contributes
no compilation of its own, only one path variable — `Src_Dir` — that a
leaf's library project reads via `Project'Project_Dir` and lists
directly in its own `Source_Dirs` (RTS.md §6, "Assembling the
directory").

Every leaf's `ravenscar_build.gpr` places this crate's `Src_Dir` between
`rts_support_mpfs`'s (board) and `rts_sources_gcc15`'s (shared) —
`("src", Rts_Support_Mpfs.Src_Dir, Rts_Core_Riscv64.Src_Dir,
Rts_Sources_Gcc15.Gnarl_Dir)`, CONTRACT.md §3.4 — matching RTS.md §6's
load-bearing rule: **board shadows core shadows shared**. `light_mpfs`'s
`runtime_build.gpr` also names this crate's `Src_Dir` (the template is
shared across all three leaves), but see "What is actually in here"
below for what that leaf actually finds there.

## Populated, not vendored

**`src/` is not committed.** `src.lst` — six filenames, one per line — is
the reviewable manifest of this crate's contents, playing the role
RTS.md §2.1 gives `Source_List_File` (CONTRACT.md §1). `../populate.sh`
copies each one out of the installed `gnat_riscv64_elf` toolchain,
searching `light-tasking-polarfiresoc/gnarl`, then
`embedded-polarfiresoc/gnarl`, then `light-polarfiresoc/gnat`, then
`light-tasking-polarfiresoc/gnat`, first match wins. `.gitignore`
excludes `src/`. Consequently **`make populate` is a prerequisite for
any build** against this crate — a fresh clone does not build until it
has run. This is the same spike-only shortcut tier 1 documents in its
own README, taken here for the same reason (CONTRACT.md §1).

Do not edit `src.lst` by hand outside the tooling that generated it, and
do not commit anything under `src/`.

Unlike tier 1 — which keeps `libgnat`/`libgnarl` apart as two separate
exported directories because the split tracks a real distinction
(tasking vs. not) — this crate's `populate.sh` search list spans *both*
the `gnat` and `gnarl` output trees of the installed runtime for a
single flat `src.lst`. That is not an oversight; it is the first piece
of evidence for the next section: which of these six names actually
live under `gnat` and which live only under `gnarl` is exactly the line
between "used everywhere" and "used only by the tasking kernel".

## What is actually in here

Reading the six populated files, and cross-checking which of the
installed toolchain's profile directories actually contain each name:

| File | Lines | Present under (installed toolchain) | Architecture-generic or RISC-V-specific | Evidence, from the code |
|---|---:|---|---|---|
| `s-bb.ads` | 96 | `light`, `light-tasking`, `embedded` — **all three** `gnat` trees; **no** `gnarl` tree | **Architecture-generic** | `pragma Pure`, empty package, pure documentation (an ASCII diagram of the whole `System.BB` hierarchy). Nothing CPU-specific in the text at all. |
| `s-bbcppr.ads` | 95 | `light-tasking`, `embedded` `gnarl` trees only | Declares the generic `CPU_Primitives` **contract** (`Context_Switch`, `Initialize_Stack`, `Initialize_Context`, `Install_Error_Handlers`, `Enable`/`Disable_Interrupts`, `Initialize_CPU`); no RISC-V token anywhere in this file's text, but it is filed and shipped only alongside the tasking kernel, paired 1:1 with an arch-specific body | Header comment only says "primitives which are dependent on the underlying processor" — a generic seam description, not a RISC-V one |
| `s-bbcppr.adb` | 234 | `light-tasking`, `embedded` `gnarl` trees only | **RISC-V-specific** | Comment: *"This package implements RISC-V architecture specific support for the GNAT Ravenscar run time."* Body manipulates `Mstatus_MIE` and `Buffer.RA`/`SP`/`S1`/`S2` — RISC-V calling-convention register names |
| `s-bbcpsp.ads` | 143 | `light-tasking`, `embedded` `gnarl` trees only | **RISC-V-specific** | `Context_Buffer` fields commented `-- X1` … `-- X27` (RISC-V integer register numbers); CSR wrappers named `"mie"`, `"mip"`, `"mcause"`, `"mstatus"`; `Stack_Alignment` comment: *"defined by the ABI (RV32I and RV64I)"* |
| `s-bbcpsp.adb` | 182 | `light-tasking`, `embedded` `gnarl` trees only | **RISC-V-specific** | Comment: *"implements RISC-V architecture specific support"*. Inline `System.Machine_Code` asm: `csrrw`, `csrr`, `csrrc`, `csrrs`, the `mtvec` register, `mcause` trap-cause decoding (7 = machine timer, 11 = machine external/ecall), `a0`-`a7` "used for function arguments in the RISC-V ABI" |
| `context_switch.S` | 105 | `light-tasking`, `embedded` `gnarl` trees only | **RISC-V-specific** | Comment: *"Functions to store and restore the context of a task for RISC-V."* RISC-V register names (`a0`, `a1`, `t0`, `ra`, `sp`, `s0`-`s11`, `fs0`-`fs11`), RISC-V mnemonics (`jalr`, `mv`), `#include "riscv_def.h"` — a header this crate does not ship; it comes from tier 3 (`rts_support_mpfs/src.lst`) |

**Five of the six files are unambiguously RISC-V-specific** — three of
them say so in their own header comment, and all five hardcode RISC-V
register numbers, CSR names, ABI conventions, or assembly mnemonics.
Only `s-bb.ads` carries zero CPU-specific content; it is the empty root
package of the `System.BB` hierarchy, present in every profile
regardless of tasking, and is the one file this crate contributes
independent of whether tasking is present at all.

**At the `light` profile, this crate contributes almost nothing.**
`light-polarfiresoc` — the runtime `light_mpfs` builds from — has **no
`gnarl/` directory in the installed toolchain at all**; verified
directly against the installation this repository's `populate.sh` reads
from. The five CPU-specific files exist *only* under
`light-tasking-polarfiresoc/gnarl` and `embedded-polarfiresoc/gnarl` —
i.e. they are `libgnarl` content, part of the Ravenscar tasking kernel,
and AdaCore ships them only for the two tasking profiles. `src.lst`
still names all six (this crate serves all three leaves with one file
list), and `populate.sh`'s fallback search means `src/` on disk always
holds all six after `make populate` — but for `light_mpfs` specifically,
the only one of those six with any upstream counterpart in a non-tasking
profile is `s-bb.ads`, a 96-line, comment-only, `Pure`, empty package.
The real `System.BB` kernel — the thing "architecture core" is meant to
name — lives in `libgnarl` and is reachable only from
`light_tasking_mpfs` and `embedded_mpfs`.

## Tier-2 assessment (RTS.md §7)

RTS.md §7 argues **"Tier 2 barely pays"**: the architecture core changes
on nearly the same cadence as tier 1, and is consumed only by tiers that
already depend on tier 1, so folding it into tier 1 "costs little and
removes a crate." **What is actually populated here supports that
verdict; nothing about it contradicts CONTRACT.md.**

1. **Footprint.** Six files, 855 lines, against tier 1's ~1049 units
   (~6 MB). This is not a partition of comparable size to tier 1 or
   tier 3 (RTS-POLARFIRE.md §3's "family support" tier); it is a
   sliver.
2. **Same provenance, same cadence, same directory tree as tier 1.**
   `../populate.sh` finds this crate's six names by searching the
   *identical* per-profile `gnat/`/`gnarl/` directories that
   `rts_sources_gcc15/libgnat.lst` and `libgnarl.lst` also draw from —
   compare the `copy` invocations in `../populate.sh` for
   `rts_sources_gcc15` and `rts_core_riscv64`. There is no separate
   upstream location, no separate release, and no vendor-register-data
   cadence the way tier 3's PLIC/CLINT bindings have
   (RTS-POLARFIRE.md §3 row 3). A GCC/bb-runtimes version bump that
   touches tier 1 necessarily touches this crate too, because both are
   drawn from the one snapshot. Every file's header banner also reads
   "GNAT RUN-TIME LIBRARY (GNARL) COMPONENTS", Copyright AdaCore/FSU/ESA
   — the same authorship and licence block as tier 1's own units, not a
   family-specific artefact.
3. **The idealized tier-2 scope in RTS.md's own general table (§6) is
   broader than what actually landed here — and the rest already sits
   in tier 1.** RTS.md §6 describes tier 2 in general as
   `System.BB.CPU_Primitives`, `Threads`, `Time`, `Interrupts`,
   protected-object support. But in this spike, `System.BB.Threads`
   (`s-bbthre.ad?`), `System.BB.Time` (`s-bbtime.ad?`),
   `System.BB.Interrupts` (`s-bbinte.ad?`) and `System.BB.Protection`
   (`s-bbprot.ad?`) are already listed in
   `../rts_sources_gcc15/libgnarl.lst`, **tier 1** — not here — because
   that scheduling logic is portable Ada that calls through the
   `CPU_Primitives`/`Board_Support` seam rather than touching hardware
   itself (exactly the layering `s-bb.ads`'s own diagram draws: `Threads`,
   `Interrupts`, `Time` and `Board_Support` sit above `CPU_Primitives`).
   `src.lst` here keeps only the seam itself: the root package and the
   two packages whose own header comments say they are
   processor-dependent. So this instantiation of tier 2 is even smaller
   than RTS.md's own idealized description of it — most of what a
   general reading of "architecture core" might expect to find here has
   already been folded into tier 1.
4. **No independent reuse value.** Nothing in this crate is consumed
   except by leaves that already depend on `rts_sources_gcc15` for the
   rest of `libgnat`/`libgnarl`; no leaf uses tier 2 without tier 1.
   RTS.md §7's "consumed only by tiers that already depend on tier 1" is
   literally true here.
5. **The `light` finding sharpens the argument.** Not only does tier 2
   change on tier 1's cadence in general — for this spike's three
   leaves specifically, one of them (`light_mpfs`) gets essentially
   nothing from this crate being separate: its only real hit in `src/`
   is one empty package that could sit in tier 1's `libgnat/` next to
   the ~963 units it already fetches from the identical snapshot,
   without adding a file.

CONTRACT.md already anticipates this: RTS-POLARFIRE.md §3's own table
entry for this crate reads *"`System.BB.CPU_Primitives`, threads, time —
or folded into (1) per RTS.md §7"* — the fold-into-tier-1 option is
flagged in the design document this crate's own contract cites, not
introduced by this assessment. There is no contradiction with
CONTRACT.md here, only confirmation, from the files actually populated,
of a call CONTRACT.md already flagged as live. Per CONTRACT.md §6 ("do
not weaken the contract... report the mismatch instead"), this crate is
still built exactly as pinned — this section reports the finding rather
than acting on it.

## Licence

`licenses = "GPL-3.0-or-later WITH GCC-exception-3.1"` in `alire.toml`,
matching every file's own header: GNU GPL v3-or-later, plus the GCC
Runtime Library Exception v3.1 that permits linking non-GPL application
code against the compiled runtime. Copyright is Universidad Politecnica
de Madrid / The European Space Agency / AdaCore, per each file's banner
comment (the bare-board port of GNARL's lineage, visible directly in the
headers).

**Do not alter the header comments in any populated file.** They are
the licence grant for that specific file and are reproduced verbatim by
`populate.sh`; this crate's own `alire.toml` licence field describes the
aggregate, it does not replace the per-file notices.

## Version

This snapshot corresponds to the **`gnat_riscv64_elf` 15.3.1** Alire
toolchain (byte-identical to the 15.1.2 snapshot it replaced; RTS-PRODUCTION.md C3), the same one `rts_sources_gcc15` is versioned against (see
that crate's README for the GCC-snapshot identity note). A
GCC/toolchain upgrade means re-running `populate.sh` against the new
installation and bumping this crate's version in lockstep with
`rts_sources_gcc15` — which is itself part of the evidence for the
tier-2 assessment above: the two crates have no independent version
axis in practice.
