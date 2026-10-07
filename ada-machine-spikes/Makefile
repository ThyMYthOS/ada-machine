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
# avrada_rts/ada_target_properties (the AVR target description GNATprove
# reads) is written by a real build of avrada_rts only: avrada_rts.gpr
# skips its "-gnatet=" switch when GPR_TOOL is "gnatprove". Regenerating it
# inside GNATprove's own parallel (-j0) compile pass let other processes
# read a half-written file ("missing entry for Bits_BE"), which failed CI
# intermittently. The gnatprove targets that load avrada_rts therefore
# build it first when the file is missing.
#
# `make cross` builds the real cross-compiled targets, separately from `all`
# (they download large toolchains/runtimes via Alire on first use):
#   spike4_g474_board  STM32G474, light_stm32g4xx + gnat_arm_elf -> ELF
#   spike1_pico_board  RP2040, light_rp2040 + gnat_arm_elf -> ELF (with boot2)
#   spike2_avr (SPI and I2C)  ATmega328P, avrada_rts + gnat_avr_elf -> ELF
#   esp32c3_hal_check  esp32c3_pac/_hal compiled (NOT linked) for RISC-V with
#                      gnat_riscv64_elf; spike3_esp itself is not linked, its
#                      runtime is pending (TODO.md #15)
# The board crates reuse the host spike's sources (Source_Dirs) and only add
# the runtime wiring; the host crates stay the native stand-ins built by `all`.
# Note the cross builds share the imported crates' obj/ dirs with the host
# builds (as spike2_avr always has), so a later `make all` recompiles those.
#
# Test mode (TODO.md #15 Step 2): the BME280 spikes can be built so that they
# run a few measurement cycles, write `ADA-MACHINE-TEST: PASS` / `FAIL <code>`
# to the UART and halt, for simulator harnesses. The switch is the GPR external
# ADA_MACHINE_TEST_MODE (off|on, default off), declared once in
# test_support/test_mode.gpr -- not an Alire config variable, because the board
# crates compile the host crates' sources under other crate names (see that
# file). `make cross-test` builds spike1_pico_board and spike2_avr (both
# buses) in test mode; the ELFs land in bin/test/ (bin/{spi,i2c}/test/ for
# spike2_avr) next to the normal ones, with separate obj/ dirs. spike4_g474
# has no test mode (no UART in stm32g474_hal, no sensor). `make test` also
# runs the log-decoder self-test (tools/).
#
# Simulators (TODO.md #15 Step 3): `make sim-avr` runs spike2_avr's test-mode
# ELFs (SPI and I2C, built by cross-test-avr) in simavr against a simulated
# BME280 -- good and wrong-chip-id sensor, four cases -- via sim/avr/. It
# needs simavr 1.7 (+ headers, libelf): `nix-shell` in sim/avr/, or a source
# build as in CI (Ubuntu's 1.6 package breaks the I2C cases). `make sim-avr-diag` is the same with two model
# behaviours relaxed (diagnostic, see sim/avr/Makefile).
#
# `make sim-rp2040` runs spike1_pico's test-mode ELF in Wokwi (the hosted RP2040
# simulator) against a custom BME280 chip (WASM, sim/rp2040/), good and
# wrong-chip-id sensor, two cases. It needs `wokwi-cli` on PATH (or WOKWI_CLI=)
# and a Wokwi CI token in the WOKWI_CLI_TOKEN environment variable (never put
# it in a file); without the token it fails at once with a message. The chip
# compiles and unit-tests without the token: `make -C sim/rp2040 chip test-chip`.
#
# Usage:
#   make             build every crate, report a pass/fail summary
#   make cross       cross-build every board crate + spike2_avr variants
#   make cross-test  cross-build the test-mode variants (see above)
#   make sim-avr     run spike2_avr's test-mode ELFs in simavr (4 cases)
#   make sim-rp2040  run spike1_pico's test-mode ELF in Wokwi (2 cases, token)
#   make <crate>     build just that one crate, e.g. `make bme280`
#   make gnatprove   run GNATprove on every crate, report a summary
#   make test        build and run host_test
#   make clean       remove every crate's build artifacts
#   make list        list the crates this Makefile knows about
#
# Optional variables:
#   ALR              command to invoke Alire (default: alr). Pass ALR="alr -n"
#                    for non-interactive operation (e.g. in CI).

SHELL := /bin/bash
ALR ?= alr

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

# Board crates / checks built by `make cross` (not part of `all`).
BOARD_CRATES := \
	spike4_g474_board \
	spike1_pico_board \
	esp32c3_hal_check

# No -f: GNATprove reuses its why3 proof session under each crate's obj/ dir,
# re-proving only changed units. Establishing that cache cold is expensive
# (notably on Apple silicon), so we keep it incremental and never `make clean`
# between proof runs. Pass -f manually if you ever need a from-scratch re-proof.
GNATPROVE_FLAGS := -j0 --level=1 --output=oneline --output-header

.PHONY: all cross cross-test cross-test-avr cross-test-rp2040 sim-avr sim-avr-diag sim-rp2040 check-wokwi-token test-decoder list test clean gnatprove spike2_avr-i2c gnatprove-spike2_avr-i2c \
        $(BOARD_CRATES) \
        $(CRATES) $(addprefix clean-,$(CRATES)) $(addprefix gnatprove-,$(CRATES))

all:
	@set -e; \
	failed=""; \
	for c in $(CRATES); do \
		echo "==> $$c"; \
		if ( cd "$$c" && $(ALR) build ); then \
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

cross:
	@set -e; \
	failed=""; \
	for c in $(BOARD_CRATES) spike2_avr spike2_avr-i2c; do \
		echo "==> $$c"; \
		if $(MAKE) --no-print-directory ALR="$(ALR)" $$c; then \
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
	echo "All cross targets built ($(words $(BOARD_CRATES)) board/check crates + spike2_avr SPI and I2C)."

# Test-mode cross builds: only the BME280 spikes that have a real target
# build (spike3_esp is not linked yet, spike4_g474 has no test mode).
TEST_MODE_X := -XADA_MACHINE_TEST_MODE=on

cross-test: cross-test-avr cross-test-rp2040
	@echo "Test-mode ELFs built: spike1_pico_board/bin/test, spike2_avr/bin/{spi,i2c}/test"

cross-test-rp2040:
	cd spike1_pico_board && $(ALR) build -- $(TEST_MODE_X)

cross-test-avr:
	cd spike2_avr && $(ALR) build -- $(TEST_MODE_X)
	cd spike2_avr && $(ALR) build -- -XBME280_BUS=I2C $(TEST_MODE_X)

# simavr runs of the spike2_avr test-mode ELFs (needs simavr, see header).
sim-avr: cross-test-avr
	$(MAKE) -C sim/avr run

sim-avr-diag: cross-test-avr
	$(MAKE) -C sim/avr run-diag

# Wokwi runs of the spike1_pico test-mode ELF (needs wokwi-cli and the token,
# see header). The token check comes first so a missing token fails before the
# build; sim/rp2040/Makefile checks it again for direct use.
check-wokwi-token:
	@if [ -z "$$WOKWI_CLI_TOKEN" ]; then \
		echo "sim-rp2040: WOKWI_CLI_TOKEN is not set (create one at https://wokwi.com/dashboard/ci and export it)"; \
		exit 1; \
	fi

sim-rp2040: check-wokwi-token cross-test-rp2040
	$(MAKE) -C sim/rp2040 run

list:
	@for c in $(CRATES); do echo "$$c"; done

# GNATprove only reads avrada_rts/ada_target_properties (see the header).
avrada_rts/ada_target_properties:
	cd avrada_rts && $(ALR) build

gnatprove gnatprove-avrada_rts gnatprove-spike2_avr gnatprove-spike2_avr-i2c: \
  avrada_rts/ada_target_properties

gnatprove:
	@set -e; \
	failed=""; \
	for c in $(CRATES); do \
		echo "==> $$c"; \
		if ( cd "$$c" && $(ALR) gnatprove $(GNATPROVE_FLAGS) ); then \
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
	cd $(patsubst gnatprove-%,%,$@) && $(ALR) gnatprove $(GNATPROVE_FLAGS)

gnatprove-spike2_avr-i2c:
	cd spike2_avr && $(ALR) gnatprove $(GNATPROVE_FLAGS) -XBME280_BUS=I2C

# Per-crate targets, e.g. `make bme280`, `make host_test`.
$(CRATES) $(BOARD_CRATES):
	cd $@ && $(ALR) build

spike2_avr-i2c:
	cd spike2_avr && $(ALR) build -- -XBME280_BUS=I2C

test: host_test test-decoder
	./host_test/bin/host_test

# Log-decoder self-test: real bytes from Ada (the Log_Sink over a mock UART,
# plus the test-mode runner's verdict) decoded by tools/decode_log.py.
test-decoder: host_test
	python3 tools/test_decode_log.py ./host_test/bin/dump_log_stream

clean:
	@for c in $(CRATES); do \
		rm -rf "$$c"/obj "$$c"/bin "$$c"/lib; \
	done

$(addprefix clean-,$(CRATES)):
	rm -rf "$(patsubst clean-%,%,$@)"/obj "$(patsubst clean-%,%,$@)"/bin "$(patsubst clean-%,%,$@)"/lib
