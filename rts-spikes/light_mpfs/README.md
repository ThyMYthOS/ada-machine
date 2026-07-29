# light_mpfs

Leaf crate of the rts-spikes hierarchy (see [../CONTRACT.md](../CONTRACT.md) §3
and [../RTS-POLARFIRE.md](../RTS-POLARFIRE.md)): the buildable "light"
(no-tasking) Ada runtime for Microchip PolarFire SoC, `riscv64-elf`.

## What this crate is

`light_mpfs` is the one crate in this spike that actually owns
`for Runtime ("Ada") use Project'Project_Dir;` and produces
`adalib/libgnat.a` (RTS.md §1). It contributes no runtime sources of its
own beyond `gnat_user/` (the configuration renaming shim, §3.3) and
`src/system.ads` + `src/s-parame.ads` (leaf-owned, copied verbatim from
the installed `light-polarfiresoc` runtime by `../populate.sh`); every
other compiled unit comes from the three source-only tiers it depends
on:

| Tier | Crate | Contributes |
|---|---|---|
| 1 | `rts_sources_gcc15` | the shared `libgnat` snapshot |
| 2 | `rts_core_riscv64` | `System.BB` / CPU-primitives core (present in `Source_Dirs`; `light.lst` selects only `s-bb.ads` from it -- this profile has no tasking, so the context-switch/CPU-primitive bodies are excluded by the list, not by directory) |
| 3 | `rts_support_mpfs` | family support: board parameters, console, machine-reset, the PLIC/FE310 register bindings, and `ld/` |

`light_mpfs` itself is what CONTRACT.md §3.1 calls **the critical-path
leaf**: it is the only one of the three that must build in this spike's
first milestone (RTS-POLARFIRE.md §10, phase P1), because it has no
tasking floor to clear first (RTS.md §4, matching AVR's own `light`
floor). Per CONTRACT.md §3.1 it therefore does **not** declare
`provides = ["gnat_rts_tasking=..."]`.

`Source_Dirs` order is load-bearing (RTS.md §2.1): `gnat_user`/`src`
(this leaf) shadow `rts_support_mpfs.Src_Dir` (board) shadow
`rts_core_riscv64.Src_Dir` (core) shadow `rts_sources_gcc15.Gnat_Dir`
(shared) -- board-specific variants win over generic ones with no
filename suffixes. `Source_List_File => "light.lst"` is the reviewable
membership manifest (513 units); shadowing only resolves *variant*
collisions, it is never relied on for *membership*.

## Two modes (RTS-POLARFIRE.md §5)

- **Standalone mode** (`MPFS_PARTITION = ""`, the default): a
  single-partition image with no system description. `Hart_Class`,
  `Harts`, `Memory_Profile` and the rest of the table below are
  authored by hand in the application's `[configuration.values]`. This
  is the only mode this milestone (P1) exercises, and the only mode
  that needs no `mpfs_system` / generator run at all.
- **Derived mode** (`MPFS_PARTITION` set to a partition name): hart
  set, memory window, console, clocks, privilege and PMP all come from
  the (not yet implemented -- RTS-POLARFIRE.md §4, phase P4)
  `mpfs_system` crate instead, generated from the vendor's MSS
  Configurator XML and the HSS payload YAML. In this mode the knobs
  below become **outputs**, and setting them by hand is a configuration
  error the generated spec is meant to reject once it exists.
  `Memory_Profile => system_partition` selects the corresponding
  generated `partition-<MPFS_PARTITION>.ld` instead of one of the five
  committed placement scripts.

## Configuration variables (CONTRACT.md §3.2 -- names pinned)

| Variable | Type | Default | Notes |
|---|---|---|---|
| `Hart_Class` | Enum `e51`, `u54` | `u54` | Does **not** by itself change `-march`/`-mabi` in this crate -- see "Two independent ISA knobs" below. Drives `MPFS_DTIM_LENGTH`/`MPFS_E51_ITIM_LENGTH`/`MPFS_U54_n_ITIM_LENGTH`/`MPFS_LOCAL_ITIM_*` ownership |
| `Harts` | String | `"1"` | A single hart number for this leaf (`"0"` for e51, `"1"`.."4" for u54); SMP (`Harts` naming several harts) is a `light_tasking_mpfs`/`embedded_mpfs` concern, not this profile's (CONTRACT.md §3.2) |
| `Privilege` | Enum `m_mode`, `s_mode` | `m_mode` | Declared per CONTRACT.md §3.2; not yet consumed by any `light_mpfs` source -- S-mode support is RTS-POLARFIRE.md §8 item 7 / phase P5, out of scope for this leaf today |
| `Memory_Profile` | Enum `envm`, `lim`, `lim_lma_scratchpad_vma`, `envm_lma_scratchpad_vma`, `ddr_by_bootloader`, `system_partition` | `lim` | Selects the `-T` placement script from `rts_support_mpfs`'s `ld/` (see below for which scripts exist today) |
| `L2_Cache_Ways` | Integer 0..16 | `1` | Not yet enforced against `L2_LIM_Ways`/`L2_Scratchpad_Ways` summing to 16 -- that check belongs in a tier-3 spec (CONTRACT.md §5), not this leaf |
| `L2_LIM_Ways` | Integer 0..16 | `15` | Feeds `MPFS_LIM_LENGTH = L2_LIM_Ways * 128K` |
| `L2_Scratchpad_Ways` | Integer 0..16 | `0` | Feeds `MPFS_SCRATCHPAD_LENGTH = L2_Scratchpad_Ways * 128K` |
| `ITIM_Ways` | Integer 0..3 | `0` | Feeds the owned hart's `MPFS_*_ITIM_LENGTH` -- see "Open: L1 way size" |
| `DTIM_Ways` | Integer 0..3 | `0` | E51 only; feeds `MPFS_DTIM_LENGTH` -- see "Open: L1 way size" |
| `DDR_Present` | Boolean | `false` | Gates all three DDR lengths to `0` when false (RTS-POLARFIRE §1.3's "absence needs no separate memory profile") |
| `DDR_Cached_KB` | Integer | `0` | Feeds `MPFS_DDR_CACHED_LENGTH` (KB, converted to bytes via ld's `K` suffix) |
| `DDR_NonCached_KB` | Integer | `0` | Feeds `MPFS_DDR_NC_LENGTH` |
| `DDR_WCB_KB` | Integer | `0` | Feeds `MPFS_DDR_WCB_LENGTH` |
| `Console` | Enum `mmuart0`..`mmuart4`, `ram_fifo`, `none` | `mmuart0` | Declared per CONTRACT.md §3.2; **not yet consumed** -- the populated `s-textio.adb` still hardcodes `System.BB.Board_Parameters.UART_Base_Address` (MMUART0). Wiring this is RTS-POLARFIRE.md §8 item 8, in `rts_support_mpfs`, not this leaf |
| `Interrupt_Stack_Size` | Integer | `8192` | Declared per CONTRACT.md §3.2; **not consumed by this profile** -- `light_mpfs` has no `s-bbpara.ads` (that file exists only in `light_tasking_mpfs`/`embedded_mpfs`, per CONTRACT.md §3.4), and a non-tasking runtime has no separate interrupt stack to size |
| `Secondary_Stack_Size` | Integer | `2048` | Declared per CONTRACT.md §3.2; **not consumed by this profile** -- `light`'s `s-parame.ads` has no body (`s-parame.adb` exists only for tasking/embedded, CONTRACT.md §3.4) and hardcodes `Runtime_Default_Sec_Stack_Size` at 1 MiB, matching the stock `light-polarfiresoc` behaviour it was copied from |
| `MPFS_PARTITION` | String | `""` | Empty = standalone mode (above). Only meaningful with `Memory_Profile => system_partition` |

## Exported GPR variables (CONTRACT.md §3.7)

`runtime_build.gpr` exports `ISA_Switches`, `Linker_Switches` and
`Defsyms`. A consuming application's own project is expected to add all
three itself (RTS.md §6 "the leaf's responsibilities" / §5.4):

```ada
for Target use Runtime_Build'Target;
for Runtime ("Ada") use Runtime_Build'Runtime ("Ada");
package Compiler is
   for Default_Switches ("Ada") use Runtime_Build.ISA_Switches;
end Compiler;
package Linker is
   for Switches ("Ada") use
     Runtime_Build.Linker_Switches & Runtime_Build.Defsyms;
end Linker;
```

`Linker_Switches` deliberately does **not** already include `Defsyms` --
the two are concatenated by the consumer, matching the app-side
handshake this crate was verified against.

## Two independent ISA knobs

This crate has **two** things that both look like "pick E51 or U54",
and they are not wired to each other:

1. `Hart_Class` (Alire configuration variable, §3.2) -- drives the
   `Defsyms` ownership computation above (ITIM/DTIM windows).
2. `MPFS_ARCH` / `MPFS_ABI` (plain GPR `external()`s, defaulting to
   `"rv64imafdc"` / `"lp64d"`, read identically by `runtime.xml` and by
   this project's own `ISA_Switches`) -- drive the actual `-march`/
   `-mabi` compiler switches, per CONTRACT.md §3.6/§3.7 verbatim.

CONTRACT.md pins `runtime.xml`'s ISA switches to `external()`, not to
`Hart_Class`, and §3.7 pins `ISA_Switches` to the same two externals --
so this split is not an implementation accident, it is what is written.
The reason is almost certainly RTS.md §2.2: "Configuration values have
no command-line override... Where a knob genuinely needs command-line
reach, it has to be a plain GPR `external()` alongside (or instead of) a
configuration variable" -- `runtime.xml` is consumed by `gprconfig` at
configuration time (RTS.md §1.1), a stage this crate's own
Alire-generated `gnat_user/light_mpfs_config.gpr` cannot easily reach
into.

**Consequence:** the two knobs can silently disagree. Setting
`Hart_Class => e51` via `[configuration.values]` alone builds a runtime
whose `Defsyms` assume the E51 (DTIM/E51-ITIM ownership, hart "0") while
still compiling at U54's `rv64imafdc`/`lp64d` (hard float, and missing
`_zicsr`, which RTS-POLARFIRE §1.1 shows is required for `start-ram.S`
to assemble at all on the E51). Building an actual E51 image also needs
`-XMPFS_ARCH=rv64imac_zicsr -XMPFS_ABI=lp64` passed alongside
`Hart_Class => e51`. Nothing in this leaf enforces the two agree --
CONTRACT.md §5 lists "`Hart_Class = e51` with a hard-float ABI → error"
as a check for a tier-3 spec to implement, which would need to read
both `MPFS_Runtime_Config.Hart_Class` (Ada-visible) and somehow the
`external()`-only `MPFS_ABI` -- worth resolving before this crate is
used for anything beyond the default U54 configuration.

## Open: L1 way size (ITIM/DTIM length placeholder)

`MPFS_LIM_LENGTH`/`MPFS_SCRATCHPAD_LENGTH` are pinned exactly as
`L2_*_Ways * 128K` (CONTRACT.md §4, and RTS-POLARFIRE §1.2.1 gives the
128 KB L2 way size as a verified fact). CONTRACT.md's table gives no
such multiplier for `MPFS_DTIM_LENGTH`/`MPFS_E51_ITIM_LENGTH`/
`MPFS_U54_n_ITIM_LENGTH` (just "`DTIM_Ways`, E51 only, else 0" etc.),
and RTS-POLARFIRE.md §11 risk 5 says why: "the L1-I and L1-D way sizes
... still to confirm from the TRM". This crate implements the same
shape as L2 (`Ways * <per-way-size>`) with a **named, clearly-flagged
placeholder** (`L1_Way_Size_Kb` in `runtime_build.gpr`, currently
`"7"`), not a verified hardware constant. Every configuration this
milestone (P1) exercises has `ITIM_Ways = DTIM_Ways = 0`, for which the
placeholder is provably irrelevant. Confirm the real per-way size from
the MSS TRM (RTS-POLARFIRE §11 risk 5) before trusting a nonzero
`MPFS_*_ITIM_LENGTH` / `MPFS_DTIM_LENGTH`.

## Defsym arithmetic, verified

`ld --defsym=SYM=expr` is commonly assumed to support only `+`/`-`
between hex constants or symbols. Measured directly against this
toolchain's `riscv64-elf-ld` (assemble a trivial `_start`, link against
a one-region `MEMORY` script reading back `LENGTH(ram)`/`ORIGIN(ram)`
via `nm`):

| `--defsym` expression | Result |
|---|---|
| `TEST_LENGTH=0x1000` | `0x1000` |
| `TEST_LENGTH=768K` | `0xc0000` (768 * 1024) |
| `TEST_LENGTH=5*0x20000` | `0xa0000` (5 * 0x20000) |
| `TEST_LENGTH=0x20000+0x20000` | `0x40000` |
| `TEST_LENGTH=768` (no prefix) | `0x300` (768 decimal, not octal) |
| `TEST_LENGTH=5*128K` | `0xa0000` (5 * 128 * 1024) |

So `*` and the `K`/`M` size suffix both work, which is what lets
`runtime_build.gpr` compute `Defsyms` as plain GPR string
concatenation (`Ways & "*128K"`, `KB_Value & "K"`) instead of an
enumerated `case` table over every possible `Integer` value.

## Known gaps outside this crate (reported, not fixed here)

Per this task's scope, issues in sibling crates are reported, not
patched:

- **`rts_core_riscv64.gpr` and `rts_support_mpfs.gpr` did not exist** at
  the time this crate was written (no `alire.toml`/`*.gpr` in either
  directory -- only the populated `src/`, `src.lst`, and, for
  `rts_support_mpfs`, `ld/common-RAM.ld.upstream` +
  `ld/memory-map.ld.upstream`). `runtime_build.gpr` `with`s
  `"rts_core_riscv64.gpr"` and `"rts_support_mpfs.gpr"` per CONTRACT.md
  §3.4 verbatim and cannot resolve until those two crates ship the
  `abstract project` CONTRACT.md §2 pins (`Rts_Core_Riscv64.Src_Dir`;
  `Rts_Support_Mpfs.Src_Dir`/`Ld_Dir`).
- **`rts_support_mpfs/ld/` has no `mpfs-memory.ld` and none of the five
  placement scripts** (`mpfs-envm.ld`, `mpfs-lim.ld`,
  `mpfs-lim-lma-scratchpad-vma.ld`, `mpfs-envm-lma-scratchpad-vma.ld`,
  `mpfs-ddr-loaded-by-boot-loader.ld` -- RTS-POLARFIRE §1.3/§6.1) that
  `Linker_Switches` selects among by name. Only the raw vendor
  `.upstream` reference copies exist. Until these are added, any link
  against this runtime fails with `cannot open linker script file
  mpfs-lim.ld` (or whichever profile is selected), regardless of how
  correctly this leaf computes `Placement_Script`.
- **`rts_support_mpfs`'s populated sources are still the stock,
  unmodified `light-polarfiresoc` files** -- `s-bbbopa.ads` hardcodes
  `PLIC_Hart_Id = 1`/`CLINT_Mtimecmp_Offset = 16#4008#` (hart 1) and
  `UART_Base_Address` at MMUART0; `s-textio.adb` reads that constant
  directly. None of them `with MPFS_Runtime_Config` yet. This
  coincidentally still matches `light_mpfs`'s own defaults (`Hart_Class
  => u54`, `Harts => "1"`, `Console => mmuart0`), so the default
  configuration is self-consistent, but no other `Harts`/`Console`
  value is actually honoured by the runtime yet -- that is
  RTS-POLARFIRE.md §8 items 1 and 8, in `rts_support_mpfs`.
- **`rts_sources_gcc15` vendors only one variant of the three
  float-dependent units** (`s-dorepr.adb`, `s-lidosq.adb`,
  `s-lisisq.adb` -- RTS.md §4.3/§9), matching the hard-float U54
  default all three shipped PolarFire runtimes ship. There is no
  soft-float variant of these three files anywhere in this spike's
  populated sources, and CONTRACT.md's pinned `Source_Dirs` list
  (§3.4) has no additional per-`Hart_Class` override directory for
  `light_mpfs` to shadow them from. Building `Hart_Class => e51`
  therefore has no mechanism yet to select the soft-float sources it
  needs.

## Populated, not vendored

Like the three source-only tiers, `src/system.ads` and `src/s-parame.ads`
are copied out of the installed `gnat_riscv64_elf` toolchain by
`../populate.sh` rather than hand-written or vendored (CONTRACT.md §1).
`.gitignore` excludes `*/src/system.ads` and `*/src/s-*.ad[bs]`
crate-wide; `make populate` is a prerequisite for any build.

## Licence

`licenses = "GPL-3.0-or-later WITH GCC-exception-3.1"`, matching every
populated file's own header (Free Software Foundation / AdaCore
copyright) and the three source-only tiers this leaf depends on.
