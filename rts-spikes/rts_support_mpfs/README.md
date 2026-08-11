# rts_support_mpfs

Tier-3, source-only board-support crate for the Microchip PolarFire SoC
(E51 monitor + 4x U54, `riscv64-elf`), per [CONTRACT.md](../CONTRACT.md)
and [../RTS-POLARFIRE.md](../RTS-POLARFIRE.md). It is **never built by
Alire** — like `rts_sources_gcc15` and `rts_core_riscv64`, it needs
`-gnatg -nostdinc`, the cross compiler, and no runtime yet selected, a
bootstrap cycle only the three buildable leaves (`light_mpfs`,
`light_tasking_mpfs`, `embedded_mpfs`) complete.

## Populate, don't vendor

The `.ads`/`.adb`/`.S`/`.h` files under `src/` are **not vendored** in
this repository. `make populate` (from the `rts-spikes/` root) copies
them out of the locally installed `gnat_riscv64_elf` 15.1.2 toolchain,
named by the committed `src.lst`. `src/` and `src.lst` are otherwise
untouched here, with one exception: `src/s-bbbopa.ads` (see below) and
the new `src/mpfs_config_checks.ads` are this crate's own, hand-authored
additions, re-applied on top of (`s-bbbopa.ads`) or added alongside
(`mpfs_config_checks.ads`) whatever `populate.sh` places. A fresh clone
does not build until `make populate` has run.

## The L2/L1 split, in two sentences

Every on-chip memory on this SoC — the 2048 KB L2, and each hart's L1-I
(and the E51's L1-D) — is a cache/SRAM split rather than a fixed-size
RAM, so "how much LIM/scratchpad/ITIM/DTIM exists" is configuration
(ways enabled, 0 to N), not a hardware constant; the reset default of
1920 KB LIM and one cache way is what makes `Memory_Profile => lim`
runnable with zero L2 setup. `ld/mpfs-memory.ld` reflects this directly:
every region's `ORIGIN` is a literal (the SoC), every region's `LENGTH`
is a symbol the leaf computes from its configuration and supplies via
`-Wl,--defsym=` (RTS-POLARFIRE.md §1.3, §1.4).

## What changed in the populated sources, and why

- **`src/s-bbbopa.ads`** (`System.BB.Board_Parameters`) — the one file
  this crate's task modifies. Upstream freezes `CLINT_Mtimecmp_Offset`,
  `PLIC_Hart_Id` and `UART_Base_Address` to hart 1 / MMUART0. This
  version `with`s `MPFS_Runtime_Config` (CONTRACT.md §3.3) and derives
  all three from it: `CLINT_Mtimecmp_Offset` becomes a fixed base plus a
  per-hart stride times the configured hart (parsed from
  `MPFS_Runtime_Config.Harts`); `PLIC_Hart_Id` follows the same hart;
  `UART_Base_Address` follows `MPFS_Runtime_Config.Console`. It also
  swaps `pragma No_Elaboration_Code_All` for the non-transitive `pragma
  Restrictions (No_Elaboration_Code)` (CONTRACT.md §7.3): the former
  requires every unit it `with`s to carry it too, and the §3.3 renaming
  shim cannot. See the file's own header comment for what is and is not
  verified about this change (in particular: three downstream
  consumers — `s-bbsuti.adb`, `s-bbripl.adb`, `s-textio.adb` — combine
  these values further inside their own Preelaborate library-level
  constants, and Ada's static-expression rules make that combination
  fail once a value is parsed out of a `String`; confirmed in isolation,
  not re-verified end-to-end here).
- **`src/mpfs_config_checks.ads`** (new) — the CONTRACT.md §5 validation
  spec, as `pragma Compile_Time_Error` (not subtypes, which only warn).
  Named `MPFS_Config_Checks` (flat), not the literally-requested
  `MPFS.Config_Checks` child unit — see the file's own header for why:
  the parent package `MPFS` already belongs to `mpfs_system` (tier 7,
  derived-mode-only), and this crate is tier 3, always present, so
  depending on that parent either duplicates it or leaves it missing in
  every standalone build.
- **`ld/mpfs-memory.ld`, `ld/place-*.ld`** (new) — see below.

## `--defsym` symbols, and which region each feeds

| Symbol | Region | Source (CONTRACT.md §4) |
|---|---|---|
| `MPFS_ENVM_LENGTH` | `envm` | fixed `0x1FF00` |
| `MPFS_DTIM_LENGTH` | `dtim` | `DTIM_Ways`, E51 only, else 0 |
| `MPFS_E51_ITIM_LENGTH` | `e51_itim` | `ITIM_Ways` if `Hart_Class=e51`, else 0 |
| `MPFS_U54_1_ITIM_LENGTH` … `_U54_4_` | `u54_1_itim` … `u54_4_itim` | `ITIM_Ways` for the owning hart, else 0 |
| `MPFS_LOCAL_ITIM_ORIGIN` / `_LENGTH` | `local_itim` | derived from `Harts` (both ORIGIN and LENGTH are symbolic) |
| `MPFS_LIM_LENGTH` | `l2lim` | `L2_LIM_Ways * 128K` |
| `MPFS_SCRATCHPAD_LENGTH` | `scratchpad` | `L2_Scratchpad_Ways * 128K` |
| `MPFS_DDR_CACHED_LENGTH` | `ddr_cached` | `DDR_Cached_KB`, 0 when `DDR_Present` is false |
| `MPFS_DDR_NC_LENGTH` | `ddr_nc` | `DDR_NonCached_KB`, 0 when `DDR_Present` is false |
| `MPFS_DDR_WCB_LENGTH` | `ddr_wcb` | `DDR_WCB_KB`, 0 when `DDR_Present` is false |

Every `ORIGIN` above (`envm` `0x20220100`, `dtim` `0x01000000`, `e51_itim`
`0x01800000`, `u54_n_itim` `0x01808000 + (n-1)*0x8000`, `l2lim`
`0x08000000`, `scratchpad` `0x0A000000`, `ddr_cached` `0x80000000`,
`ddr_nc` `0xC0000000`, `ddr_wcb` `0xD0000000`) is literal, not symbolic —
it is the SoC, not configuration (RTS-POLARFIRE.md §1.2/§1.3).

## Placement scripts

One per non-`system_partition` `Memory_Profile` value (`system_partition`
is generated per-partition by the forked configurator, outside this
crate — RTS-POLARFIRE.md §6.1). Each `INCLUDE mpfs-memory.ld` and is
adapted from the populated `ld/common-RAM.ld.upstream`, keeping every
symbol name that script defines (`__text`, `__rom_end`,
`__eh_frame_hdr`, `__data`, `__data_start`, `__global_pointer$`,
`__data_end`, `__data_words`, `__data_load`, `__bss_start`,
`__interrupt_stack_start`, `__interrupt_stack_end`, `__stack_start`,
`__stack_end`, `_end`, `__heap_start`, `__heap_end`, `__bss_end`,
`__bss_words`) — all of them were preservable, differing only in which
region(s) receive `.text`/`.data`/`.bss`/stack/heap, and whether a
section's LMA and VMA coincide:

| Script | `Memory_Profile` | Code + data region(s) | LMA ≠ VMA? |
|---|---|---|---|
| `place-lim.ld` | `lim` (default) | everything in `l2lim` | no |
| `place-ddr-by-bootloader.ld` | `ddr_by_bootloader` | everything in `ddr_cached` | no |
| `place-envm.ld` | `envm` | code in `envm`; data VMA in `l2lim` | yes, for data only |
| `place-lim-lma-scratchpad-vma.ld` | `lim_lma_scratchpad_vma` | LMA in `l2lim`, VMA in `scratchpad` | yes, for everything loaded |
| `place-envm-lma-scratchpad-vma.ld` | `envm_lma_scratchpad_vma` | LMA in `envm`, VMA in `scratchpad` | yes, for everything loaded |

**`place-envm.ld`'s gap is closed** (RTS-PRODUCTION.md §A6): `src/start-ram.S`
now copies `__data_load .. ` (envm) to `__data_start .. __data_end` (l2lim)
unconditionally, skipping the loop (zero iterations) whenever a profile's
LMA and VMA already coincide — so one startup file serves every script in
the table above with no per-profile variant. Measured under QEMU
(`hello_envm_mpfs`, `../QEMU.md`): a package-level, non-constant `String`
printed correctly at this profile, which is only possible if the copy ran
before it was read.

**Known gap that remains, for the other two:** `place-lim-lma-scratchpad-vma.ld`
and `place-envm-lma-scratchpad-vma.ld` need *everything loaded* — code
included — copied from LMA to VMA before execution can even reach it,
which is a copy-and-jump problem, not a data-initialisation one, and out
of §A6's scope (its two axes are boot medium and boot role, not
execute-from-a-different-address). Those two scripts remain syntactically
complete and link-clean (verified — see below) but not, by themselves,
bootable images.

## What was verified, and how

This crate cannot be built alone (source-only; a leaf compiles it), and
this workspace has no leaf-generated `MPFS_Runtime_Config` to link
against yet. What was checked:

- `ld/mpfs-memory.ld` plus each `ld/place-*.ld` accepted by
  `riscv64-elf-ld` in a trivial link supplying every `--defsym` the
  memory map requires (command and result in the task report).
- `rts_support_mpfs.gpr` loads (`Project'Project_Dir` usage, exported
  `Src_Dir`/`Ld_Dir`).
- `src/mpfs_config_checks.ads`: every `pragma Compile_Time_Error`
  condition was deliberately triggered at least once against a stand-in
  config package shaped like `MPFS_Runtime_Config`, and confirmed to
  report its own message rather than silently no-op (CONTRACT.md §7.4).

Not verified end-to-end in this workspace: `src/s-bbbopa.ads` compiling
against a real, leaf-generated `MPFS_Runtime_Config`, and the three
downstream consumers named above still compiling against the new,
`Harts`-derived values. See that file's header comment and the task
report.
