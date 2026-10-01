#  rts-spikes -- populate, build, verify.
#
#  WHY A MAKEFILE AND NOT AN ALIRE ROOT CRATE.
#
#  An AMP system is N binaries whose runtime configurations differ. Alire
#  cannot express that in one solution: configuration values must be unanimous,
#  and a root crate is a peer of its dependencies rather than an authority over
#  them, so two partitions wanting one runtime crate at different Harts_Mask
#  values is a hard error (RTS.md 2.2, measured). Independently, one gprbuild
#  invocation carries one Target/Runtime/Builder, so differently-ABI'd
#  partitions cannot be produced in a single pass either way.
#
#  So each partition stays its own Alire root and this file drives N builds.
#  Note carefully what that does and does not buy:
#
#    this Makefile          ordering, N invocations, one entry point, and
#                           cross-partition checks on the PRODUCED ELFs
#    mpfs_system crate      the AGREEMENT between partitions (hart ownership,
#                           memory windows, peripheral ownership) as generated
#                           data every partition depends on
#    Alire                  per-partition resolution and configuration
#    Config_Tag             keeps a shared, path-pinned runtime crate's outputs
#                           apart; a fetched crate gets this from Alire's
#                           hash-keyed build cache instead (CONTRACT.md 7.11)
#
#  A Makefile cannot enforce agreement -- it is a build driver. It can do one
#  thing nothing else can, though: `ld` never checks region overlap, and it can
#  never see a collision between two SEPARATELY linked partitions
#  (RTS-POLARFIRE.md 6.3). This file sees both ELFs, so `make amp` checks it.

TOOLCHAIN := $(firstword $(wildcard $(HOME)/.local/share/alire/toolchains/gnat_riscv64_elf_15.1.2_*/bin))
SIZE      := $(TOOLCHAIN)/riscv64-elf-size
READELF   := $(TOOLCHAIN)/riscv64-elf-readelf
ARM_TC      := $(firstword $(wildcard $(HOME)/.local/share/alire/toolchains/gnat_arm_elf_15.1.2_*/bin))
ARM_SIZE    := $(ARM_TC)/arm-eabi-size
ARM_READELF := $(ARM_TC)/arm-eabi-readelf

#  Two targets now live side by side, so each application carries its own
#  inspection toolchain: riscv64-elf for the PolarFire leaves, arm-eabi for the
#  Pico one. There is nothing else target-specific in this file.
#
#  hello_envm_mpfs (RTS-PRODUCTION.md §A6) is the XIP cell of the four-boot-
#  scenario table: Memory_Profile => envm, so it is the one application here
#  whose .data has LMA (envm) != VMA (l2lim) and therefore actually exercises
#  start-ram.S's copy loop -- the other four are RAM-resident, where the loop
#  runs zero iterations by construction.
APPS     := hello_mpfs clock_switch_e51 tasking_mpfs embedded_app hello_envm_mpfs
ARM_APPS := hello_rp2040

#  The two AMP partitions in this spike: an E51 monitor (soft-float, Harts_Mask
#  = 1) and a U54 application (hard-float, Harts_Mask = 2), both pinning the
#  SAME light_mpfs crate at different configurations.
#
#  `make amp` CURRENTLY FAILS, correctly. Both are Memory_Profile => lim, so
#  both link at the LIM base 0x08000000 and their load segments overlap
#  completely -- they are two independent demos, not a coexisting pair. Giving
#  them disjoint windows needs per-partition placement scripts generated from
#  mpfs_system, which is RTS-POLARFIRE.md phase P4. Until then this target is
#  the first executable statement of that requirement, and a failing check that
#  encodes a real constraint is worth more than no check.
AMP_PARTITIONS := clock_switch_e51 hello_mpfs

#  A1 (RTS-PRODUCTION.md) -- get one byte out of QEMU. Full writeup, including
#  what was tried and why, is QEMU.md; this is only the working invocation.
#
#  QEMU_APP defaults to clock_switch_e51 because that is what A1 names, but
#  `make qemu QEMU_APP=hello_mpfs` boots the other console-producing image.
#  (tasking_mpfs and embedded_app boot fine under the same command line but
#  never call Ada.Text_IO themselves, so there is nothing to see either way
#  -- QEMU.md "Memory_Profile results".)
#
#  WHAT WAS WRONG, so the next person does not re-spend the day on it:
#    - LIM (Memory_Profile => lim, 0x08000000) was suspected of not being
#      backed by QEMU's model. WRONG -- measured working, see QEMU.md.
#    - MMUART base/divisor was suspected of disagreeing with QEMU's model.
#      WRONG -- our own console driver never programs a divisor at all
#      (rts_support_mpfs/src/s-textio.adb `Initialize` just sets a flag);
#      the base address (0x2000_0000) matches QEMU's mmuart0 exactly.
#    - The boot flow WAS the problem: QEMU's default `-bios` loads OpenSBI
#      (fw_dynamic), which produced no output at all -- not even OpenSBI's
#      own banner -- within a bounded run. `-bios none` lets `-kernel` run
#      directly with no firmware in between, and both console-producing
#      images print immediately. See QEMU.md for the measured comparison.
#
#  BOUNDING THE RUN. A plain -kernel bare-metal image never exits on its own,
#  so `make qemu` must impose a limit or it hangs forever -- which in CI is
#  worse than a failure, because a hang looks like a slow build.
#
#  This host has no `timeout`/`gtimeout` (BSD userland, not GNU coreutils).
#  The obvious substitute, `perl -e 'alarm(N); exec ...'`, DOES NOT WORK HERE
#  and was measured not to: QEMU installs its own SIGALRM disposition, so the
#  inherited alarm is swallowed. Sending SIGALRM to a running qemu directly
#  leaves it alive, and a target built on alarm() runs unbounded.
#
#  So the bound is an explicit watchdog: background qemu, race it against a
#  `sleep`, SIGKILL on expiry. QEMU_TIMEOUT is seconds; raise it if the
#  console is slow to appear.
QEMU          := qemu-system-riscv64
QEMU_MACHINE  := microchip-icicle-kit
QEMU_APP      := clock_switch_e51
QEMU_TIMEOUT  := 8

.PHONY: all populate build verify bless amp qemu clean help

help:
	@echo "populate  copy runtime sources from the installed toolchain, run all guards"
	@echo "build     build every application (implies populate)"
	@echo "verify    ASSERT every built image matches metrics.golden (text/data/bss/entry/ISA/ABI); non-zero on any drift"
	@echo "bless     rewrite metrics.golden from the current images (review the git diff, commit it with the change)"
	@echo "amp       build the E51 + U54 partitions and check they do not collide"
	@echo "qemu      boot QEMU_APP (default clock_switch_e51) under QEMU and show its console"
	@echo "clean     remove build output (keeps populated sources)"

all: build verify

populate:
	@sh populate.sh

build: populate
	@set -e; for a in $(APPS) $(ARM_APPS); do \
	  printf '==> %s\n' "$$a"; \
	  ( cd "$$a" && alr -n build >/dev/null ) || { echo "FAILED: $$a"; exit 1; }; \
	done
	@echo "all $(words $(APPS) $(ARM_APPS)) applications built"

#  A2 (RTS-PRODUCTION.md) -- the metrics are an ASSERTION, not a table.
#
#  metrics.golden is the committed expectation: for every application, text /
#  data / bss, the ELF entry point, e_flags, the full ISA tag and every other
#  build-attribute tag, recorded raw (metrics.sh has the field-by-field
#  rationale; the file's own header repeats it). `make verify` measures the
#  built images, prints the table, and EXITS NON-ZERO on any difference, showing
#  expected vs. actual per field. Exact match; no tolerances.
#
#  WORKFLOW for a deliberate change:
#    1. change code             2. `make build verify` -- fails, shows the delta
#    3. inspect: is it the delta you meant?
#    4. `make bless`            rewrites metrics.golden from the current images
#    5. commit metrics.golden TOGETHER WITH the change that caused it, so the
#       number change is a reviewable diff in the same commit as its cause.
#
#  What verify refuses to do silently (each was a way the old target "passed"):
#  an image that is not built (failure, not a skip); an app set that differs from
#  the golden file in either direction; a missing toolchain (TOOLCHAIN matched
#  nothing); an empty or unparseable field. `bless` likewise refuses to write
#  unless every app measured cleanly.
#
#  verify measures what is ON DISK; it does not build. Use `make all`
#  (build + verify) when the sources may be newer than the images.
GOLDEN := metrics.golden
METRICS_ENV = GOLDEN='$(GOLDEN)' RV_SIZE='$(SIZE)' RV_READELF='$(READELF)' \
              ARM_SIZE='$(ARM_SIZE)' ARM_READELF='$(ARM_READELF)' \
              RV_APPS='$(APPS)' ARM_APPS='$(ARM_APPS)' \
              RV_TC='$(TOOLCHAIN)' ARM_TC='$(ARM_TC)'

verify:
	@$(METRICS_ENV) sh metrics.sh verify

bless:
	@$(METRICS_ENV) sh metrics.sh bless
	@echo "review with: git diff $(GOLDEN) -- and commit it with the change that caused it"

#  Build both partitions, then do the check no single link can do: compare the
#  PT_LOAD segments of two separately linked images for overlap.
amp: populate
	@set -e; for p in $(AMP_PARTITIONS); do \
	  printf '==> partition %s\n' "$$p"; ( cd "$$p" && alr -n build >/dev/null ); \
	done
	@echo "--- ABIs must differ (E51 has no FPU) ---"
	@set -e; for p in $(AMP_PARTITIONS); do \
	  ar=$$($(READELF) -A "$$p/bin/$$p" | awk -F'"' '/Tag_RISCV_arch/{print $$2}'); \
	  case "$$ar" in *_f*_d*) fl=hard ;; *) fl=soft ;; esac; \
	  printf '  %-18s %s\n' "$$p" "$$fl"; \
	done
	@echo "--- load segments must not overlap ---"
	@python3 -c 'import subprocess, sys, itertools; \
	    parts = sys.argv[2:]; segs = []; \
	    [segs.append((p, int(f[2], 16), int(g[1], 16))) \
	     for p in parts \
	     for L in [subprocess.run([sys.argv[1], "-lW", p + "/bin/" + p], \
	                              capture_output=True, text=True).stdout.splitlines()] \
	     for f, g in [(l.split(), n.split()) for l, n in zip(L, L[1:]) if l.strip().startswith("LOAD")]]; \
	    bad = [(a, b) for a, b in itertools.combinations(segs, 2) \
	           if a[0] != b[0] and a[1] < b[1] + b[2] and b[1] < a[1] + a[2]]; \
	    [print("  OVERLAP: %s [%#x,+%#x) and %s [%#x,+%#x)" % (a[0], a[1], a[2], b[0], b[1], b[2])) \
	     for a, b in bad]; \
	    print("  error: partitions collide in memory") if bad else \
	    print("  %d load segments compared across %d partitions, no overlap" % (len(segs), len(parts))); \
	    sys.exit(1 if bad else 0)' $(READELF) $(AMP_PARTITIONS)

#  Measured working command line (QEMU.md has the full comparison table):
#
#    qemu-system-riscv64 -M microchip-icicle-kit -m 2G -nographic \
#        -serial mon:stdio -bios none -kernel <app>/bin/<app> -no-reboot
#
#  `-bios none` is not optional -- QEMU's default firmware choice for this
#  machine, when a kernel is given, is OpenSBI (fw_dynamic); measured, that
#  path produces no console output whatsoever within a bounded run (not even
#  OpenSBI's own banner), so our payload never gets a chance to run.
qemu:
	@a="$(QEMU_APP)"; e="$$a/bin/$$a"; \
	[ -f "$$e" ] || { echo "$$e not built -- run 'make build' first"; exit 1; }; \
	echo "==> booting $$a under $(QEMU_MACHINE), bounded to $(QEMU_TIMEOUT)s"; \
	echo "    $(QEMU) -M $(QEMU_MACHINE) -m 2G -nographic -serial mon:stdio -bios none -kernel $$e -no-reboot"; \
	$(QEMU) -M $(QEMU_MACHINE) -m 2G -nographic \
	  -serial mon:stdio -bios none -kernel "$$e" -no-reboot & \
	qpid=$$!; \
	( sleep $(QEMU_TIMEOUT); kill -9 $$qpid 2>/dev/null ) & \
	wdog=$$!; \
	wait $$qpid 2>/dev/null; \
	kill $$wdog 2>/dev/null; \
	echo "==> stopped after $(QEMU_TIMEOUT)s (a -kernel image never exits by itself)"; \
	true

clean:
	@for a in $(APPS) $(ARM_APPS); do rm -rf "$$a/obj" "$$a/bin"; done
	@rm -rf */adalib-* */obj-* */obj-gnarl-*
	@echo "build output removed (populated sources kept; use git clean -fdx for those)"
