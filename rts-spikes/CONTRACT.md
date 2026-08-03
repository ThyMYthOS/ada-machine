# rts-spikes — interface contract

**Read this before touching any crate.** Every name below is pinned. Seven crates are built in parallel against this document; if a crate invents its own name for anything here, the set will not compose.

Target: PolarFire SoC, `riscv64-elf`, per [../RTS-POLARFIRE.md](../RTS-POLARFIRE.md). Toolchain: `gnat_riscv64_elf` 15.1.2.

---

## 1. Layout and the sources question

```
rts-spikes/
├── CONTRACT.md              this file
├── Makefile                 populate, build, verify, amp — all five apps
├── populate.sh              TIER 1 ONLY; everything else is owned (§1)
├── lists/                   partition provenance (generated, committed)
│
├── rts_sources_gcc15/       tier 1 — populated, shared by BOTH targets
├── rts_core_riscv64/        tier 2 — owned    riscv64-elf
├── rts_core_cortexm/        tier 2 — owned    arm-eabi
├── rts_support_mpfs/        tier 3 — owned    PolarFire SoC
├── rts_support_pico/        tier 3 — owned    RP2040 + RP2350
│
├── light_mpfs/              leaf — riscv64-elf, light
├── light_tasking_mpfs/      leaf — riscv64-elf, light-tasking
├── embedded_mpfs/           leaf — riscv64-elf, embedded
├── light_tasking_pico/      leaf — arm-eabi,   light-tasking
├── mpfs_system/             generated system description (stand-in)
│
└── hello_mpfs/ clock_switch_e51/ tasking_mpfs/ embedded_app/ hello_rp2040/
                             applications
```

**Two targets, one tree.** There was a separate `rts-spikes-rp2040/` while the
ARM work was exploratory; it is gone. Tier 1 is shared (§7.19), tier 2 and
tier 3 are per-target/per-family, and the leaves sit alongside each other. The
ownership rule is what makes that flat layout workable: only tier 1 is
reproduced from upstream, so nothing else needs a per-spike populate script.

**TIER 1 TRACKS UPSTREAM; EVERYTHING ELSE IS OURS.** This is the ownership rule
the whole layout follows.

*Tier 1 is not committed.* It is ~1050 units of FSF/AdaCore code that is a
snapshot of the compiler's own sources, so `rts_sources_gcc15` commits **file
lists** and `populate.sh` copies the named files out of the installed
toolchains — both of them, since the crate serves two targets — and asserts
that the two agree ([§7.19](#719-one-tier-1-crate-serves-more-than-one-target)).
Consequences: `make populate` is a prerequisite, a fresh clone does not build,
and the lists are the reviewable artifact — the role
[RTS.md §2.1](../RTS.md#21-gpr-source-resolution) gives `Source_List_File`.

*Everything below tier 1 is committed and hand-editable.* Tier 2, tier 3 and
every leaf `src/` are ours: no populate step, no prune, no no-clobber rule. Two
things follow that are worth stating, because both were bought with pain:

- A board file can be **fixed in place** rather than re-derived. The RP2350 half
  of `rts_support_pico` came from a published crate rather than a toolchain,
  which under "populate everything" was a second kind of upstream with nothing
  to assert it against; owned, it is simply ours.
- The leaf prune is **gone**, and with it the defect that deleted a
  correctly-listed hand-authored file three times
  ([§7.12](#712-a-new-unit-must-be-added-to-the-membership-lists-or-it-is-dead-code)).
  Removing the mechanism beat adding a fourth guard to it.

The one exception, marked as such: `rts_sources_gcc15/libgnat-patched/` holds
bodies we own *inside* the tier that syncs. `.gitignore` excludes tier 1's
populated directories and re-admits exactly that one.

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
| `rts_core_cortexm` | `Rts_Core_Cortexm` | `Src_Dir` |
| `rts_support_mpfs` | `Rts_Support_Mpfs` | `Src_Dir`, `Ld_Dir` |
| `rts_support_pico` | `Rts_Support_Pico` | `Src_Dir`, `Rp2040_Dir`, `Rp2350_Dir` |

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
output_dir = "gnat_config"
generate_c = false
```

**Every leaf declares its capability floor**, as a version on one shared virtual
name. The profiles are ordered — `light` ⊆ `light-tasking` ⊆ `embedded`, because
light code compiles unchanged on the profiles above it — so a version expresses
the whole chain and a dependent states a *lower bound*
([RTS.md §4](../RTS.md#4-where-each-axis-falls)):

| Leaf | `provides` |
|---|---|
| `light_mpfs` | `["gnat_rts=1.0.0"]` |
| `light_tasking_mpfs`, `light_tasking_pico` | `["gnat_rts=2.0.0"]` |
| `embedded_mpfs` | `["gnat_rts=3.0.0"]` |

**Changed from the earlier contract**, which said tasking leaves declare
`gnat_rts_tasking=0.1.0` and `light_mpfs` must declare nothing. Silence is
indistinguishable from a crate nobody has classified, and a boolean name throws
away the field that carries the ordering. A library needing tasking now depends on
`gnat_rts = ">=2.0.0"` and accepts `embedded` too.

Only the *declaration* side is exercised here — no crate in this tree constrains a
virtual name, so the `>=` half is untested ([RTS.md §8](../RTS.md#8-open-problems)
item 5).

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

Alire generates `gnat_config/<crate>_config.ads`, whose name embeds the profile. Shared sources cannot `with` a varying name, so **every leaf commits** `src/mpfs_runtime_config.ads`:

```ada
pragma Restrictions (No_Elaboration_Code);
pragma Style_Checks (Off);
with Light_Mpfs_Config;                              --  per leaf
package MPFS_Runtime_Config renames Light_Mpfs_Config;
```

Tier-3 sources `with MPFS_Runtime_Config` and nothing else. The stable name is `MPFS_Runtime_Config` in all three leaves.

It lives in `src/`, not in `gnat_config/`, so generated and hand-written files are never mixed in one directory: `gnat_config/` is wholly Alire's output and wholly gitignored. It is named in the **gnat-side** `Source_List_File` only — the libgnarl project reaches it through `ada_source_path` as an ordinary cross-library reference. That is why there is no gnarl-side configuration directory: the earlier `gnarl_user/` held a byte-identical copy of this file that no `Source_List_File` ever named, so it was never a member of anything. Verified after removal: `mpfs_runtime_config.ali` appears once, under the libgnat object directory, while `s-bbpara.ads` still compiles on the gnarl side.

**On the old names.** These directories were `gnat_user/` and `gnarl_user/` until they were renamed. That spelling came from the runtimes GNAT ships, where `gnat_user`/`gnarl_user`/`ld_user` are hooks for *users* to drop in their own overriding sources. Nothing user-authored goes here — it is generated configuration plus one rename — so the old name asserted the opposite of the truth. The `gnat`/`gnarl` half is kept because it is load-bearing: it says which library project claims the units, and a unit cannot belong to two projects.

### 3.4 `runtime_build.gpr`

```ada
with "rts_sources_gcc15.gpr";
with "rts_core_riscv64.gpr";
with "rts_support_mpfs.gpr";
with "gnat_config/light_mpfs_config.gpr";

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
     ("gnat_config", "src",
      Rts_Support_Mpfs.Src_Dir,
      Rts_Core_Riscv64.Src_Dir,
      Rts_Sources_Gcc15.Gnat_Dir);
   for Source_List_File use "light.lst";
   ...
end Runtime_Build;
```

`src/` holds the leaf-owned units: `system.ads`, `s-parame.ads` (+ `s-parame.adb`, `s-bbpara.ads` for tasking/embedded). Copy them from the corresponding installed runtime; `s-bbpara.ads` must derive `Max_Number_Of_CPUs` from `MPFS_Runtime_Config.Harts`.

`ravenscar_build.gpr` (tasking/embedded only): `Library_Name "gnarl"`, same `Library_Dir "adalib"`, `Source_Dirs` = `("src", Rts_Support_Mpfs.Src_Dir, Rts_Core_Riscv64.Src_Dir, Rts_Sources_Gcc15.Gnarl_Dir)`, and it `with`s `runtime_build.gpr`.

### 3.5 Metadata files — committed, relative paths

Sibling path pins make relative entries stable (verified, RTS.md [A.4](../RTS.md#a4)). `ada_source_path`:

```
gnat_config
src
../rts_support_mpfs/src
../rts_core_riscv64/src
../rts_sources_gcc15/libgnat
```

(tasking/embedded append `../rts_sources_gcc15/libgnarl` — and **not** a gnarl-side configuration directory: there is none.) `ada_object_path` is one line: `adalib`. A published crate would generate these — see [RTS.md §8](../RTS.md#8-open-problems) item 1.

### 3.6 No `runtime.xml` — `target_options.gpr` owns the ISA

There is **no `runtime.xml` in any leaf**, following `avrada_rts`. See [§7.10](#710-there-is-no-runtimexml-target_optionsgpr-owns-the-isa) for
why (and for the retraction of the earlier, wrong reason). `target_options.gpr`
is the single derivation site:

```ada
with "gnat_config/<leaf>_config.gpr";

abstract project Target_Options is
   --  Hart_Class is IMPLIED by the mask: bit 0 is the E51, bits 1..4 the U54s.
   type Hart_Mask_Kind is ("1", "2", "4", "6", "8", "16", "30");
   Hart_Mask : Hart_Mask_Kind := <Leaf>_Config.Harts_Mask;

   type Hart_Class_Kind is ("e51", "u54");
   Hart_Class : Hart_Class_Kind := "u54";
   case Hart_Mask is
      when "1"    => Hart_Class := "e51";
      when others => Hart_Class := "u54";
   end case;

   Arch := "rv64imafdc_zicsr_zifencei";
   Abi  := "lp64d";
   case Hart_Class is
      when "e51" => Arch := "rv64imac_zicsr_zifencei";  --  no FPU
                    Abi  := "lp64";
      when "u54" => null;
   end case;

   ISA_Switches := ("-march=" & Arch, "-mabi=" & Abi);

   --  Must reach applications too, not just the runtime.
   Global_Ada_Switches := ISA_Switches & ("-fno-tree-loop-distribute-patterns");

   ALL_ADAFLAGS := ADAFLAGS & COMFLAGS & ISA_Switches;

   package Builder is
      for Global_Compilation_Switches ("Ada")     use Global_Ada_Switches;
      for Global_Compilation_Switches ("Asm_Cpp") use ISA_Switches;
      --  embedded_mpfs also: ("C") use Global_Ada_Switches;
   end Builder;
end Target_Options;
```

Rules that follow from this:

- No other project may assign `ISA_Switches`; they re-export
  `Target_Options.ISA_Switches`. [§7.10](#710-there-is-no-runtimexml-target_optionsgpr-owns-the-isa) records the leaf that broke this.
- `-gnatg`/`-nostdinc` are **not** in `ALL_ADAFLAGS` (applications reference it);
  each library project adds them as `RTS_ADAFLAGS`/`RTS_GNARL_ADAFLAGS`.
- `embedded_mpfs` **must** add
  `"-Wl,--start-group,-lgnarl,-lgnat,-lc,-lgcc,--end-group"` to
  `Linker_Switches` — without it the link fails with ~30 undefined
  `memcpy`/`memset` references (RTS.md [A.14](../RTS.md#a14)).
- `-march=rv64imac` alone fails to assemble the startup: the E51 string is
  **`rv64imac_zicsr`** (RTS-POLARFIRE §1.1).

### 3.7 Exported GPR variables — the app's interface

Every leaf exports these from `runtime_build.gpr`:

| Variable | Contents |
|---|---|
| `ISA_Switches` | re-exported from `Target_Options`, derived from `Harts_Mask` ([§3.6](#36-no-runtimexml--target_optionsgpr-owns-the-isa)). Must not be reassigned here |
| `Linker_Switches` | `-T`/`-L` for the selected `Memory_Profile`, plus `Defsyms` |
| `Defsyms` | the `-Wl,--defsym=` list of [§4](#4---defsym-symbol-names--pinned) below |

---

## 4. `--defsym` symbol names — pinned

`ld` accepts symbols for both `ORIGIN` and `LENGTH`, and enforces overflow (verified, RTS.md [A.20](../RTS.md#a20)). `rts_support_mpfs/ld/mpfs-memory.ld` declares literal bases and these symbolic lengths; each leaf computes them from configuration:

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

Subtypes only warn; the pragma is what enforces (RTS.md [A.15](../RTS.md#a15)). Put these in a tier-3 spec that reads `MPFS_Runtime_Config`:

- `Hart_Class = e51` with a hard-float ABI → error (no FPU)
- `Hart_Class = e51` and `Harts /= "0"` → error; `Hart_Class = u54` and hart 0 in the set → error
- `L2_Cache_Ways + L2_LIM_Ways + L2_Scratchpad_Ways /= 16` → error; `L2_LIM_Ways > 15` → error; `L2_Cache_Ways < 1` → error
- `DTIM_Ways /= 0` with `Hart_Class /= e51` → error
- multi-hart `Harts` with `ITIM_Ways /= 0` → error (ITIM is per-hart private)
- `Memory_Profile` needing DDR with `DDR_Present = false` → error

---

## 6. What "done" means per crate

A crate is done when: its `alire.toml` and project file match this contract exactly; `make populate` places its sources; and — for leaves — `alr build` in `hello_mpfs` reaches its stage. Do not weaken the contract to make something build; report the mismatch instead.

---

## 7. Resolved blockers — do NOT re-investigate

Every item here was measured. Apply the answer; do not re-derive it. Each cost an agent a large amount of budget the first time.

### 7.1 `Source_List_File` only — never `Excluded_Source_Files`

`Source_List_File` already *restricts* the candidate set to exactly what it names, so there is nothing to subtract. Do not use `Excluded_Source_Files` at all, and never both mechanisms in one project: gprbuild warns `both attributes Excluded_Source_Files and Excluded_Source_List_File are present` and then one **silently wins**, discarding the other.

### 7.2 `Languages` per profile, and no headers in the lists

| Crate | `for Languages use` |
|---|---|
| `light_mpfs` | `("Ada", "Asm_Cpp")` |
| `light_tasking_mpfs` | `("Ada", "Asm_Cpp")` |
| `embedded_mpfs` | `("Ada", "Asm_Cpp", "C")` — it really does compile `raise-gcc.c`, `adaint-xi.c`, `newlib-bb.c`, `unwind-dw2-fde-bb.c` |

`.h` files are includes, not compilable units. Naming one in a `Source_List_File` makes gprbuild classify it and hard-error with `language unknown for "riscv_def.h"`, and exclusion does *not* suppress that. The membership lists have been regenerated with headers stripped (`light` 512, `light-tasking` 601, `embedded` 1053 units). The headers remain on disk in their source directories, where the assembler and C compiler find them by include path.

### 7.3 `s-bbbopa.ads`: swap `No_Elaboration_Code_All` for `Restrictions (No_Elaboration_Code)`

Upstream's `s-bbbopa.ads` carries `pragma No_Elaboration_Code_All`, which propagates **transitively**: every unit it `with`s must carry it too. The `MPFS_Runtime_Config` shim ([§3.3](#33-the-renaming-shim)) is a *renaming*, and a renaming cannot carry that pragma —

```
shim.ads:3:01: error: pragma "No_Elaboration_Code_All" not allowed for renamed package
```

— so the shim can never satisfy it. Measured: `Pure` is not the problem (Alire already generates `pragma Pure` on its config package); `No_Elaboration_Code_All` is.

Fix, with production precedent: replace it with the non-transitive `pragma Restrictions (No_Elaboration_Code);` at the top of the file. That is exactly what damaki's shipped `rp2040` crate does in the same unit for the same reason. Keep `pragma Pure`.

### 7.4 `pragma Compile_Time_Error` silently no-ops on non-static conditions

Measured, both conditions true:

```ada
A_Base : constant := 100;  B_Base : constant := 100;
pragma Compile_Time_Error (A_Base = B_Base, "FLAT");                         --  FIRES
pragma Compile_Time_Error (Windows (A).Base = Windows (B).Base, "INDEXED");  --  SILENT
```

Indexing an array constant or selecting a record component makes the condition non-static. GNAT does not diagnose the mistake — no error, no warning, even under `-gnatwa`. The check simply never fires.

So: **every quantity feeding a check must be a flat, independent named scalar constant.** Build any nicer aggregate view separately, for ordinary non-static consumption. And after writing checks, deliberately break at least two and confirm each reports *your* message — an unexercised check is worse than none, because it reads as assurance.

### 7.5 Leaves need explicit dependencies and pins

CONTRACT [§3.1](#31-manifest)'s snippet is illustrative, not complete. A leaf must also declare, or `with "rts_sources_gcc15.gpr"` will not resolve:

```toml
[[depends-on]]
rts_sources_gcc15 = "*"
rts_core_riscv64  = "*"
rts_support_mpfs  = "*"

[[pins]]
rts_sources_gcc15 = { path = "../rts_sources_gcc15" }
rts_core_riscv64  = { path = "../rts_core_riscv64" }
rts_support_mpfs  = { path = "../rts_support_mpfs" }
```

### 7.6 The source partition changed

18 units differ in **content** between profiles (`a-except`, `a-elchha`, `a-tags`, `a-strsup`, `s-assert`, `s-memory`, `s-taskin`, `s-tpobop`, `s-tposen`, `system.ads`, `s-parame.*`). They are leaf-owned, not tier-1, and `populate.sh` places each leaf's correct variant in its `src/`. Tier 1 is now 952 `libgnat` + 81 `libgnarl`. `lists/profile-variant.lst` records the set.

### 7.7 Two library projects need two source lists

A combined membership list cannot be the `Source_List_File` of two projects with disjoint `Source_Dirs` — gprbuild reports "source file not found" and "unit cannot belong to several projects". The tasking profiles therefore use per-library lists, already generated:

| Crate | `runtime_build.gpr` (libgnat) | `ravenscar_build.gpr` (libgnarl) |
|---|---|---|
| `light_tasking_mpfs` | `light-tasking.gnat.lst` (513) | `light-tasking.gnarl.lst` (88) |
| `embedded_mpfs` | `embedded.gnat.lst` (959) | `embedded.gnarl.lst` (94) |

The combined `*.lst` remains as provenance only. Correction to [§3.4](#34-runtime_buildgpr): `ravenscar_build.gpr` **must** include `"src"` in `Source_Dirs` — six GNARL-side leaf-owned units (`s-bbpara.ads`, `s-taskin.ads`, `s-tpobop.*`, `s-tposen.*`) exist only there.

### 7.8 SUPERSEDED — `Harts` is now an Integer bitmask

Kept for the reasoning. The String form was replaced by
`Harts_Mask = { type = "Integer", first = 1, last = 31 }`: bit N selects hart N,
bit 0 being the E51. Every derived value — `First_Hart` (lowest set bit),
`Hart_Count` (five-term popcount), the CLINT `mtimecmp` offset, `PLIC_Hart_Id`,
`Max_Number_Of_CPUs` — is then an ordinary static named number, usable in the
number declarations and scalar range bounds that the String form could not
satisfy. It also expresses non-contiguous sets, which `First_Hart + Count`
cannot, and the count cannot disagree with the set because it is derived.

Two mechanics worth knowing. A GPR `case` needs a *typed* string variable and
Alire emits Integers untyped, so the leaf declares
`type U54_Mask_Kind is ("1", "2", "4", "8", "16")` — which doubles as
validation, rejecting a multi-hart mask in a single-hart profile with
`value "6" is illegal for typed string`. And "more than one hart" is
`Harts_Mask not in 1 | 2 | 4 | 8 | 16`, not `> 1`: mask 2 is the single hart 1.

The original reasoning follows.

### 7.8.1 Why the `String` form could not work

RM 4.9 makes any value derived from *indexing* a string constant non-static, and a non-static value cannot initialise a library-level constant in a preelaborated unit (`not a static constant (RM 4.9(5))`). Static **equality against a literal** is static, so enumerate the legal spellings instead:

```ada
Max_Number_Of_CPUs : constant :=
  (if    MPFS_Runtime_Config.Harts = "1"    then 1
   elsif MPFS_Runtime_Config.Harts = "1..2" then 2
   elsif MPFS_Runtime_Config.Harts = "1..4" then 4
   else  1);
pragma Compile_Time_Error (<unrecognised>, "unrecognised Harts spelling");
```

**This is a flaw in [§3.2](#32-configuration-variables--names-pinned), not just a workaround.** A hart *set* typed as `String` forces every consumer into literal-matching. A published crate should make `Harts` an `Enum` of the legal sets, so comparison is naturally static and a typo is rejected by Alire rather than by a hand-written pragma. Left as `String` here only because three crates already build against it.

### 7.9 The `e51` + hard-float check of §5 is not implementable as specified

[§5](#5-validation--pragma-compile_time_error-not-subtypes) requires "`Hart_Class = e51` with a hard-float ABI → error". As specified it is
unimplementable: there is no ABI field in `MPFS_Runtime_Config`, so the ABI is
invisible to Ada and no `pragma Compile_Time_Error` can see it.

**The check is no longer needed, because the state it guarded against is now
unrepresentable.** The ABI used to arrive through a separate
`external("MPFS_ABI", ...)` read independently by `runtime.xml` and by the leaf's
`ISA_Switches`, so `Hart_Class => e51` could sit correctly in the generated
config while the compiler received `rv64imafdc`/`lp64d`. Since [§3.6](#36-no-runtimexml--target_optionsgpr-owns-the-isa)/[§7.10](#710-there-is-no-runtimexml-target_optionsgpr-owns-the-isa) there
is exactly one derivation — `Harts_Mask` → `Hart_Class` → `ISA_Switches`, in
`target_options.gpr` — and no `external()` overriding it. A disagreeing pair
cannot be expressed, which is a stronger guarantee than a diagnostic.

Implement it as a documented non-check rather than a pragma that can never fire. The real fix is for `Hart_Class` to *derive* `MPFS_ARCH`/`MPFS_ABI` rather than sit beside them — recorded here as a design gap for RTS-POLARFIRE §5.3.

### 7.10 There is no `runtime.xml`; `target_options.gpr` owns the ISA

**This entry previously said the opposite, and was wrong.** It claimed
`runtime.xml` is "parsed but ineffective" when the runtime is reached through a
withed library project. The real cause was that `light_mpfs/runtime.xml` was
**malformed XML** — a `--` used as an em-dash inside an XML comment, which is
illegal — and **gprconfig silently ignores an unparseable `runtime.xml`**. The
mechanism works fine when the file is valid; `light_tasking_mpfs`'s was valid
all along and its switches were in effect. Full retraction in RTS.md [A.22](../RTS.md#a22).

The files are now **deleted**, following
[`avrada_rts`](https://github.com/RREE/AVRAda_RTS), which ships no `runtime.xml`
at all. The reason is fit, not function: a gprconfig `<config>` fragment cannot
`with` a crate's generated configuration project, so everything in it must
arrive as an `external()`/`-X` — a second source of truth alongside the Alire
configuration variable it duplicates. That is what produced [§7.9](#79-the-e51--hard-float-check-of-5-is-not-implementable-as-specified).

The contract:

- `target_options.gpr` derives `Hart_Class` from `Harts_Mask` **once**, computes
  `ISA_Switches`, and folds them into `ALL_ADAFLAGS`/`ALL_CFLAGS`. Neither
  `runtime_build.gpr` nor `ravenscar_build.gpr` may redefine `ISA_Switches` —
  `light_tasking_mpfs` did, hardcoded to `rv64imafdc`/`lp64d`, which overrode
  the derived value and made that leaf hard-float for every hart mask.
- `target_options.gpr` exports a `Builder` package. Applications **rename** it,
  never restate it:

```ada
package Builder renames Target_Options.Builder;
```

- `Linker_Switches` carries `-nostartfiles`, `-nolibc`, the ISA, and — for
  `embedded_mpfs` only — the `--start-group` set. Deleting
  `light_tasking_mpfs/runtime.xml` broke its link with `cannot find crt0.o` and
  `cannot find -lgloss` until these were restated, proof that its
  `Linker'Required_Switches` had been load-bearing.
- `-gnatg`/`-nostdinc` stay **out** of `ALL_ADAFLAGS`, because applications
  reference it; each library project adds them as `RTS_ADAFLAGS`.
- `-fno-tree-loop-distribute-patterns` must reach applications too, so it lives
  in `Global_Ada_Switches` (the `Builder` package), not in the runtime's own
  switches. Without it GCC may emit a `memcpy`/`memset` call that does not exist
  here. Losing it was the one real regression from deleting the file.

Forgetting the rename is now a **link error**, not a silent miscompile, because
the runtime library's own ABI no longer depends on the application:
`ld: can't link soft-float modules with double-float modules`. Verified by
removing the rename from `clock_switch_e51`.

### 7.11 Per-configuration output directories — a path-pin workaround only

**Do not copy this into a published crate.** A crate Alire *fetches* needs none
of it: Alire builds each release in its own hash-keyed directory under
`~/.local/share/alire/builds/<crate>_<version>_<id>/<build-hash>/`, so two
configurations are already in two places and plain `for Library_Dir use "adalib"`
is correct. `embedded_rp2040` does exactly that.

Verified: building one application against `embedded_rp2040`, then changing a
single configuration value (`Max_CPUs` 2 → 1) and rebuilding, produced a second
build directory beside the first —

```
ab1ed99f021b245db80a2a16df934fb845dd96497ee86d38db490c7ecee18d4e   Max_CPUs = 2
95abe71e90e1ab318a96d93d582660046610678d37b5c3dd65909deda6393ff5   Max_CPUs = 1
```

— with the crate itself using plain `adalib`/`obj`.

The three leaves here are **path-pinned** (`[[pins]]`), so Alire builds them *in
tree* and that isolation does not apply. Everything below exists for that reason
alone. It is also why the object-reuse defect in the next paragraphs was
reachable at all: a pinned runtime crate under development gets weaker build
isolation than its published users will get, which is a trap worth knowing for
anyone iterating on a runtime locally.


Two applications setting different `[configuration.values]` for the same
path-pinned runtime crate shared one `adalib/` and overwrote each other's
library. `runtime_build.gpr` now tags `Library_Dir`/`Object_Dir` with every
configuration variable a compiled unit can read, so the instances coexist:

```
light_mpfs/adalib-e51-0-m_mode-mmuart0-8192-2048-1-15-0-0-1
light_mpfs/adalib-u54-1-m_mode-mmuart0-8192-2048-1-15-0-2-1
```

**The tag must name every variable a COMPILED unit can read.** Getting that
wrong is silent: two configurations differing only in an untagged value share
one `adalib`, and the second reuses the first's objects — including a stale
`mpfs_config_checks.o` whose `Compile_Time_Error` checks were evaluated for the
*other* configuration, so the validation "passes" without ever running. That was
a live defect: `Memory_Profile`, `DDR_Present` and `MPFS_PARTITION` were
excluded as "link-only" while `mpfs_config_checks.ads` reads all three.

Only genuinely link-only values are exempt — they become `-Wl,--defsym=`
arguments and change no object file. They are listed, with reasons, in
`lists/config-tag-exempt.lst`: `DDR_Cached_KB`, `DDR_NonCached_KB`,
`DDR_WCB_KB`, `Main_Stack_Size`.

`populate.sh` enforces this against **Alire's own build-hash input list**
(`<leaf>/alire/build_hash_inputs`, which enumerates every configuration
variable Alire keys a build on): each one must be in `Config_Tag` or in the
exempt list, or the populate fails. A newly added variable therefore forces a
decision instead of defaulting to "untagged". Verified by removing
`Memory_Profile` from the tag: `MISSING from light_mpfs Config_Tag:
memory_profile`.

**Why not use Alire's hash directly?** Because it is not reachable. `alr`
computes it (`Alire.Roots.Build_Hash`) and writes the inputs file, but never
exports it to GPR: `External ("ALIRE_BUILD_HASH", "default")` yields the literal
`"default"`, which would put *every* configuration in one `adalib-default` — the
same bug, total and undetectable. Verified directly. Exporting the hash as a
scenario variable would delete this whole hand-maintained mechanism, and is
worth asking Alire for. Two notes: `Config_Tag` must be declared *after*
`Hart_Class` (it starts with it), and `ada_object_path` may keep naming plain
`adalib` even though `Library_Dir` is `adalib-<tag>` — a stale entry is
tolerated because the withed library project is authoritative (§1.1). The link
line does show a harmless `-L …/adalib/` for the directory that does not exist.

### 7.12 A new unit must be added to the membership lists or it is dead code

`mpfs_config_checks.ads` was authored by hand, so the lists — generated from the
toolchain's own unit set — did not name it. It was therefore never compiled, and
all of its `pragma Compile_Time_Error` checks were **dead code that looked like
assurance**: builds passed with configurations the checks were written to reject.

Adding it to each leaf's `Source_List_File` immediately caught a real
misconfiguration that had been sitting in the tree — `hello_mpfs` carried
`DTIM_Ways = 1` on a U54, and DTIM is E51-only.

So the [§7.4](#74-pragma-compile_time_error-silently-no-ops-on-non-static-conditions) rule needs a companion: proving a check fires is not only about the
condition being static, it is also about the unit being *compiled*. Verify by
breaking the data and watching the message appear.

### 7.13 Derive what is implied; keep application policy out of the runtime

Two configuration variables were removed after the spike built, for the same
reason the `Harts` string became a mask: **a value that is implied should be
derived, not configured alongside what implies it.**

- **`Hart_Class` is implied by `Harts_Mask`** — bit 0 is the E51, bits 1..4 the
  U54s. It is now derived in `runtime_build.gpr`. That deletes two
  `Compile_Time_Error` checks outright ("e51 requires mask 1", "hart 0 cannot be
  in a U54 mask"): they existed *only* to catch the two disagreeing, and a
  disagreement is no longer representable. What survives is the check that a
  mask must not mix the soft-float E51 with the hard-float U54s, which is a real
  hardware constraint rather than a bookkeeping one.

  GPR has no conditional expression, so the derivation is a `case` on the typed
  mask variable, and both must be declared at the top of the project — before
  `Config_Tag` and the ISA derivation use them.

- **`Switch_Code_Bytes` was too specific to be runtime configuration.** How much
  DTIM to reserve for a memory-reconfiguration routine is application policy;
  the runtime only declares that the region *may* exist. `MPFS_SWITCH_CODE_LENGTH`
  is therefore optional in `mpfs-memory.ld` —
  `DEFINED (MPFS_SWITCH_CODE_LENGTH) ? ... : 0`, the same idiom the placement
  scripts already use for `__stack_size` — and the application supplies it from
  its own `package Linker`. Leaving it undefined is not an error, it just yields
  a zero-length region, so an accidental placement fails the link.

Net effect on `light_mpfs`: 15 configuration variables instead of 17, two fewer
checks, and two fewer ways for two settings to contradict each other.

### 7.14 The runtime declares regions; applications declare sections

The runtime's linker scripts may declare **MEMORY regions** — what the SoC has,
and where — plus the output sections the runtime needs for **its own** code and
data. They must not declare sections for what an *application* chooses to put in
tightly-integrated memory. A section name is an application convention, not
hardware.

An earlier version of this spike got that wrong twice over: `mpfs-memory.ld`
declared a `switch_code_dtim` region and `place-lim.ld` defined `.switch_code`,
`.itim_text` and `.dtim_data`. "Switch code" is an application concept; so is
every one of those section names.

**Mechanism.** Each placement script ends its `SECTIONS` with

```
  INCLUDE app-sections.ld
```

`rts_support_mpfs/ld/app-sections.ld` is empty. An application that needs to
place code or data in ITIM/DTIM ships its own `ld/app-sections.ld` and puts its
own `-L` **ahead** of the runtime's — `ld` searches `-L` paths for `INCLUDE`, so
the application's file wins:

```ada
for Switches ("Ada") use
  ("-L", Project'Project_Dir & "ld") &        --  ours first
  Runtime_Build.Linker_Switches & Runtime_Build.Defsyms & ("-Wl,--gc-sections");
```

Verified both directions: with only the runtime's `-L` the image has no
application sections; with the application's `-L` first its section appears at
the intended address.

**`INSERT AFTER` does not work here.** It augments `ld`'s *default* script only,
not a user script supplied with `-T`, and fails with `.text not found for
insert`. That was the first thing tried.

**What this deleted**, beyond the misplaced concept: the `switch_code_dtim`
region, the two-region DTIM split with its `ld` arithmetic, and the silent
region-overlap hazard that split created — it no longer has anything to overlap.
`Switch_Code_Bytes` and `MPFS_SWITCH_CODE_LENGTH` are gone entirely rather than
merely relocated.

### 7.15 Tier 1 is NOT a flat union — profiles need different *content*

`Source_List_File` names basenames. It cannot choose between two different
versions of the same basename, and **eighteen units differ in content between the
three profiles**. One directory cannot serve all three.

Symptom: `light_tasking_mpfs` compiled all ~600 units of both libraries and then
failed to bind, wanting `a-sttebu`, then `a-stuten`, then `s-putima` — the Ada
2022 `Put_Image` chain that the `light-tasking` profile deliberately excludes.

Cause: over a union directory, a non-embedded build compiles **embedded's**
variant of a content-variant unit. `a-strsup` is the clearest case —

| `a-strsup` variant | `Put_Image` mentions, `.ads` / `.adb` |
|---|---|
| `light`, `light-tasking` | 1 / **0** |
| `embedded` | 2 / **4** |

— so the embedded text genuinely uses `Put_Image`, the chain it needs is on the
source path but not in the profile's `Source_List_File`, and the failure lands at
bind time rather than at compile time.

**What this is NOT: a visibility effect.** An earlier version of this entry
claimed GNAT's configurable-runtime logic enables features from what is merely
*visible* on the source path. Tested directly on a pristine tree —
`libgnat-embedded` added to `light_mpfs`'s `Source_Dirs` **and**
`ada_source_path`, `a-sttebu`/`a-stuten`/`s-putima` confirmed reachable and
present nowhere else, rebuilt from an empty object directory — the build
succeeded and produced a **byte-identical** binary (`text 1340, bss 65541`), with
none of the three units in the ALI. With the right variant in place, another
profile's units being visible costs nothing.

The earlier diagnosis rested on "leaf's `a-strsup` md5 == upstream's, so the
sources are not the variable". **That check is unsound in a union layout**:
duplicate basenames resolve by `Source_Dirs` order and no error is reported
([§3.4](#34-runtime_buildgpr)), so the file inspected need not be the file
compiled. Verify the artifact — the `.ali` dependency list — not the candidate.

**Structure.** Tier 1 ships the units *common to all profiles* plus a per-profile
overlay, and a leaf lists its overlay **before** the common directory:

| Directory | Units | Mounted by |
|---|---|---|
| `libgnat` | 479 | all three |
| `libgnat-light` | 21 | light **and** light-tasking (§7.16) |
| `libgnat-embedded` | 462 — exception propagation and the image machinery | embedded |
| `libgnarl` | 72 | light-tasking and embedded |
| `libgnarl-embedded` | 9 | embedded |

There is **no `libgnarl-light-tasking`**. Its three units — `s-restri.ads/.adb`,
`s-rident.ads` — are not content variants: they are byte-identical to embedded's
copies and differ only in *which library claims them*, gnarl-side for
light-tasking and gnat-side for embedded (`embedded.gnat.lst` names them).
Nothing needs an overlay to express that, because `Source_List_File` already
decides membership per project. Verified by merging them into `libgnarl`: all
four applications rebuild byte-identically, and no project's source path gains a
duplicate basename.

`ada_source_path` needs the same ordering. Duplication stays small: the embedded
overlay is large because that profile genuinely has far more units, not because
anything is copied twice.

**Corollary: `populate.sh` must PRUNE, not just copy.** This survives the
correction above, and is if anything more important under it: a file left from an
earlier layout is a *wrong-variant* file sitting where the right one belongs, and
`Source_Dirs` order will silently prefer whichever comes first. Copying alone is
not idempotent. Pruning is restricted to lists: leaf and tier-3 `src/` dirs also
hold hand-authored files no membership list names, which is why the leaf prune
consults `lists/leaf-keep.lst` — an unrestricted prune once deleted
`mpfs_config_checks.ads`.

**This qualifies RTS.md's tier-1 claim.** The snapshot is *not* "identical for
every target on earth": it has a second axis, the runtime profile, for the 18
content-variant units of [§7.6](#76-the-source-partition-changed).

### 7.16 Overlays are keyed by content, not by profile name

[§7.15](#715-tier-1-is-not-a-flat-union--profiles-need-different-content) requires per-profile overlays. It does **not** require one overlay *per
profile*: two profiles that agree on every unit they vary can mount the same
directory. Measured on this toolchain, `light` and `light-tasking` agree on all
of them, so `libgnat-light-tasking` held a second byte-identical copy of
`libgnat-light` — 11 files duplicated for no content reason.

The rule, which also decides where a profile-variant unit lives:

> An overlay exists to resolve a **content disagreement** under one basename.
> A unit belongs in a **shared overlay** when two or more profiles agree on its
> content, stays **leaf-owned** only when every profile differs, and belongs in
> the **common directory** when the profiles do not disagree at all — even if
> only some of them compile it.

The last clause is the one that is easy to get backwards. A unit that exists in
only one profile, or that different profiles file under different *libraries*,
needs no overlay: `Source_List_File` already decides membership per project, and
a unit merely present on the source path but named by no list is inert
([§7.15](#715-tier-1-is-not-a-flat-union--profiles-need-different-content)).
`libgnarl-light-tasking` was such a case and no longer exists.

Applying it removed 21 of 42 physical files with no content lost:

| | before | after |
|---|---|---|
| `libgnat-light` + `libgnat-light-tasking` | 11 + 11 (identical) | 21, one directory |
| the 10 units `light` and `light-tasking` share, per leaf | 10 + 10 in leaf `src/` | in the shared overlay |
| `light_mpfs/src` | 14 files | 4 |
| `light_tasking_mpfs/src` | 21 files | 11 |

`s-memory` is the case that shows why the spec and the body must be placed
**independently**: `s-memory.ads` is identical across `light`/`light-tasking`
and moves to the shared overlay, while `s-memory.adb` differs in all three and
stays leaf-owned. A unit is not an indivisible placement decision.

Two guards make this safe rather than merely smaller, and both are in
`populate.sh`:

1. **`assert_identical`** re-checks, on every populate, that the profiles
   sharing an overlay still agree byte-for-byte, and fails with instructions to
   split the overlay again if a toolchain update breaks it. The sharing is a
   measured fact about GCC 15, not a guarantee.
2. **Leaf `src/` is now pruned** against its own lists plus `lists/leaf-keep.lst`.
   This is what makes a move *take effect*: leaf `src/` precedes the overlay in
   `Source_Dirs`, so a left-behind copy still wins and the move would silently
   do nothing — the leaf-level form of [§7.15](#715-tier-1-is-not-a-flat-union--profiles-need-different-content)'s visibility hazard.

**What deliberately stays duplicated.** `s-parame.ads`, `s-parame.adb` and
`s-bbpara.ads` are identical in `light-tasking` and `embedded`. A shared
"tasking family" overlay would save three files and cost a directory, and
`s-bbpara.ads` is hand-edited *and committed* — moving it into
`rts_sources_gcc15` would stop it being tracked, since that crate is gitignored
in full. They stay duplicated, but `populate.sh` now compares them and fails on
divergence, so the drift that duplication invites is caught rather than assumed
away.

### 7.17 One directory may feed two different libraries

`librestrictions` holds `s-restri.ads/.adb` and `s-rident.ads`. These are not a
profile variant of anything: the text is byte-identical everywhere. What varies
is **which library claims them** — `libgnarl` for light-tasking, `libgnat` for
embedded.

That needs no duplication, because `Source_List_File` decides membership *per
project*. Both `light_tasking_mpfs/ravenscar_build.gpr` and
`embedded_mpfs/runtime_build.gpr` mount the one directory; each leaf's list
names the three units on exactly one side; the other project sees them and does
not select them. Verified: the same source compiles into `libgnarl.a` for
light-tasking and into `libgnat.a` for embedded, all four applications rebuild
byte-identically, and no project's resolved source path gains a duplicate
basename.

This is worth stating as a rule because the intuition runs the other way:

> A directory in tier 1 is **not** owned by a library. It is a set of sources.
> Which library a unit ends up in is a property of the *leaf's list*, not of
> where the file sits.

`populate.sh` asserts the two vendor copies (`light-tasking/gnarl` and
`embedded/gnat`) are byte-identical and fails if a toolchain update breaks that,
exactly as for the shared `libgnat-light` overlay ([§7.16](#716-overlays-are-keyed-by-content-not-by-profile-name)).

### 7.18 To audit what is really in the runtime, read the `.ali` files

Nothing in the project files is evidence. `Source_Dirs` says where gprbuild
*looked*, `Source_List_File` says what it was *allowed* to select, and duplicate
basenames resolve by directory order **with no diagnostic**
([§3.4](#34-runtime_buildgpr)). None of those tell you which file was compiled.

The `.ali` files do, and they are the only artifact that does:

| Line | Answers |
|---|---|
| `U` | which unit this is |
| `D` | every source file it depended on, **with timestamp and checksum** |
| `A` | the exact switches it was compiled with, including `--RTS=` |

So, to establish what a runtime actually contains:

```
ls adalib-<tag>/*.ali | wc -l        # units actually in the library
grep '^D ' adalib-<tag>/<unit>.ali   # the sources really used, with checksums
grep '^A ' adalib-<tag>/<unit>.ali   # the switches really applied
```

This is not a style preference. Two conclusions in this spike were wrong because
a *candidate* source file was inspected instead of the compiled artifact: the
`a-strsup` md5 check of [§7.15](#715-tier-1-is-not-a-flat-union--profiles-need-different-content),
which in a union layout could not have been the file compiled, and an ISA claim
read from a linked ELF whose attributes `ld` had merged across all inputs. In
both cases the `.ali` would have given the answer immediately. For a
certification reader asking "show me exactly what is in this runtime", the
`Source_List_File` is the *claim* and the set of `.ali` files is the *evidence*.

### 7.19 One tier-1 crate serves more than one target

`rts_sources_gcc15` is shared by `arm-eabi` and `riscv64-elf`. It was two crates
until measurement: of the units the two toolchains have in common, **339 of 343
libgnat and 66 of 67 libgnarl are byte-identical**. The snapshot is keyed to the
GCC release, not to the target — which is consistent with the crate depending on
no compiler crate at all (each leaf declares its own).

Three mechanisms carry the difference, in increasing cost:

1. **Membership.** A unit only one target compiles needs no overlay and no copy:
   it sits in the common directory and the other target's `Source_List_File`
   simply never names it, which is inert ([§7.17](#717-one-directory-may-feed-two-different-libraries)).
   That covers 122 of the 136 RISC-V-only units — 128-bit integer and
   packed-array support a 32-bit target cannot use.
2. **Overlay pairs**, where two targets genuinely disagree on one basename.
   Neither member sits in a common directory and a leaf mounts exactly one:
   `libgnat-32`/`libgnat-64` (word size), `libgnat-textio`/`libgnat-semihosting`
   (console), `libgnarl-sp`/`libgnarl-smp` (multiprocessor support).
3. **An in-body test**, where the variation is per-file rather than per-target —
   `libgnat-patched`, see [§7.16](#716-overlays-are-keyed-by-content-not-by-profile-name)
   and the Patched_Dir comment in `rts_sources_gcc15.gpr`.

**Board units belong to tier 3, never here.** `s-bbbosu.*`, `a-intnam.ads`,
`s-macres.*` and `s-textio.*` were in tier 1 *and* in tier 3 for PolarFire,
resolved silently by `Source_Dirs` order. The merge exposed it by making an ARM
build compile PolarFire's Board_Support and fail on `System.Bb.Riscv_Plic is not
a predefined library unit`. `populate.sh` asserts both halves — the gnarl guard
was missing at first, and that is exactly where the duplication hid.

**The guards are the point.** Four `assert_identical` calls run on every
populate: libgnat and libgnarl across targets, libgnat-light across profiles,
and librestrictions across the library split. Sharing is a measured fact about
one toolchain, not a guarantee; when a compiler release breaks it, the populate
fails with instructions rather than a silently wrong build.
