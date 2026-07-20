# Makefile for ada-machine-spikes: (re-)builds every crate.
#
# Each crate directory carries its own alire.toml with [[pins]] to its
# sibling dependencies by relative path; `alr build` resolves those and
# selects/builds the toolchain automatically, so no manual PATH/gprbuild
# setup is needed here.
#
# Crates that target real hardware (rp2040_pac, rp2040_hal,
# atmega328p_pac, atmega328p_hal, esp32c3_pac, esp32c3_hal, spike1_pico,
# spike3_esp) have no cross toolchain in most environments -- see each
# crate's own alire.toml for that note. Building them here compiles/
# checks their sources against the *native host* GNAT as a stand-in
# (real target code generation is out of scope); host_test is the one
# crate meant to actually run, which `make test` does.
#
# spike2_avr is the exception: it really does cross-build (avrada_rts is
# a local fork of RREE/AVRAda_RTS, patched to build against gnat_avr_elf
# =15.3.1 -- see avrada_rts/alire.toml). `alr build` there invokes the
# real AVR GNAT and produces a linked ELF for the ATmega328P, not a
# native stand-in -- its main.adb's literal AVR inline assembly ("sei")
# is exactly why it couldn't build natively before this.
#
# `make gnatprove` runs `alr gnatprove` (SPARK flow analysis + proof) the
# same way, per crate. Generic-only crates (machine, machine_async,
# machine_blocking, machine_regmap, machine_tasking) get flow/proof
# skipped for their own generic units -- GNATprove only analyzes a
# generic through an instantiation, and none of these instantiate
# anything themselves; spike3_esp and host_test are where the deepest,
# real instantiated analysis happens. gnatprove's exit code (unlike a
# plain read of its output) only goes nonzero on genuine errors -- a
# crate that merely has unproved "medium" checks left (an accepted,
# documented residual for bme280's Bosch arithmetic and a few others,
# see prior session notes) still counts as OK here, same as `alr build`.
#
# Usage:
#   make             build every crate, report a pass/fail summary
#   make <crate>     build just that one crate, e.g. `make bme280`
#   make gnatprove   run GNATprove on every crate, report a summary
#   make test        build and run host_test
#   make clean       remove every crate's build artifacts
#   make list        list the crates this Makefile knows about

SHELL := /bin/bash

CRATES := \
	machine \
	machine_async \
	machine_blocking \
	machine_regmap \
	machine_tasking \
	bme280 \
	rp2040_pac \
	rp2040_hal \
	atmega328p_pac \
	atmega328p_hal \
	avrada_rts \
	esp32c3_pac \
	esp32c3_hal \
	host_test \
	spike1_pico \
	spike2_avr \
	spike3_esp

GNATPROVE_FLAGS := -j0 --level=1 --output=oneline --output-header -f

.PHONY: all list test clean gnatprove $(CRATES) $(addprefix clean-,$(CRATES)) \
        $(addprefix gnatprove-,$(CRATES))

all:
	@set -e; \
	failed=""; \
	for c in $(CRATES); do \
		echo "==> $$c"; \
		if ( cd "$$c" && alr build ); then \
			echo "==> $$c: OK"; \
		else \
			echo "==> $$c: FAILED"; \
			failed="$$failed $$c"; \
		fi; \
		echo; \
	done; \
	if [ -n "$$failed" ]; then \
		echo "Failed:$$failed"; \
		exit 1; \
	fi; \
	echo "All $(words $(CRATES)) crates built."

list:
	@for c in $(CRATES); do echo "$$c"; done

gnatprove:
	@set -e; \
	failed=""; \
	for c in $(CRATES); do \
		echo "==> $$c"; \
		if ( cd "$$c" && alr gnatprove $(GNATPROVE_FLAGS) ); then \
			echo "==> $$c: OK"; \
		else \
			echo "==> $$c: FAILED"; \
			failed="$$failed $$c"; \
		fi; \
		echo; \
	done; \
	if [ -n "$$failed" ]; then \
		echo "Failed:$$failed"; \
		exit 1; \
	fi; \
	echo "GNATprove ran clean (errors only -- see above for any unproved checks) on $(words $(CRATES)) crates."

# Per-crate GNATprove targets, e.g. `make gnatprove-bme280`.
$(addprefix gnatprove-,$(CRATES)):
	cd $(patsubst gnatprove-%,%,$@) && alr gnatprove $(GNATPROVE_FLAGS)

# Per-crate targets, e.g. `make bme280`, `make host_test`.
$(CRATES):
	cd $@ && alr build

test: host_test
	./host_test/bin/host_test

clean:
	@for c in $(CRATES); do \
		rm -rf "$$c"/obj "$$c"/bin "$$c"/lib; \
	done

$(addprefix clean-,$(CRATES)):
	rm -rf "$(patsubst clean-%,%,$@)"/obj "$(patsubst clean-%,%,$@)"/bin "$(patsubst clean-%,%,$@)"/lib
