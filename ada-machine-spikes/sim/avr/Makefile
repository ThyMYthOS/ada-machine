# simavr harness for spike2_avr's test-mode ELFs (TODO.md #15 Step 3).
#
#   make            build avr_harness
#   make run-diag   the same cases with two model behaviours relaxed (see below)
#   make run        run the four cases (SPI/I2C x good/wrong-chip-id sensor)
#                   against the test-mode ELFs and print a pass/fail summary
#   make clean      remove the harness binary and captured logs
#
# Variables:
#   ELF_DIR         directory holding {spi,i2c}/test/spike2_avr (default: the
#                   crate's own bin/, i.e. what `make cross-test` builds; CI
#                   points it at the downloaded artifact)
#   OUT_DIR         where captured USART0 bytes and decoded logs go (logs/)
#   SIMAVR_PREFIX   install prefix of simavr (include/simavr, lib/); if unset,
#                   pkg-config is used. Needed under Nix, whose simavr.pc has
#                   an empty prefix (`nix-shell` in this directory sets it).
#
# Ubuntu 24.04: apt-get install simavr libsimavr-dev libelf-dev (1.6); also
# works with simavr 1.7 (the nixpkgs version used for the local run).

CC      ?= cc
ELF_DIR ?= ../../spike2_avr/bin
OUT_DIR ?= logs
DECODE  := ../../tools/decode_log.py
PYTHON  ?= python3

ifdef SIMAVR_PREFIX
SIM_CFLAGS := -I$(SIMAVR_PREFIX)/include/simavr
SIM_LIBS   := -L$(SIMAVR_PREFIX)/lib -lsimavr -lelf -lm -lpthread
else
SIM_CFLAGS := $(shell pkg-config --cflags simavr)
SIM_LIBS   := $(shell pkg-config --libs simavr) -lelf -lm -lpthread
endif

CFLAGS ?= -O2
CFLAGS += -Wall -Wextra -std=gnu11 $(SIM_CFLAGS)

SHELL := /bin/bash

# Wrong chip id: 0x58 is what a real BMP280 answers.
BAD_ID := 0x58

all: avr_harness

avr_harness: avr_harness.c bme280_model.c bme280_model.h
	$(CC) $(CFLAGS) -o $@ avr_harness.c bme280_model.c $(SIM_LIBS)

# Cases: name bus chip-id expected-verdict expected-exit-status [harness flags]
WRONG := FAIL INIT-WRONG_CHIP_ID

# Shell function shared by `run` and `run-diag`.
define RUNCASE
runcase() { \
	name="$$1"; bus="$$2"; id="$$3"; want="$$4"; rc="$$5"; shift 5; \
	total=$$((total+1)); \
	echo "==> $$name (bus=$$bus chip-id=$$id, expect '$$want') $$*"; \
	./avr_harness --bus $$bus --chip-id $$id --out $(OUT_DIR)/$$name.bin "$$@" \
		$(ELF_DIR)/$$bus/test/spike2_avr \
		> $(OUT_DIR)/$$name.stdout 2> $(OUT_DIR)/$$name.stderr; \
	status=$$?; \
	got=$$(sed -n 's/^VERDICT: //p' $(OUT_DIR)/$$name.stdout); \
	cat $(OUT_DIR)/$$name.stderr; \
	$(PYTHON) $(DECODE) $(OUT_DIR)/$$name.bin > $(OUT_DIR)/$$name.txt || true; \
	cat $(OUT_DIR)/$$name.txt; \
	temps=$$(grep -c 'temperature=25.08 degC' $(OUT_DIR)/$$name.txt || true); \
	if [ "$$want" = "PASS" ] && [ "$$temps" != "3" ]; then \
		got="$$got, but $$temps/3 'temperature=25.08 degC' events"; \
	fi; \
	if [ "$$got" = "$$want" ] && [ "$$status" = "$$rc" ]; then \
		echo "==> $$name: OK (verdict '$$got', exit $$status)"; \
	else \
		echo "==> $$name: FAILED (verdict '$$got' exit $$status; want '$$want' exit $$rc)"; \
		failed="$$failed $$name"; \
	fi; \
	echo; \
}
endef

.PHONY: all run run-diag clean

# The real check: hardware-faithful SPIF/TWINT behaviour, no diagnostics.
run: avr_harness
	@mkdir -p $(OUT_DIR); failed=""; total=0; \
	$(RUNCASE); \
	runcase spi-good spi 0x60 "PASS" 0; \
	runcase spi-bad  spi $(BAD_ID) "$(WRONG)" 1; \
	runcase i2c-good i2c 0x60 "PASS" 0; \
	runcase i2c-bad  i2c $(BAD_ID) "$(WRONG)" 1; \
	if [ -n "$$failed" ]; then echo "sim-avr failed:$$failed"; exit 1; fi; \
	echo "sim-avr: all $$total cases passed."

# DIAGNOSTIC (not a test of the target as written): the same four cases with
# the two hardware behaviours the HAL currently trips over switched off in the
# model (see TODO.md #15 findings): SPIF visible inside the SPI ISR, TWINT set
# after a STOP. Shows that the harness and BME280 model themselves are sound.
run-diag: avr_harness
	@mkdir -p $(OUT_DIR); failed=""; total=0; \
	$(RUNCASE); \
	runcase diag-spi-good spi 0x60 "PASS" 0 --diag-spif-in-isr; \
	runcase diag-spi-bad  spi $(BAD_ID) "$(WRONG)" 1 --diag-spif-in-isr; \
	runcase diag-i2c-good i2c 0x60 "PASS" 0 --diag-twint-after-stop; \
	runcase diag-i2c-bad  i2c $(BAD_ID) "$(WRONG)" 1 --diag-twint-after-stop; \
	if [ -n "$$failed" ]; then echo "sim-avr diagnostics failed:$$failed"; exit 1; fi; \
	echo "sim-avr diagnostics: all $$total cases passed."

clean:
	rm -rf avr_harness avr_harness.dSYM $(OUT_DIR)
