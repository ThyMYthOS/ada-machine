# Wokwi (RP2040) simulation of spike1_pico's test-mode ELF against a custom
# BME280 chip (TODO.md #15 Step 3).
#
#   make chip       compile bme280-chip.c to bme280.chip.wasm (wokwi-cli chip
#                   compile: fetches wasi-sdk and wokwi-api.h on first use;
#                   needs no token)
#   make test-chip  unit-test the chip's register logic natively (no Wokwi)
#   make run        run both cases with wokwi-cli (needs WOKWI_CLI_TOKEN):
#                     good   chip id 0x60 -> ADA-MACHINE-TEST: PASS
#                     badid  chip id 0x58 -> ADA-MACHINE-TEST: FAIL INIT-WRONG_CHIP_ID
#                   the serial capture of each goes to logs/<case>.bin and is
#                   judged by check_capture.py (tools/decode_log.py rendering)
#   make clean      remove the chip binary, firmware copy, logs and test build
#
# Variables:
#   ELF          the test-mode ELF (default: the crate's bin/test/spike1_pico,
#                what `make cross-test` builds; CI points it at the downloaded
#                artifact)
#   WOKWI_CLI    the wokwi-cli executable (default: wokwi-cli on PATH)
#   TIMEOUT_MS   simulated-time limit per case (default 10000; the CLI stops
#                earlier as soon as --expect-text matches)
#
# The token is only ever read from the environment by wokwi-cli itself.
# Docs: https://docs.wokwi.com/wokwi-ci/cli-usage,
#       https://docs.wokwi.com/guides/custom-chips-to-wasm

SHELL := /bin/bash

ELF        ?= ../../spike1_pico_board/bin/test/spike1_pico
WOKWI_CLI  ?= wokwi-cli
TIMEOUT_MS ?= 10000
PYTHON     ?= python3
CC         ?= cc

WASM := bme280.chip.wasm
FW   := firmware/spike1_pico.elf
LOGS := logs

.PHONY: all chip test-chip run firmware clean

all: chip

chip: $(WASM)

# wokwi-cli chip compile drops wokwi-api.h next to the source on first use.
$(WASM): bme280-chip.c
	$(WOKWI_CLI) chip compile bme280-chip.c -o $(WASM)

# The chip source is compiled from a copy in build/host/ so that it picks up
# the stub wokwi-api.h in test/ rather than the real one fetched next to it.
test-chip: test/test_bme280_chip.c bme280-chip.c test/wokwi-api.h
	@mkdir -p build/host
	cp bme280-chip.c build/host/bme280-chip.c
	$(CC) -std=gnu11 -Wall -Wextra -Werror -O1 -Itest -Ibuild/host \
		-o build/host/test_bme280_chip test/test_bme280_chip.c
	./build/host/test_bme280_chip

firmware:
	@test -f "$(ELF)" || { echo "sim-rp2040: ELF '$(ELF)' not found (make cross-test, or set ELF=)"; exit 1; }
	@mkdir -p firmware
	cp "$(ELF)" $(FW)

# Cases: name diagram-file expected-verdict
define RUNCASE
runcase() { \
	name="$$1"; diagram="$$2"; want="$$3"; \
	echo "==> $$name ($$diagram, expect '$$want')"; \
	rc=0; \
	$(WOKWI_CLI) --timeout $(TIMEOUT_MS) \
		--diagram-file "$$diagram" \
		--expect-text "ADA-MACHINE-TEST: $$want" \
		--fail-text "$$fail" \
		--serial-log-file $(LOGS)/$$name.bin . || rc=$$?; \
	echo "==> $$name: wokwi-cli exit $$rc"; \
	if [ ! -s $(LOGS)/$$name.bin ]; then \
		echo "==> $$name: FAILED (no serial capture)"; failed="$$failed $$name"; return; \
	fi; \
	if [ $$rc -ne 0 ]; then \
		echo "==> $$name: FAILED (wokwi-cli exit $$rc; 42 = timeout)"; failed="$$failed $$name"; \
	fi; \
	$(PYTHON) check_capture.py $(LOGS)/$$name.bin "$$want" | tee $(LOGS)/$$name.txt \
		|| { echo "==> $$name: FAILED (capture check)"; failed="$$failed $$name"; return; }; \
	[ $$rc -eq 0 ] && echo "==> $$name: OK"; \
	echo; \
}
endef

run: $(WASM) firmware
	@if [ -z "$$WOKWI_CLI_TOKEN" ]; then \
		echo "sim-rp2040: WOKWI_CLI_TOKEN is not set (create one at https://wokwi.com/dashboard/ci)"; exit 1; fi
	@set -o pipefail; mkdir -p $(LOGS); failed=""; \
	$(RUNCASE); \
	fail="ADA-MACHINE-TEST: FAIL" runcase good diagram.json "PASS"; \
	fail="ADA-MACHINE-TEST: PASS" runcase badid diagram-bad-id.json "FAIL INIT-WRONG_CHIP_ID"; \
	if [ -n "$$failed" ]; then echo "sim-rp2040 failed:$$failed"; exit 1; fi; \
	echo "sim-rp2040: both cases passed."

clean:
	rm -rf $(WASM) wokwi-api.h firmware build $(LOGS)
