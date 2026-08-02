# rts_core_cortexm

Tier 2 (source-only) of the `rts-spikes-rp2040` hierarchy: the ARM equivalent
of `rts-spikes/rts_core_riscv64`. Six files, same count as RISC-V's six, but a
**different composition** -- this is the headline finding for this crate.

`src.lst` is the combined membership used by `populate.sh` (provenance, mirrors
`rts-spikes`'s combined `*.lst` files). `src.gnat.lst` (3) and `src.gnarl.lst`
(3) are the two per-library `Source_List_File`s the leaf actually builds
with -- one directory feeding two different library projects needs two lists
(`rts-spikes/CONTRACT.md` §7.7), because `s-bb.ads`/`s-bbarat.*` compile into
`libgnat` while `s-bbcppr.*`/`s-bbcpsp.ads` compile into `libgnarl`.

## The six files

```
s-bb.ads         System.BB                    (gnat side  -- present in EVERY profile, incl. the non-tasking light-cortex-* runtimes)
s-bbarat.ads     System.BB.Armv6m_Atomic       (gnat side  -- ditto)
s-bbarat.adb
s-bbcppr.ads     System.BB.CPU_Primitives      (gnarl side -- tasking profiles only)
s-bbcppr.adb
s-bbcpsp.ads     System.BB.CPU_Specific        (gnarl side -- tasking profiles only; no .adb)
```

## How this compares to RISC-V's six

RISC-V (`rts_core_riscv64/src.lst`): `s-bb.ads`, `context_switch.S`,
`s-bbcppr.ads/.adb`, `s-bbcpsp.ads/.adb`.

Differences, both verified directly against the installed toolchains:

1. **No separate context-switch assembly file.** RISC-V's context switch lives
   in `context_switch.S`, a standalone `Asm_Cpp` unit. ARM's lives **inline**,
   as `Asm` statements inside `s-bbcppr.adb` (617 lines, 15 occurrences of
   `Asm` counted directly) -- there is no `.S` file for it anywhere in
   `light-tasking-rpi-pico/gnarl`.
2. **An extra unit RISC-V does not need: `System.BB.Armv6m_Atomic`.**
   ARMv6-M (Cortex-M0/M0+/M1) has no LDREX/STREX exclusive-access
   instructions -- those arrived at ARMv7-M -- so atomic read-modify-write
   needs a software (interrupt-masking) emulation. RISC-V's `rv64imac` always
   includes the `A` (atomic) extension, even at the E51's narrowest
   configuration, so no analogous unit exists on that side. This unit is
   present even in the fully non-tasking generic-core profiles
   (`light-cortex-m0p` etc., which have no `gnarl` at all), confirming it is
   architecture-level, not tasking-level.
3. **`s-bbcpsp.ads` has no body** on this target (spec-only); RISC-V's does.

## Does RTS.md's "tier 2 barely pays" conclusion generalise?

Yes, on the numeric axis (six files either side is a thin layer by any
measure), but the **reason** it is thin is target-specific in a way RTS.md's
RISC-V-only text does not anticipate: RISC-V's tier 2 is thin because the ISA
already provides what a CPU-primitives layer would otherwise have to
synthesise (native atomics). ARM's tier 2 is thin for schedule/count reasons
only -- it still has to synthesise atomics in software, it just does not need
much code to do it (Armv6m_Atomic is small). A Cortex-M target with a
different ARMv*-M generation could plausibly need a **different**
Armv*m_Atomic variant (see `light-cortex-m4` vs `light-cortex-m0p`, which
differ only in the sqrt tier-1 overlay, not here -- their CPU_Primitives
family was not diffed further in this spike, but the existence of ten
separate `light-cortex-*` runtime directories in this one toolchain, one per
core, is itself evidence that tier 2 is the axis most likely to vary again if
this design were pushed across the whole Cortex-M family rather than one
device).

## Verified independently: `breakpoint_handler-cortexm.S` membership

This file is **not** part of `rts_core_cortexm` (it lives in the common tier-1
directory, not here -- it is byte-identical across every Cortex-M profile in
this toolchain, `light-cortex-m0p` included) but it is worth recording here
because it is the sharpest illustration of CONTRACT.md §7.18's "audit the
compiled artifact, not source presence" rule found in this spike. The file's
assembly hardcodes `.cpu cortex-m4` even though it is present in
`light-cortex-m0p`'s source tree. Checked directly with
`arm-eabi-ar t light-cortex-m0p/adalib/libgnat.a`: **it IS present** as
`breakpoint_handler-cortexm.o`, defining the weak symbol `__gnat_bkpt_trap`,
in both `light-cortex-m0p` and `light-tasking-rpi-pico`'s prebuilt
`libgnat.a`. Reading the source explains why the `.cpu cortex-m4` directive is
harmless here: every instruction the handler actually uses (`and`, `cmp`,
`beq`, `mrs`, `add`, `ldr`, `str`, `bx`) is valid ARMv6-M Thumb, so the file
assembles and links on Cortex-M0+ despite the stale `.cpu` line -- GNU `as`'s
`.cpu` directive controls instruction-set *validation* within the file, not
what the command-line `-mcpu=` target actually requires. So this is presence
**and** membership, contradicting a claim floated mid-task that it was
present-but-not-a-member; the general lesson (verify via `ar t`/`.ali`, don't
trust source-tree presence) still held, it just pointed the other way once
actually checked.
