# Running the PolarFire images under QEMU

Delivers [A1](RTS-PRODUCTION.md#a1-get-one-byte-out-of-qemu): a documented,
working `qemu-system-riscv64` command line that prints something our
program wrote. Everything below is measured against QEMU 11.0.1
(Homebrew, macOS/aarch64 host) with `-M microchip-icicle-kit`.

## The working command

```
qemu-system-riscv64 -M microchip-icicle-kit -m 2G -nographic \
    -serial mon:stdio -bios none -kernel clock_switch_e51/bin/clock_switch_e51 \
    -no-reboot
```

or, via the Makefile (bounded so it cannot hang a terminal or CI job):

```
make qemu                       # clock_switch_e51, the app A1 names
make qemu QEMU_APP=hello_mpfs   # the other console-producing image
```

### How the run is bounded, and the way that does *not* work

A `-kernel` bare-metal image never exits on its own, so the target must
impose a limit. In CI an unbounded run is worse than a failing one, because
a hang is indistinguishable from a slow build.

This host has no `timeout`/`gtimeout` (BSD userland). The obvious
substitute — `perl -e 'alarm(N); exec ...'` — **does not work against QEMU,
measured**: QEMU installs its own `SIGALRM` disposition, so the inherited
alarm is swallowed and the target runs unbounded. Sending `SIGALRM` to a
running `qemu-system-riscv64` directly leaves it alive:

```
$ kill -ALRM <qemu pid>   # then, 2 s later
SIGALRM: qemu SURVIVED -> alarm() bound is ineffective
```

So `make qemu` backgrounds QEMU, races it against a `sleep`, and `SIGKILL`s
it on expiry. Verified to stop by itself in exactly `QEMU_TIMEOUT` seconds
with no stray process left behind.

**Measured output** (clock_switch_e51):

```
qemu-system-riscv64: warning: The QEMU microchip-icicle-kit machine does not generate a device tree, so no device tree is being provided to the guest.
E51 monitor: staging switch code into DTIM
E51 monitor: switching
E51 monitor: switch complete
```

**Measured output** (hello_mpfs):

```
qemu-system-riscv64: warning: The QEMU microchip-icicle-kit machine does not generate a device tree, so no device tree is being provided to the guest.
Hello from PolarFire SoC (U54 hart 1, LIM)
```

The warning line is QEMU's own, unconditional, and appears on every run
regardless of image; the lines after it are the two images' own
`Ada.Text_IO.Put_Line` calls.

### Proof the byte came from our program, not from QEMU or a stale binary

Changed `hello_mpfs.adb`'s message from `"Hello from PolarFire SoC (U54
hart 1, LIM)"` to `"A1 CAUSALITY CHECK 7f3c9 -- this is our program"`,
rebuilt (`alr -n build`), and reran the same command line:

```
qemu-system-riscv64: warning: The QEMU microchip-icicle-kit machine does not generate a device tree, so no device tree is being provided to the guest.
A1 CAUSALITY CHECK 7f3c9 -- this is our program
```

The output tracked the source change exactly. Reverted immediately after
(`git checkout -- hello_mpfs/src/hello_mpfs.adb`); `git status --short` was
clean before and after, and `make build && make verify` below still report
the five pinned metrics unchanged.

---

## What was wrong, and what was not

The task's own hypothesis list, in the order actually resolved:

### 1. "LIM might not be backed by QEMU's model" -- WRONG

Both `hello_mpfs` and `clock_switch_e51` are `Memory_Profile => lim`,
linking their whole image at `0x0800_0000` (`readelf -h`: `Entry point
address: 0x8000000` for both). Both printed their own text with no load
error and no illegal-instruction abort. LIM is fully usable as a `-kernel`
target under this QEMU model. `embedded_app`'s `ddr_by_bootloader` profile
(`0x8000_0000`) also loaded without error, so the DDR-resident fallback
the task's hypothesis 1 suggested was never actually needed -- **no new
app crate was created**, because the existing `lim`-profile apps already
work.

### 2. "MMUART base/divisor might disagree with QEMU's model" -- WRONG, and not even engaged

`rts_support_mpfs/src/s-textio.adb`'s `Initialize` procedure does not
program a divisor, baud rate, or line-control register at all -- it sets
one boolean flag. `Put` writes the output byte directly to `Base_Address +
16#00#` with no wait on `Is_Tx_Ready` first. `System.BB.Board_Parameters.
UART_Base_Address` is `16#2000_0000#`, which is exactly QEMU's
`MICROCHIP_PFSOC_MMUART0` base (`{ 0x20000000, 0x1000 }`, from
`hw/riscv/microchip_pfsoc.c`). There was no divisor mismatch to have,
because there is no divisor. QEMU's UART model accepted raw writes to the
data register immediately.

### 3. "Boot flow / HSS-in-eNVM expectation" -- RIGHT, this was the actual blocker

QEMU's own selection table (`docs/system/riscv/microchip-icicle-kit.rst`,
mirrored in `hw/riscv/microchip_pfsoc.c`) is:

```
-bios         | -kernel    | firmware
--------------+------------+--------
none          |          N | error
none          |          Y | kernel
NULL, default |          N | BIOS_FILENAME (hss.bin)
NULL, default |          Y | a generic OpenSBI fw_dynamic image
other         | don't care | other
```

**Measured**: the exact same `hello_mpfs` invocation with no `-bios` flag
(QEMU's default, which loads OpenSBI's `fw_dynamic` since a kernel was
given) produced *no console output whatsoever* within a bounded 12-second
run -- not even OpenSBI's own startup banner, which OpenSBI normally
prints unconditionally. Re-running with `-d guest_errors,unimp,int -D
qemu.log` logged nothing either. The most likely explanation (**inferred,
not measured further**): this machine "does not generate a device tree"
(QEMU's own warning, present on every run here since no `-dtb` was
supplied) and OpenSBI's dynamic firmware needs a discovered console via
the FDT it is handed; without one it may never reach a point where it can
print, and therefore never reaches our payload either. This matches
exactly the earlier report (`hello_mpfs` and `clock_switch_e51` both
"accepted... without complaint... and produced no console output"): both
prior attempts omitted `-bios none` and so went through this same dead
path.

`-bios none` removes OpenSBI entirely: with no firmware, `-kernel`'s ELF
entry point becomes the address QEMU's reset ROM jumps to, directly, in
M-mode, with no intermediate S-mode payload boundary. Confirmed fix,
reproduced above.

---

## What QEMU actually does at reset (measured from `hw/riscv/boot.c`,
`hw/riscv/microchip_pfsoc.c`, quoted from a QEMU source mirror)

- The machine creates one **E51 hart at hartid 0** (`e_cpus`,
  `hartid-base 0`, `SIFIVE_E51`) and up to four **U54 harts at hartid
  1..4** (`u_cpus`, `hartid-base 1`, `SIFIVE_U54`).
- With `-bios none`, `riscv_setup_rom_reset_vec` writes a small ROM blob at
  the reset vector (`0x2022_0000`, in the eNVM data region) that is
  **identical for every hart**: `csrr a0, mhartid`, then an unconditional
  `jr t0` to the ELF's entry point. There is **no hart-id gate in this ROM
  code** -- every hart that exists gets sent to the same address.
- With the default `-bios`, that same ROM instead jumps to OpenSBI's
  `fw_dynamic` image, which (per the measurement above) never produced
  observable output or reached our code in this configuration.
- DDR is mapped at `0x8000_0000` (`MICROCHIP_PFSOC_DRAM_LO`, 1 GiB),
  matching this project's `ddr_cached` region exactly. MMUART0..4 are at
  `0x2000_0000`, `0x2010_0000`, `0x2010_2000`, `0x2010_4000`,
  `0x2010_6000`.

## A surprising, well-evidenced finding: the wrong hart runs the E51 image

`rts_support_mpfs/src/start-ram.S` gates on a **hard-coded** `mhartid`,
independent of the image's `Harts_Mask`:

```asm
li   t0, 1 /* hart id that will be allowed to run */
csrr t1, mhartid
bne t0, t1, infinite_loop
```

with the comment *"we select hart one because it is the first core other
than the monitor, and the monitor doesn't have floating point support."*
This file is shared, unmodified, by every RISC-V MPFS leaf
(`light_mpfs`, `light_tasking_mpfs`, `embedded_mpfs`), so it runs
identically whether the image's `Harts_Mask` says hart 0 (the E51,
`clock_switch_e51`) or hart 1 (a U54, `hello_mpfs`/`tasking_mpfs`/
`embedded_app`).

**Measured** (temporary instrumentation only, reverted before commit --
see "Reproduce" below): inserted one line into a local copy of
`start-ram.S`, before the `bne` gate, that writes `mhartid + '0'` to the
MMUART0 data register. Rebuilt `clock_switch_e51` (`Harts_Mask => 1`,
i.e. built to run on hart 0, the E51) and reran it under the command
above. Output:

```
01E51 monitor: staging switch code into DTIM
...
```

Both digits `0` and `1` appear -- **both hart 0 and hart 1 reach
`_start_ram`**, exactly as the ROM-code reading above predicts (every
hart gets the same jump target, unconditionally). Hart 0 (the E51, which
is what `clock_switch_e51` is actually configured for) then takes the
`bne` branch to `infinite_loop` and produces nothing further. Hart 1 (a
U54!) is the one that satisfies the hard-coded `== 1` check and goes on
to execute `clock_switch_e51`'s body -- which is why the messages above
say "E51 monitor" but were, in this run, executed by a U54 core.

**Why this matters beyond QEMU.** The output is genuinely from our
program (the causality check above is unaffected by this), but it is not
evidence that `clock_switch_e51` runs correctly as designed. Its whole
premise (RTS-POLARFIRE.md 6.4: the E51 must perform the clock switch from
code *not resident in the memory being reconfigured*, because a
U54-resident LIM image cannot safely reconfigure the L2 timing it depends
on) requires hart 0 to be the one running it. Under QEMU with `-bios
none`, that premise is not tested -- a U54 core runs the E51 monitor's
code path instead, coincidentally producing the same printed text. On
real hardware, if Microchip's HSS releases *only* the E51 into a
`Harts_Mask => 1` partition (consistent with the AMP partition model this
project already assumes, RTS-POLARFIRE.md S6.3), hart 0 would hit this
same hard-coded gate and never call `main` at all -- `clock_switch_e51`
would sit in `infinite_loop` silently, forever. Whether HSS actually does
that is **not measured here** (needs a board, or a closer reading of the
HSS boot-flow code) -- flagged as a real, board-relevant risk, not
resolved.

**Not fixed in this task**, for two reasons: (1) `start-ram.S` is shared,
byte-for-byte, by every RISC-V MPFS leaf, so any change to it changes
`.text` for `hello_mpfs`, `clock_switch_e51`, `tasking_mpfs`, and
`embedded_app` alike, which would break the pinned metrics
(`1340 / 1756 / 8058 / 52436`) this task is required to preserve exactly;
(2) the right general fix -- gating on whether *this* hart's bit is set in
`Harts_Mask` rather than a literal `1` -- touches multi-hart masks too
(`Harts_Mask` can be a combination of U54 bits) and deserves its own
change and its own metrics re-baseline, not a rider on A1. Recorded as
follow-up work.

### Reproduce the hart-id measurement

```
$ git diff  # should be clean before starting
$ sed -n '24,26p' rts_support_mpfs/src/start-ram.S
        li   t0, 1 /* hart id that will be allowed to run */
        csrr t1, mhartid
        bne t0, t1, infinite_loop
```

Insert, immediately before the `li t0, 1` line:

```asm
csrr t1, mhartid
li   t2, 0x20000000
addi t3, t1, 48
sb   t3, 0(t2)
```

(and drop the now-duplicate `csrr t1, mhartid` a few lines down). Rebuild
`clock_switch_e51` (`cd clock_switch_e51 && alr -n build`), rerun the
command line above, observe the leading `01`, then `git checkout --
rts_support_mpfs/src/start-ram.S` and rebuild again to restore the
original binary before doing anything else.

---

## Which `Memory_Profile` values work

| `Memory_Profile` | App(s) | Result |
|---|---|---|
| `lim` (`0x0800_0000`) | `hello_mpfs`, `clock_switch_e51` | **Works.** Loads and prints under `-bios none`; causality-checked. |
| `lim` (`0x0800_0000`, RWX single-segment) | `tasking_mpfs` | Loads without error under the same command line. Produces no console output -- but `tasking_mpfs.adb` never calls `Ada.Text_IO` (it only ticks a protected counter via `delay until`), so silence here is not a finding about the memory profile, just about the app. |
| `ddr_by_bootloader` (`0x8000_0000`) | `embedded_app` | Loads without error under the same command line. Also produces no console output, and also never calls `Ada.Text_IO` (it raises and catches a `Constraint_Error` and delays); DDR was not exercised as a console path here. **Caveat, stated plainly: DDR is untested for console output** -- LIM is the profile actually proven to print. |

No profile failed to load. The task's suggested fallback ("try a
DDR-resident image instead") was not needed, because `lim` worked once
`-bios none` was supplied -- the memory profile was never the blocker.

## Caveats and what is still unmeasured

- Only `hello_mpfs` and `clock_switch_e51` were used to prove console
  output, because they are the only two of the five spike applications
  that call `Ada.Text_IO` at all. `tasking_mpfs` and `embedded_app`'s
  silence under QEMU is expected and uninformative, not a negative
  result.
- The hart-identity finding above is real and board-relevant but
  unresolved: it is not known whether real hardware's HSS would release
  hart 0 or hart 1 (or both) into a `Harts_Mask => 1` partition's image.
- The reset-ROM and firmware-selection behaviour above is read from QEMU's
  own source (`hw/riscv/boot.c`, `hw/riscv/microchip_pfsoc.c`) via a
  source mirror, not from a local checkout of the QEMU tree -- flagged as
  read-not-verified-by-recompilation, though it matches every measurement
  taken here.
- `-serial mon:stdio` was used throughout, matching the task's own prior
  measurement. It multiplexes the QEMU monitor onto the same stream but
  was never invoked for anything but plain console capture here.

## `make build && make verify` after all of the above

The five metrics are pinned by [A2](RTS-PRODUCTION.md#a2-make-the-metrics-assertions-rather-than-decoration)
(not yet automated) and were reconfirmed by hand before committing:

```
APP                TEXT     BSS       ENTRY       FLOAT
hello_mpfs         1340     65541     0x8000000   hard
clock_switch_e51   1756     65545     0x8000000   soft
tasking_mpfs       8058     42368     0x8000000   hard
embedded_app       52436    1144944   0x80000000  hard
hello_rp2040       1984     2196      0x10000381  v6S-M
```

`git status --short` was clean both before starting and after reverting
the two temporary, uncommitted diagnostic edits described above.
