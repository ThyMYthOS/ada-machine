# rts-spikes — interface contract

**Read this before touching any crate.** Every name below is pinned. Seven crates are built in parallel against this document; if a crate invents its own name for anything here, the set will not compose.

Target: PolarFire SoC, `riscv64-elf`, per [../RTS-POLARFIRE.md](../RTS-POLARFIRE.md). Toolchain: `gnat_riscv64_elf` 15.1.2.

---

## 1. Layout and the sources question

```
rts-spikes/
├── CONTRACT.md              this file
├── Makefile                 populate + build
├── populate.sh              copies runtime sources from the installed toolchain
├── lists/                   partition provenance (generated, committed)
├── rts_sources_gcc15/       tier 1 — source-only
├── rts_core_riscv64/        tier 2 — source-only
├── rts_support_mpfs/        tier 3 — source-only
├── light_mpfs/              leaf — buildable
├── light_tasking_mpfs/      leaf — buildable
├── embedded_mpfs/           leaf — buildable
├── mpfs_system/             generated system description (stand-in)
└── hello_mpfs/              example application
```

**The runtime sources are NOT committed.** Tier 1 alone is 963 + 86 units (~6 MB) of FSF/AdaCore code. Instead each source crate commits a **file list** and `populate.sh` copies the named files out of the installed toolchain. Consequences:

- `make populate` is a prerequisite for any build. A fresh clone does not build.
- The lists are the reviewable artifact — the same role RTS.md §2.1 gives `Source_List_File`.
- A *published* crate would vendor the sources. This is a spike-only shortcut, and it must be stated in each source crate's `README.md`.

Do not commit anything under `*/libgnat/`, `*/libgnarl/` or `*/src/` in the three source crates; `.gitignore` already excludes them.

---

## 2. Source-only crates (tiers 1–3)

These are **never built by Alire**. They need `-gnatg -nostdinc`, the cross compiler and no runtime — a bootstrap cycle. Each ships an `abstract` project that exports only paths.

`alire.toml` — Alire caps `description` at **72 characters** (a longer one is rejected with `Description string is too long (must be no more than 72)`). That field is the one-line summary; put anything fuller in **`long-description`**, which is free-form and is what `alr show` prints in full. Every crate here should have both.

```toml
name = "<crate>"
description = "..."                      # one line, <= 72 characters
long-description = """
... what the crate is, why it is source-only, the populate-not-vendor note ...
"""
version = "0.1.0-dev"
licenses = "GPL-3.0-or-later WITH GCC-exception-3.1"
authors = ["Free Software Foundation", "AdaCore"]
maintainers = ["Manuel Stahl <manuel.stahl@awesome-technologies.de>"]
maintainers-logins = ["thymythos"]
auto-gpr-with = false
project-files = ["<crate>.gpr"]
```

`<crate>.gpr` — **exported variable names are pinned**:

| Crate | Project name | Exports |
|---|---|---|
| `rts_sources_gcc15` | `Rts_Sources_Gcc15` | `Gnat_Dir`, `Gnarl_Dir` |
| `rts_core_riscv64` | `Rts_Core_Riscv64` | `Src_Dir` |
| `rts_support_mpfs` | `Rts_Support_Mpfs` | `Src_Dir`, `Ld_Dir` |

```ada
abstract project Rts_Core_Riscv64 is
   for Source_Dirs use ();
   Src_Dir := Project'Project_Dir & "src";
end Rts_Core_Riscv64;
```

`Project'Project_Dir` already ends in a separator — do **not** add one.

Directory names inside each source crate, also pinned: `rts_sources_gcc15/libgnat/`, `rts_sources_gcc15/libgnarl/`, `rts_core_riscv64/src/`, `rts_support_mpfs/src/`, `rts_support_mpfs/ld/`.

---

## 3. Leaf crates

### 3.1 Manifest

```toml
name = "light_mpfs"                     # or light_tasking_mpfs / embedded_mpfs
licenses = "GPL-3.0-or-later WITH GCC-exception-3.1"
project-files = ["runtime_build.gpr"]   # + "ravenscar_build.gpr" for tasking/embedded

[configuration]
output_dir = "gnat_user"
generate_c = false
```

Tasking leaves additionally declare `provides = ["gnat_rts_tasking=0.1.0"]`. `light_mpfs` must **not** — AVR-style, its floor excludes tasking (RTS.md §4).

### 3.2 Configuration variables — names pinned

| Name | Type | Default |
|---|---|---|
| `Hart_Class` | Enum `e51`, `u54` | `u54` |
| `Harts` | String | `"1"` |
| `Privilege` | Enum `m_mode`, `s_mode` | `m_mode` |
| `Memory_Profile` | Enum `envm`, `lim`, `lim_lma_scratchpad_vma`, `envm_lma_scratchpad_vma`, `ddr_by_bootloader`, `system_partition` | `lim` |
| `L2_Cache_Ways` / `L2_LIM_Ways` / `L2_Scratchpad_Ways` | Integer 0..16 | `1` / `15` / `0` |
| `ITIM_Ways` / `DTIM_Ways` | Integer 0..3 | `0` / `0` |
| `DDR_Present` | Boolean | `false` |
| `DDR_Cached_KB` / `DDR_NonCached_KB` / `DDR_WCB_KB` | Integer | `0` |
| `Console` | Enum `mmuart0`..`mmuart4`, `ram_fifo`, `none` | `mmuart0` |
| `Interrupt_Stack_Size` | Integer | `8192` |
| `Secondary_Stack_Size` | Integer | `2048` |
| `MPFS_PARTITION` | String | `""` (empty = standalone mode) |

Only `light_tasking_mpfs` and `embedded_mpfs` also declare `Max_CPUs`-affecting behaviour; they derive it from `Harts`, they do not add a variable.

### 3.3 The renaming shim

Alire generates `gnat_user/<crate>_config.ads`, whose name embeds the profile. Shared sources cannot `with` a varying name, so **every leaf commits** `gnat_user/mpfs_runtime_config.ads`:

```ada
pragma Restrictions (No_Elaboration_Code);
pragma Style_Checks (Off);
with Light_Mpfs_Config;                              --  per leaf
package MPFS_Runtime_Config renames Light_Mpfs_Config;
```

Tier-3 sources `with MPFS_Runtime_Config` and nothing else. The stable name is `MPFS_Runtime_Config` in all three leaves.

### 3.4 `runtime_build.gpr`

```ada
with "rts_sources_gcc15.gpr";
with "rts_core_riscv64.gpr";
with "rts_support_mpfs.gpr";
with "gnat_user/light_mpfs_config.gpr";

project Runtime_Build is
   for Languages use ("Ada", "Asm_Cpp");      --  + "C" for embedded_mpfs
   for Target use "riscv64-elf";
   for Runtime ("Ada") use Project'Project_Dir;
   for Library_Name use "gnat";
   for Library_Kind use "static";
   for Library_Dir use "adalib";
   for Object_Dir use "obj";

   --  ORDER IS LOAD-BEARING: board shadows core shadows shared (RTS.md §2.1)
   for Source_Dirs use
     ("gnat_user", "src",
      Rts_Support_Mpfs.Src_Dir,
      Rts_Core_Riscv64.Src_Dir,
      Rts_Sources_Gcc15.Gnat_Dir);
   for Source_List_File use "light.lst";
   ...
end Runtime_Build;
```

`src/` holds the leaf-owned units: `system.ads`, `s-parame.ads` (+ `s-parame.adb`, `s-bbpara.ads` for tasking/embedded). Copy them from the corresponding installed runtime; `s-bbpara.ads` must derive `Max_Number_Of_CPUs` from `MPFS_Runtime_Config.Harts`.

`ravenscar_build.gpr` (tasking/embedded only): `Library_Name "gnarl"`, same `Library_Dir "adalib"`, `Source_Dirs` = `("gnarl_user", Rts_Support_Mpfs.Src_Dir, Rts_Core_Riscv64.Src_Dir, Rts_Sources_Gcc15.Gnarl_Dir)`, and it `with`s `runtime_build.gpr`.

### 3.5 Metadata files — committed, relative paths

Sibling path pins make relative entries stable (verified, RTS.md A.4). `ada_source_path`:

```
gnat_user
src
../rts_support_mpfs/src
../rts_core_riscv64/src
../rts_sources_gcc15/libgnat
```

(tasking/embedded append `gnarl_user` and `../rts_sources_gcc15/libgnarl`.) `ada_object_path` is one line: `adalib`. A published crate would generate these — see RTS.md §8 item 1.

### 3.6 `runtime.xml`

ISA switches come from `external()` so the E51/U54 split is a knob (RTS-POLARFIRE §4.2, verified A.16/§9):

```
type Loaders is ("RAM", "USER");
Loader : Loaders := external("LOADER", "RAM");
MPFS_ARCH := external("MPFS_ARCH", "rv64imafdc");
MPFS_ABI  := external("MPFS_ABI",  "lp64d");

package Compiler is
   Common_Required_Switches := ("-march=" & MPFS_ARCH, "-mabi=" & MPFS_ABI,
                                "-fno-tree-loop-distribute-patterns");
   for Leading_Required_Switches ("Ada") use
      Compiler'Leading_Required_Switches ("Ada") & Common_Required_Switches;
   --  ... same for C, C++, Asm, Asm2, Asm_Cpp
end Compiler;

package Linker is
   for Required_Switches use Linker'Required_Switches &
     ("-Wl,-L${RUNTIME_DIR(Ada)}/adalib", "-nostartfiles", "-nolibc",
      "-L${RUNTIME_DIR(ada)}/ld_user", "-L${RUNTIME_DIR(ada)}/ld")
     & Compiler.Common_Required_Switches;
end Linker;
```

`embedded_mpfs` **must** add `"-Wl,--start-group,-lgnarl,-lgnat,-lc,-lgcc,--end-group"` to the Linker switches — without it the link fails with ~30 undefined `memcpy`/`memset` references (RTS.md A.14).

Note `-march=rv64imac` alone fails to assemble the startup: the E51 string is **`rv64imac_zicsr`** (RTS-POLARFIRE §1.1).

### 3.7 Exported GPR variables — the app's interface

Every leaf exports these from `runtime_build.gpr`:

| Variable | Contents |
|---|---|
| `ISA_Switches` | `("-march=" & MPFS_ARCH, "-mabi=" & MPFS_ABI)` |
| `Linker_Switches` | `-T`/`-L` for the selected `Memory_Profile`, plus `Defsyms` |
| `Defsyms` | the `-Wl,--defsym=` list of §4 below |

---

## 4. `--defsym` symbol names — pinned

`ld` accepts symbols for both `ORIGIN` and `LENGTH`, and enforces overflow (verified, RTS.md A.20). `rts_support_mpfs/ld/mpfs-memory.ld` declares literal bases and these symbolic lengths; each leaf computes them from configuration:

| Symbol | From |
|---|---|
| `MPFS_ENVM_LENGTH` | fixed `0x1FF00` |
| `MPFS_DTIM_LENGTH` | `DTIM_Ways`, E51 only, else 0 |
| `MPFS_E51_ITIM_LENGTH` | `ITIM_Ways` if `Hart_Class=e51`, else 0 |
| `MPFS_U54_1_ITIM_LENGTH` … `_U54_4_` | `ITIM_Ways` for the owned hart, else 0 |
| `MPFS_LOCAL_ITIM_ORIGIN` / `_LENGTH` | derived from `Harts` |
| `MPFS_LIM_LENGTH` | `L2_LIM_Ways * 128K` |
| `MPFS_SCRATCHPAD_LENGTH` | `L2_Scratchpad_Ways * 128K` |
| `MPFS_DDR_CACHED_LENGTH` / `_NC_` / `_WCB_` | `DDR_*_KB`, 0 when `DDR_Present` is false |

Region bases (literal, from RTS-POLARFIRE §1.2): envm `0x20220100`, dtim `0x01000000`, e51_itim `0x01800000`, u54_n_itim `0x01808000 + (n-1)*0x8000`, l2lim `0x08000000`, scratchpad `0x0A000000`, ddr_cached `0x80000000`, ddr_nc `0xC0000000`, ddr_wcb `0xD0000000`.

---

## 5. Validation — `pragma Compile_Time_Error`, not subtypes

Subtypes only warn; the pragma is what enforces (RTS.md A.15). Put these in a tier-3 spec that reads `MPFS_Runtime_Config`:

- `Hart_Class = e51` with a hard-float ABI → error (no FPU)
- `Hart_Class = e51` and `Harts /= "0"` → error; `Hart_Class = u54` and hart 0 in the set → error
- `L2_Cache_Ways + L2_LIM_Ways + L2_Scratchpad_Ways /= 16` → error; `L2_LIM_Ways > 15` → error; `L2_Cache_Ways < 1` → error
- `DTIM_Ways /= 0` with `Hart_Class /= e51` → error
- multi-hart `Harts` with `ITIM_Ways /= 0` → error (ITIM is per-hart private)
- `Memory_Profile` needing DDR with `DDR_Present = false` → error

---

## 6. What "done" means per crate

A crate is done when: its `alire.toml` and project file match this contract exactly; `make populate` places its sources; and — for leaves — `alr build` in `hello_mpfs` reaches its stage. Do not weaken the contract to make something build; report the mismatch instead.
