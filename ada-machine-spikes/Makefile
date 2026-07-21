# Makefile for ada-machine-spikes: (re-)builds every crate.
#
# Each crate directory carries its own alire.toml with [[pins]] to its
# sibling dependencies by relative path; `alr build` resolves those and
# selects/builds the toolchain automatically, so no manual PATH/gprbuild
# setup is needed here.
#
# Crates that target real hardware (rp2040_pac, rp2040_hal,
# atmega328p_pac, atmega328p_hal, esp32c3_pac, esp32c3_hal, stm32g474_pac,
# stm32g474_hal, spike1_pico, spike3_esp, spike4_g474) have no cross
# toolchain in most environments -- see each crate's own alire.toml for
# that note. Building them here compiles/checks their sources against
# the *native host* GNAT as a stand-in (real target code generation is
# out of scope); host_test is the one crate meant to actually run, which
# `make test` does. (stm32g474_hal additionally has a tests/conformance.gpr,
# not built by this Makefile -- see its own comment for why, and build it
# directly with `alr exec -- gnatprove -P tests/conformance.gpr` from
# inside stm32g474_hal/ for the deepest instantiated check of the new
# I2C-target/RNG signatures against real, if unverified-on-silicon,
# volatile registers.)
#
# spike2_avr is the exception: it really does cross-build (avrada_rts is
# a local fork of RREE/AVRAda_RTS, patched to build against gnat_avr_elf
# =15.3.1 -- see avrada_rts/alire.toml). `alr build` there invokes the
# real AVR GNAT and produces a linked ELF for the ATmega328P, not a
# native stand-in -- its main.adb's literal AVR inline assembly ("sei")
# is exactly why it couldn't build natively before this.
#
# spike2_avr also has a BME280_BUS Alire config switch (alire.toml),
# defaulting to SPI; `make spike2_avr-i2c` builds/proves the I2C variant
# (ATmega328P's TWI, TODO.md P0 #1) via `-XBME280_BUS=I2C` -- a plain GPR
# external in spike2_avr.gpr, not Alire's own config-value mechanism
# (which only offers a depending crate's [configuration.values], with no
# command-line override), so both variants stay reachable from one crate
# built directly, as here.
#
# `make gnatprove` runs `alr gnatprove` (SPARK flow analysis + proof) the
# same way, per crate. Generic-only crates (machine, machine_async,
# machine_blocking, machine_regmap, machine_tasking, time_rng_target) get
# flow/proof skipped for their own generic units -- GNATprove only
# analyzes a generic through an instantiation, and none of these
# instantiate anything themselves; spike3_esp, spike4_g474 and host_test
# are where the deepest, real instantiated analysis happens (spike4_g474
# and host_test both instantiate Time_RNG_Target for real -- one over
# STM32G474's actual volatile registers, the other over host_test's
# scripted mocks -- and both must pass clean, unlike the "medium checks
# accepted" carve-out below). gnatprove's exit code (unlike a plain read
# of its output) only goes nonzero on genuine errors -- a crate that
# merely has unproved "medium" checks left (an accepted, documented
# residual for bme280's Bosch arithmetic and a few others, see prior
# session notes) still counts as OK here, same as `alr build`.
#
# Known flakiness: avrada_rts.gpr's "-gnatet=" switch dumps
# avrada_rts/ada_target_properties to one fixed path shared by every
# consumer (both spike2_avr bus variants), regenerated afresh each time
# anything recompiles system.ads -- gnatprove's own compile pass uses
# different switches than a real build, so running `make gnatprove`
# straight after avrada_rts's own gnatprove entry can occasionally leave
# spike2_avr reading a properties dump for a different mode ("missing
# entry for Bits_BE/Double_Float_Alignment..."), a pre-existing quirk of
# that shared-file mechanism, not spike2_avr's own sources -- re-running
# `make gnatprove-spike2_avr`/`-spike2_avr-i2c` on their own always
# regenerates it correctly and passes.
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
	time_rng_target \
	rp2040_pac \
	rp2040_hal \
	atmega328p_pac \
	atmega328p_hal \
	avrada_rts \
	esp32c3_pac \
	esp32c3_hal \
	stm32g474_pac \
	stm32g474_hal \
	host_test \
	spike1_pico \
	spike2_avr \
	spike3_esp \
	spike4_g474

GNATPROVE_FLAGS := -j0 --level=1 --output=oneline --output-header -f

.PHONY: all list test clean gnatprove spike2_avr-i2c gnatprove-spike2_avr-i2c \
        $(CRATES) $(addprefix clean-,$(CRATES)) $(addprefix gnatprove-,$(CRATES))

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
	echo "==> spike2_avr-i2c"; \
	if $(MAKE) spike2_avr-i2c; then \
		echo "==> spike2_avr-i2c: OK"; \
	else \
		echo "==> spike2_avr-i2c: FAILED"; \
		failed="$$failed spike2_avr-i2c"; \
	fi; \
	echo; \
	if [ -n "$$failed" ]; then \
		echo "Failed:$$failed"; \
		exit 1; \
	fi; \
	echo "All $(words $(CRATES)) crates built (+ spike2_avr's I2C variant)."

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
	echo "==> spike2_avr-i2c"; \
	if $(MAKE) gnatprove-spike2_avr-i2c; then \
		echo "==> spike2_avr-i2c: OK"; \
	else \
		echo "==> spike2_avr-i2c: FAILED"; \
		failed="$$failed spike2_avr-i2c"; \
	fi; \
	echo; \
	if [ -n "$$failed" ]; then \
		echo "Failed:$$failed"; \
		exit 1; \
	fi; \
	echo "GNATprove ran clean (errors only -- see above for any unproved checks) on $(words $(CRATES)) crates (+ spike2_avr's I2C variant)."

# Per-crate GNATprove targets, e.g. `make gnatprove-bme280`.
$(addprefix gnatprove-,$(CRATES)):
	cd $(patsubst gnatprove-%,%,$@) && alr gnatprove $(GNATPROVE_FLAGS)

gnatprove-spike2_avr-i2c:
	cd spike2_avr && alr gnatprove $(GNATPROVE_FLAGS) -XBME280_BUS=I2C

# Per-crate targets, e.g. `make bme280`, `make host_test`.
$(CRATES):
	cd $@ && alr build

spike2_avr-i2c:
	cd spike2_avr && alr build -- -XBME280_BUS=I2C

test: host_test
	./host_test/bin/host_test

clean:
	@for c in $(CRATES); do \
		rm -rf "$$c"/obj "$$c"/bin "$$c"/lib; \
	done

$(addprefix clean-,$(CRATES)):
	rm -rf "$(patsubst clean-%,%,$@)"/obj "$(patsubst clean-%,%,$@)"/bin "$(patsubst clean-%,%,$@)"/lib
