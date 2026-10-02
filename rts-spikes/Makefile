#  rts-spikes -- toolchains, populate, build, verify, smoke.
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

#  THE PINNED COMPILER. Tier 1 is a byte snapshot of GNAT 15.3.1's runtime
#  sources (populate.sh asserts it), so the compiler that builds against it must
#  be exactly that release. The leaf manifests say `gnat_riscv64_elf = "=15.3.1"`
#  / `gnat_arm_elf = "=15.3.1"` for the same reason -- `^15` admits any 15.x
#  the community index carries (15.1.2, 15.2.1, 15.3.1 today), and a fresh
#  machine is handed the newest (RTS-PRODUCTION.md A3). Moving the pin is a
#  rehearsed operation: RTS-PRODUCTION.md C3 has the 15.1.2 -> 15.3.1 numbers.
#
#  Alire deploys a compiler crate into <cache>/toolchains/<crate>_<ver>_<hash>,
#  where <hash> is the first 8 hex digits of the release's per-host archive
#  sha256 -- so it DIFFERS between macOS and Linux and must stay a glob. The
#  cache folder is $HOME/.local/share/alire on both hosts (`alr version` prints
#  it); override ALIRE_TC_DIR if yours differs.
#
#  These are RECURSIVE (=), not simple (:=), variables: on a fresh machine the
#  toolchains do not exist when make parses this file, and `make toolchains`
#  creates them mid-run. A `:=` would freeze an empty TOOLCHAIN at parse time
#  and every path below would degrade to "/riscv64-elf-size".
GNAT_VERSION := 15.3.1
ALIRE_TC_DIR := $(HOME)/.local/share/alire/toolchains
TOOLCHAIN   = $(firstword $(wildcard $(ALIRE_TC_DIR)/gnat_riscv64_elf_$(GNAT_VERSION)_*/bin))
SIZE        = $(TOOLCHAIN)/riscv64-elf-size
READELF     = $(TOOLCHAIN)/riscv64-elf-readelf
STRINGS     = $(TOOLCHAIN)/riscv64-elf-strings
ARM_TC      = $(firstword $(wildcard $(ALIRE_TC_DIR)/gnat_arm_elf_$(GNAT_VERSION)_*/bin))
ARM_SIZE    = $(ARM_TC)/arm-eabi-size
ARM_READELF = $(ARM_TC)/arm-eabi-readelf
ARM_STRINGS = $(ARM_TC)/arm-eabi-strings

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

#  A3 (RTS-PRODUCTION.md) -- `make smoke`: the QEMU run as an ASSERTION. `make
#  qemu` shows output and exits 0 whatever it saw -- the flaw A2 removed from
#  `verify` -- so CI cannot use it. smoke.sh boots every image listed in
#  SMOKE_EXPECTED and fails unless each expected string appears on the GUEST's
#  console. See smoke.sh for the design rules (and QEMU_MIN, the version floor).
SMOKE_EXPECTED := smoke.expected
SMOKE_TIMEOUT  := 20
QEMU_MIN       := 10.1

#  B1 (RTS-PRODUCTION.md) -- the exit criterion for "a leaf can be CONSUMED":
#  `make fetched-check` packs the leaves and the tier crates they pin into a
#  throwaway file-based Alire index in a scratch directory, then builds each
#  leaf's application from a copy with NO [[pins]] at all, in another directory,
#  with Alire fetching every crate into its own (private) build cache. It does
#  not touch your Alire settings, index list or cache -- see fetched-check.py.
#  Not part of `all`: it rebuilds all four runtimes from a cold cache.
#  FETCHED_CHECK_ARGS: e.g. `--qemu` to also boot the fetched hello_mpfs image,
#  or `--work DIR` to choose the (empty) scratch directory; FETCHED_LEAVES to
#  restrict the leaves.
FETCHED_LEAVES     ?= light_mpfs light_tasking_mpfs embedded_mpfs light_tasking_pico
FETCHED_CHECK_ARGS ?=

#  A4 (RTS-PRODUCTION.md) -- `make test`: the runtime's OWN behaviour, not the
#  images' shape (verify) or their greeting (smoke).
#
#    positive   tests/tests.list lists test applications (tasking, protected
#               objects, exceptions, Text_IO, the Console value). Each is built
#               (like any application: `alr -n build`), booted under QEMU by
#               tests/run_tests.sh, and passes only if it prints
#               "TEST <name>: PASS" on its console. A row may be `xfail`: a
#               DOCUMENTED runtime defect that must keep failing in exactly the
#               documented way, and turns the build red if it starts to pass.
#    negative   tests/negative/run_negative.sh: builds that MUST fail, each with
#               its diagnostic asserted -- the `light` floor rejecting tasking,
#               and every `pragma Compile_Time_Error` in mpfs_config_checks.ads
#               firing for a configuration that violates it. They run in a
#               scratch copy of the tree; nothing committed is touched.
#
#  Both always run (one failing does not hide the other) and the target fails if
#  either does. The test applications are deliberately NOT in APPS: they are not
#  in verify's application set, so they never enter metrics.golden.
TEST_LIST    := tests/tests.list
TEST_TIMEOUT := 30
NEG_LIST     := tests/negative/cases.list

.PHONY: all toolchains populate build verify smoke test bless sections amp qemu clean help fetched-check

help:
	@echo "all        build -> verify -> smoke -> test (the phases CI runs, there as separate steps; build implies populate implies toolchains)"
	@echo "toolchains install the pinned cross compilers ($(GNAT_VERSION)) through Alire if absent; needs alr + network, once"
	@echo "populate   copy runtime sources from the installed toolchain, run all guards (implies toolchains)"
	@echo "build      build every application (implies populate)"
	@echo "verify     ASSERT every built image matches metrics.golden (text/data/bss/entry/ISA/ABI); non-zero on any drift"
	@echo "smoke      ASSERT every console-producing image prints its smoke.expected strings under QEMU (needs QEMU >= $(QEMU_MIN))"
	@echo "test       build and boot the tests/ applications under QEMU, and run the must-fail negative builds (needs QEMU >= $(QEMU_MIN), rsync)"
	@echo "bless      rewrite THIS compiler's rows of metrics.golden (other compilers' rows kept); review the diff, commit it"
	@echo "sections   print size -A for every built image, to compare two builds section by section"
	@echo "fetched-check  build each leaf from a throwaway Alire index with NO pins, from another directory (B1; slow, not in 'all')"
	@echo "amp        build the E51 + U54 partitions and check they do not collide"
	@echo "qemu       boot QEMU_APP (default clock_switch_e51) under QEMU and SHOW its console (asserts nothing; use smoke)"
	@echo "clean      remove build output (keeps populated sources)"

#  `all` is a chain of sub-makes, not `all: build verify smoke`, for two reasons:
#    - ORDER. As prerequisites those three are unordered under `make -j`, and
#      verify/smoke measure what is ON DISK, so they must run after build.
#    - A FRESH MACHINE. `build` -> `populate` -> `toolchains` creates the
#      directories the TOOLCHAIN globs look in; verify then runs in a NEW make
#      process that re-reads them from scratch instead of trusting what the
#      parent saw (GNU make caches directory listings).
#  The first failing phase stops the chain, and its name is the last
#  `==> make ...` line above the error.
all:
	@$(MAKE) --no-print-directory build
	@$(MAKE) --no-print-directory verify
	@$(MAKE) --no-print-directory smoke
	@$(MAKE) --no-print-directory test

#  A fresh machine has no toolchains, and `populate` copies tier 1 OUT of them,
#  so before this target existed `make build` could not work on one at all
#  (populate.sh stopped with "gnat_riscv64_elf 15.3.1 not installed"; the thing
#  that installs it, `alr build`, runs after populate). toolchains.sh closes the
#  loop with an idempotent, pinned install. Silent no-op once they exist.
toolchains:
	@echo "==> make toolchains"
	@GNAT_VERSION='$(GNAT_VERSION)' ALIRE_TC_DIR='$(ALIRE_TC_DIR)' sh toolchains.sh

populate: toolchains
	@GNAT_VERSION='$(GNAT_VERSION)' ALIRE_TC_DIR='$(ALIRE_TC_DIR)' sh populate.sh

build: populate
	@echo "==> make build"
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
#  (build + verify + smoke) when the sources may be newer than the images.
GOLDEN := metrics.golden
#  verify also writes this host's measured rows here (gitignored); CI uploads it.
MEASURED := metrics.measured
METRICS_ENV = GOLDEN='$(GOLDEN)' MEASURED='$(MEASURED)' \
              RV_SIZE='$(SIZE)' RV_READELF='$(READELF)' RV_STRINGS='$(STRINGS)' \
              ARM_SIZE='$(ARM_SIZE)' ARM_READELF='$(ARM_READELF)' ARM_STRINGS='$(ARM_STRINGS)' \
              RV_APPS='$(APPS)' ARM_APPS='$(ARM_APPS)' \
              RV_TC='$(TOOLCHAIN)' ARM_TC='$(ARM_TC)'

verify:
	@echo "==> make verify"
	@$(METRICS_ENV) sh metrics.sh verify

smoke:
	@echo "==> make smoke"
	@QEMU='$(QEMU)' QEMU_MACHINE='$(QEMU_MACHINE)' QEMU_MIN='$(QEMU_MIN)' \
	  SMOKE_EXPECTED='$(SMOKE_EXPECTED)' SMOKE_TIMEOUT='$(SMOKE_TIMEOUT)' sh smoke.sh

#  `test` builds first (so it works from a clean tree, like `build`), then runs
#  both kinds regardless of the other's outcome and fails if either failed.
test: populate
	@echo "==> make test"
	@set -e; for d in $$(awk -F'\t' '/^[ \t]*#/ || /^[ \t]*$$/ { next } !h { h = 1; next } { print $$2 }' $(TEST_LIST)); do \
	  printf '==> build %s\n' "$$d"; \
	  ( cd "$$d" && alr -n build >/dev/null ) || { echo "FAILED: $$d"; exit 1; }; \
	done
	@rc=0; \
	  QEMU='$(QEMU)' QEMU_MACHINE='$(QEMU_MACHINE)' QEMU_MIN='$(QEMU_MIN)' \
	  TEST_LIST='$(TEST_LIST)' TEST_TIMEOUT='$(TEST_TIMEOUT)' sh tests/run_tests.sh || rc=1; \
	  echo "==> negative builds (scratch copy of the tree; takes a few minutes)"; \
	  NEG_LIST='$(NEG_LIST)' RV_GCC='$(TOOLCHAIN)/riscv64-elf-gcc' sh tests/negative/run_negative.sh || rc=1; \
	  [ "$$rc" -eq 0 ] || echo "make test FAILED (see above)" >&2; \
	  exit $$rc

bless:
	@$(METRICS_ENV) sh metrics.sh bless
	@echo "review with: git diff $(GOLDEN) -- and commit it with the change that caused it"

#  Section-by-section sizes. `size`'s text column lumps code and rodata
#  together, so when two builds differ only in text this is how to tell
#  whether code or data moved. CI prints it; run it here and diff the two.
sections:
	@for a in $(APPS); do echo "==> $$a"; '$(SIZE)' -A "$$a/bin/$$a" | sed -n '3,$$p'; done
	@for a in $(ARM_APPS); do echo "==> $$a"; '$(ARM_SIZE)' -A "$$a/bin/$$a" | sed -n '3,$$p'; done

fetched-check: populate
	@echo "==> make fetched-check"
	@python3 fetched-check.py $(FETCHED_CHECK_ARGS) $(FETCHED_LEAVES)

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
	@for d in $$(awk -F'\t' '/^[ \t]*#/ || /^[ \t]*$$/ { next } !h { h = 1; next } { print $$2 }' $(TEST_LIST)); do rm -rf "$$d/obj" "$$d/bin"; done
	@rm -rf */adalib-* */obj-* */obj-gnarl-*
	@echo "build output removed (populated sources kept; use git clean -fdx for those)"
