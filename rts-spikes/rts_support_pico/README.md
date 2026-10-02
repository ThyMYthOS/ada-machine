# rts_support_pico

Tier 3 (source-only) of the `rts-spikes` hierarchy: Raspberry Pi Pico board
support for **both** RP2040 and RP2350, mirroring
`rts-spikes/rts_support_mpfs`. Named for the family, not a device, because
that is what tier 3 varies by (RTS.md §6). 17 files in `src.lst`,
derived by diffing `light-tasking-rpi-pico/gnat` (398 files) against the
generic, board-agnostic `light-cortex-m0p/gnat` (380 files) -- the 18-file
difference, minus `s-parame.adb` (leaf-owned, differs in *content* rather
than being board-specific, kept in `light_tasking_pico/src`), is exactly this
crate:

```
boot2.S                    RP2040 stage-2 bootloader (the 256-byte, checksummed
                            image the on-chip boot ROM copies into SRAM and
                            executes before jumping to flash-resident code)
start-rom.S                ROM entry point / vector table / jump to Ada elaboration
s-bootro.ads/.adb          System.Bootrom -- boot ROM function table lookups
i-rp2040.ads               top-level peripheral-address package
i-rp2040-clocks.ads        \
i-rp2040-pll_sys.ads        |
i-rp2040-psm.ads            |
i-rp2040-resets.ads         | RP2040 peripheral register interfaces
i-rp2040-rosc.ads           | (clocks, resets, oscillators, timer, SIO, watchdog)
i-rp2040-sio.ads            |
i-rp2040-timer.ads          |
i-rp2040-watchdog.ads       |
i-rp2040-xosc.ads          /
s-bbbopa.ads               System.BB.Board_Parameters
s-bbmcpa.ads               System.BB.MCU_Parameters
setup_clocks.adb           clock-tree initialisation run before elaboration
```

Plus `ld/common-ROM.ld` and `ld/memory-map.ld`. `common-ROM.ld` is verbatim from
the same runtime (and byte-identical to `embedded-rpi-pico`'s copy, checked);
XIP flash boot via `boot2`, used as-is. There is no PolarFire-style
memory-profile axis, so unlike `rts_support_mpfs` there is no family of
placement scripts here.

`memory-map.ld` is the **one modified file** in this crate. The vendor copy has
`LENGTH = 2M` for flash; here it is `LENGTH = PICO_FLASH_LENGTH`, supplied by
the leaf from `Flash_Size_KB`. The QSPI flash is external and a board choice --
2/4/8/16 MB parts all ship on RP2040 boards -- and the published
`embedded_rp2040` crate spends four committed directories on exactly that one
number (RTS.md §5.3 / [A.25](../../RTS.md#a25)). `sram` stays literal at 256 KB
at `0x2000_0000`, because on-chip SRAM is a property of the die and not
configurable. Verified that the value genuinely reaches `LENGTH(flash)` rather
than being substituted and ignored: with the script's `ASSERT` threshold
temporarily raised to `4M`, the link fails at `Flash_Size_KB = 2048` and
succeeds at `4096`.

## The device axis

This crate serves both devices, and the split is measured rather than guessed.
`gnat_arm_elf` ships no RP2350 board runtime at all (checked in 15.1.2 and 15.3.1) (only the generic
`light-cortex-m33f` and friends), so the RP2350 half was taken from the
published `light_rp2350` / `light_tasking_rp2350` crates. Under this tree's
ownership rule -- tier 1 tracks upstream, everything below it is ours
(`../CONTRACT.md` §1) -- that is not a second kind of upstream needing its own
assertion; it is simply ours, with no second copy to drift from.

Measured against those crates: of ~400 units, **378 are byte-identical, 5
differ, 18 are RP2040-only and 13 RP2350-only**, and the device-only names are
**disjoint** (`i-rp2040-*.ads` versus `i-rp2350-*.ads`, `boot2-*.S` versus
`image_def.S.inc`). Disjoint names need no overlay -- one directory holds them
and each leaf's `Source_List_File` picks its own. So the layout is:

```
src/           19 device-neutral units, shared
src-rp2040/    s-bbbopa.ads s-bbbosu.adb s-bbmcpa.ads setup_clocks.adb start-rom.S
src-rp2350/    the same five names, RP2350 content
```

A leaf puts exactly one `src-<device>/` ahead of `src/` in `Source_Dirs`; both
directories are exported by `rts_support_pico.gpr` as `Rp2040_Dir` and
`Rp2350_Dir`.

**What is still missing for an RP2350 leaf to build** — the overlay is here,
the rest is not:

- `ld/` holds only the RP2040 pair. The RP2350 scripts differ (six files versus
  five in the published crates) and have not been compared.
- `light_tasking_pico/target_options.gpr` maps `rp2350` to `-mcpu=cortex-m33`
  with `-mfloat-abi=soft`; the published crate uses **hard**, and its M33 FPU is
  single-precision — so an RP2350 leaf also needs its own
  `rts_capabilities.ads` (`Has_Hw_Sqrt_Single => True`,
  `Has_Hw_Sqrt_Double => False`; see that file's header).
- `a-intnam.ads` is absent from the RP2350 crate's `gnat/` and `gnarl/`, and
  that is unexplained.
- `light_tasking_pico/src/pico_config_checks.ads` still rejects the value.
