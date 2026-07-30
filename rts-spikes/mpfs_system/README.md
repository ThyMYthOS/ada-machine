# mpfs_system

Crate 7 of the rts-spikes hierarchy (RTS-POLARFIRE.md §3, §4): the generated
AMP system description for the PolarFire SoC. See
[../CONTRACT.md](../CONTRACT.md) for the overall layout and
[../../RTS-POLARFIRE.md](../../RTS-POLARFIRE.md) §4 for the design this
crate implements.

## What this crate is

An AMP system is N independent binaries (RTS-POLARFIRE.md §4): each
partition is its own Alire root, and Alire configuration only flows
downward from a root, so no partition's manifest can carry an agreement
that spans all of them. `mpfs_system` is the answer — not configuration,
but **generated data every partition depends on**: which harts, which
memory windows, which console, which privilege mode, and which partition
owns the L2 configuration. Because it is the one place that sees every
partition at once, it is also the only place that can make the
cross-partition checks (window overlap, hart collisions, MMUART
collisions, hardware-maximum violations, an IPC window placed somewhere
coherence isn't free) — everything else in the hierarchy sees at most one
partition.

`src/mpfs-system_map.ads` holds a worked three-partition Icicle-Kit-like
example. `ld/partition-<name>.ld` holds the per-partition linker
placement scripts that would accompany it.

## This is a hand-written stand-in, not a generator run

In the real design this whole crate is emitted by a fork of Microchip's
`mpfs_configuration_generator.py`, reading two vendor files:

- **The MSS Configurator XML** — one per board, in the HSS repository,
  e.g. `boards/mpfs-icicle-kit/soc_fpga_design/xml/ICICLE_MSS_mss_cfg.xml`.
  This is the hardware envelope: memory instances and their base/size,
  per-hart PMP configuration, which peripherals (including which MMUART)
  appear in which AXI split, clock tree and DDR configuration.
- **The HSS payload YAML** — the config consumed by
  `tools/hss-payload-generator`. This is the software partitioning:
  `hart-entry-points` plus a `payloads` map, each entry naming an
  `owner-hart`, optional `secondary-harts` (an SMP partition), and a
  `priv-mode`. This crate's worked example copies its hart ownership and
  privilege modes directly from the sample YAML already quoted in
  RTS-POLARFIRE.md §4.1 rather than inventing them.

Nothing in `src/mpfs-system_map.ads` or `ld/*.ld` was decoded from a real
vendor file — there was no XML or YAML to read for this spike. Every
value is hand-picked but shaped exactly as the generator would emit it,
so the file is honestly marked as a stand-in in its own header comment.
Hand-editing a file like this in the real design is precisely the
"second source of truth" RTS-POLARFIRE.md §4.3 rejects; it is acceptable
here only because the point of this crate is to demonstrate the
mechanism (the static cross-partition checks), not to describe a real
system.

## The generator fork (RTS-POLARFIRE.md §4.3)

Microchip's own
[`polarfire-soc-configuration-generator`](https://github.com/polarfire-soc/polarfire-soc-configuration-generator)
is a single 677-line Python file, `mpfs_configuration_generator.py`
(~28 KB; the repository contains nothing else but a Jenkinsfile). Its
C-emission surface — the part a fork replaces to emit Ada and linker
fragments instead of C headers — is about six functions:

- `start_define` / `end_define` — C `#ifndef`/`#define` include guards
- `start_cplus` / `end_cplus` — `extern "C" { … }` wrapping
- `write_line` — the line-oriented C output writer
- `generate_header` — the file-level header/banner emission

Everything else is **reused unchanged**, because it is the vendor's own
knowledge of the XML format, not C-specific: `read_xml_file` and the
ElementTree traversal that walks the document, and the `input_xml_tags`
tables that say which XML elements matter. `generate_mem_elements` and
`generate_register` also carry over structurally — they already walk
exactly the sections this crate needs (`mss_memory_map`, `pmp_h0..h4`,
`apb_split`) — only their emission target changes from a C `#define` to
an Ada constant declaration or a `pragma Compile_Time_Error`.

What a fork does **not** buy: the tool emits register *values*, not
decoded *semantics*. `generate_mem_elements` produces raw
`LIBERO_SETTING_<NAME>`/`_SIZE` pairs straight from XML attributes;
turning a PLL register into a frequency or `PMP0CFG = 0x9F` into a
base/size still has to be written, in Ada, in `rts_support_mpfs`
(RTS-POLARFIRE.md §4.3) — this crate only carries the pipeline's output
data, not a register decoder.

## Two-input hash-stamp staleness mitigation (§4.4)

Nothing stops a partition from being built against a stale
`mpfs_system`, or from the FPGA design being re-exported while the HSS
payload assignment is not (or vice versa). The mitigation the real
generator applies: stamp a hash of **both** vendor inputs — the MSS XML
and the HSS payload YAML — into the generated spec
(`Mss_Config_Xml_Hash`, `Hss_Payload_Yaml_Hash` in
`src/mpfs-system_map.ads`; fixed placeholder values here, since this
stand-in was not generated from real files). Each partition is then
expected to assert its own compiled-in expectation against those two
values with its own `pragma Compile_Time_Error`. That conversion of
"stale" into a compile error was checked in isolation for this crate
(task report): a cross-package reference to a `String` constant remains
a static expression in Ada, so the pattern genuinely compiles.

What this does **not** buy, and RTS-POLARFIRE.md §11 item 7 says so
plainly: `mpfs_system` cannot perform the assertion itself, cannot force
a partition to depend on it at all, and cannot detect a partition that
depends on it but skips the check. The hash stamp is a convention
Alire's dependency graph cannot enforce, not a guarantee.

## Verification

`src/mpfs-system_map.ads` is `Pure` (see the spec's own top-of-file
rationale) and self-contained — it only `with`s the predefined `Pure`
package `Interfaces` — so it needed no cross toolchain to check: it was
compiled directly with the native `gnat_native` GNAT (`gcc -c -gnatc`),
which needed no `alr` workspace once the toolchain's own `bin/` directory
was used directly. The full verification, including two deliberate
data-corruption tests confirming the `pragma Compile_Time_Error` checks
actually fire (not merely compile), is in the task report rather than
duplicated here.

## What is NOT verified here

- **The three `ld/partition-*.ld` scripts are not link-tested.** There is
  no object code to link them against in this task's scope, and
  `rts_support_mpfs/ld/mpfs-memory.ld` — which they `INCLUDE` — does not
  exist yet at the time of writing (only `*.ld.upstream` reference
  copies are present under `rts_support_mpfs/ld/`). The `INCLUDE` path
  (`../../rts_support_mpfs/ld/mpfs-memory.ld`) follows CONTRACT.md's
  pinned directory name and RTS-POLARFIRE.md §6.1's file name; it is an
  assumption about a sibling crate still being built, not a verified
  fact.
- **The L2 configuration ordering rule (§6.4) is recorded, not
  enforced.** `L2_Configuration_Owner` names the partition responsible;
  nothing can check that it actually ran first, because that is a
  property of one specific boot sequence across N independently linked
  binaries — observable at run time at the earliest, never at any one
  partition's compile time.
- **The two 38-bit DDR aliases' non-cached/WCB sizes are "board-dependent"
  (RTS-POLARFIRE.md §1.2)** — there is no SoC-fixed ceiling for those two
  regions the way there is for every other region, so no "exceeds
  hardware maxima" check is possible for them from this crate alone. This
  stand-in's worked example does not use either alias, so the gap does
  not affect it, but a partition that did would need that ceiling from
  the board's own DDR controller configuration, not from this crate.

## Licence

`Apache-2.0 WITH LLVM-exception`, matching this repository's own
non-runtime-source crates (e.g. `machine`, `bme280` in the sibling
`ada-machine-spikes` tree) rather than the GPL-3.0-or-later
WITH GCC-exception-3.1 of the tier-1-3 runtime-source crates
(CONTRACT.md §2): unlike those, nothing here is a copy of GNAT runtime
source — it is original, hand-authored data standing in for a
generator's output.
