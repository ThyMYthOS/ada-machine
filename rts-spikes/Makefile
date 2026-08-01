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

APPS := hello_mpfs clock_switch_e51 tasking_mpfs embedded_app

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

.PHONY: all populate build verify amp clean help

help:
	@echo "populate  copy runtime sources from the installed toolchain, run all guards"
	@echo "build     build every application (implies populate)"
	@echo "verify    report text/bss/entry/ABI for every built image"
	@echo "amp       build the E51 + U54 partitions and check they do not collide"
	@echo "clean     remove build output (keeps populated sources)"

all: build verify

populate:
	@sh populate.sh

build: populate
	@set -e; for a in $(APPS); do \
	  printf '==> %s\n' "$$a"; \
	  ( cd "$$a" && alr -n build >/dev/null ) || { echo "FAILED: $$a"; exit 1; }; \
	done
	@echo "all $(words $(APPS)) applications built"

verify:
	@printf '%-18s %-8s %-9s %-11s %s\n' APP TEXT BSS ENTRY FLOAT
	@set -e; for a in $(APPS); do \
	  e="$$a/bin/$$a"; [ -f "$$e" ] || { printf '%-18s (not built)\n' "$$a"; continue; }; \
	  t=$$($(SIZE) "$$e" | awk 'NR==2{print $$1}'); \
	  b=$$($(SIZE) "$$e" | awk 'NR==2{print $$3}'); \
	  en=$$($(READELF) -h "$$e" | awk '/Entry point/{print $$4}'); \
	  ar=$$($(READELF) -A "$$e" | awk -F'"' '/Tag_RISCV_arch/{print $$2}'); \
	  case "$$ar" in *_f*_d*) fl=hard ;; *) fl=soft ;; esac; \
	  printf '%-18s %-8s %-9s %-11s %s\n' "$$a" "$$t" "$$b" "$$en" "$$fl"; \
	done

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

clean:
	@for a in $(APPS); do rm -rf "$$a/obj" "$$a/bin"; done
	@rm -rf */adalib-* */obj-* */obj-gnarl-*
	@echo "build output removed (populated sources kept; use git clean -fdx for those)"
