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
maintainers = ["Manuel Stahl <thymythos@googlemail.com>"]
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

### 3.6 No `runtime.xml` — `target_options.gpr` owns the ISA

There is **no `runtime.xml` in any leaf**, following `avrada_rts`. See §7.10 for
why (and for the retraction of the earlier, wrong reason). `target_options.gpr`
is the single derivation site:

```ada
with "gnat_user/<leaf>_config.gpr";

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
  `Target_Options.ISA_Switches`. §7.10 records the leaf that broke this.
- `-gnatg`/`-nostdinc` are **not** in `ALL_ADAFLAGS` (applications reference it);
  each library project adds them as `RTS_ADAFLAGS`/`RTS_GNARL_ADAFLAGS`.
- `embedded_mpfs` **must** add
  `"-Wl,--start-group,-lgnarl,-lgnat,-lc,-lgcc,--end-group"` to
  `Linker_Switches` — without it the link fails with ~30 undefined
  `memcpy`/`memset` references (RTS.md A.14).
- `-march=rv64imac` alone fails to assemble the startup: the E51 string is
  **`rv64imac_zicsr`** (RTS-POLARFIRE §1.1).

### 3.7 Exported GPR variables — the app's interface

Every leaf exports these from `runtime_build.gpr`:

| Variable | Contents |
|---|---|
| `ISA_Switches` | re-exported from `Target_Options`, derived from `Harts_Mask` (§3.6). Must not be reassigned here |
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

Upstream's `s-bbbopa.ads` carries `pragma No_Elaboration_Code_All`, which propagates **transitively**: every unit it `with`s must carry it too. The `MPFS_Runtime_Config` shim (§3.3) is a *renaming*, and a renaming cannot carry that pragma —

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

CONTRACT §3.1's snippet is illustrative, not complete. A leaf must also declare, or `with "rts_sources_gcc15.gpr"` will not resolve:

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

The combined `*.lst` remains as provenance only. Correction to §3.4: `ravenscar_build.gpr` **must** include `"src"` in `Source_Dirs` — six GNARL-side leaf-owned units (`s-bbpara.ads`, `s-taskin.ads`, `s-tpobop.*`, `s-tposen.*`) exist only there.

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

**This is a flaw in §3.2, not just a workaround.** A hart *set* typed as `String` forces every consumer into literal-matching. A published crate should make `Harts` an `Enum` of the legal sets, so comparison is naturally static and a typo is rejected by Alire rather than by a hand-written pragma. Left as `String` here only because three crates already build against it.

### 7.9 The `e51` + hard-float check of §5 is not implementable as specified

§5 requires "`Hart_Class = e51` with a hard-float ABI → error". As specified it is
unimplementable: there is no ABI field in `MPFS_Runtime_Config`, so the ABI is
invisible to Ada and no `pragma Compile_Time_Error` can see it.

**The check is no longer needed, because the state it guarded against is now
unrepresentable.** The ABI used to arrive through a separate
`external("MPFS_ABI", ...)` read independently by `runtime.xml` and by the leaf's
`ISA_Switches`, so `Hart_Class => e51` could sit correctly in the generated
config while the compiler received `rv64imafdc`/`lp64d`. Since §3.6/§7.10 there
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
all along and its switches were in effect. Full retraction in RTS.md A.22.

The files are now **deleted**, following
[`avrada_rts`](https://github.com/RREE/AVRAda_RTS), which ships no `runtime.xml`
at all. The reason is fit, not function: a gprconfig `<config>` fragment cannot
`with` a crate's generated configuration project, so everything in it must
arrive as an `external()`/`-X` — a second source of truth alongside the Alire
configuration variable it duplicates. That is what produced §7.9.

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

### 7.11 Per-configuration output directories

Two applications setting different `[configuration.values]` for the same
path-pinned runtime crate shared one `adalib/` and overwrote each other's
library. `runtime_build.gpr` now tags `Library_Dir`/`Object_Dir` with every
configuration variable a compiled unit can read, so the instances coexist:

```
light_mpfs/adalib-e51-0-m_mode-mmuart0-8192-2048-1-15-0-0-1
light_mpfs/adalib-u54-1-m_mode-mmuart0-8192-2048-1-15-0-2-1
```

Link-only values (`Memory_Profile`, `DDR_*`, `Main_Stack_Size`,
`Switch_Code_Bytes`) are excluded deliberately — they change the linker
invocation, not the library. Two notes: `Config_Tag` must be declared *after*
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

So the §7.4 rule needs a companion: proving a check fires is not only about the
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

### 7.15 Tier 1 is NOT a flat union — GNAT keys off *visibility*

The single most consequential finding of the spike. `Source_List_File` controls
what gets compiled **into** the library; it does **not** control which units are
*visible on the source path*, and GNAT's configurable-runtime logic decides which
language features are available from **visibility**.

Symptom: `light_tasking_mpfs` compiled all ~600 units of both libraries and then
failed to bind, wanting `a-sttebu`, then `a-stuten`, then `s-putima` — the Ada
2022 `Put_Image` chain that the `light-tasking` profile deliberately excludes.

Proved by elimination. Reading the switches from our own generated `a-strsup.ali`
and upstream's showed them **identical** apart from the `--RTS=` path (same
`-O2 -gnatA -gnatg -gnatp -gnatn2 -march=…`) — Alire already builds dependencies
as Release, so an earlier guess about a "development profile leak" was wrong. With
switches and sources identical, the only remaining variable was the source path.
Hiding `s-putima`, `a-sttebu` and `a-stuten` made the entire cascade vanish.

**Structure.** Tier 1 ships the units *common to all profiles* plus a per-profile
overlay, and a leaf lists its overlay **before** the common directory:

| Directory | Units |
|---|---|
| `libgnat` | 479 (common) |
| `libgnat-light`, `libgnat-light-tasking` | 11 each |
| `libgnat-embedded` | 462 — exception propagation and the image machinery |
| `libgnarl` | 69 (common) |
| `libgnarl-light-tasking`, `libgnarl-embedded` | 3, 9 |

`ada_source_path` needs the same ordering. Duplication stays small: the embedded
overlay is large because that profile genuinely has far more units, not because
anything is copied twice.

**Corollary: `populate.sh` must PRUNE, not just copy.** A file left behind from an
earlier layout stays *visible*, so copying alone is not idempotent — a stale
embedded-only unit silently re-enables `Put_Image` in a light build. Pruning is
restricted to the tier-1 directories: leaf and tier-3 `src/` dirs hold
hand-authored files no list names, and an unrestricted prune deleted
`mpfs_config_checks.ads`.

**This qualifies RTS.md's tier-1 claim.** The snapshot is *not* "identical for
every target on earth": it has a second axis — the runtime profile — for
visibility as well as for the 18 content-variant units of §7.6.
