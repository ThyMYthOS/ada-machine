# light_mpfs

Leaf crate of the rts-spikes hierarchy (see [../CONTRACT.md](../CONTRACT.md) §3
and [../RTS-POLARFIRE.md](../RTS-POLARFIRE.md)): the buildable "light"
(no-tasking) Ada runtime for Microchip PolarFire SoC, `riscv64-elf`.

## What this crate is

`light_mpfs` owns `for Runtime ("Ada") use Project'Project_Dir;` and
produces `adalib/libgnat.a` (RTS.md §1). It contributes no runtime
sources of its own beyond `src/mpfs_runtime_config.ads` (the
configuration renaming shim, CONTRACT.md §3.3) and `src/system.ads` +
`src/s-parame.ads`
(leaf-owned, populated by `../populate.sh`); every other compiled unit
comes from the three source-only tiers it depends on
(`rts_sources_gcc15`, `rts_core_riscv64`, `rts_support_mpfs`).

It is the critical-path leaf of this spike (CONTRACT.md §3.1): the only
one of the three that must build in the first milestone, because it has
no tasking floor to clear (RTS.md §4, matching AVR's `light` floor).

It declares `provides = ["gnat_rts=1.0.0"]` — the bottom of the ordered
capability scale (1 light, 2 light-tasking, 3 embedded). It declares the
floor it *does* satisfy rather than staying silent, because silence is
indistinguishable from a leaf nobody has classified. A library requiring
`gnat_rts = ">=2.0.0"` will not resolve against this leaf, which is the
guarantee the earlier "declare nothing" rule was trying to express.

`Source_Dirs` order is load-bearing (RTS.md §2.1): `gnat_config`/`src`
(this leaf) shadow `rts_support_mpfs` (board) shadow `rts_core_riscv64`
(core) shadow `rts_sources_gcc15` (shared). `Source_List_File =>
"light.lst"` (513 units) is the reviewable membership manifest;
shadowing only resolves per-unit variant collisions, never membership.

## Two modes (RTS-POLARFIRE.md §5)

- **Standalone mode** (`MPFS_PARTITION = ""`, the default): a
  single-partition image with no system description. `Hart_Class`,
  `Harts`, `Memory_Profile` and the rest of the table below are
  authored by hand in the application's `[configuration.values]`. This
  is the only mode this milestone (P1) exercises, and needs no
  `mpfs_system` / generator run at all.
- **Derived mode** (`MPFS_PARTITION` set to a partition name): hart
  set, memory window, console, clocks, privilege and PMP all come from
  the (not yet implemented, RTS-POLARFIRE.md §4, phase P4) `mpfs_system`
  crate instead, generated from the vendor's MSS Configurator XML and
  the HSS payload YAML. The knobs below become **outputs** in this mode.
  `Memory_Profile => system_partition` selects the corresponding
  generated `partition-<MPFS_PARTITION>.ld` instead of one of the five
  committed placement scripts.

## Configuration variables (CONTRACT.md §3.2 -- names pinned)

| Variable | Type | Default | Notes |
|---|---|---|---|
| `Hart_Class` | Enum `e51`, `u54` | `u54` | Drives `Defsyms` ITIM/DTIM ownership only -- does not by itself change `-march`/`-mabi` (see task report, "two independent ISA knobs") |
| `Harts` | String | `"1"` | Single hart number for this leaf (`"0"` e51, `"1"`.."4" u54); SMP is `light_tasking_mpfs`/`embedded_mpfs`'s concern |
| `Privilege` | Enum `m_mode`, `s_mode` | `m_mode` | Declared per contract; not yet consumed (S-mode is RTS-POLARFIRE §8 item 7 / phase P5) |
| `Memory_Profile` | Enum `envm`, `lim`, `lim_lma_scratchpad_vma`, `envm_lma_scratchpad_vma`, `ddr_by_bootloader`, `system_partition` | `lim` | Selects the `-T` placement script from `rts_support_mpfs/ld/` |
| `L2_Cache_Ways` | Integer 0..16 | `1` | Sum-to-16 check belongs in a tier-3 spec (CONTRACT.md §5), not this leaf |
| `L2_LIM_Ways` | Integer 0..16 | `15` | Feeds `MPFS_LIM_LENGTH = L2_LIM_Ways * 128K` |
| `L2_Scratchpad_Ways` | Integer 0..16 | `0` | Feeds `MPFS_SCRATCHPAD_LENGTH` |
| `ITIM_Ways` | Integer 0..3 | `0` | Feeds the owned hart's `MPFS_*_ITIM_LENGTH`; per-way KB size is an unconfirmed placeholder (see task report) |
| `DTIM_Ways` | Integer 0..3 | `0` | E51 only; feeds `MPFS_DTIM_LENGTH`, same caveat |
| `DDR_Present` | Boolean | `false` | Gates all three DDR lengths to `0` when false |
| `DDR_Cached_KB` | Integer | `0` | Feeds `MPFS_DDR_CACHED_LENGTH` |
| `DDR_NonCached_KB` | Integer | `0` | Feeds `MPFS_DDR_NC_LENGTH` |
| `DDR_WCB_KB` | Integer | `0` | Feeds `MPFS_DDR_WCB_LENGTH` |
| `Console` | Enum `mmuart0`..`mmuart4`, `ram_fifo`, `none` | `mmuart0` | Declared per contract; not yet consumed -- `s-textio.adb` still hardcodes MMUART0 (RTS-POLARFIRE §8 item 8, in `rts_support_mpfs`) |
| `Interrupt_Stack_Size` | Integer | `8192` | Declared per contract; not consumed by this profile -- `light_mpfs` has no `s-bbpara.ads` |
| `Secondary_Stack_Size` | Integer | `2048` | Declared per contract; not consumed by this profile -- `light`'s `s-parame.ads` has no body and hardcodes its own default, matching stock `light-polarfiresoc` |
| `MPFS_PARTITION` | String | `""` | Empty = standalone mode above; only meaningful with `Memory_Profile => system_partition` |

## Exported GPR variables (CONTRACT.md §3.7)

`runtime_build.gpr` exports `ISA_Switches`, `Linker_Switches` and
`Defsyms`. A consuming application adds all three itself:

```ada
for Target use Runtime_Build'Target;
for Runtime ("Ada") use Runtime_Build'Runtime ("Ada");
package Linker is
   for Switches ("Ada") use
     Runtime_Build.Linker_Switches & Runtime_Build.Defsyms;
end Linker;
```

`Linker_Switches` deliberately does not already include `Defsyms` -- the
consumer concatenates both.

## Populated, not vendored

`src/system.ads` and `src/s-parame.ads` are copied out of the installed
`gnat_riscv64_elf` toolchain by `../populate.sh` (CONTRACT.md §1), like
the three source-only tiers. `make populate` is a prerequisite for any
build.

## Licence

`licenses = "GPL-3.0-or-later WITH GCC-exception-3.1"`, matching every
populated file's own header and the three tiers this leaf depends on.

## Status

See the task report for the full build-verification transcript,
including the not-yet-resolved cross-crate findings (missing
`rts_support_mpfs` packaging/ld scripts at the time of writing, a
`rts_sources_gcc15` source-selection bug, and a GPR
`Excluded_Source_Files` interaction) that currently prevent a complete
`adalib/libgnat.a` build.
