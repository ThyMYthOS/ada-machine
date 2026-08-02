# rts_sources_gcc15_arm

Tier 1 (source-only) of the `rts-spikes-rp2040` hierarchy: the libgnat/libgnarl
snapshot shared by every arm-eabi runtime profile this spike touches. Mirrors
`rts-spikes/rts_sources_gcc15` for PolarFire/RISC-V (see `../../rts-spikes/CONTRACT.md`
§1-§2), including the same shortcut: **sources are not committed**. `populate.sh`
(one level up) copies the files named in the `.lst` files here out of an
installed `gnat_arm_elf` 15.1.2's `light-tasking-rpi-pico` runtime. A published
crate would vendor them; this is a spike.

## Contents

| Directory | `.lst` | Files | Source |
|---|---|---|---|
| `libgnat/` | `libgnat.lst` | 362 | `light-tasking-rpi-pico/gnat`, content-identical to `embedded-rpi-pico/gnat` for 351 of them; 11 exist only in the light-tasking profile (`s-memcom`, `s-memcop`, `s-memmov`, `s-memset`, `s-memtyp`, `s-sssita` -- embedded links against newlib and needs none of them) |
| `libgnarl/` | `libgnarl.lst` | 75 | `light-tasking-rpi-pico/gnarl`; 72 content-identical to `embedded-rpi-pico/gnarl`, plus `s-restri.ads/.adb`, `s-rident.ads` (identical byte-for-byte to `embedded-rpi-pico`'s **gnat**-side copies -- CONTRACT.md §7.17's "one directory, library membership decided by the leaf's list" pattern, confirmed on ARM) |
| `libgnat-armv6m/` | `libgnat-armv6m.lst` | 2 | `s-lidosq.adb`, `s-lisisq.adb` -- RP2040/Cortex-M0+ variant of the double/single sqrt helpers (populated) |
| `libgnat-armv8m/` | (none) | 0 | RP2350/Cortex-M33 variant -- **not populated**, no RP2350 runtime ships in this toolchain |

## How these numbers were derived

Measured directly (not estimated), comparing this toolchain's
`light-tasking-rpi-pico` and `embedded-rpi-pico` runtimes (`gnat_arm_elf`
15.1.2, `$HOME/.local/share/alire/toolchains/`):

- `light-tasking-rpi-pico/gnat` = 398 files, `gnarl` = 84 files.
- `embedded-rpi-pico/gnat` = 845 files, `gnarl` = 90 files (embedded is far
  larger for the same reason it is on RISC-V: exception propagation and the
  full image/Put_Image machinery -- CONTRACT.md §7.15).
- Of the 398/84, the files that are genuinely CPU-architecture level
  (`rts_core_cortexm`, 6), RP2040-board-specific (`rts_support_rp2040`, 17),
  device-variant (2), or profile/leaf-owned (20, matching almost exactly the
  RISC-V profile-variant set: `a-except`, `a-elchha`, `a-strsup`, `a-tags`,
  `s-assert`, `s-memory`, `system.ads`, `s-parame.*`, `s-taskin`, `s-tpobop`,
  `s-tposen`, `s-bbpara`) were pulled out first; **362 + 75 = 437 is what is
  left**, and 437 + 6 + 17 + 2 + 20 + 11(light-tasking-only, folded into
  `libgnat.lst` since there is no second leaf here to need excluding them) =
  482 = 398 + 84 exactly. Every file in both source trees is accounted for.

## Device axis (new relative to the PolarFire spike)

Across this toolchain's ten chip-agnostic `light-cortex-*` runtimes (m0, m0p,
m1, m23, m3, m33df, m33f, m4, m4f, m7df, m7f), the 380-file source tree is
identical except for `s-lidosq.adb`/`s-lisisq.adb` (soft-float sqrt), which
vary with FPU/architecture generation. `light-cortex-m0p` (ARMv6-M, ==
RP2040's Cortex-M0+) vs `light-cortex-m33f` (ARMv8-M, == RP2350's Cortex-M33)
differ in exactly these 2 of 380 -- verified directly with `diff -rq`. That is
CONTRACT.md §7.16's "overlay keyed by content, not by profile name" applied to
a **device** axis rather than a **profile** axis: PolarFire never needed this,
because RISC-V's Hart_Class variance (E51 vs U54) is purely an ISA-switches
question with no source-level difference. On ARM the two axes are independent
and this repository only needed the device axis at the tier-1 level, once.
