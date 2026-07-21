# Ada Machine — Spike Review Action Plan

Derived from the architecture review of `ada-machine-spikes/` (2026-07-20). Items
are ordered by how much they gate a `machine` 1.0 freeze. Section numbers in
parentheses reference `README.md`.

Legend: **P0** = must resolve before freezing any contract · **P1** = doc/spec
reconciliation, cheap and clarifying · **P2** = consistency & cleanup.

Guiding principle from the review: the contract *shapes* are mostly right; what
is missing is **breadth of validation**, not restructuring. Prioritise widening
the evidence base over re-designing.

---

## P0 — Contract validation (blocks 1.0 freeze)

### 1. Validate the I²C contract against a non-FIFO controller — DONE
`Machine.I2C.Generic_Master` was modelled on RP2040's DW_apb_i2c command FIFO and
RP2040 was the *only* I²C controller in the spikes. STM32 I²C / AVR TWI are
register-event state machines, not command FIFOs — the shape's fit was unverified.
(README §6.3, B.4, C.4, open question 3)

- [x] Add an AVR TWI I²C L2 spike (`atmega328p_hal`): implemented `Set_Target`,
      `Can_Push`, `Push_Write`, `Push_Read_Request`, `Can_Pop`, `Pop` over TWCR/TWDR/TWSR
      (`atmega328p-i2c.ads/.adb`). Closes the missing **8-bit I²C** data point.
- [x] Wired the *unchanged* `bme280` driver over TWI (`spike2_avr/src/i2c/`,
      selectable via the new `BME280_BUS` Alire config switch alongside the
      existing SPI wiring) — confirms the portability claim survives a second,
      structurally different I²C controller.
- [x] TWI *does* fit, but not without contortion — documented, not hidden:
      TWI has no FIFO and no auto-start-on-write, so a full byte transfer needs
      up to three chained hardware actions (START, address+R/W, data) the first
      time in a transaction, gated one at a time by the single TWINT flag.
      `Push_Write`/`Push_Read_Request` hide the START/address sub-steps behind a
      **bounded busy-spin** (§6.2 permits "completes in bounded short time", not
      only "returns immediately") — each sub-step is one hardware action, same
      order of magnitude as the register setup `Enable` already does
      synchronously elsewhere in this HAL. Only the actual data byte — the
      repeated, hot-path operation — stays fully async, gated by `Can_Push`/
      `Can_Pop` reading `TWINT` directly, the same depth-1 shape as
      `ATmega328P.SPI`'s `Busy`. No signature revision was needed.
- **Done when:** two structurally different I²C controllers instantiate the same
      signature and drive the same driver, OR the signature is revised and
      re-validated. → RP2040's command FIFO and AVR TWI's register-event state
      machine both drive `Machine.Blocking.I2C` + unmodified `bme280`; `alr build`/
      `alr gnatprove` pass clean (flow, same residual-tolerance level as the rest
      of the repo) for both `spike2_avr`'s SPI and I2C variants.

### 2. Fix the `machine_async` ISR race (critical-section signature, §14.4)
`Machine.Async.SPI` shares `Active`/`Sent`/`Got` with the ISR pump using only
`Volatile`, and `Generic_Await.Exchange` writes `Active := False` to abort on
timeout — a real race with `On_Interrupt`. §14.4's critical-section signature
exists precisely to close this and is not implemented anywhere.
Files: `machine_async/src/machine-async-spi.adb`

- [ ] Add `machine/src/machine-generic_critical_section.ads` (formals:
      `Mask_State`, `Enter`, `Leave`) per §14.4.
- [ ] Instantiate/thread it through `Machine.Async.SPI` around the abort and the
      shared-state updates the ISR also touches.
- [ ] Provide the ATmega implementation (I-bit in SREG) so spike 2 exercises it.
- **Done when:** the timeout-abort path can no longer interleave with `On_Interrupt`
      on the shared state, and spike 2 wires a real critical section.

### 3. Close the "v1 signature list" gap or re-scope the claim
README §6.3 advertises v1 = `Digital_Out, Digital_In, UART, SPI_Master,
I2C_Master, Clock, Delays`. Shipped: `Digital_Out, Clock, Delays, I2C, SPI`.
GPIO `Is_High` in every HAL conforms to nothing because there is no `Digital_In`.

- [ ] Add `machine/src/machine-generic_digital_in.ads` and instantiate it in each
      HAL's conformance unit against `Is_High`.
- [ ] Decide UART: either add a minimal `Machine.UART` + `Generic_Port` spike
      (README's showcase example), or explicitly mark UART out-of-scope for the
      spikes in the README so the v1 claim isn't overstated.
- **Done when:** every convention subprogram a HAL exposes has a signature it is
      checked against, or the README scopes the exception.

---

## P1 — Spec ↔ implementation reconciliation (cheap, do alongside P0)

### 4. Amend the adapter dependency rule for `machine_tasking`
README §4 says "L3 adapters depend on `machine` only," but `machine_tasking`
legitimately wraps `machine_async` + `machine_blocking` (§8.3). The rule is what's
wrong, not the code.
Files: `README.md` §4/§16, `machine_tasking/alire.toml`, `spike3_esp/alire.toml`

- [ ] Reword §4/§16: "adapters depend on `machine`, and may compose other adapter
      crates," citing `machine_tasking → machine_async` as the canonical example.
- [ ] Add the tasking-runtime dependency to `machine_tasking/alire.toml`, OR add an
      explicit "runtime omitted — no cross toolchain in this repo" note matching the
      HAL manifests, so the runtime-gating mechanism (§5) is at least documented.
- [ ] Fix the stale `spike3_esp/alire.toml` wording: it says `Generic_DMA_SPI` is
      "awaited through a protected entry" — the code polls a plain protected
      function under a delay-until loop (`machine-tasking-generic_dma_spi.adb`).
- **Done when:** the rule as written matches the shipped dependency graph and no
      manifest describes a mechanism the code doesn't use.

### 5. Give abort/cleanup operations a defined status convention (§7.1)
`ESP32C3.SPI2.Cancel_Transfer` takes `Status : in out` but `pragma Unreferenced`s
it and always runs — a silent break of skip-if-pending. This is arguably correct
for teardown (it's called *because* an error is pending) but currently masquerades
as an ordinary chained op.
Files: `README.md` §7.1, `esp32c3_hal/src/esp32c3-spi2.adb`

- [ ] Add a §7.1 carve-out: abort/cleanup/teardown ops run regardless of pending
      error and get a distinct signature convention (not `in out Status` skip-if-pending).
- [ ] Re-type `Cancel_Transfer` (and any sibling teardown ops) to match the new
      convention so the parameter isn't inert.
- **Done when:** the spec names the exception explicitly and no op declares a
      `Status` parameter it ignores.

---

## P2 — Conformance, config, and consistency

### 6. Fill the conformance-unit holes
- [ ] Instantiate the DMA-SPI profiles (`Start_Transfer`/`Cancel_Transfer`/
      `Read_Response`) in `esp32c3_hal/tests/conformance.ads` — today they're only
      checked downstream in `spike3_esp/src/board.ads`, so the crate's own CI
      conformance claim has a hole exactly where it's most novel. (Or document that
      block-transfer conformance is intentionally board-level.)
- [ ] Define a standardized `HAL_Info` record shape in `machine` (it's referenced by
      the console/drain-ownership and boardgen designs, §10.3/§13 — it deserves a
      contract, not per-HAL `Has_X : Boolean` stubs).
- [ ] Add the missing `ESP32C3.HAL_Info` package once the shape exists.
- **Done when:** each HAL has a `HAL_Info` of the standard shape and every signature
      it implements is instantiated in its own conformance unit.

### 7. Plumb the compile-time configuration mechanism end-to-end
"Everything the binary does is what the manifest says" (§14.5) is unproven: the
PAC/HAL `.gpr` files never include `config/` or `with` the generated
`*_config.gpr`, so `No_Elaboration_Code`, `Pure`, and `-O3 -gnatn` are dead.

- [ ] Adopt the standard Alire gpr layout on one crate end-to-end as the reference
      (`with "config/<crate>_config.gpr"`, config dir in `Source_Dirs`); then roll
      out to the rest.
- [ ] Delete the hand-authored duplicate `atmega328p_hal/src/atmega328p_hal_config.ads`
      (conflicts with the generated `config/` copy; its "no toolchain" comment is stale).
- **Done when:** the generated config restrictions actually take effect and no crate
      carries a duplicate config unit.

### 8. Canonicalize PAC volatility encoding
Representation is meant to be svd2ada *policy* (§9), so decide once and apply
uniformly. Converge on the ESP32-C3 encoding (the review's model).

- [ ] Replace the blanket `Volatile` on `rp2040_pac` `IO_Bank0.Pins` / `Pads_Bank0.Pads`
      with precise flavors — §6.6/§9 explicitly call blanket Volatile a conformance defect.
- [ ] Pick one encoding for write-1/pulse (SET/CLR/XOR) registers: use ESP's
      `Async_Readers, Effective_Writes => True`, not RP2040's `Effective_Reads => False`.
- [ ] Add `Volatile_Full_Access` + explicit `Object_Size` where word-access APB/RISC-V
      buses require it (§9 rule 2) — currently on no register in any PAC.
- **Done when:** one documented volatility encoding per register-kind, applied across
      all three PACs.

### 9. Smaller cleanups
- [ ] **Naming rule:** decide whether a single-instance peripheral is `SPI` or `SPI0`
      and state it in §6.1. `ATmega328P.SPI` currently diverges from `RP2040.I2C0` /
      `ESP32C3.SPI2`; copy-paste-portable app code depends on the answer.
- [ ] **Regmap auto-increment assumption:** `Regmap.Generic_Device.Read_Regs` bakes
      "auto-incrementing burst read" into the *bus-neutral* seam. Document the
      assumption and plan how a non-auto-increment device is expressed before the
      next non-BME280 driver lands.
- [ ] **esp32c3_pac GDMA over-curation:** a whole interrupt/config/peri-sel block is
      0-referenced and self-labelled "for completeness" — tensions with §9 rule 1.
      Trim, or confirm the DMA path isn't silently relying on reset defaults.
- [ ] **Alire tag hygiene:** drop the `"hal"` tag from the three PACs and the `machine`
      spec crate — only the `*_hal` crates should carry it.
- [ ] **Demo main:** `spike3_esp/src/main.adb` is a tight unpaced retry loop that
      re-measures a never-initialized device on Initialize failure. Add pacing/guard —
      it's the example people copy.

### 10. Wire a UART-backed logging facility into every spike
Every spike currently instantiates `bme280` with the default **null** `Log_Event`,
so the logging design is entirely unexercised. All three spikes should demonstrate
the architecture's logging facility, backed by a UART, end-to-end. (README §14.1
null-object formals, §14.2 deferred formatting + static thresholds, §10.3 the
diagnostic channel a log sink reuses.)

**Depends on the UART work in P0 #3** — a log sink backed by a UART presupposes a
`Machine.UART` signature and a `<MCU>.UARTx` L2 package in each HAL. Sequence this
after #3.

- [ ] Extend `machine/src/machine-log.ads`: add `type Level is (Error, Warning,
      Info, Debug, Trace)` and the enabled threshold as an Alire config variable
      rendered to a static constant (so disabled `if L <= Enabled_Level` folds away —
      §14.2). Ties into the config plumbing in #7.
- [ ] Define the log-sink shape as a generic formal (deferred formatting: the sink
      receives `Level` + `Event_Id` + scalar `Arg`, never a formatted string — §14.2),
      defaulted `is null` so not wiring it still costs nothing (§14.1).
- [ ] Provide a `machine_blocking`-based sink implementation that drains log events
      over an L2/L3 UART ("a log sink is just the §10.3 diagnostic channel wearing a
      different hat"). The spikes have no runtime FIFO (§10.3), so the pragmatic
      transport is a direct blocking UART drain — document that choice.
- [ ] In each board wiring (`spike1_pico`, `spike2_avr`, `spike3_esp`), instantiate
      `bme280` with a real `Log_Event` bound to that UART sink instead of the null
      default; emit at least the existing driver events (`Wrong_Chip_Id`, `Bus_Fault`,
      `Timed_Out`) and a per-measurement Info/Trace line.
- [ ] Keep the discipline from §14.2: log only decisions/state transitions/error
      paths — never per-byte data phases, never inside L2 primitives.
- [ ] Extend `host_test` to instantiate the driver with a recording log sink and
      assert on emitted events (the logging formals double as test probes — §14.5).
- **Done when:** all three spikes route their driver's log events through a
      UART-backed sink using the deferred-formatting + static-threshold facility, and
      `host_test` verifies emitted events via a recording sink.

### 11. Close spike 4's open items (I²C target + RNG, Appendix D)
Spike 4 (`spike4_g474`, STM32G474) introduced two new `machine` signatures --
`Machine.I2C.Generic_Target` and `Machine.RNG.Generic_Source` -- plus a
spike-local responder (`time_rng_target`), proven against one real HAL
(`stm32g474_hal`, GNATprove-clean) and a scripted `host_test` mock (latch
consistency, repeated-START register-pointer persistence, settable-epoch
write, all passing). Several things were deliberately deferred rather than
silently glossed over (README §18 D19, Appendix D):

- [ ] Verify `stm32g474_pac`'s RCC enable-bit positions (`AHB2ENR.RNGEN`,
      `APB1ENR1.I2C1EN`) against RM0440's actual register tables -- currently
      transcribed from memory/CMSIS convention and flagged as such in
      `stm32g474_pac-rcc.ads`, the one unverified fact in an otherwise
      CMSIS-header-cross-checked PAC.
- [ ] Recompute `STM32G474.I2C1`'s `TIMINGR` placeholder against the real
      core clock (STM32CubeMX's I2C timing tool, or RM0440's worked
      examples) before any real hardware bring-up.
- [ ] Add bus-fault detection (`BERR`/`ARLO`) to `STM32G474.I2C1.Pop`/`.Push`
      -- deferred in this first cut; `Status` currently never leaves `Ok` in
      either, which is why GNATprove flags both `Status` parameters as
      "not modified, could be IN" (an honest reflection of the gap, not a
      separate bug).
- [ ] Decide whether `Machine.I2C.Generic_Target` / `Machine.RNG.Generic_Source`
      promote to the README §6.3 v1 list, or need revision, once a second
      *structurally different* target-mode I2C controller exists (e.g. AVR
      TWI in target mode, or a legacy-IP STM32 for contrast) -- the same
      one-data-point bar `Machine.I2C.Generic_Master` was itself held to
      until item 1 (above) closed it by adding AVR TWI as a second,
      structurally different controller.
- [ ] Decide whether `Time_RNG_Target`'s register-file responder deserves a
      generic `Machine.I2C.Generic_Target_Regfile` (the mirror of
      `Machine.Regmap.Generic_Device`) once a second target-mode
      application exists -- kept spike-local for now (§6.3).
- [ ] Attempt a real cross-build once a `gnat_arm_elf` toolchain +
      `embedded_stm32g4xx` (damaki) resolve in a given environment --
      unlike RP2040/ESP32-C3, a published Alire runtime crate already
      exists for this family, so this may be closer than the other three
      spikes' cross-build gaps.
- **Done when:** the RCC/TIMINGR facts are checked against RM0440, `Pop`/
      `Push` either detect bus faults or the deferral is reflected in a
      signature-level comment (not just a HAL-body one), and the
      v1-promotion/generalization questions have an explicit answer either way.

---

## Not in scope here
- Formal-verification / GNATprove residuals (tracked separately; a GNATprove run
  was in progress at review time). Note the *architectural* observation that the
  SPARK-mandatory pillar (§6.6/D10) is unevenly realized — two of three HALs use
  volatile-function/expression patterns that flow analysis rejects while ESP32-C3
  is clean — but the specifics belong to the proof pass, not this plan.
- `machine_classes`, `machine_streams`, `machine_typed_io`, `boardgen`, `maker` —
  not yet spiked; out of scope until the P0/P1 contract questions settle.
