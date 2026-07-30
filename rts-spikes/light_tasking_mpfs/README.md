# light_tasking_mpfs

Buildable leaf crate (CONTRACT.md §3) for the **light-tasking** (Ravenscar/
Jorvik) GNAT runtime profile, Microchip PolarFire SoC, `riscv64-elf`.

Composes tier 1 (`rts_sources_gcc15`), tier 2 (`rts_core_riscv64`) and
tier 3 (`rts_support_mpfs`) source-only crates, adding only:

- the leaf-owned units in `src/` (20 files — see below),
- the configuration variables and renaming shim,
- the two library projects and the metadata files a runtime directory
  needs (`runtime.xml`, `ada_source_path`, `ada_object_path`,
  `target_options.gpr`).

It produces — does not ship — `adalib/libgnat.a` and `adalib/libgnarl.a`.

## Two library projects, not one

Unlike `light_mpfs`, this profile has tasking, so it owns **two** GPR
library projects sharing one `adalib`:

| Project | File | Library | `Source_List_File` |
|---|---|---|---|
| `Runtime_Build` | `runtime_build.gpr` | `libgnat.a` | `light-tasking.gnat.lst` (513 units) |
| `Ravenscar_Build` | `ravenscar_build.gpr` | `libgnarl.a` | `light-tasking.gnarl.lst` (88 units) |

`Ravenscar_Build` `with`s `Runtime_Build` and reuses its exported
`ISA_Switches` so the two archives are always built with the same
`-march`/`-mabi`. An application `with`s **both** project files and links
both archives.

### `Source_List_File` only — per CONTRACT.md §7.1

`light-tasking.lst` (601 units) is the whole profile's membership
manifest and stays as provenance, but is **not** used as either
project's `Source_List_File`: it mixes gnat-side and gnarl-side names,
and every `Source_List_File` entry must resolve to a real file somewhere
in that project's own `Source_Dirs` (verified) — so a shared, unsplit
list would need one of the two projects to also see the *other's*
tier-1 directory, and once both projects can see both tier-1
directories, gprbuild refuses with `unit "..." cannot belong to several
projects` for every name reachable from both.

`light-tasking.gnat.lst` (513) and `light-tasking.gnarl.lst` (88) are a
disjoint partition of the 601 (513 + 88 = 601 exactly) used as-is —
**no** `Excluded_Source_Files` or `Excluded_Source_List_File` anywhere
in either project file. CONTRACT.md §7.1 is explicit that combining
`Source_List_File` with either exclusion attribute is a mistake:
gprbuild warns `both attributes Excluded_Source_Files and
Excluded_Source_List_File are present` and then one **silently wins**,
discarding the other — which is exactly the failure mode an earlier
version of this crate hit (self-derived exclude-lists, since replaced).

Each project's `Source_Dirs` therefore lists only its **own** tier-1
directory (`Rts_Sources_Gcc15.Gnat_Dir` for `Runtime_Build`,
`.Gnarl_Dir` for `Ravenscar_Build`), plus `gnat_user`/`gnarl_user`,
`src`, and both tier 2/tier 3 directories (shared, since some tier 2/3
units belong to one project and some to the other — `Source_List_File`
alone decides which, `Source_Dirs` only decides where to look).

### Leaf-owned units in `src/` (20 files)

18 units differ in *content* between the three runtime profiles and so
cannot live in the shared tier-1 snapshot; `system.ads` and
`s-parame.ads/.adb` were always leaf-owned. `populate.sh` places the
light-tasking variant of each. Membership between the two library
projects (confirmed against `light-tasking.gnat.lst`/`.gnarl.lst`):

| Side | Files |
|---|---|
| gnat (14, in `light-tasking.gnat.lst`, compiled by `runtime_build.gpr`) | `system.ads`, `s-parame.ads/.adb`, `a-except.ads/.adb`, `a-elchha.ads/.adb`, `a-tags.ads/.adb`, `a-strsup.ads/.adb`, `s-assert.adb`, `s-memory.ads/.adb` |
| gnarl (6, in `light-tasking.gnarl.lst`, compiled by `ravenscar_build.gpr`) | `s-bbpara.ads`, `s-taskin.ads`, `s-tpobop.ads/.adb`, `s-tposen.ads/.adb` |

`s-bbpara.ads` (`System.BB.Parameters`) is gnarl-side: several gnarl
tier-1 units (`System.Multiprocessors`, `System.BB.Time_Events`, ...)
read it, and it is grouped with the tasking kernel's own leaf-owned
units rather than with `system.ads`/`s-parame.*`. Both library projects
list `src` in `Source_Dirs` (needed either way, since each project's own
`Source_List_File` must find its members there), and each finds only
its own 14 or 6 thanks to the split lists above.

`s-taskin.ads`'s tier-1 body (`s-taskin.adb`) and the two
`s-tpobop`/`s-tposen` units' companions are ordinary same-*library*
units in `rts_sources_gcc15/libgnarl`, which is why `Ravenscar_Build`
needs `src` in its own `Source_Dirs` and not merely in
`ada_source_path` (RTS.md §1.1/A.13 distinguishes the two: same-library
references need `Source_Dirs`; only *cross*-library references are
resolved via `ada_source_path` at compile time).

## `Max_Number_Of_CPUs` derivation (`src/s-bbpara.ads`)

Upstream hardcodes `Max_Number_Of_CPUs : constant := 1` even for
light-tasking (RTS-POLARFIRE.md §2). Here it derives from
`MPFS_Runtime_Config.Harts`, and **must** stay a static expression:
tier 1's `System.Multiprocessors` (`rts_sources_gcc15/libgnarl/
s-multip.ads`) declares `type CPU_Range is range 0 .. System.BB.
Parameters.Max_Number_Of_CPUs;`, and a `signed_integer_type_definition`'s
bounds are syntactically required to be static (RM 3.5.4) — not a style
preference, a hard compiler error if violated.

**Two mechanisms were tried and empirically rejected** by this exact
compiler (`gnat_riscv64_elf` 15.1.2), each reproduced twice:

1. Indexing (`Harts (Harts'First)`, `Character'Pos (Harts (N))`):
   `error: indexed component is never static (RM 4.9)`.
2. Whole-string equality against a literal (`Harts = "1"`), including
   the exact form suggested mid-task —
   `(if MPFS_Runtime_Config.Harts = "1" then 1 elsif ... = "1..4" then 4
   ... )` — reproduced verbatim through the real
   `gnat_user/mpfs_runtime_config.ads` shim:
   `error: non-static expression used in number declaration`.
   This is *not* the same claim as (1) — RM 4.9 does not obviously
   forbid string equality — but it is what this compiler does with it,
   confirmed twice independently (once via a bare external package,
   once via the real shim), so it was not adopted for the committed
   file despite being suggested during the task.

What **is** static and used here: `Harts'Length` alone. A comma-
separated list of *N* single-digit harts is always exactly `2N-1`
characters (`N` digits, `N-1` commas), so
`Max_Number_Of_CPUs = (Harts'Length + 1) / 2` for `Harts'Length` in
`{1, 3, 5, 7, 9}` (1 to 5 harts). `pragma Compile_Time_Error` rejects
any other length outright (RTS.md §5.2/A.15: a subtype only warns and
still lets the build reach `Last_Chance_Handler`; the pragma actually
enforces).

**This does not accept the `"a..b"` range shorthand** used as an
illustrative example in RTS-POLARFIRE.md §5.1 (`"1..4"`) or suggested
mid-task (`"1..2"`, `"1..4"`). A range's hart count depends on its two
endpoint digits, which — per finding (1) above — cannot be read back out
of the string in a static expression, and per finding (2), comparing the
whole string against each candidate range literal does not work either
with this compiler. `Harts => "1..4"` is rejected by the
`pragma Compile_Time_Error` (length 4 is not in the accepted set); write
out the members instead, e.g. `"1,2,3,4"`. CONTRACT.md §3.2 does not
itself pin the range shorthand (only the type, `String`, and the
default, `"1"`).

`Multiprocessor : constant Boolean := Max_Number_Of_CPUs /= 1;` is a
relational operator over two static integers, so it stays static too —
confirmed by using it, together with `Max_Number_Of_CPUs`, inside a
second `pragma Compile_Time_Error` self-check while developing this file
(removed from the committed version; both evaluated correctly for
`Harts => "1"`, `"2,3"` and `"0,1,2,3,4"`, and `type CPU_Range is range 0
.. Max_Number_Of_CPUs;` — the actual tier-1 use site — compiled in every
case, and the full leaf build in the verify app compiled `s-bbpara.ads`
successfully with the pinned default `Harts => "1"`).

## Configuration variables (CONTRACT.md §3.2)

| Name | Type | Default |
|---|---|---|
| `Hart_Class` | Enum `e51`, `u54` | `u54` |
| `Harts` | String | `"1"` |
| `Privilege` | Enum `m_mode`, `s_mode` | `m_mode` |
| `Memory_Profile` | Enum (6 values, see CONTRACT.md §3.2) | `lim` |
| `L2_Cache_Ways` / `L2_LIM_Ways` / `L2_Scratchpad_Ways` | Integer 0..16 | `1` / `15` / `0` |
| `ITIM_Ways` / `DTIM_Ways` | Integer 0..3 | `0` / `0` |
| `DDR_Present` | Boolean | `false` |
| `DDR_Cached_KB` / `DDR_NonCached_KB` / `DDR_WCB_KB` | Integer | `0` |
| `Console` | Enum `mmuart0`..`mmuart4`, `ram_fifo`, `none` | `mmuart0` |
| `Interrupt_Stack_Size` | Integer | `8192` |
| `Secondary_Stack_Size` | Integer | `2048` |
| `MPFS_PARTITION` | String | `""` |

`Hart_Class` and `MPFS_ARCH`/`MPFS_ABI` (the `external()`s in
`runtime.xml`/`runtime_build.gpr`, CONTRACT.md §3.6) are two independent
knobs, per CONTRACT.md's own design — the ISA switches are not derived
from `Hart_Class` automatically. A `Hart_Class => e51` build needs
`-XMPFS_ARCH=rv64imac_zicsr -XMPFS_ABI=lp64` set explicitly
(RTS-POLARFIRE.md §1.1: bare `rv64imac` cannot even assemble the startup
code, the E51 string is `rv64imac_zicsr`).

`Secondary_Stack_Size` is declared (CONTRACT.md §3.2 pins the name) but
not yet consumed by any switch or spec in this leaf — the shipped
`light-tasking-polarfiresoc` runtime does not expose it as a knob either;
left for a future revision.

## Why `provides` is here, not on `light_mpfs`

`light_mpfs`'s floor excludes tasking (RTS.md §4: AVR-style — a
non-tasking leaf must never claim to satisfy a tasking dependency). This
profile has tasking (a second library project, `Ravenscar_Build`,
producing `libgnarl.a`), so it is the first leaf in this family that can
honestly declare `provides = ["gnat_rts_tasking=0.1.0"]`. Per RTS.md §4:
a *library* crate should depend on the virtual name (`gnat_rts_tasking`)
to mean "I need a tasking runtime, whichever one the application already
chose"; the *application* must still depend on a concrete runtime crate
by name, since a bare `gnat_rts_tasking = "*"` dependency would resolve
against an arbitrary provider (verified elsewhere in this repository,
RTS.md A.17, for the analogous `gnat=<version>` alias).

## Verification status

A throwaway `alr` application (path-pinned to this crate and its three
tier dependencies, toolchain `gnat_riscv64_elf=15.1.2` selected, one
package with a library-level task, a protected object and a `delay
until`) was built against both `runtime_build.gpr` and
`ravenscar_build.gpr`. Compilation reached deep into both projects —
every leaf-owned unit in `src/` compiled, including this crate's own
modified `s-bbpara.ads`, both tier-2 asm files, and the majority of both
the 513-unit gnat list and the 88-unit gnarl list — but did not reach
`adalib/libgnat.a`/`libgnarl.a` because of a build-blocking error in
**tier 1 and tier 3, not in this crate**:

```
s-bbsuti.adb:60:04: error: violation of restriction "No_Elaboration_Code" at s-bbbosu.ads:41
s-bbsuti.adb:63:04: error: violation of restriction "No_Elaboration_Code" at s-bbbosu.ads:41
s-bbripl.adb:131:04: error: violation of restriction "No_Elaboration_Code" at s-bbbosu.ads:41
```

`rts_support_mpfs/src/s-bbbosu.ads:41` declares
`pragma Restrictions (No_Elaboration_Code);` (the CONTRACT.md §7.3 fix,
correctly applied there). That restriction is partition-wide, not local
to the declaring unit, so it also binds `rts_sources_gcc15/libgnarl/
s-bbsuti.adb` (a `separate (System.BB.Board_Support)` subunit of tier 1,
declaring `Mtimecmp_Lo`/`Mtimecmp_Hi` as `Volatile` objects with an
`Address` clause at lines 60/63) and `rts_support_mpfs/src/
s-bbripl.adb:131` (`Use_Hart_0 : constant Boolean := PLIC_Hart_Id = 0;`).
Neither file is owned by this crate — see the task report for the
precise fix needed in `rts_support_mpfs`/`rts_sources_gcc15`.

Given this, `adalib/libgnat.a` and `adalib/libgnarl.a` were **not**
produced, and the tasking application did not link. Nothing in this
crate's own files was the cause: every one of this crate's own
compilations (the 20 leaf units, both `runtime.xml`/`target_options.gpr`
switches, both `Source_List_File`s) succeeded.

## Known gaps / `UNVERIFIED` items

- The cross-tier `No_Elaboration_Code` violation above — blocks the
  final link, not owned by this crate.
- **L1-I / L1-D per-way byte size** (`runtime_build.gpr`, `L1_I_Way_Size`
  / `L1_D_Way_Size`): not given in CONTRACT.md or RTS-POLARFIRE.md —
  RTS-POLARFIRE.md §11 item 5 flags this as still needing the TRM.
  Harmless at the pinned defaults (`ITIM_Ways`/`DTIM_Ways` = `0`).
- **`place-envm-lma-scratchpad-vma.ld`** does not exist yet in
  `rts_support_mpfs/ld` (the other four `place-*.ld` scripts do); falls
  back safely since the default `Memory_Profile => lim` never selects it.
- **Per-hart U54 ITIM ownership** for a *multi*-hart `Harts` with
  `ITIM_Ways /= 0`: already a tier-3 validation error per
  RTS-POLARFIRE.md §5.3 (ITIM is per-hart private); this leaf's own
  `case ... Harts is when "1" | "2" | "3" | "4" => ... when others =>
  null;` only assigns a length for the single-hart case, matching that
  restriction.
- **`target_options.gpr`** is modelled directly on (and mostly copied
  from) the shipped `light-tasking-polarfiresoc` runtime's own file, read
  from the installed `gnat_riscv64_elf` 15.1.2 toolchain.

## Populate

`make populate` (from `rts-spikes/`) must run before this crate builds;
see CONTRACT.md §1. It copies the light-tasking variant of every leaf-
owned unit into `src/` and the tier lists into the three source-only
crates.
