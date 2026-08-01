# Implementation plan: PolarFire SoC runtime crates

- **Status:** Draft 1 — 2026-07-28
- **Companion to:** [RTS.md](RTS.md), which establishes the crate/configuration boundary rule this plan applies.
- **Target:** Microchip PolarFire SoC (MPFS), MSS based on SiFive U54-MC — one E51 monitor core plus four U54 application cores.
- **Why this target:** it breaks every simplifying assumption in the general design at once. Two core classes with *different ABIs* in one chip, SMP and AMP simultaneously, and a memory system that is genuinely configurable rather than merely parameterised — optional DDR, L2 ways reassignable as LIM or scratchpad, per-hart ITIM/DTIM. If the crate structure survives MPFS, it survives anything in scope.

---

## 1. The hardware, as a runtime must see it

Addresses below are taken from Microchip's own reference linker scripts in [polarfire-soc-bare-metal-examples](https://github.com/polarfire-soc/polarfire-soc-bare-metal-examples) (`src/platform/platform_config_reference/linker/`), which are the authoritative machine-readable form, cross-checked against the [MSS Technical Reference Manual](https://www.microchip.com/content/dam/mchp/documents/FPGA/ProductDocuments/ReferenceManuals/PolarFire_SoC_FPGA_MSS_Technical_Reference_Manual_VC.pdf) and the [memory-hierarchy knowledge base](https://github.com/polarfire-soc/polarfire-soc-documentation/blob/master/knowledge-base/mpfs-memory-hierarchy.md).

### 1.1 Cores

| Hart | Core | ISA | `-march` / `-mabi` | Local memory |
|---|---|---|---|---|
| 0 | E51 monitor | RV64IMAC, **no FPU** | `rv64imac_zicsr` / `lp64` | 8 KB DTIM, 28 KB ITIM |
| 1–4 | U54 application | RV64GC | `rv64imafdc` / `lp64d` | 28 KB ITIM each, 32 KB L1 I+D |

The ABI difference is the single most consequential fact in this document: **an AMP system that uses the E51 needs two runtimes with different ABIs resident at once.** Both resolve to installed libgcc multilibs (`rv64imac/lp64` and `rv64imafdc/lp64d`), so both are buildable — verified in §9.

Note `_zicsr`: bare `rv64imac` does *not* imply the CSR instructions the startup code uses, and assembling `start-ram.S` fails with `unrecognized opcode 'csrr t1,mhartid', extension 'zicsr' required`. `rv64imafdc` happens to imply it. This is exactly the class of ISA-string detail that must live in a validated enumeration rather than in prose.

### 1.2 Memory regions

| Region | Base | Size | Notes |
|---|---|---|---|
| eNVM | `0x2022_0100` | 128 KB − 0x100 | non-volatile; boot source |
| DTIM (E51) | `0x0100_0000` | 8 KB window; usable amount **variable** | the L1 **data** side is either D-cache or SRAM — same split as ITIM. Vendor's 7 KB + 1 KB `switch_code_dtim` at `0x0100_1c00` is their chosen configuration plus a convention: memory-reconfiguration code must not execute from the memory it reconfigures |
| E51 ITIM | `0x0180_0000` | window 28 KB; usable amount **variable** | carved from the L1 I-cache — enabling it reduces cache, exactly as LIM reduces L2 |
| U54 *n* ITIM | `0x0180_8000 + (n−1)·0x8000` | window 28 KB each; usable amount **variable** | *n* = 1…4; per-hart **private** |
| L2 LIM | `0x0800_0000` | **1920 KB at reset**; 128 KB granularity | ways not enabled as cache; not cached (it *is* the memory) |
| L2 scratchpad | `0x0A00_0000` | 0 at reset; 128 KB granularity | cache ways pinned via `WayMask`; **cacheable**, ~3× faster than LIM |
| DDR cached, 32-bit | `0x8000_0000` | 768 MB | |
| DDR non-cached, 32-bit | `0xC000_0000` | 256 MB | the sane place for AMP IPC buffers |
| DDR write-combine, 32-bit | `0xD000_0000` | 256 MB | |
| DDR cached, 38-bit | `0x10_0000_0000` | 1024 MB | |
| DDR non-cached / WCB, 38-bit | `0x14_0000_0000` / `0x18_0000_0000` | board-dependent | |
| CLINT | `0x0200_0000` | `mtime` at +`0xBFF8`, `mtimecmp` at +`0x4000 + 8·hart` | |
| L2 controller | `0x0201_0000` | `Config`, `WayEnable` +`0x08`, `WayMask` +`0x800`… | |
| PLIC | `0x0C00_0000` | 5 hart contexts, 185 sources, 3 priority bits | |

### 1.2.1 The L2 way model

The L2 is **16 ways of 128 KB (2048 KB total)**, and each way is assigned exactly one of three roles:

| Role | Addressed at | Cached | Set by |
|---|---|---|---|
| cache | — | — | `WayEnable` (ways 0…`WayEnable` are cache) |
| LIM | `0x0800_0000` + offset | no | the ways above `WayEnable` |
| scratchpad | `0x0A00_0000` + offset | **yes** | `WayMask`, pinning a cache way out of general allocation |

So the allocation is a partition, and the invariant is:

```
cache_ways + lim_ways + scratchpad_ways = 16
lim_ways <= 15        --  way 0 cannot be LIM: max LIM is 1920 KB
cache_ways >= 1       --  something must remain a real cache
```

**The reset default is 1920 KB of LIM and one way of cache** — i.e. the whole L2 is directly addressable SRAM before anything configures it. Two consequences the plan leans on:

- **Running from LIM needs no L2 configuration at all.** That is what makes `Memory_Profile => lim` the right first milestone (§10): a P1 image can boot and run with zero dependency on HSS having programmed anything, and with no DDR at all.
- **Every other memory profile is a *reduction* of LIM.** Enabling cache or creating a scratchpad takes ways away from LIM, so the vendor scripts' 256 KB LIM is a configured state, not the hardware default. Anything that shrinks LIM must run before a partition placed in the vanished region does — which is the ordering problem §6.4 addresses.

### 1.3 What is actually invariant — and what §1.2.1 makes variable

All five of Microchip's reference linker scripts — `mpfs-envm.ld`, `mpfs-lim.ld`, `mpfs-lim-lma-scratchpad-vma.ld`, `mpfs-envm-lma-scratchpad-vma.ld`, `mpfs-ddr-loaded-by-boot-loader.ld` — contain a **byte-identical `MEMORY` block**, and differ only in `SECTIONS` placement.

That is tempting to read as "the region declaration is invariant, the placement is the configuration", which is the shape [RTS.md §5.3](RTS.md) recommends. **But it is only half true, and §1.2.1 is why.** Splitting it properly:

| Invariant — it *is* the SoC | Variable — it is configuration |
|---|---|
| the *set* of regions | LIM length (0 … 1920 KB, in 128 KB ways) |
| every *base address* | scratchpad length (0 … 15 ways) |
| ITIM/DTIM base per hart | DDR presence, and each alias's length |
| CLINT / PLIC / L2-controller bases | ITIM and DTIM lengths — where the L1 cache/SRAM trade-offs are taken (§1.4) |

The five vendor scripts agree on lengths because **all five assume one reference L2 and DDR configuration** — 256 KB LIM, 256 KB scratchpad, 768 MB DDR — not because the hardware fixes them. Copying that block verbatim would freeze this design into Microchip's reference configuration and silently contradict §1.2.1, where LIM ranges over sixteen values and defaults to 1920 KB.

Nor can the variation be handled by shipping committed variants: the cross product of LIM ways × scratchpad ways × DDR sizes is far too large to enumerate as files.

**The resolution: literal bases, symbolic lengths.** One shared `mpfs-memory.ld` keeps every `ORIGIN` as a constant and takes every variable `LENGTH` from a symbol the leaf supplies via `-Wl,--defsym=`, computed from the configuration variables:

```
MEMORY
{
  l2lim      (rwx) : ORIGIN = 0x08000000, LENGTH = MPFS_LIM_LENGTH
  scratchpad (rwx) : ORIGIN = 0x0A000000, LENGTH = MPFS_SCRATCHPAD_LENGTH
  ddr_cached (rwx) : ORIGIN = 0x80000000, LENGTH = MPFS_DDR_CACHED_LENGTH
  ...
}
```

Verified to work and — more importantly — to be *enforced*: `__heap_end` tracked a `--defsym`-supplied length exactly, and an undersized value produced `region 'ram' overflowed by 2096944 bytes` at link time (§9). So a partition that does not fit the LIM it was configured for fails the build with a clear message rather than corrupting memory on silicon.

A pleasant side effect: the vendor scripts already encode "region unused" as `LENGTH = 0k` for the unused 38-bit DDR aliases. With symbolic lengths, `0` is the natural encoding for `DDR_Present => False`, so absence needs no separate memory profile.

So the corrected division of labour is:

- **`--defsym` for region *sizes*** — continuous, config-computed, link-time checked;
- **committed script variants for *placement*** — the five vendor profiles, selected by enum, exactly as RTS.md §5.3 recommends;
- **generated scripts** only for `system_partition`, where the placement itself is per-partition data (§4).

### 1.4 ITIM and DTIM in the linker script

These are the one place where "declare always" and "declare when enabled" genuinely differ, because ITIM and DTIM are **per-hart private** while every other region is shared.

**They are the same kind of thing as LIM**, which is the useful realisation: every on-chip memory on this SoC is a cache/SRAM split, at three levels.

| Level | Roles a unit can take | Granularity | Scope |
|---|---|---|---|
| L2 (2048 KB) | cache · LIM · scratchpad | 128 KB way | **global** — one shared allocation |
| L1-I per hart | I-cache · ITIM | cache way | **per hart, private** |
| L1-D, **E51 only** | D-cache · DTIM | cache way | **private to the E51** |

So `L2_LIM_Ways`, `ITIM_KB` and `DTIM_KB` are one rule shape repeated three times — a partition of a fixed capacity, with a compile-time sum check and a `--defsym` length per resulting region. No region on this SoC needs a different mechanism, which is what makes §1.3's "literal bases, symbolic lengths" sufficient rather than merely convenient.

The scope column is where the design consequence lives, and it splits cleanly:

- **The L2 split is global and single-actor.** Shrinking LIM affects every hart, so it must happen once, before any partition placed in the affected region runs (§6.4).
- **The L1 splits are private and self-service.** A hart's own startup can convert its own cache ways with no coordination and no race, because nothing else can address that window. This is ordinary runtime work, not system policy.

That asymmetry is worth keeping: it means enabling ITIM/DTIM is something a partition may simply *do*, while reconfiguring L2 is something a partition must be *told has already happened*.

**Declare all six windows unconditionally** — the E51 DTIM plus five ITIMs — in the shared `mpfs-memory.ld`. Names and bases are invariant, and a declared-but-unused region costs nothing: `ld` accepts `LENGTH = 0` and still lists the region in the map (verified, §9).

**Then set each length from *ownership*, not from availability:**

| Region | `Hart_Class => e51`, `Harts => "0"` | `Hart_Class => u54`, `Harts => "2"` |
|---|---|---|
| `dtim` | `DTIM_KB` | **0** — only the E51 has a configurable DTIM |
| `e51_itim` | `ITIM_KB` | **0** |
| `u54_2_itim` | **0** | `ITIM_KB` |
| `u54_1/3/4_itim` | **0** | **0** |

A foreign hart's window at `LENGTH = 0` turns an accidental placement into a link-time `region '…' overflowed` instead of a silently accepted image — the same device the vendor scripts already use for their unused 38-bit DDR aliases. Cost: one `--defsym` per region, computed from `Harts` and `Hart_Class`.

**Add a generic `local_itim` alias with symbolic `ORIGIN` *and* `LENGTH`:**

```
local_itim (rwx) : ORIGIN = MPFS_LOCAL_ITIM_ORIGIN, LENGTH = MPFS_LOCAL_ITIM_LENGTH
```

Without it, any placement profile that puts the trap path in ITIM needs one variant per hart — five copies of each of the five profiles. With it, one script serves any hart. Symbolic `ORIGIN` via `--defsym` is verified to work (§9), so this needs no generation.

**Two limits to state plainly:**

- **`ld` checks region *overflow*, not region *overlap*.** Two regions declared 32 KB into each other drew no diagnostic at all (§9). The zero-length device therefore catches "I placed something where I declared nothing"; it cannot catch "my regions collide", and it can never see a collision between two *separately linked* AMP partitions. Overlap checking stays in `System_Map` (§4), in Ada, as `pragma Compile_Time_Error`.
- **An SMP partition cannot live in ITIM.** It is per-hart private, so an image shared by several harts has no single ITIM to occupy. This is the `Use_ITIM` × multi-hart check in §5.3, and it is a real restriction rather than an implementation shortcut: ITIM is for one hart's hot path — a trap vector, an ISR — not for a shared runtime.

---

## 2. What GNAT ships today, and the gap

`gnat_riscv64_elf` 15.1.2 bundles `light-polarfiresoc`, `light-tasking-polarfiresoc` and `embedded-polarfiresoc`. Inspecting them:

| Aspect | Shipped state |
|---|---|
| ISA | all three at `-march=rv64imafdc -mabi=lp64d` — **U54 only; the E51 cannot be targeted** |
| Cores | `Max_Number_Of_CPUs : constant := 1` **even in light-tasking** — no SMP is built |
| Hart binding | hart 1 baked into constants: `CLINT_Mtimecmp_Offset = 16#4008#` ("mtimecmp for hart 1"), `PLIC_Hart_Id = 1`, `GDB_First_CPU_Id = 1` |
| Memory | one flat region: `ram : ORIGIN = 0x80000000, LENGTH = 128M` — DDR assumed present, size fixed, everything else unreachable |
| Startup | `start-ram.S` reads `mhartid` and parks every hart but one |
| Console | `UART_Base_Address = 16#2000_0000#` (MMUART0), owned by the runtime |
| AMP | not modelled at all |

Upstream [bb-runtimes](https://github.com/AdaCore/bb-runtimes) does carry more than is built: `riscv/microchip/polarfiresoc/` has `start-ram-smp.S` and `common-RAM-smp.ld` alongside the single-hart pair. The SMP startup parks hart 0 (`beqz a0, infinite_hart_parking`) and brings up harts 1–4 — so upstream's SMP is "all four U54s, E51 unused", hardcoded. AMP, per-hart memory, LIM/scratchpad/ITIM placement and E51 support are all absent.

**Gap summary.** Everything the target is interesting for is missing: the E51, SMP as a build option, AMP, and every memory configuration except "DDR exists and I own 128 MB of it".

---

## 3. Applying the boundary rule

[RTS.md §4.1](RTS.md) gives: one crate per (target triple × runtime profile × device-support family); device, board and ISA/ABI are configuration. For MPFS the family is the SoC itself, so:

| # | Crate | Kind | Contents |
|---|---|---|---|
| 1 | `rts_sources_gcc15` | source-only, shared | the `libgnat`/`libgnarl` snapshot (RTS.md tier 1) |
| 2 | `rts_core_riscv64` | source-only | `System.BB.CPU_Primitives`, threads, time — or folded into (1) per RTS.md §7 |
| 3 | `rts_support_mpfs` | source-only | `s-bbbopa.ads`, `s-bbripl.adb` (PLIC), `a-intnam.ads`, `riscv_def.h`, startup variants (single-hart / SMP × M-mode / S-mode), CLINT / PLIC / L2-controller / L1-split private register bindings, the Ada that *interprets* the generator's raw values (§4.3), `ld/mpfs-memory.ld` + the five placement scripts (§6.1) |
| 4 | `light_mpfs` | **buildable leaf** | manifest, config variables, metadata, per-profile source list, and the exported `ISA_Switches`/`Linker_Switches`/`Defsyms`. No `runtime.xml`: `target_options.gpr` owns the ISA and exports the `Builder` package applications rename — see §11 item 13 |
| 5 | `light_tasking_mpfs` | **buildable leaf** | + `ravenscar_build.gpr`/`libgnarl` |
| 6 | `embedded_mpfs` | **buildable leaf** | + full exception propagation, C unwinder |
| 7 | `mpfs_system` | **generated, project-local** | derived from the MSS Configurator XML + HSS payload YAML — see §4 |

Plus one thing that is *not* a crate: the **generator** itself — a fork of Microchip's `mpfs_configuration_generator.py` emitting Ada instead of C (§4.3). It is build-time tooling, versioned with the project rather than published to the index, and it produces crate 7.

**Both core classes share crate 3 and the leaves.** They are configurations, not crates — verified in §9: one source tree built a working E51 (`rv64imac_zicsr`/`lp64`, no FPU in the ELF attributes) and U54 (`rv64imafdc`/`lp64d`) runtime, differing only in switches plus the three float-dependent source variants.

Crate 7 is the new thing, and it exists because of AMP.

---

## 4. AMP is not a runtime configuration — it is system composition

This is the part the general design does not cover, and it needs stating plainly.

An AMP system is **N independent binaries**. Each partition has its own runtime, its own ABI potentially, its own memory window and its own harts. Alire cannot hold two different configurations of one crate in a single solution, and configuration values flow *downward from a root*. Two partitions have no common root. Therefore:

> **Each AMP partition is its own Alire root crate.** No amount of runtime configuration can express "these three programs form one system".

But partitions must agree on things no single partition can see: hart ownership, non-overlapping memory windows, which MMUART belongs to whom, the L2 way split, and where the IPC regions live. Configuration cannot carry that agreement — so it has to be **data, generated once, depended on by all partitions**.

### 4.1 Do not invent a system description — Microchip already ships two

**The MSS Configurator XML** (`<design>_mss_cfg.xml`; the HSS repository carries one per board, e.g. `boards/mpfs-icicle-kit/soc_fpga_design/xml/ICICLE_MSS_mss_cfg.xml`) is the *hardware envelope*. It contains, as inspected:

| XML section | What it gives the runtime |
|---|---|
| `mss_memory_map/map/mem_elements` | named memory instances with base and size, including `RESET_VECTOR_HART0…4` |
| `pmp_h0` … `pmp_h4` | full per-hart PMP configuration (8/16 regions, NAPOT encoding) |
| `apb_split/APBBUS_CR` | **AMP peripheral ownership** — per peripheral, whether it appears in the `0x2000_0000` range (AXI5) or `0x2800_0000` (AXI6) |
| `apb_split/MEM_CONFIGS_ENABLED` | whether the design enables PMP and/or MPU at all |
| `mss_pll`, `mss_ddr`, `mss_io` | clock tree, DDR configuration, pin muxing |

**The HSS payload YAML** (`tools/hss-payload-generator`) is the *software partitioning*, and its vocabulary maps one-to-one onto what this plan needs:

```yaml
hart-entry-points: {u54_1: '0x80200000', u54_2: '0x80200000', u54_3: '0xB0000000'}
payloads:
  app-smp.elf:   {owner-hart: u54_1, secondary-harts: [u54_2], priv-mode: PRV_M}
  app-single.elf: {owner-hart: u54_3, priv-mode: PRV_S}
```

`owner-hart` plus `secondary-harts` **is** the partition/hart assignment — a payload with secondaries is an SMP partition, two payloads are two AMP partitions — and it is already consumed by the bootloader that actually places the images. `priv-mode` is the boot privilege level.

So the generator input is not something to design, only something to read:

```
<design>_mss_cfg.xml   (MSS Configurator)  ─┐
hss-payload config.yaml (HSS)              ─┤► generator ►  mpfs_system/
                                            │                ├── src/mpfs-system_map.ads
                                            │                └── ld/partition-<name>.ld
```

**This inverts the relationship in a way that matters.** The earlier design had each leaf configured by hand and `System_Map` *checking* it. Deriving the leaf's hart set, memory window, console and clocks *from* the vendor files instead makes divergence between the FPGA design and the software structurally impossible rather than merely detected. `pragma Compile_Time_Error` then guards the residue — overlaps the designer created, and windows exceeding the §1.2 hardware maxima.

### 4.2 Two findings that fall out of reading the real files

**Privilege mode is a runtime input, not just a boot detail.** `priv-mode: PRV_S` means the partition starts in supervisor mode under OpenSBI, where the timer and interrupt paths are `stimecmp`/`sie` rather than `mtimecmp`/`mie`. A `light-tasking` runtime that assumes M-mode simply will not work there. This is a genuine second axis for `rts_support_mpfs` — `Privilege => m_mode | s_mode` — and it was absent from the earlier draft entirely.

**PMP has a data source already**, so the P5 work (§10) is decoding rather than designing: `pmp_h<n>` carries the regions the hardware designer intended for each hart.

### 4.3 The decoding risk, and how not to take it

The XML is a **register-value dump** — 838 `<register>` elements and 2445 `<field>`s — not a semantic model. Turning `mss_pll` register values into a frequency, or `PMP0CFG = 0x9F` into a base and size, means implementing vendor register encodings, and those are exactly the kind of thing that drifts.

Do not re-derive them, and do not parse C headers either. Microchip's [`polarfire-soc-configuration-generator`](https://github.com/polarfire-soc/polarfire-soc-configuration-generator) is **a single 677-line Python file** (`mpfs_configuration_generator.py`, ~28 KB; the repository contains nothing else but a Jenkinsfile), and it is structured so that retargeting it to Ada is a contained change rather than a rewrite:

| Part | Status for a fork |
|---|---|
| `read_xml_file`, ElementTree traversal, the `input_xml_tags` tables | **reuse unchanged** — this is the vendor's knowledge of the XML |
| `generate_mem_elements`, `generate_register` | retarget: they already walk exactly the sections §4.1 needs |
| `start_define` / `end_define` / `start_cplus` / `end_cplus` / `write_line` | **replace** — C include guards, `extern "C"`, `#define` emission |

That is roughly six emission functions standing between the XML and Ada output. Forking it to emit `MPFS.System_Map` and the linker fragments directly is preferable to consuming the C headers: no intermediate artifact, no header parsing, no C toolchain in the loop, and the vendor's XML knowledge stays in the part we do not touch. It also keeps the right division of ownership — **own the data pipeline, never hand-edit its output**: the XML stays vendor-owned, the fork is reviewed code, and the generated Ada is regenerated rather than patched. Every would-be hand edit to the generated spec is by definition a bug in the fork or in the XML.

**What a fork does not buy.** The tool emits register *values*, not decoded semantics — `generate_mem_elements` produces `LIBERO_SETTING_<NAME>` and `LIBERO_SETTING_<NAME>_SIZE` pairs straight from the XML attributes, and `generate_register` does the same for register fields. So the fork yields the same numbers in Ada instead of C; interpreting them (PLL registers → a frequency, `PMP0CFG = 0x9F` → base and size) still has to happen. The right place for that is `rts_support_mpfs`, as ordinary Ada — where §5.2's `pragma Compile_Time_Error` checks can act on the derived values, which is not possible while they are C macros.

One caveat on trusting the XML's memory list: on the Icicle reference design the DDR entries are labelled `description="example instance"` with 1 MB sizes. `mem_elements` is **designer-declared intent**, not hardware ground truth — so range-check every window against the §1.2 maxima rather than assuming the XML is self-consistent.

### 4.4 What `mpfs_system` contains

`MPFS.System_Map` is an ordinary `Pure` Ada spec, generated from the two vendor inputs of §4.1, containing the whole allocation. Because it sees *every* partition, the cross-partition checks can be static:

```ada
--  in MPFS.System_Map, generated:
pragma Compile_Time_Error
  (Overlaps (Partitions (Monitor).Window, Partitions (App1).Window),
   "monitor and app1 memory windows overlap");
pragma Compile_Time_Error
  (Partitions (App1).Harts and Partitions (App2).Harts) /= 0,
   "app1 and app2 both claim a hart");
```

Each partition's leaf sets one variable — `MPFS_PARTITION = "app1"` — and its runtime takes its window, hart set and console from `System_Map`. Every partition build therefore re-validates the entire system allocation, and a deliberate overlap fails *someone's* compile rather than corrupting memory on silicon.

Three consequences worth accepting up front:

- **The agreement is a convention, not an enforcement.** Nothing stops a partition being built against a stale `mpfs_system`. Mitigation: the generator stamps a hash of **both inputs** — the MSS XML and the HSS payload YAML — into the spec, and each partition asserts the pair it was told to expect. That converts "stale" into a compile error, and catches the case where the FPGA design was re-exported but the payload assignment was not (or vice versa).
- **Soft-float and hard-float partitions can share memory but not signatures.** IEEE representation is identical; only argument passing differs, and IPC across shared memory has no call boundary. Keep IPC records scalar-and-array only, `Scalar_Storage_Order`-explicit, and the ABI difference is invisible.
- **Coherence is not free.** The U54s are coherent through L2; a partition running out of LIM and one out of cached DDR are not automatically coherent with each other. IPC regions belong in the non-cached DDR alias (`0xC000_0000`) unless the description says otherwise, and `System_Map` should refuse to place an IPC region in a cached window.

---

## 5. Configuration variable design

Three levels, narrowing, per [RTS.md §4.1](RTS.md) — but read §4.1 of *this* document first, because there are two modes and only one of them uses the knobs below.

- **Derived mode** (`MPFS_PARTITION` set): hart set, memory windows, console, clocks, privilege and PMP all come from `mpfs_system`, generated from the vendor XML and payload YAML. The level-2 and level-3 variables are then **outputs**, not inputs, and setting them by hand is a configuration error the generated spec should reject.
- **Standalone mode** (no `MPFS_PARTITION`): a single-partition image with no system description — the P1 case, and the only mode in which the knobs below are authored by hand.

Standalone mode is not a lesser path: a single-image bring-up, a monitor-only build, or a unit-test image has no AMP allocation to describe and should not need a generator run.

### 5.1 Level 1 — role

| Variable | Type | Derives |
|---|---|---|
| `Harts_Mask` | `Integer` bitmask, bit *N* = hart *N*, bit 0 the E51 | **everything on this axis.** `Hart_Class` is *derived* from it, and from that `-march`/`-mabi` (§1.1, note `_zicsr`), the float source variants, ITIM base and whether a DTIM exists at all. Also `Max_Number_Of_CPUs`, startup variant, per-hart `mtimecmp` and PLIC context, `MPFS_LOCAL_ITIM_ORIGIN` (§6.2). In derived mode this is the payload YAML's `owner-hart` + `secondary-harts` (§4.1) |
| ~~`Hart_Class`~~ | — | **not a configuration variable.** It was one, independently of the ISA, which is exactly how a correct `Hart_Class => e51` coexisted with a hard-float build (§11 item 13). Deriving it from the mask makes the disagreeing pair unrepresentable. An `Integer` mask rather than a `String` hart set also keeps every derived value static, which a `String` did not (CONTRACT.md §7.8) |
| `MPFS_PARTITION` | `String` | when set, hart set / window / console / clocks / privilege all come from `mpfs_system` (§4) instead of the knobs below |
| `Privilege` | `Enum ("m_mode", "s_mode")` | timer and interrupt paths: `mtimecmp`/`mie` vs. `stimecmp`/`sie` (§4.2) |

### 5.2 Level 2 — memory profile

`Memory_Profile : Enum` mirroring the vendor's own taxonomy, plus one:

`envm` · `lim` · `lim_lma_scratchpad_vma` · `envm_lma_scratchpad_vma` · `ddr_by_bootloader` · `system_partition`

The first five select a committed placement script; `system_partition` selects the generated `partition-<name>.ld` (§6.1). All six share the one `mpfs-memory.ld`, so the profile chooses *placement* only — sizes always arrive as `--defsym` (§6.2).

### 5.3 Level 3 — individual knobs, and what checks them

| Variable | Validation |
|---|---|
| `DDR_Present : Boolean`, `DDR_Cached_KB`, `DDR_NonCached_KB` | a profile needing DDR with `DDR_Present = False` → compile error |
| `L2_Cache_Ways`, `L2_LIM_Ways`, `L2_Scratchpad_Ways` | `= 16` in total, `L2_LIM_Ways <= 15`, `L2_Cache_Ways >= 1` (§1.2.1). Express in *ways*, not KB, so the check is exact and a non-multiple of 128 KB is unrepresentable rather than silently rounded |
| `ITIM_Ways` | ≤ the L1-I way count − 1 (leave one I-cache way); a multi-hart `Harts` with `ITIM_Ways /= 0` → error, since ITIM is per-hart and a shared runtime cannot live in one (§1.4). Expressed in ways for the same reason as `L2_*_Ways`; the L1 way size is a TRM item (§11) |
| `DTIM_Ways` | ≤ the E51 L1-D way count − 1; `Hart_Class /= e51 and then DTIM_Ways /= 0` → error: only the E51 has a configurable DTIM (§1.4) |
| `Console : Enum ("mmuart0".."mmuart4", "ram_fifo", "none")` | two partitions claiming one MMUART → error in `System_Map`. In derived mode the XML's `APBBUS_CR` already says which address range each MMUART appears in (§4.1), so the assignment is read rather than declared |
| `Interrupt_Stack_Size`, `Secondary_Stack_Size`, `Tick_Frequency` | ranges |

Plus the cross-variable rules that matter most:

```ada
--  What this section originally specified -- all three now MOOT:
pragma Compile_Time_Error
  (Hart_Class = E51 and then Float_ABI = Hard, "the E51 has no FPU; ...");
pragma Compile_Time_Error
  (Hart_Class = E51 and then Hart_Set /= Hart_0, "the E51 is hart 0; ...");
pragma Compile_Time_Error
  (Hart_Class = U54 and then (Hart_Set and Hart_0) /= 0, "hart 0 is the E51; ...");
```

**These three checks were deleted rather than implemented, and that is the better outcome.** Each guarded a disagreement between two independently-set variables — `Hart_Class` against the ABI, and `Hart_Class` against the hart set. Since `Harts_Mask` is the only input and `Hart_Class` is derived from it (§5.1), none of the three states can be expressed at all. A check that cannot fire beats a check that fires, and the first was unimplementable anyway: the ABI never reached Ada, so no pragma could see it (CONTRACT.md §7.9).

Where `pragma Compile_Time_Error` *is* still the enforcement mechanism — the way sums of §5.3, the multi-hart-with-ITIM rule — it is because constrained subtypes only **warn**: RTS.md §5.2 measured that, and a surviving build reaches `Last_Chance_Handler` at startup. The general rule this yields is worth stating once: **prefer making a bad state unrepresentable, fall back to `Compile_Time_Error`, and never rely on a subtype.**

---

## 6. Memory implementation

Everything the memory system needs reduces to three artifacts and one ordering rule. Nothing here is a new mechanism — §1.3 verified the linker behaviour, RTS.md §5.3 verified the selection behaviour, and §4 supplies the data.

### 6.1 The three artifacts

**1. One `mpfs-memory.ld`** in `rts_support_mpfs`, shared by every profile and every partition. Every `ORIGIN` is a literal from §1.2; every variable `LENGTH` is a symbol the leaf supplies via `-Wl,--defsym=`. The generic `local_itim` (§1.4) takes a symbolic `ORIGIN` too:

```
MEMORY
{
  envm       (rx)  : ORIGIN = 0x20220100, LENGTH = MPFS_ENVM_LENGTH
  dtim       (rwx) : ORIGIN = 0x01000000, LENGTH = MPFS_DTIM_LENGTH
  e51_itim   (rwx) : ORIGIN = 0x01800000, LENGTH = MPFS_E51_ITIM_LENGTH
  u54_1_itim (rwx) : ORIGIN = 0x01808000, LENGTH = MPFS_U54_1_ITIM_LENGTH
  ...                                                --  four of these
  local_itim (rwx) : ORIGIN = MPFS_LOCAL_ITIM_ORIGIN, LENGTH = MPFS_LOCAL_ITIM_LENGTH
  l2lim      (rwx) : ORIGIN = 0x08000000, LENGTH = MPFS_LIM_LENGTH
  scratchpad (rwx) : ORIGIN = 0x0A000000, LENGTH = MPFS_SCRATCHPAD_LENGTH
  ddr_cached (rwx) : ORIGIN = 0x80000000, LENGTH = MPFS_DDR_CACHED_LENGTH
  ddr_nc     (rwx) : ORIGIN = 0xC0000000, LENGTH = MPFS_DDR_NC_LENGTH
  ...
}
```

**2. Committed placement scripts**, one per `Memory_Profile` value, adapted from the vendor's five (§1.3). Selected by GPR `case` on the configuration value.

**3. Generated placement scripts** for `system_partition`, one per partition, emitted by the forked generator (§4.3) alongside `MPFS.System_Map`.

### 6.2 Where each length comes from

| Symbol | Source | Zero means |
|---|---|---|
| `MPFS_LIM_LENGTH`, `MPFS_SCRATCHPAD_LENGTH` | `L2_*_Ways` × 128 KB, or the XML's L2 configuration | no LIM / no scratchpad |
| `MPFS_DDR_*_LENGTH` | `DDR_Present`/`DDR_*_KB`, or the XML's `mem_elements` | alias absent — the vendor's own idiom (§1.3) |
| `MPFS_DTIM_LENGTH` | `DTIM_KB`, E51 only | not this hart's, or not split as SRAM |
| `MPFS_E51_ITIM_LENGTH`, `MPFS_U54_n_ITIM_LENGTH` | `ITIM_KB` for the owning hart, **0 for the other four** (§1.4) | not this partition's — placement there becomes a link error |
| `MPFS_LOCAL_ITIM_ORIGIN`/`_LENGTH` | derived from `Harts` | ITIM unused by this partition |

In `system_partition` mode every one of these comes from `System_Map` rather than from a knob, so the FPGA design and the linker script cannot disagree (§4.1).

### 6.3 What is checked, where, and what is not

This is the part worth being precise about, because the three mechanisms have genuinely different reach:

| Check | Mechanism | Verified |
|---|---|---|
| a section exceeds its region | `ld` region overflow | §9 — `region 'ram' overflowed by 2096944 bytes` |
| something placed in a region this partition does not own | `LENGTH = 0` → overflow | §1.4 |
| two regions overlap **within one link** | — **nothing** | §9 — 32 KB overlap drew no diagnostic |
| two *partitions'* windows overlap | `pragma Compile_Time_Error` in `System_Map` | §4.4 |
| a window exceeds the §1.2 hardware maximum | `pragma Compile_Time_Error` in `System_Map` | §4.3 — the XML is designer *intent*, not ground truth |
| way allocations sum correctly | `pragma Compile_Time_Error` on `L2_*_Ways` | §5.3 |

The row that matters is the empty one: **`ld` never checks region overlap**, so no linker-side arrangement can catch a bad allocation. That is why the overlap checks live in Ada in `System_Map`, and why they must be *generated* from the same data that generates the scripts — a hand-maintained duplicate of the allocation would be exactly the second source of truth §4.1 rejects.

### 6.4 The one ordering rule

**L2 way programming stays out of the runtime, and the reset default makes that cheap.** All 15 non-cache ways are LIM after reset (§1.2.1), so a LIM-resident image needs *no* L2 programming at all — the runtime asserts its window fits and that is the whole story. Programming is required only to *shrink* LIM in favour of cache or scratchpad, and that is a single-actor action: five harts racing on `WayEnable`/`WayMask` is a bug, and it is peripheral policy rather than runtime mechanism. Either the HSS does it, or the monitor partition does it as ordinary application code before releasing the others.

**The L1 splits are the opposite case** (§1.4): ITIM and DTIM are per-hart and private, so a partition converts its own cache ways in its own startup with no coordination and no race. Enabling ITIM is something a partition may simply do; L2 reconfiguration is something a partition must be told has already happened.

So there is exactly one cross-partition ordering constraint, and it is not expressible as a compile-time check:

> A partition placed in LIM and a partition that reduces LIM are in a startup-order relationship.

`System_Map` should therefore record **which partition owns the L2 configuration**, and every other partition's window should be validated against the *post-configuration* layout rather than the reset one. The HSS payload YAML's `owner-hart` ordering and the XML's `RESET_VECTOR_HART*` entries (§4.1) are the data that makes this checkable at generation time; at run time it remains a contract.

---

## 7. SMP implementation

- `Max_Number_Of_CPUs` derived from `Harts`; `Multiprocessor` follows. In derived mode `Harts` *is* the payload YAML's `owner-hart` + `secondary-harts` (§4.1), so an SMP partition is declared once, in the file the bootloader already reads.
- `start-ram-smp.S` and `common-RAM-smp.ld` selected instead of the single-hart pair via config-driven `Excluded_Source_Files` — RTS.md's verified mechanism, and exactly what upstream's filename-suffix pairs become. Note this axis multiplies with `Privilege` (§4.2): single-hart/SMP × M-mode/S-mode is four startup variants, not two.
- **The hart set has three declarations that must agree**: the payload YAML's `owner-hart`/`secondary-harts`, the XML's `RESET_VECTOR_HART*`, and the runtime's own parking logic. Generating all three views from the same source (§4.1) is what keeps them consistent; hand-maintaining any one of them is how a hart ends up either unstarted or running two images.
- **SMP and AMP compose without new machinery**: an SMP partition is one root crate whose `Harts` names several harts; an AMP system is several such roots. "Monitor on E51, 2-hart SMP Ada partition on harts 1–2, single-hart partition on hart 3, Linux on hart 4" is four independent builds against one `mpfs_system`.
- **What SMP does *not* get**: ITIM. It is per-hart private, so a multi-hart image has no single ITIM to occupy (§1.4) — the fast-path placement trick is available to single-hart partitions only.

---

## 8. Source changes that configuration cannot fix

These are real patches to `rts_support_mpfs`, and they are prerequisites, not nice-to-haves:

1. **De-hardcode the hart index.** `CLINT_Mtimecmp_Offset = 16#4008#` must become `0x4000 + 8·mhartid` computed at run time; `PLIC_Hart_Id = 1` must become a per-hart context derivation (MPFS gives the E51 an M-mode context and each U54 M- and S-mode contexts, so context ≠ hart id). Without this, SMP is impossible and single-core is stuck on hart 1.
2. **Parameterise the startup hart set.** Both `start-ram.S` and `start-ram-smp.S` bake in which harts run and which park. They need a mask from the linker/`System_Map`.
3. **Make the float source variants config-selected**, not target-selected — the three files (`s-dorepr.adb`, `s-lidosq.adb`, `s-lisisq.adb`) that differ between soft and hard float.
4. **Add `zicsr`** to the E51 arch string, or place `.option arch, +zicsr` in the startup asm.
5. **Replace the flat 128 MB DDR memory map** with the region set of §1.2, in the symbolic-length form of §6.1 — every `ORIGIN` literal, every variable `LENGTH` a `--defsym`.
6. **Add L1 cache/SRAM split code.** Nothing in the runtime today enables ITIM or DTIM. Because the split is per-hart and private (§1.4), this is the partition's own startup work and needs no coordination — but it is new code, and it must run before anything is fetched from the window it creates.
7. **Support S-mode.** The bare-board runtime assumes M-mode throughout — CLINT `mtimecmp`, `mie`/`mip`, machine trap vector. A partition booted `priv-mode: PRV_S` under OpenSBI needs the supervisor equivalents (§4.2). This is the largest single item on this list and can be deferred past P4 if every partition boots `PRV_M`.
8. **Stop the runtime owning an MMUART.** `s-textio.adb` hardcodes MMUART0; in an AMP system that silently collides with whichever partition also claims it. Either make the instance a configuration value or — better — use the RAM-FIFO console so the runtime owns no peripheral at all.

---

## 9. What has already been verified

Measured on `alr 2.1.0`, `gnat_riscv64_elf` 15.1.2, macOS/Apple Silicon, using a copy of the shipped `light-polarfiresoc` runtime with its `adalib` deleted so the runtime rebuilt from source each time, `-march`/`-mabi` externalised in `runtime.xml`, and the three float files swapped from `light-rv64imac` for the soft-float case.

*(This was P0, run against a **shipped** runtime directory reached by gprconfig discovery — which is why `runtime.xml` is the vehicle here. The crates built since carry no `runtime.xml`; the ISA arrives from `target_options.gpr`, §11 item 13. The ISA findings below are properties of the toolchain and are unaffected.)*

| Configuration | Result | `Tag_RISCV_arch` |
|---|---|---|
| U54: `rv64imafdc` / `lp64d` (as shipped) | builds | `rv64i…f2p2_d2p2_c2p0_zicsr2p0_…` |
| E51: `rv64imac` / `lp64` | **fails** | `unrecognized opcode 'csrr t1,mhartid', extension 'zicsr' required` |
| E51: `rv64imac_zicsr` / `lp64` | builds | `rv64i2p1_m2p0_a2p1_c2p0_zicsr2p0_…` — **no `f`/`d`** |

Multilib resolution (`-print-multi-directory`): `rv64imac_zicsr`/`lp64` → `rv64imac/lp64`; `rv64imafdc`/`lp64d` → `rv64imafdc/lp64d`. Both installed.

**Symbolic region lengths (§1.3).** The runtime's `memory-map.ld` was changed from `LENGTH = 128M` to `LENGTH = MPFS_RAM_LENGTH`, with the value supplied from the application's `package Linker` as `-Wl,--defsym=MPFS_RAM_LENGTH=0x4000000`:

| Check | Result |
|---|---|
| does the link succeed? | yes |
| is the symbol really used? | `__heap_end = 0x8400_0000` = `ORIGIN + 0x0400_0000` — derived symbols follow it |
| is it enforced? | with `MPFS_RAM_LENGTH=0x200`: `section '.bss' will not fit in region 'ram'`, `region 'ram' overflowed by 2096944 bytes` |

Extending the same test to the local memories (§1.4), read back from `-Wl,-Map`:

```
Name             Origin             Length             Attributes
ram              0x0000000080000000 0x0000000004000000 axw
local_itim       0x0000000001810000 0x0000000000007000 xrw   <- ORIGIN also from --defsym
foreign_itim     0x0000000001810000 0x0000000000000000 xrw   <- zero-length, accepted
e51_dtim         0x0000000001000000 0x0000000000001c00 xrw
```

- **Symbolic `ORIGIN` works**, not just `LENGTH` — so a generic `local_itim` needs no per-hart script variant.
- **`LENGTH = 0` is accepted** and the region still appears in the map.
- **Region *overlap* is not diagnosed.** Two regions declared to overlap by 32 KB produced no linker diagnostic whatsoever; the only warnings in the build were Alire's own. `ld` enforces overflow, never overlap.

So variable region sizes need neither generated scripts nor a committed variant per combination, and an over-large partition is a link error — but overlap detection cannot be delegated to the linker, which is why §4 keeps it in `System_Map`.

**So the plan's load-bearing assumption holds: one family crate serves both core classes as configurations.** The second row is why the ISA knob must be a validated enumeration rather than a free string.

Also confirmed by inspection: the shipped `light-tasking-polarfiresoc` has `Max_Number_Of_CPUs = 1`; the shipped memory map is a single flat DDR region; upstream carries SMP startup/linker variants that the shipped build does not use.

---

## 10. Phases

| Phase | Deliverable | Milestone that proves it |
|---|---|---|
| **P0** ✔ | Spike: one source tree, both core classes; symbolic region sizes | done — §9 |
| **P1** | `rts_support_mpfs` + `light_mpfs` in **standalone mode** (§5): `Hart_Class`, the §6.1 memory script, five placement profiles, single hart, M-mode | E51 image **and** U54 image, both `Memory_Profile => lim`, both from one crate, on an Icicle Kit — LIM at its reset default, so no HSS memory setup, no DDR and no L2 programming. Then the same U54 image at `ddr_by_bootloader` to prove the profile axis |
| **P2** | Hart-indexed CLINT/PLIC (§8 item 1); L1 split code (§8 item 6); `light_tasking_mpfs` | Ravenscar tasking on hart 3, not hart 1; and an ISR placed in that hart's ITIM |
| **P3** | SMP: `Harts` set, smp source variants, `Max_Number_Of_CPUs > 1` | 2-hart and 4-hart SMP with `delay until` across cores |
| **P4** | Generator fork (§4.3) → `mpfs_system`; **derived mode**; AMP | monitor + 2-hart SMP partition + single-hart partition, all generated from the **Icicle Kit's own** `ICICLE_MSS_mss_cfg.xml` and an HSS payload config; plus a deliberately overlapping design that **fails to compile** |
| **P5** | S-mode support (§8 item 7); `embedded_mpfs`; PMP/U-mode partitioning; IPC over the non-cached alias | an Ada partition booted `priv-mode: PRV_S` under OpenSBI; exception propagation across a task; a PMP-confined partition faulting on a foreign window |

Ordering rationale: **P1 and P2 unblock everything** and need no vendor tooling at all, which is why standalone mode is a first-class path rather than a stepping stone. **P4 is where the design is genuinely novel** — deriving configuration from the MSS XML and payload YAML — and therefore where it is most likely to need revision. **S-mode moved to P5** because it is the largest single source change (§8 item 7) and nothing before it needs supervisor mode.

A useful property of this order: each phase's milestone is checkable on hardware without the next phase existing, and P1's does not even need a bootloader configuration.

---

## 11. Risks and open questions

**Settled during planning**

1. ~~L2 geometry is not pinned.~~ 16 ways × 128 KB, three roles per way, 1920 KB LIM at reset (§1.2.1). The validation rule is now exact and expressed in ways.
2. ~~DTIM is dedicated SRAM of fixed size.~~ It is a cache/SRAM split like ITIM, E51-only, so its length is configuration (§1.4).
3. ~~A system description must be designed.~~ Microchip ships both halves — the MSS Configurator XML and the HSS payload YAML (§4.1); inventing one was a mistake.
4. ~~Variable region sizes need generated linker scripts.~~ `--defsym` supplies both `ORIGIN` and `LENGTH`, and overflow is enforced (§1.3, §9).

**Open**

5. **Register encodings still to confirm from the TRM**: `WayEnable`/`WayMask` layout (needed only by whichever partition programs L2), the L1-I and L1-D **way sizes** (needed for the `ITIM_Ways`/`DTIM_Ways` checks in §5.3), and the PLIC **context** numbering — the shipped `PLIC_Hart_Id = 1` conflates hart id with context index, and getting the M-/S-mode context layout wrong is a silent interrupt-routing bug rather than a build failure.
6. **ISA extension strings are GCC-version-dependent.** `zicsr` had to be named explicitly at GCC 15; other versions differ in what the base strings imply. The enumeration must be validated per compiler-crate version, as RTS.md §4.3 concluded for RISC-V generally.
7. **`mpfs_system` is a convention Alire cannot enforce.** The two-input hash stamp (§4.4) turns staleness into a compile error, but nothing prevents a partition from not depending on the system crate at all, or from being rebuilt while a sibling was not.
8. **The generator fork inherits vendor register encodings.** Forking `mpfs_configuration_generator.py` (§4.3) keeps the XML-parsing half untouched, but the interpretation of raw values into frequencies, PMP regions and way counts is ours to maintain and will drift with the XML format version. The script already reads `xml_format_version`; the fork should refuse an unknown one rather than mis-decode it.
9. **`mem_elements` is designer intent, not hardware truth** (§4.3) — the Icicle reference labels its DDR entries "example instance" at 1 MB. Every derived window needs range-checking against §1.2 regardless of what the XML says.
10. **The L2 startup-order contract is not checkable at run time** (§6.4). Generation can verify that whoever reduces LIM runs first; nothing verifies it actually did.
13. **There is no `runtime.xml` — settled.** (Numbered out of sequence, and kept here rather than moved, because other files cite `§11 risk 5` and `risk 8` by number.)

    An earlier version of this item claimed `runtime.xml` "is parsed but its `Compiler` and `Linker` packages do not take effect" in a tier-composed runtime. **That was false.** The file under test was malformed XML — a `--` used as an em-dash inside an XML comment, which is illegal — and **gprconfig silently ignores an unparseable `runtime.xml`** at any verbosity. The mechanism works exactly as documented once the file is valid, as `embedded_rp2040` demonstrates in production. Retracted in full in RTS.md A.22.

    The files are nonetheless **deleted**, following `avrada_rts`, on a different and surviving argument: a gprconfig `<config>` fragment cannot `with` a crate's generated configuration project, so every value in it must arrive as an `external()` — a second source of truth beside the Alire configuration variable it duplicates. That is what produced the hard-float-E51 defect, and a malformed file being ignored in silence is what made it expensive to find. `target_options.gpr` now derives `Hart_Class` from `Harts_Mask` once and computes `ISA_Switches` from it, with no `external()` able to override.

    **The ABI-witness risk is closed, structurally.** It was real only while the ISA lived solely in the application's `Builder` package: runtime and application then both fell back to the compiler default and agreed. Now that the runtime library is compiled from its own derived ISA, a wrong application ABI cannot link — `ld: can't link soft-float modules with double-float modules`, verified by removing the `Builder` rename from `clock_switch_e51`. What remains genuinely missing from GPR is any way for a *withed* project to contribute required switches to its dependents; the rename is a convention, and conventions are forgettable.

11. **Who owns HSS.** This plan assumes HSS stays responsible for DDR training and optionally L2 configuration. Replacing it with Ada is a much larger project and explicitly out of scope.
12. **PMP/U-mode is deferred to P5** but the data exists in `pmp_h0…h4` (§4.2), so `System_Map` should carry per-hart PMP regions from the start — that keeps P5 a decoding exercise rather than a schema change.

---

## 12. Duplicate-code measurement of the spike

Every number below comes from `wc`, `diff -u`, `shasum -a 256`, `comm` and `git ls-files` run directly against `rts-spikes/` as it stands on disk (2026-07-31), never estimated. The counts were first taken while a concurrent rename was in flight (`gnat_user/` → `gnat_config/`, with the `mpfs_runtime_config.ads` shim moving to `src/`) and have since been re-measured against the settled tree; every changed-line figure below is the post-rename value. Five axes, matching §3's crate boundaries.

### 12.1 Provenance: tracked vs vendored

| | Tracked (`git ls-files`) | On disk now (`find -type f`) |
|---|---|---|
| all of `rts-spikes/` | 119 | 12,516 |

The gap is almost entirely build output (`obj*/`, `adalib*/`, `bin/`, `alire/`, `config/` — all gitignored) plus the vendored tier-1 snapshot. `rts-spikes/.gitignore` excludes `rts_sources_gcc15/libgnat*/` and `libgnarl*/` outright, and excludes `*/src/*.ad[bs]` wholesale, re-admitting only nine explicitly un-ignored hand-written files (five in `rts_support_mpfs/src`, two `s-bbpara.ads`, and the three `mpfs_runtime_config.ads` shims). The shims needed adding to that list: they moved into `src/` during the `gnat_config` rename and were covered by the blanket pattern, staying tracked only because `git mv` keeps an already-indexed file tracked regardless of `.gitignore` — a new leaf's shim would have been silently dropped. **A fresh clone has none of the tier-1/3 source counts below until `populate.sh` runs** against an installed `gnat_riscv64_elf_15.1.2` toolchain (CONTRACT.md §1); every count in §12.4 is therefore a vendored-working-tree number, not a repository fact.

### 12.2 Axis 1 — the three leaves' hand-maintained scaffolding

| File | `light_mpfs` | `light_tasking_mpfs` | `embedded_mpfs` | changed lines, LM↔LT / LM↔E / LT↔E | identical text, all 3 |
|---|---|---|---|---|---|
| `target_options.gpr` | 145 | 121 | 143 | 230 / 252 / 56 | 4 |
| `runtime_build.gpr` | 240 | 256 | 333 | 354 / 439 / 439 | 40 |
| `README.md` | 104 | 263 | 306 | 331 / 360 / 493 | 3 |
| `alire.toml` | 130 | 70 | 158 | 150 / 212 / 190 | 17 |
| `ravenscar_build.gpr` | — | 78 | 93 | — / — / 97 | (2 files) 30 |

("changed lines" = `diff -u | grep -c '^[+-]'`, header stripped — i.e. lines added plus removed, not a percentage.)

These are **not literal copies** — as few as 3 lines of `README.md` are word-for-word identical across all three — but they are near-copies in *structure*: same comment blocks, same `case Build is` skeleton, same ISA-derivation shape, reworded per leaf. `light_mpfs/target_options.gpr` is the visible outlier: it is the only one of the three still at 2-space indentation, still carrying the dead `Lib_Type`/`LOPTIONS` dynamic-library machinery the other two dropped, and still defaulting `GNAT_VERSION` to `"26"` where the others use `"15"` or nothing — a leftover from an earlier edit that was never propagated sideways. The shape of the divergence is what identifies it as drift rather than designed variation: `light_tasking_mpfs` and `embedded_mpfs` differ from each other by only **56** changed lines, while each differs from `light_mpfs` by **230** and **252**. Two of the three files converged on the newer three-space-indented, crate-prefixed-`external()` shape and the third was left behind — the opposite of what deliberate per-profile variation would look like, which would put the two *tasking* profiles together and `light_mpfs` nowhere in particular. §12.7 has the concrete cost of this pattern.

`runtime_build.gpr`'s 352–437 changed lines per pair are mostly genuine: `Config_Tag`, `Source_Dirs`, `Source_List_File` and the exported §3.7 variables differ by construction because each leaf lists a different tier-1 overlay and a different unit count. But the 40 lines identical across all three are the load-bearing derivation skeleton (`type Hart_Mask_Kind`, the `Hart_Class` case, the `ISA_Switches := Target_Options.ISA_Switches` restatement) — exactly the block CONTRACT.md §7.10 records as duplicated *and once wrongly re-derived*: `light_tasking_mpfs/runtime_build.gpr` used to assign `ISA_Switches` a second time, hardcoded to `rv64imafdc`/`lp64d`, silently overriding the `Hart_Class`-derived value and making that leaf hard-float for every hart mask. It survived because nobody was diffing these three files against each other; the fix (commit `4d9d4b9`, "delete runtime.xml, follow avrada_rts's pure-GPR pattern") moved the derivation into `target_options.gpr` as the single site and left a comment in `runtime_build.gpr` forbidding reassignment — a convention, not a structural guard.

### 12.3 Axis 2 — leaf-owned `src/` units

| Leaf | Files in `src/` | Tracked in git |
|---|---|---|
| `light_mpfs` | 14 | 1 (`mpfs_runtime_config.ads`) |
| `light_tasking_mpfs` | 21 | 2 (`mpfs_runtime_config.ads`, `s-bbpara.ads`) |
| `embedded_mpfs` | 21 | 2 (`mpfs_runtime_config.ads`, `s-bbpara.ads`) |
| **total** | **56** | **5** |

`shasum -a 256` over all 56 files, `sort \| uniq -c` on the digest: **43 distinct contents**, meaning **13 files are byte-for-byte duplicates of a file already counted** (26 of the 56 file-instances participate in a duplicate pair). Every duplicate pair is (`light_mpfs`, `light_tasking_mpfs`) or (`light_tasking_mpfs`, `embedded_mpfs`) — `a-except.{ads,adb}`, `a-strsup.{ads,adb}`, `a-tags.{ads,adb}`, `a-elchha.{ads,adb}`, `s-memory.{ads,adb}`, `s-parame.ads`/`.adb`, `s-assert.adb`, `s-bbpara.ads` — **none is identical across all three simultaneously**, and `mpfs_runtime_config.ads` (the one file present in all three) is genuinely distinct in each, as CONTRACT.md §3.3 intends for a per-leaf shim.

This is the leaf-level analogue of the tier-1 overlay problem in §12.4, at a tenth of the scale — and it is the more exposed one, because `populate.sh`'s prune step (CONTRACT.md, comment in the script) deliberately does **not** touch leaf `src/` dirs, "they hold hand-authored files... that no list names." That exemption is correct for the handful of genuinely edited files, but it means these 13 duplicated-but-unedited files sit in three copies with nothing checking they stay byte-identical — structurally the same blind spot that let the `runtime_build.gpr` ISA bug (§12.2) go undetected.

### 12.4 Axis 3 — tier-1/tier-3 overlays (`rts_sources_gcc15/`)

| Directory | Files | Tracked |
|---|---|---|
| `libgnat` (common) | 479 | 0 |
| `libgnat-light` | 11 | 0 |
| `libgnat-light-tasking` | 11 | 0 |
| `libgnat-embedded` | 462 | 0 |
| `libgnarl` (common) | 69 | 0 |
| `libgnarl-light-tasking` | 3 | 0 |
| `libgnarl-embedded` | 9 | 0 |

Same-basename comparison, common dir vs each overlay: **zero collisions in every case** — 0 identical, 0 differing, every overlay filename is absent from its common directory. `libgnat.lst`/`libgnarl.lst` now genuinely exclude every profile-variant unit (as CONTRACT.md §7.15's fix requires), so the tier-1 split is a clean partition, not padding.

But `libgnat-light` and `libgnat-light-tasking` are **100% duplicates of each other**: all 11 files, byte-identical by `cmp`, same 11 basenames. Two physical copies of one snapshot exist for no content reason — they exist because `light_mpfs` and `light_tasking_mpfs` are separate leaves, each needing its own directory on its own source path, and GNAT's configurable-runtime logic keys off *visibility* of a directory, not the identity of its contents (RTS.md A.23, CONTRACT.md §7.15). `libgnarl-light-tasking` (3 files) and `libgnarl-embedded` (9 files) share no filenames at all, so this doubling is confined to the `libgnat-light*` pair — it is the one place in the whole tier-1/3 layer where inherent (visibility-driven) duplication and *coincidentally* identical content overlap, and it is the cleanest illustration in this codebase of "duplication that is unavoidable, not sloppy": no `Source_Dirs` trick lets `light_tasking_mpfs` borrow `light_mpfs`'s overlay directory without also inheriting light's visibility set, so the copy is the price of the correct build, per RTS.md A.23 / CONTRACT.md §7.15.

`rts_core_riscv64/src` (tier 2) has exactly **6 files, 855 lines** — matching RTS.md §7's own count precisely — against tier 1's 479/462-file overlays; `rts_support_mpfs/src` (tier 3) has 15 files (5 tracked), 1,660 lines. Both confirm §7's scale claim directly on this spike rather than by analogy.

### 12.5 Axis 4 — linker scripts (`rts_support_mpfs/ld/`)

| File | Lines |
|---|---|
| `mpfs-memory.ld` | 73 |
| `place-envm.ld` | 201 |
| `place-envm-lma-scratchpad-vma.ld` | 199 |
| `place-lim-lma-scratchpad-vma.ld` | 199 |
| `place-ddr-by-bootloader.ld` | 192 |
| `place-lim.ld` | 193 |
| `app-sections.ld` | 3 |

Pairwise changed lines among the five `place-*.ld` range from 28 (`envm-lma-scratchpad-vma` ↔ `lim-lma-scratchpad-vma`, the two LMA≠VMA variants, which differ mainly in target region name) to 82 (`envm-lma-scratchpad-vma` ↔ `envm`, and `envm` ↔ `lim-lma-scratchpad-vma`). The line-set intersection across **all five** files at once — text identical regardless of order — is **122 lines**, roughly 62% of an average 197-line file. Reading what those 122 lines actually are: almost entirely the `SECTIONS` boilerplate (`.text`/`.data`/`.bss`/the full `.debug_*` block/stack and heap symbol arithmetic), not the memory map. The `MEMORY` block itself is **not duplicated at all** — every `place-*.ld` pulls it in with a single `INCLUDE mpfs-memory.ld` (§6.1), so the one part of the file that must stay byte-identical across profiles never has a chance to drift, because there is only one copy of it. `app-sections.ld` is a deliberately empty 3-line extension point, also `INCLUDE`d by every profile, so an application's own `-L` can override it without touching any of the five.

What differs between the five is exactly what should: which `MEMORY` region each output section targets (`> l2lim` vs `> envm` vs `> ddr_cached`), and, for the two `*-lma-scratchpad-vma` variants, an `AT>` load-address split for `.data` because code executing in place from eNVM cannot also hold writable `.data` there. That is genuine placement variation, not copy-paste residue — confirmed by inspection of the `place-lim.ld`/`place-envm.ld` diff, where every changed line is a region name or an added `AT>` clause, never a rewritten boilerplate rule.

### 12.6 Axis 5 — application crates (`hello_mpfs`, `clock_switch_e51`, `tasking_mpfs`, `embedded_app`)

| | `.gpr` lines | `alire.toml` lines |
|---|---|---|
| `hello_mpfs` | 30 | 26 |
| `clock_switch_e51` | 28 | 46 |
| `tasking_mpfs` | 25 | 28 |
| `embedded_app` | 25 | 28 |

Pairwise changed `.gpr` lines run 14–23 across all six pairs; changed `alire.toml` lines run 28–48. Text identical across **all four** `.gpr` files: **14 lines** — the `with "runtime_build.gpr"`/`with "target_options.gpr"` pair, the `for Target`/`for Runtime`/`for Source_Dirs`/`for Object_Dir`/`for Exec_Dir` restatement, `package Builder renames Target_Options.Builder;`, and the `package Linker is … Runtime_Build.Linker_Switches & Runtime_Build.Defsyms & ("-Wl,--gc-sections")` skeleton. Text identical across all four `alire.toml`: **11 lines** — `authors`, `licenses`, `maintainers`/`maintainers-logins`, `version`, and the bare `[[depends-on]]`/`[[pins]]`/`[configuration.values]` table headers.

This scaffolding is thin (roughly half of each `.gpr`, a fifth to a third of each `alire.toml`) but **mandatory**, not laziness: `gprbuild` reads `Target`, `Runtime` and `Builder` only from the root project, never from a withed dependency, so every application that wants the runtime's derived ISA has to restate the first two and rename the third (avrada_rts's pattern, CONTRACT.md §7.10). The remainder — `[[depends-on]]` version pins, `[configuration.values]` (`Harts_Mask`, `Memory_Profile`, `DTIM_Ways`, …; `Hart_Class` is derived, never set) — differs because each application genuinely targets a different hart, memory profile or peripheral set; `clock_switch_e51`'s longer `alire.toml` (46 vs 26–28) is not extra configuration: it used to carry an `[environment]` block setting `MPFS_ARCH`/`MPFS_ABI`, which became dead when `runtime.xml` was deleted and was removed; what remains in its place is the comment explaining why a second ISA knob must not come back (CONTRACT.md §7.10).

### 12.7 Inherent vs accidental — the verdict

**Inherent dominates, and it dominates by a wide margin.** Three of the five axes are duplication the design cannot avoid without a mechanism GPR/`ld`/GNAT does not offer:

- **Axis 3's `libgnat-light`/`libgnat-light-tasking` doubling** exists solely because GNAT decides feature availability from source-path *visibility*, not `Source_List_File` membership (RTS.md A.23, CONTRACT.md §7.15) — the crate must expose a per-profile overlay even when two profiles want identical content.
- **Axis 4's 122 shared `SECTIONS` lines** are boilerplate that could in principle be factored further, but the `MEMORY` block — the part that must never drift between profiles — already isn't duplicated at all (one `INCLUDE`d `mpfs-memory.ld`); what remains genuinely different is the placement, which is the entire point of having five files (RTS.md §5.3).
- **Axis 5's 14/11-line application skeleton** is forced by `gprbuild` reading `Target`/`Runtime`/`Builder` only from the root project.

**Axis 1 and axis 2 are where accidental duplication actually lives, and axis 1 already produced a real, shipped defect.** `light_tasking_mpfs/runtime_build.gpr`'s now-fixed second `ISA_Switches` assignment (hardcoded `rv64imafdc`/`lp64d`, silently overriding the `Hart_Class`-derived value, CONTRACT.md §7.10) is the textbook case: it survived precisely because the three leaves' `target_options.gpr`/`runtime_build.gpr` are close enough in shape (40 identical lines out of ~250 in `runtime_build.gpr`, only 4 out of ~140 in `target_options.gpr`, per §12.2) that nobody was diffing them line-for-line, and different enough (352–437 changed lines) that a casual read did not surface the redefinition. Axis 2's 13 byte-identical `src/` file pairs (§12.3) are the same failure mode *not yet* triggered: nothing but discipline keeps `light_tasking_mpfs/src/s-memory.adb` and `light_mpfs/src/s-memory.adb` in sync, and `populate.sh` explicitly does not prune leaf `src/` dirs, so a future edit to one copy alone would be invisible until a build broke or (worse) silently produced a working but subtly wrong image, exactly as the ISA bug did before §7.10 caught it.

### 12.8 Against §3 and RTS.md §7

**This does not undermine §3's seven-crate split.** The tier-1/tier-3 boundary is exactly as clean as RTS.md §7 predicted: zero basename collisions between common and overlay directories (§12.4), tier 2 at 6 files/855 lines against tier 1's 400+-file overlays — the same "6 files against ~1050" ratio RTS.md §7 states, confirmed here rather than merely asserted. It also does not undermine RTS.md §7's "tier 2 barely pays" conclusion; if anything it reinforces it, since this spike still keeps `rts_core_riscv64` as its own crate (§3 item 2) with the escape hatch "or folded into (1) per RTS.md §7" un-exercised, and nothing measured here gives a reason not to take that fold.

**What the measurement adds that §7 does not cover at all: the leaf layer itself.** RTS.md §7's "honest assessment" is framed entirely in terms of tiers 1–3; it says nothing about the three leaf crates' own scaffolding, because in the general design the leaf is meant to be "thin and generated" (RTS.md §7, closing line). On this spike the leaves are not generated — they are three hand-written `target_options.gpr`/`runtime_build.gpr`/`README.md`/`alire.toml` sets plus 56 hand-populated `src/` files — and axis 1/2 show that layer carrying exactly the kind of near-copy duplication §7 warns about for tiers, with one instance (§7.10) having already caused a real hard-float defect. That is a gap in RTS.md §7's boundary accounting, not a refutation of it: the fix is not to redraw the seven-crate boundary, but to extend the same discipline that already fixed the ISA duplication — single derivation, sibling renaming (`target_options.gpr`'s `Builder` export, CONTRACT.md §3.6) — to `runtime_build.gpr`'s `Config_Tag` block and the 13 duplicated `src/` files, rather than leaving three leaves to hand-copy them and trust that nobody edits only one.
