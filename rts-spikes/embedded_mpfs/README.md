# embedded_mpfs

The `embedded` leaf of the rts-spikes crate hierarchy (see
[../CONTRACT.md](../CONTRACT.md) §3 and
[../../RTS-POLARFIRE.md](../../RTS-POLARFIRE.md)) for Microchip PolarFire
SoC, `riscv64-elf`. Full exception propagation (the zero-cost/C unwinder),
the C unwinder itself, and Ravenscar tasking -- the largest of the three
profiles in this spike (1053 units against `light_mpfs`'s 512,
CONTRACT.md §7.2 -- headers stripped from the membership lists, see
below).

## What this crate is

`embedded_mpfs` owns `for Runtime ("Ada") use Project'Project_Dir;` and
produces -- does not ship -- `adalib/libgnat.a` and `adalib/libgnarl.a`
from two library projects:

- `runtime_build.gpr` -- `libgnat`, compiling **Ada, Asm_Cpp, and C**
  (`for Languages use ("Ada", "Asm_Cpp", "C");`). C is needed for the
  unwinder (`raise-gcc.c`) that gives this profile full exception
  propagation, unlike `light_mpfs`.
- `ravenscar_build.gpr` -- `libgnarl`, into the same `adalib/`.

Both are assembled, per RTS.md §6, from three source-only tier crates
(never vendored into this one):

| Tier | Crate | What it contributes here |
|---|---|---|
| 1 | `rts_sources_gcc15` | `libgnat`/`libgnarl` snapshot (`Gnat_Dir`, `Gnarl_Dir`) -- including the tasking *kernel* units (`s-bbthre`, `s-bbtime`, `s-bbinte`, `s-bbprot`, ...), which live in tier 1's `libgnarl`, not tier 2 |
| 2 | `rts_core_riscv64` | the RISC-V *CPU-primitives* layer only (`s-bb.ads`, `s-bbcppr.ad[sb]`, `s-bbcpsp.ad[sb]`, `context_switch.S`) |
| 3 | `rts_support_mpfs` | `System.BB.Board_Support`, startup, `a-intnam.ads`, PLIC/register bindings, `ld/mpfs-memory.ld` + placement scripts |

`ravenscar_build.gpr`'s `Source_Dirs` therefore names **both** tier 1's
`Gnarl_Dir` and tier 2's `Src_Dir` -- tier 2 alone is not enough.

`src/` holds **20 files**: `system.ads`, `s-parame.ads`/`.adb`,
`s-bbpara.ads`, plus 16 more whose *content* (not merely their switches)
differs between the `light`/`light-tasking`/`embedded` profiles and so
cannot live in the shared tier-1 snapshot --
`a-except.ads`/`.adb`, `a-elchha.ads`/`.adb`, `a-tags.ads`/`.adb`,
`a-strsup.ads`/`.adb`, `s-assert.adb`, `s-memory.ads`/`.adb`,
`s-taskin.ads`, `s-tpobop.ads`/`.adb`, `s-tposen.ads`/`.adb`. These are
exactly the units full exception propagation depends on
(`a-except`/`a-elchha`/`a-tags`), so their being the *embedded* variant
here (not shadowed by a lighter profile's) matters more for this crate
than for its siblings. All 20 are listed early in `Source_Dirs` so they
shadow any same-named file the tier crates might otherwise supply
(RTS.md §2.1); `rts_sources_gcc15/libgnat.lst`/`libgnarl.lst` no longer
carry these 18 basenames at all, so there is no shadowing to reason
about for them -- this leaf is the only place they exist. `s-bbpara.ads`
is additionally modified from the populated copy -- see below.

Everything under `libgnat/`, `libgnarl/`, `src/` in the *tier* crates is
populated by `../populate.sh`, not committed (CONTRACT.md §1); this
leaf's own `src/` is populated the same way as a starting point but is
meant to be hand-edited and committed (§3.4 explicitly requires editing
`s-bbpara.ads`), which is why it is not covered by that same rule -- see
"Known gap" below regarding `.gitignore`.

## The two embedded-specific traps (RTS.md A.14)

**(a) It compiles C.** `runtime_build.gpr` declares
`for Languages use ("Ada", "Asm_Cpp", "C");` -- `light_mpfs` and
`light_tasking_mpfs` do not need the third language. This is for the
unwinder (`raise-gcc.c`, compiled here with `-fexceptions`, see the
per-unit switch overrides below).

**(b) The link group.** `runtime.xml`'s `Linker` package **must** include:

```
"-Wl,--start-group,-lgnarl,-lgnat,-lc,-lgcc,--end-group"
```

Without it, the link fails with **~30 undefined references** to
`memcpy`, `memset`, `memmove`, `memcmp` (verified on the Cortex-M
`embedded_stm32g4xx` crate, RTS.md A.14): `libgnarl`, `libgnat`, `libc`
and `libgcc` have circular references (GNARL calls into GNAT calls into
libc string functions calls into libgcc, and back), and a plain link
order cannot resolve a cycle -- only a `--start-group`/`--end-group`
lets `ld` keep re-scanning the named archives until nothing new
resolves. `light_tasking_mpfs` needs no such group; do not add it there
either (RTS.md A.14 measured that both ways). This crate's `runtime.xml`
is otherwise byte-for-byte the same shape as a `light_tasking_mpfs`
would be (same `Compiler` package, same ISA-switch mechanism); the
`Linker` package's extra line is the one place they differ.

## Configuration variables (CONTRACT.md §3.2 -- names and defaults pinned)

| Variable | Type | Default | Notes |
|---|---|---|---|
| `Harts_Mask` | Integer 1..31 | 6 | bit N = hart N, bit 0 the E51. **Derives** `Hart_Class`, and through it `ISA_Switches`, `Max_Number_Of_CPUs`'s domain and ITIM/DTIM ownership; see "One knob" below. There is no separate `Hart_Class` variable |
| `Harts` | String | `"1"` | hart set owned by this partition; drives `Max_Number_Of_CPUs` (`src/s-bbpara.ads`) and the ITIM `Defsyms` |
| `Privilege` | Enum (`m_mode`, `s_mode`) | `m_mode` | not yet consumed by this leaf's own project files (S-mode support is RTS-POLARFIRE.md §8 item 7, deferred) |
| `Memory_Profile` | Enum, 6 values | `lim` | selects the `-T` placement script (see "Cross-crate dependency" below) |
| `L2_Cache_Ways` / `L2_LIM_Ways` / `L2_Scratchpad_Ways` | Integer 0..16 | 1 / 15 / 0 | feed `MPFS_LIM_LENGTH` / `MPFS_SCRATCHPAD_LENGTH` via `N*128K` |
| `ITIM_Ways` / `DTIM_Ways` | Integer 0..3 | 0 / 0 | feed the five `MPFS_*_ITIM_LENGTH` symbols / `MPFS_DTIM_LENGTH` |
| `DDR_Present` | Boolean | `false` | gates the three DDR `Defsyms` |
| `DDR_Cached_KB` / `DDR_NonCached_KB` / `DDR_WCB_KB` | Integer | 0 | bounds not pinned by CONTRACT.md; chosen as 1 GiB / 256 MiB / 256 MiB in KB, the largest alias each region has (RTS-POLARFIRE.md §1.2) |
| `Console` | Enum, 7 values | `mmuart0` | not yet consumed by this leaf's own project files (tier-3's `s-textio.adb` owns the console; RTS-POLARFIRE.md §8 item 8) |
| `Interrupt_Stack_Size` | Integer | 8192 | bounds not pinned; chosen as 256 .. 1 MiB |
| `Secondary_Stack_Size` | Integer | 2048 | bounds not pinned; chosen as 0 .. 1 MiB |
| `MPFS_PARTITION` | String | `""` | empty = standalone mode; non-empty selects a generated `partition-<name>.ld` (RTS-POLARFIRE.md §6.1) |

`provides = ["gnat_rts_tasking=0.1.0"]`, unlike `light_mpfs` (RTS.md §4).

## Exported GPR variables (CONTRACT.md §3.7)

`runtime_build.gpr` exports `ISA_Switches`, `Linker_Switches` and
`Defsyms`. An application's own project restates `Target`/`Runtime` and
combines these, e.g.:

```ada
with "runtime_build.gpr";
with "ravenscar_build.gpr";
project My_App is
   for Target use Runtime_Build'Target;
   for Runtime ("Ada") use Runtime_Build'Runtime ("Ada");
   package Linker is
      for Switches ("Ada") use
        Runtime_Build.Linker_Switches & Runtime_Build.Defsyms;
   end Linker;
end My_App;
```

`Defsyms` is **not** folded into `Linker_Switches` (CONTRACT.md §3.7's
table phrase "plus Defsyms" is read here as "used alongside", not
"concatenated into") -- both are combined explicitly by the caller,
matching how this crate was verified (see below).

### GPR has no arithmetic; `ld` does

None of `Defsyms`'s byte lengths are computed by string-processing in
GPR -- GPR has no arithmetic operators at all, only string
concatenation (`&`). Instead, each `-Wl,--defsym=` value is a **linker
expression** (`N*128K`, `NK`), and `ld` evaluates it: verified directly,

```
$ riscv64-elf-ld -e _start --defsym=X=3*128K --defsym=Y=200K empty.o -o t.elf
$ riscv64-elf-nm t.elf | grep -E 'X|Y'
0000000000060000 A X   #  3*128*1024 = 0x60000
0000000000032000 A Y   #  200*1024   = 0x32000
```

The one case this does not reach is "which single hart owns this
ITIM" -- not an arithmetic question, so it is a GPR `case` on `Harts`
instead (verified: GPR's `case` works directly on a plain, untyped
`String` variable imported from another project, with `others` as a
catch-all; no locally-declared enumeration type is required, unlike
what a first reading of the GPR reference suggests).

### One knob -- the gap is closed

This section used to describe `Hart_Class` and `runtime.xml`'s
`MPFS_ARCH`/`MPFS_ABI` as "two knobs, not one": two independent
mechanisms sharing the same u54 defaults, which an E51 application had
to keep in step by also passing `-XMPFS_ARCH=rv64imac_zicsr
-XMPFS_ABI=lp64`. Nothing detected a mismatch.

**That is no longer the case, and the reason it existed was a mistake.**
The gap was blamed on a `gprconfig` `<config>` fragment being unable to
`with` a generated configuration project -- which is true, but the
conclusion drawn from it (that `runtime.xml` had to stay the source of
the ISA, read through externals) was not forced. `runtime.xml` is now
deleted, following `avrada_rts`; `target_options.gpr` derives
`Hart_Class` from `Harts_Mask` and computes `ISA_Switches` from it, once,
with no `external()` able to override it. See CONTRACT.md 3.6 / 7.10 and
RTS.md A.22.

Consequences for this crate:

- `Harts_Mask` alone decides both source selection
  (`Max_Number_Of_CPUs`, `Single_Hart`/DTIM ownership) and the compiler
  switches. A disagreeing pair is unrepresentable, so the
  `Hart_Class = e51` + hard-float check CONTRACT.md 5 asked for is
  unnecessary rather than unimplementable.
- There is no `Hart_Class` configuration variable any more; it is
  derived. The table above is corrected accordingly.
- An application no longer passes any `-X` for the ISA. It renames the
  exported `Builder` package instead:
  `package Builder renames Target_Options.Builder;`
- Forgetting that rename is now a **link error**
  (`can't link soft-float modules with double-float modules`), because
  this crate's `libgnat`/`libgnarl` are built from the derived ISA
  regardless of what the application does.

### Cross-crate dependency on `rts_support_mpfs`

`Linker_Switches`' placement-script names were initially guessed from
RTS-POLARFIRE.md §1.3's five vendor script names (`mpfs-envm.ld`, ...)
before `rts_support_mpfs` existed, and corrected once it did: the real
committed scripts are `place-<profile>.ld` (`place-envm.ld`,
`place-lim.ld`, `place-lim-lma-scratchpad-vma.ld`,
`place-ddr-by-bootloader.ld`), each `INCLUDE mpfs-memory.ld` (that
shared-memory-block name *was* guessed correctly). As of this writing
`place-envm-lma-scratchpad-vma.ld` has no committed script yet --
`Placement_Script`'s case for `envm_lma_scratchpad_vma` follows the
same naming pattern as the other four but is unverified until that file
exists. `system_partition`'s generated `partition-<name>.ld` is likewise
unverified (standalone mode, this crate's default, does not exercise
it).

### `ITIM_Way_Size` / `DTIM_Way_Size` -- unresolved TRM item

RTS-POLARFIRE.md §11 itself flags the L1 way size as "a TRM item" --
not yet looked up in the MSS Technical Reference Manual by anyone in
this spike. `runtime_build.gpr` assumes 4 total L1 ways per hart
(`ITIM_Ways`/`DTIM_Ways` cap at 3, "leave one cache way" per
RTS-POLARFIRE.md §5.3) and divides the stated window sizes
accordingly: `ITIM_Way_Size = 28 KB / 4 = 7168` bytes,
`DTIM_Way_Size = 8 KB / 4 = 2048` bytes. Both are marked
`--  UNVERIFIED:` at their declaration; replace once the true per-way
size is known.

## `Max_Number_Of_CPUs` (task item 4)

`src/s-bbpara.ads` derives `Max_Number_Of_CPUs` from
`MPFS_Runtime_Config.Harts` instead of the hardcoded `1`. This has to be
a genuine RM-static Ada expression -- `System.Multiprocessors`
(`rts_sources_gcc15/libgnarl/s-multip.ads`) declares
`type CPU_Range is range 0 .. System.BB.Parameters.Max_Number_Of_CPUs;`,
and RM 3.5.9 requires both bounds of an integer type definition to be
static, which rules out any general string-parsing function (Ada has no
static loops). Since PolarFire SoC has exactly five harts, every legal
`Harts` value names a subset of `{0, 1, 2, 3, 4}`, enumerable by static
string equality (`=` on static string primaries is a predefined
operator, hence static per RM 4.9). A `pragma Compile_Time_Error` rejects
any `Harts` value outside the 22 recognised spellings (single harts,
comma sets, and `..` ranges, both spellings accepted for the same
contiguous set) rather than silently defaulting to 1 CPU.

## Verification

A throwaway application (path-pinning this crate, restating
`Target`/`Runtime`, combining `Linker_Switches` and `Defsyms`) exercised
a library-level task (declared in a library-level package -- a task
object in `procedure Main`'s own declarative part violates
`No_Task_Hierarchy`, which Jorvik imposes; RM D.7 requires library level
in the stricter, package-only sense) and a `raise ... with "msg"` caught
by `exception when E : others => ... Ada.Exceptions.Exception_Message
(E)`.

**This crate's own project files (both libraries) got past source
resolution and into real compilation** -- `embedded.gnat.lst` /
`embedded.gnarl.lst` (below) resolved the "source file ... not found" /
"unit ... cannot belong to several projects" errors that CONTRACT.md §7
also names as a shared blocker, and dozens of libgnat/libgnarl units
compiled successfully (`main.adb`, `a-synbar.adb`, `a-retide.adb`,
`s-tasque.adb`, `s-tpoben.adb`, `g-boumai.ads`, `s-bcprmu.adb`,
`s-taprop.adb`, ...). **Full link was not reached**: compilation is
blocked by bugs in `rts_support_mpfs/src/s-bbbopa.ads` (not this crate,
not edited here) -- first `MPFS_Runtime_Config.Console = ...Mmuart0`
etc. (five comparisons, lines 165/167/169/171/173) failing "operator for
type Console_Kind ... is not directly visible" for want of `use
MPFS_Runtime_Config;` (fixed upstream between two verification runs);
then, on the next attempt, `s-bbbopa.ads:196:07: error: expected private
type "System.Address", found type universal integer` (also unfixed as
of this writing -- almost certainly `PLIC_Base_Address` or similar,
declared `constant := 16#0C00_0000#` a few lines above, used somewhere
expecting `System.Address` without a conversion). Both are real,
reproducible compiler diagnostics against an unmodified upstream file,
not something introduced by or fixable from this crate. See the task's
final report for the verbatim tails.

### The `embedded.gnat.lst` / `embedded.gnarl.lst` split

`embedded.lst` (1053 units) is this profile's *total* membership, but it
cannot be `runtime_build.gpr`'s or `ravenscar_build.gpr`'s
`Source_List_File` unmodified: libgnat's `Source_Dirs` has no `libgnarl`
directory, so every libgnarl-only name in it is "not found", and
tier-2/tier-3's shared directories (listed in *both* projects'
`Source_Dirs`) need something to decide which of their files belongs to
which library. `Source_List_File` alone -- not `Excluded_Source_Files`
too (CONTRACT.md §7.1) -- resolves both: each project's own list already
restricts it to the matching subset, so the other side's files in a
shared directory are simply never selected.

`embedded.gnat.lst` (959 units) and `embedded.gnarl.lst` (94 units) are
therefore committed here, concatenated from the read-only
`lists/embedded.gnat.tier1/2/3.lst` + `lists/embedded.gnat.leaf.lst` and
the `.gnarl.` equivalents (`embedded.lst` and `lists/` themselves are
untouched). Verified: their union is exactly `embedded.lst`'s 1053 lines
and they share no line (`diff`/`sort | uniq -d` both empty) --
re-verified after `lists/embedded.gnat.tier3.lst` was found to still
include the six headers CONTRACT.md §7.2 says must not appear in either
list, by re-deriving `embedded.gnat.lst` as `embedded.lst` minus the
(unaffected) `embedded.gnarl.lst` directly rather than re-concatenating
the stale per-tier files.

## Licence

`licenses = "GPL-3.0-or-later WITH GCC-exception-3.1"`, matching every
populated file's own header (Free Software Foundation / AdaCore). **Do
not alter the FSF/AdaCore header comments** in `src/system.ads`,
`src/s-parame.ads`, `src/s-parame.adb` or `src/s-bbpara.ads`; the
`s-bbpara.ads` modification is a clearly-marked addition after the
header, not a change to it.
