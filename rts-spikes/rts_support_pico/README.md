# rts_support_rp2040

Tier 3 (source-only) of the `rts-spikes-rp2040` hierarchy: RP2040 board
support, mirroring `rts-spikes/rts_support_mpfs`. 17 files in `src.lst`,
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

Genuinely RP2040-only, unlike tier 1: this toolchain ships no RP2350 board
runtime at all (only the generic, board-agnostic `light-cortex-m33f` etc.), so
there is nothing to diff an RP2350 board-support variant against, and no
overlay is attempted here. See `../rts_sources_gcc15_arm/README.md` for where
the device axis actually lives (two sqrt files, tier 1).
