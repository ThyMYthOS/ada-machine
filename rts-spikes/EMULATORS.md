# Renode or QEMU for the runtime's tests

Research only. Nothing in this file was run on Renode: it was not installed,
and no Renode binary exists on this machine. Every Renode statement is one of

- **docs** — read in Renode's or QEMU's documentation,
- **source** — read in the public source (file named; Renode peripherals from
  `renode-infrastructure` master as fetched 2026-10-01, `.repl`/`.resc`/`.robot`
  from the `renode` tag v1.17.0),
- **measured** — measured in this project with QEMU (QEMU.md, RTS-PRODUCTION.md
  A3/A4) or queried from the GitHub API on 2026-10-01 (release dates, asset sizes),
- **inference** — mine, from the above; not shown.

What a hands-on trial would settle is in [Open questions](#open-questions--to-settle-by-a-hands-on-trial).

## Summary and recommendation

**Keep QEMU as the only gating emulator; trial Renode as a non-gating second opinion.**

- Renode ships an MPFS platform with more of what the runtime touches than QEMU (L2 WayEnable, ITIMs, populated sysreg, Robot tests) but is not in apt: CI would pin a downloaded tarball.
- It would tell us nothing about PLIC_INIT, and would hide it: its PLIC allows `QuadWordToDoubleWord` (source), so the 64-bit `sd` is split and accepted; QEMU's PLIC allows 4-byte accesses only (source) and faults. Neither is silicon; the PLIC spec says 32-bit registers, LW/SW (docs).
- The xfail rows in `tests.list` match QEMU's `-d int` trace and do not port; the three PLIC_INIT rows would become `UNEXPECTED PASS` under Renode.
- RP2040: neither emulator ships it; Renode only via the third-party `matgla/Renode_RP2040` (pinned to Renode 1.16.1, current is 1.17.0). QEMU has no RP2040 machine.
- Deterministic time is Renode's design; QEMU has `-icount ...,sleep=off`, untried here. Try both before counting it as a differentiator.

## Side-by-side

| | QEMU (microchip-icicle-kit, v10.2.1 source; 11.x measured) | Renode (`polarfire-soc.repl` + `mpfs-icicle-kit.repl`, v1.17.0) |
|---|---|---|
| Platform shipped | Yes, `hw/riscv/microchip_pfsoc.c` (source) | Yes, `platforms/cpus/polarfire-soc.repl`, `platforms/boards/mpfs-icicle-kit.repl`, `scripts/single-node/{polarfire-soc,icicle-kit}.resc` (source) |
| Harts | E51 hartid 0 + up to 4 U54, hartids 1–4 (source) | `e51` rv64imac id 0, `u54_1..4` rv64gc ids 1–4, `Priv1_10` (source) |
| MMUART0–4 | at 0x2000_0000, 0x2010_0000, 0x2010_2000, 0x2010_4000, 0x2010_6000; PLIC IRQ 90–94 (source) | same addresses, `UART.NS16550` with `wideRegisters: true`, IRQ 90–94 (source); NS16550 has byte and dword interfaces |
| CLINT / mtime | ACLINT SWI+MTIMER at 0x200_0000; property `clint-timebase-frequency`, default 1 000 000 Hz (source) | `CoreLevelInterruptor` at 0x200_0000, `frequency: 1000000`, 5 targets (source). Writes of 64-bit `mtimecmp` are split into lo/hi 32-bit writes by `QuadWordToDoubleWord` (source; the interrupt-glitch consequence is inference) |
| PLIC | `sifive_plic`, 187 sources, 7 priorities, priority/threshold implemented; **only 4-byte accesses valid** — an 8-byte store faults (source; fault measured, A4) | `PlatformLevelInterruptController`, 186 sources, 9 contexts, `prioritiesEnabled: false`, threshold "not supported" (source); **QuadWord→DoubleWord and Byte→DoubleWord translated, no fault** (source) |
| eNVM | `eNVM_DATA` 128 KiB at 0x2022_0000 as **ROM**; `ENVM_CR` in sysreg; eNVM cfg 0x2020_0000 mapped in the memmap (source) | `MappedMemory` 0x2022_0000, 128 KiB, plus `MPFS_eNVM` cfg at 0x2020_0000 (source); writable memory (inference from `MappedMemory`) |
| LIM / L2 | LIM 32 MiB RAM at 0x0800_0000; comment: LIM is *not* shrunk when WayEnable changes (source). L2CC 0x201_0000 4 KiB is `create_unimplemented_device` (source) | LIM 32 MiB at 0x0800_0000, a second 32 MiB "zero device" at 0x0A00_0000, WayEnable 0x0201_0008 a read/write Python stub, 0x0201_0010–FFF silenced; LIM not shrunk either (source) |
| DTIM / ITIM | E51 DTIM 8 KiB at 0x100_0000 only; no ITIM in the memmap (source) | E51 DTIM 8 KiB, E51 ITIM 8 KiB, U54 ITIMs 28 KiB each at 0x0180_8000.. (source) |
| DDR | DRAM_LO 1 GiB at 0x8000_0000, DRAM_HI at 0x10_0000_0000; DDR PHY/CFG are real (small) models (source) | 1 GiB at 0x8000_0000 plus aliases (non-cached windows, 0x10_0000_0000..), `MPFS_DDRMock` and tagged training registers so HSS passes (source) |
| Sysreg / clock tree | `mchp_pfsoc_sysreg`: only `ENVM_CR`, `MSS_RESET_CR`, `MESSAGE_INT` do anything; every other access logs `LOG_UNIMP` (source). docs: "running the HSS no longer works ... missing support in the clock and memory controller devices". AXISW, MPUCFG, FMETER unimplemented | `MPFS_Sysreg`: `SUBBLK_CLOCK_CR` / `SOFT_RESET_CR` enable, disable and reset the peripherals; `PLL_STATUS_SR` reset 0x707; `CLOCK_CONFIG_CR` is a tag, i.e. no behaviour (source). Neither emulator has a clock tree |
| Hart start | `-bios none -kernel`: reset ROM at 0x2022_0000 sends **every** hart to the ELF entry in M-mode (source; measured: harts 0 and 1 both reach `_start`, QEMU.md) | `sysbus LoadELF` calls `InitFromElf` on **every** CPU on the bus (source, `FileLoaderExtensions.cs`), so all five harts start at the entry; the shipped `.resc` says to halt unwanted cores by hand (`u54_4 IsHalted true`) |
| Unmapped access | store/load fault (measured: PLIC case) | warning in the log and a 0 read / dropped write by default; `sysbus UnhandledAccessBehavior ThrowException` makes it a bus error (source, `SystemBus.cs`) |
| RP2040 | no machine (file-name search of the QEMU tree, 2026-10-01) | none upstream (same search of `renode`, `renode-infrastructure`); third-party models exist |
| Licence | GPL-2.0 (QEMU) — not re-checked here | MIT (docs: README) |

## 1. MPFS model fidelity

**What the runtime touches, and what each model does with it**

| Runtime access | QEMU | Renode |
|---|---|---|
| UART data/LSR at 0x2000_0000, byte accesses (`s-textio.adb`) | works (measured) | NS16550 byte interface (source); not run |
| `mtime` 0x0200_BFF8 / `mtimecmp` 0x0200_4008 (`s-bbbopa.ads`), 1 MHz | works, same 1 MHz default (source) | same 1 MHz (source) |
| PLIC enable block `sd` at 0x0C00_2080 (PLIC_INIT) | **faults** (measured) | **accepted** as two 32-bit writes (source). Offsets beyond the registered enable words fall to the register collection's unhandled-write path (inference: a logged warning, not a fault) |
| `clock_switch_e51`: L2 WayEnable 0x0201_0008 write | swallowed by an unimplemented device (source) | stored and read back (source) |
| `clock_switch_e51`: staged code in E51 DTIM, `fence.i` | works (measured) | DTIM exists (source). Whether Renode's translation cache sees code written to DTIM before `fence.i` — not found; see open questions |
| `MSS_Clock_Config` | not written: the runtime guards it with `/= 0` and the constant is 0, "UNVERIFIED" (`mss_clock.adb`) | same; neither model could say anything about the real register |

**Clock tree.** The runtime programs no PLL (the only clock-ish write is
WayEnable, above), so no emulator is being asked a clock-tree question today.
Renode's sysreg gates peripherals only when software *writes* `SUBBLK_CLOCK_CR`
or `SOFT_RESET_CR` (callbacks in `MPFS_Sysreg.cs`); nothing is applied at reset
(inference), so an image that never touches those registers — which is every
image here — sees all peripherals enabled. Real silicon reset values were not
looked up, and on a no-HSS boot (`hello_envm_mpfs`, eNVM execute-in-place) the
runtime would have to release the MMUART itself. Neither emulator catches that.
**QEMU does not model the clock tree** (measured/docs); **Renode does not
either**, beyond the gating above.

**Hart release.** Both emulators start all harts at the entry point, so
`start.S`'s hart-mask gate (A6) runs identically. Neither reproduces what
HSS does on silicon; this is the open A5 question and neither emulator can
answer it.

**Interrupts.** For the later external-interrupt tests (D1/D2) QEMU's PLIC is
the more faithful: it implements priorities and thresholds; Renode's ignores
them and its repl turns priorities off (source).

## 2. RP2040

- **QEMU:** no RP2040/RP2350 or Pico machine (searched file names of
  `qemu/qemu` master; only `raspberrypi-fw-defs.h` matched). Generic M-profile
  machines exist, but `rts_support_pico`'s `setup_clocks.adb` polls
  `XOSC.STATUS.STABLE`, `PLL.CS.LOCK` and `CLK_SYS_SELECTED` (source, this repo),
  which need an RP2040 model. Inference: it would hang on any generic board.
- **Renode:** not upstream (no RP2040 `.repl` among the ~200 platform files in `renode`
  at master; no RP2040 peripheral file in `renode-infrastructure`). Third-party:
  [`matgla/Renode_RP2040`](https://github.com/matgla/Renode_RP2040), MIT, pushed
  2026-09-18, README (docs): dual Cortex-M0+, SIO partial, DMA, GPIO, XOSC/ROSC/PLL,
  clocks "mostly just stubs ... but virtual time is always correct", UART,
  SPI/I2C, timers, watchdog, ADC, SSI/XIP partial, PIO via an external C++
  simulator; **not** USB, PWM, RTC. "Requires Renode version 1.16.1".
  Results table: 40+ passing pico-examples, failures in USB, PWM, PIO.
  A second repo (`chatelao/xiao-seeed-rp2040-renode`, 0 stars, MIT) carries its
  own C# models and also pins 1.16.1; not evaluated further.
- **Console.** `hello_rp2040` prints by **semihosting**: the vendor
  `s-semiho.adb` uses `SYS_WRITEC`, `SYS_WRITE0`, `SYS_READC`, `SYS_EXIT` (source,
  in the installed toolchain). Renode's `SemihostingHandler.cs` handles
  `SYS_WRITEC`, `SYS_WRITE0`, `SYS_WRITE` (source), and the 1.17.0 notes list
  further calls. How a Cortex-M `.repl` attaches `SemihostingUart` was not found
  in docs; see open questions. QEMU supports ARM semihosting in general (not
  re-checked for M-profile).
- **Boot.** The image is XIP flash with `boot2` entered via the boot ROM at
  0x0 (`s-bootro.adb`); matgla's README says "bootrom correctly starts firmware",
  and the repo has a `bootroms/` directory (contents not examined).
- **Verdict:** Renode is the only route to running the RP2040 image at all, and
  only through a community model whose Renode pin (1.16.1) differs from the
  current release (1.17.0). Whether it works for `light_tasking_pico` is
  unknown without the trial.

## 3. Testing ergonomics

| | QEMU | Renode |
|---|---|---|
| Virtual / deterministic time | Default: `mtime` follows the host clock (measured, A4). `-icount shift=N,sleep=off` (docs, `qemu-options.hx`): one instruction per 2^N ns, and "virtual time will jump to the next timer deadline instantly whenever the virtual cpu goes to sleep"; icount is incompatible with multi-threaded TCG (docs). **Not tried here on the icicle kit.** | Deterministic virtual time is the design (docs: time framework): quanta, CPU speed in MIPS (default 100 MIPS), `RunFor` and Robot timeouts in virtual time; by default throttles to real time, `AdvanceImmediately` removes that. How WFI idle is treated is not in the page read. The repl sets `CyclesPerInstruction: 8` on every hart (source); its effect on `mtime` was not determined |
| Robot Framework | none; shell scripts today | first-class: `renode-test`, `Create Terminal Tester sysbus.mmuart0`, `Wait For Line On Uart`, `Send Key To Uart`, `Write Line To Uart`, `Provides`/`Requires`, `-j` parallel (docs). The shipped `Icicle-Kit.robot` (source) creates two UART testers (`mmuart0`, `mmuart1`) in one test |
| UART capture | `-serial file:` per port (used today, two ports in `run_tests.sh`); input via `-chardev file,input-path=` | `uart CreateFileBackend @file true` (output only, docs), terminal testers, PTY / socket terminals (docs). Any number of UARTs, each attachable independently |
| Fault diagnostics | `-d int,guest_errors -D log` gives `riscv_cpu_do_interrupt: hart:1, cause:7, epc, tval` per trap; the xfail rows match it (measured) | `cpu CreateExecutionTracing "t" @file Disassembly` (PC/opcode/disassembly with symbols), `cpu LogFunctionNames true`, `sysbus LogAllPeripheralsAccess`, bus-level warnings for unhandled accesses (docs/source). A per-trap line like `-d int` was **not found** in the docs read; open question |
| GDB | `-s -S`; one inferior per hart | `machine StartGdbServer 3333 true`, one stub per CPU/cluster, `monitor` passthrough (docs); the shipped `.resc` notes that GDB initialises only the E51 and the others need `PC` copied by hand (source) |
| Scripting | command line only | `.resc` scripts, monitor, Python hooks, C# peripherals |
| Multi-hart | all harts run, TCG round-robin or MTTCG | all five CPUs from `polarfire-soc.repl`; serialisation behaviour not examined |
| Speed | not measured on the icicle kit beyond "a passing boot ends in about a second" (smoke.sh); full `make test` is 3 min, nearly all negative builds | not measured; the shipped Robot suite boots HSS, U-Boot and Linux on this platform in CI upstream (source: `Icicle-Kit.robot`) |

Renode's strongest relevant point is that `delay until` assertions would have
exact virtual-time bounds instead of the 500 ms slack in `tasking_test`
(A4 notes), but the same effect may be reachable with QEMU's `-icount`.
Both must be tried before it counts. Note also the limit A4 already records:
the guest compares `Ada.Real_Time` with itself, so a wrong `mtime` frequency is
not caught by either; a Renode test could check it from the host side by
asserting virtual elapsed time in Robot (inference).

## 4. Operations

| | QEMU | Renode |
|---|---|---|
| macOS/aarch64 | Homebrew, native (measured) | `renode-1.17.0.osx-arm64-portable.dmg` (75.7 MB) and `brew install renode/tap/renode` (docs: README). Filename says arm64; whether the emulation core is native arm64 was not verified. Only a minimal run (`renode --console --disable-gui`) is needed; the `.app` is called via `/Applications/Renode.app/Contents/MacOS/renode` (docs) |
| ubuntu-26.04 runner | `apt install qemu-system-riscv` 10.2.1 (measured, A3) | no apt repo. Options (docs/API): `renode_1.17.0_amd64.deb` (35.5 MB), `renode-1.17.0.linux-portable.tar.gz` (63.5 MB, "embeds dotnet runtime"), Docker `antmicro/renode`, `antmicro/renode-test-action` (builds Renode **from source** and caches it — heavy; source tarball is 329 MB). README's Linux dependency line: `policykit-1 libgtk2.0-0 screen uml-utilities gtk-sharp2 libc6-dev libicu-dev gcc python3 python3-pip` (written for Ubuntu 20.04; GTK2 is for the UI only per the same README; whether the names exist on 26.04 is unknown) |
| Install time/size | apt, a few seconds | tarball ~63 MB download; unpacked size and time not known |
| Python | not needed | `renode-test` needs a venv with `tests/requirements.txt` (docs); brew preconfigures it |
| Licence | GPL-2.0 | MIT (docs) |
| Release cadence | not tabulated (tags seen: v11.1.2 latest on 2026-10-01) | 1.15.0 2024-03-18, 1.15.3 2024-09-18, 1.16.0 2025-08-03, 1.16.1 2026-02-16, **1.17.0 2026-09-07** (GitHub API) — about one release a year, with nightlies at builds.renode.io |
| Pinning in CI | the runner image's apt version (a moving target, today fixed by `ubuntu-26.04`) | download the release asset by exact URL, verify a sha256 you commit, cache with `actions/cache`. Do not use the action's default `renode-revision: master` |

A `linux-arm64-portable.tar.gz` also exists (API); the project's CI is x86_64.

## 5. Fit with this project

**What changes to run `make smoke` / `make test` under Renode**

- `smoke.sh` and `run_tests.sh` hard-wire QEMU's command line, `-serial file:`,
  `-d int,guest_errors`, `ulimit -f`, and a kill-based watchdog. A Renode
  variant is a separate script, not a flag. A sketch, per image:

  ```
  mach create "mpfs"
  machine LoadPlatformDescription @platforms/boards/mpfs-icicle-kit.repl
  sysbus.mmuart0 CreateFileBackend @<console0> true
  sysbus.mmuart1 CreateFileBackend @<console1> true
  sysbus LoadELF @<image>
  emulation RunFor "2"
  quit
  ```

  The virtual-time bound replaces the 20 s wall-clock watchdog; a wall-clock
  CI timeout is still needed for a hung process. `smoke.expected` is reusable
  unchanged (it is only strings on MMUART0). `tests.list` rows for `pass`
  tests are reusable; `console.in` needs the Robot keyword route
  (`Write Line To Uart`), since file backends are output-only (docs).
- **xfail rows do not port.** `observe` is a regexp over QEMU's trap log. The
  three PLIC_INIT rows would produce `UNEXPECTED PASS` under Renode (the image
  boots), and CONSOLE_DEAD would need a separate signature. A Renode run needs
  either its own list with its own expectations, or an `expect` column per
  emulator. This is the largest piece of work.
- **Robot route** instead of shell: one `.robot` file with a test per image
  using `Create Terminal Tester sysbus.mmuart0` and `Wait For Line On Uart`;
  `make test` would call `renode-test`. This duplicates `tests.list` unless the
  list is generated into Robot.

**Both emulators in CI.** The case for it: two independently written models
disagreeing is a cheap signal before hardware (A5). Known disagreements today
are the PLIC access width, L2 WayEnable (swallowed vs stored), unmapped
accesses (fault vs warning) and PLIC priorities. The case against: both models
were written from the same public documents and for the same reason (booting
HSS/Linux), so agreement is weak evidence, and a disagreement says only "one
of them is wrong", not which, which will cost investigation each time
(inference). It also doubles the setup (one `curl`+checksum step, a Python venv)
and a second set of expected-failure signatures. Hence non-gating first.

**PLIC_INIT specifically.** Renode would not inform it. Its acceptance of
the 64-bit store is the result of an explicit model decision
(`AllowedTranslations`), and the model was written to run HSS, U-Boot and
Linux, not to find access-width faults. A pass there is not evidence about
silicon, and it would flip the three xfail rows to `UNEXPECTED PASS` without
the underlying question having moved. Evidence that could move it: the board
(A5), Microchip's PolarFire SoC register documentation for the PLIC (not
located here), or the PLIC spec's wording above (32-bit registers; "other
widths" left unaddressed per the page read). If the project later decides on
the per-register repair, it is correct under both emulators regardless.

## Open questions — to settle by a hands-on trial

Each needs software this task was told not to install. Commands to run, in
order, in a scratch directory (not in the repo).

**Install (Linux, x86_64, as CI would):**

```
curl -fLO https://github.com/renode/renode/releases/download/v1.17.0/renode-1.17.0.linux-portable.tar.gz
sha256sum renode-1.17.0.linux-portable.tar.gz        # record it; this becomes the CI pin
mkdir renode && tar xf renode-1.17.0.linux-portable.tar.gz -C renode --strip-components=1
./renode/renode --version
```

**Install (macOS/aarch64):** `brew install renode/tap/renode`, or the
`renode-1.17.0.osx-arm64-portable.dmg`; then `renode --version`, and
`file $(which renode)` plus `sysctl -n sysctl.proc_translated` while it runs
to see whether it is native or under Rosetta.

**Run the existing images** (from `rts-spikes/`, after `make build`):

```
cat > /tmp/mpfs.resc <<'EOF'
mach create "mpfs"
machine LoadPlatformDescription @platforms/boards/mpfs-icicle-kit.repl
sysbus.mmuart0 CreateFileBackend @/tmp/con0.log true
sysbus.mmuart1 CreateFileBackend @/tmp/con1.log true
sysbus LoadELF @IMAGE
emulation RunFor "2"
quit
EOF
sed 's#IMAGE#'"$PWD"'/hello_mpfs/bin/hello_mpfs#' /tmp/mpfs.resc > /tmp/run.resc
renode --disable-gui --console -e "include @/tmp/run.resc"; cat /tmp/con0.log
```

Questions this answers, with what to look for:

1. Do `hello_mpfs`, `clock_switch_e51`, `hello_envm_mpfs` print their
   `smoke.expected` strings? Any log line "locked peripheral" or "non existing
   peripheral" is a model/runtime mismatch worth reading.
2. PLIC_INIT: run `tests/tasking_test`. Expected (inference): it boots and
   passes, with PLIC warnings about enable offsets. Then add
   `sysbus UnhandledAccessBehavior ThrowException` before `LoadELF` and rerun:
   does the access now fault, and where?
3. Time: run `tasking_test` ten times with `emulation RunFor` and compare its
   printed elapsed times (should be identical if time is deterministic); repeat
   under host load (`yes > /dev/null &` x cores). Compare with QEMU
   `-icount shift=0,sleep=off` on the same image (needs the PLIC repair in a
   scratch copy as in A4): `qemu-system-riscv64 -M microchip-icicle-kit -icount shift=0,sleep=off ...`
4. Does `clock_switch_e51` pass (code staged to DTIM, `fence.i`, jump)? If
   Renode's block cache does not honour `fence.i`, it will run stale code or crash.
5. Fault diagnostics: is there a per-trap log? Try `logLevel -1 cpu` and
   `cpu CreateExecutionTracing`; look for any `trap`/`exception` line for the
   QEMU PLIC case reproduced with `ThrowException`.
6. `renode-test` route: `pip install -r renode/tests/requirements.txt` and a
   two-UART `.robot` copy of `Icicle-Kit.robot`'s `Create Terminal Tester`
   pattern; `renode-test x.robot`. Measure wall time per image.
7. ubuntu-26.04: run steps above in a throwaway workflow (`workflow_dispatch`)
   on the same runner label; note any missing library (ICU, GTK2) and the
   download+unpack time.
8. RP2040: `git clone https://github.com/matgla/Renode_RP2040`, read
   `README.md` for the required Renode version, run its `run_firmware.resc`
   with `$global.FIRMWARE=hello_rp2040/bin/hello_rp2040` under both 1.16.1 and
   1.17.0. Look for: boot2/bootrom handoff, `setup_clocks` completing (XOSC
   stable, PLL lock), and whether semihosting output appears at all (the
   board `.repl` must attach a `SemihostingUart`; if not, that is the work).
9. Multi-hart start: with the five harts all starting at `_start`, does
   Renode's execution order matter for `start.S`'s gate? (Compare with
   QEMU.md's `01` hart-id experiment.)

## Sources

QEMU (read in source / docs):
- `hw/riscv/microchip_pfsoc.c` v10.2.1 — https://raw.githubusercontent.com/qemu/qemu/v10.2.1/hw/riscv/microchip_pfsoc.c (and `master`, diff of API refactors only in the part inspected)
- `include/hw/riscv/microchip_pfsoc.h` — https://raw.githubusercontent.com/qemu/qemu/v10.2.1/include/hw/riscv/microchip_pfsoc.h
- `hw/intc/sifive_plic.c` v10.2.1 (`valid.min/max_access_size = 4`) — https://raw.githubusercontent.com/qemu/qemu/v10.2.1/hw/intc/sifive_plic.c
- `hw/misc/mchp_pfsoc_sysreg.c` v10.2.1 — https://raw.githubusercontent.com/qemu/qemu/v10.2.1/hw/misc/mchp_pfsoc_sysreg.c
- Icicle Kit board docs — https://raw.githubusercontent.com/qemu/qemu/v10.2.1/docs/system/riscv/microchip-icicle-kit.rst
- `-icount` option text — https://raw.githubusercontent.com/qemu/qemu/master/qemu-options.hx ; https://raw.githubusercontent.com/qemu/qemu/master/docs/devel/tcg-icount.rst
- QEMU tree listing (RP2040 absent) — GitHub API tree of `qemu/qemu` master, 2026-10-01; latest tag then v11.1.2

Renode:
- Releases and asset sizes/dates — GitHub API `renode/renode/releases` (v1.17.0, 2026-09-07); notes https://github.com/renode/renode/releases/tag/v1.17.0
- README (install, licence, dotnet, Docker, brew) — https://raw.githubusercontent.com/renode/renode/master/README.md
- Platforms and scripts at v1.17.0 — https://raw.githubusercontent.com/renode/renode/v1.17.0/platforms/cpus/polarfire-soc.repl ; `.../platforms/boards/mpfs-icicle-kit.repl` ; `.../scripts/single-node/polarfire-soc.resc` ; `.../scripts/single-node/icicle-kit.resc` ; `.../tests/platforms/Icicle-Kit.robot` ; `.../tests/platforms/PolarFireSoC.robot`
- Peripheral sources (`renode-infrastructure`, master, 2026-10-01), under `src/Emulator/`: `Cores/RiscV/PlatformLevelInterruptController.cs`, `Cores/RiscV/PLIC/PlatformLevelInterruptControllerBase.cs`, `Cores/RiscV/CoreLevelInterruptor.cs`, `Peripherals/Peripherals/Miscellaneous/MPFS_Sysreg.cs`, `Peripherals/Peripherals/UART/NS16550.cs`, `Main/Peripherals/Bus/SystemBus.cs` (access translation, unhandled access), `Main/Core/Extensions/FileLoaderExtensions.cs` (`LoadELF`), `Cores/Arm/SemihostingHandler.cs` — base URL https://github.com/renode/renode-infrastructure/tree/master/src/Emulator
- Peripheral modelling guide, access width / `AllowedTranslations` — https://renode.readthedocs.io/en/latest/advanced/writing-peripherals.html
- Time framework — https://renode.readthedocs.io/en/latest/advanced/time_framework.html
- Robot Framework / testing — https://renode.readthedocs.io/en/latest/introduction/testing.html
- UART host integration — https://renode.readthedocs.io/en/latest/host-integration/uart.html
- GDB — https://renode.readthedocs.io/en/latest/debugging/gdb.html
- Execution tracing — https://renode.readthedocs.io/en/latest/execution-tracing/execution-tracing.html
- GitHub Action — https://github.com/antmicro/renode-test-action

Other:
- RISC-V PLIC spec, "Memory Map" — https://github.com/riscv/riscv-plic-spec/blob/master/riscv-plic.adoc
- Third-party RP2040 models — https://github.com/matgla/Renode_RP2040 ; https://github.com/chatelao/xiao-seeed-rp2040-renode
- This repo: `rts-spikes/QEMU.md`, `RTS-PRODUCTION.md` A1/A3/A4/A5, `rts-spikes/smoke.sh`, `rts-spikes/tests/run_tests.sh`, `rts-spikes/tests/tests.list`, `.github/workflows/rts-spikes.yml`, `rts_support_mpfs/src/{s-bbbopa.ads,s-textio.adb}`, `rts_support_pico/src-rp2040/setup_clocks.adb`, vendor `s-semiho.adb` in the installed `gnat_arm_elf_15.1.2`
