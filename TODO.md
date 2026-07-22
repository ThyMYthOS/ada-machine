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

### 2. Fix the `machine_async` ISR race (critical-section signature, §14.4) — DONE
`Machine.Async.SPI` shares `Active`/`Sent`/`Got` with the ISR pump using only
`Volatile`, and `Generic_Await.Exchange` writes `Active := False` to abort on
timeout — a real race with `On_Interrupt`. §14.4's critical-section signature
exists precisely to close this and is not implemented anywhere.
Files: `machine_async/src/machine-async-spi.adb`

- [x] Add `machine/src/machine-generic_critical_section.ads` (formals:
      `Mask_State`, `Enter`, `Leave`) per §14.4.
- [x] Instantiate/thread it through `Machine.Async.SPI` around the abort and the
      shared-state updates the ISR also touches. Added a required generic formal
      package `with package Critical is new Machine.Generic_Critical_Section (<>);`
      (matching this codebase's existing "required formal package" idiom, e.g.
      `Port`/`Time` elsewhere) and bracketed the three genuinely-racy mainline
      regions in Enter/Leave: `Start_Exchange`'s kick-off (from `Active := True`
      through the first `Push`/`Sent := 1`), `Read_Response`'s `Got`+`RX_Buf`
      snapshot, and `Generic_Await.Exchange`'s timeout-abort (`Active := False`).
      `On_Interrupt` itself stays untouched by design (hardware ISR-entry masking
      already covers it; re-disabling inside it would only cost the hot path).
      Both existing instantiation sites updated: `spike2_avr/src/spi/avr_board.ads`
      now instantiates `Machine.Generic_Critical_Section` with the real ATmega
      SREG implementation (below); `machine_tasking/src/machine-tasking-generic_spi.adb`
      passes a documented no-op (`Mask_State => Boolean`, both ops trivial) --
      justified in a comment there: on that path, whatever attaches
      `Async_Core.On_Interrupt` to the real vector must, under Ravenscar/Jorvik,
      be a protected procedure (the only legal `pragma Attach_Handler` target),
      so a board routing its `Exchange` calls through that same protected
      object's operations gets real atomicity for free -- the same "defer to
      the runtime's own primitive" shape `Signal`/`Done`'s `Suspension_Object`
      already uses for the completion signal.
- [x] Provide the ATmega implementation (I-bit in SREG) so spike 2 exercises it.
      Added `atmega328p_hal/src/atmega328p-critical_section.ads/.adb`
      (`ATmega328P.Critical_Section`): `Mask_State` is the raw saved `SREG`
      byte; `Enter` reads `SREG` then `cli`s in one inline-asm block, `Leave`
      restores the saved byte with a single `out` -- nesting-safe (save/restore,
      never blind set/clear), body `SPARK_Mode => Off` for the inline asm
      (mirrors `ATmega328P.Delays.Sleep_Idle`), spec stays `SPARK_Mode`. Both
      marked `Inline_Always` (like every other HAL leaf primitive) so the
      native-host stand-in build (no AVR calls in sight) drops the never-called
      body instead of assembling AVR-only mnemonics for the host backend --
      the real AVR cross-build (spike2_avr) forces genuine inlining at its real
      call sites. `spike2_avr/src/spi/avr_board.ads` instantiates
      `Machine.Generic_Critical_Section` with it and threads it into `SPI_Async`.
- [x] Added a ghost-balance proof on top of the Enter/Leave bracketing, and
      **verified** it with GNATprove (not just built): a package-level
      `In_Critical : Boolean := False with Ghost` in `Machine.Async.SPI`'s spec,
      set True right after each `Critical.Enter` and False right before the
      matching `Critical.Leave` in the body, with `Post => ... and then not
      In_Critical` on `Start_Exchange`, `Read_Response`, and
      `Generic_Await.Exchange`, plus `pragma Loop_Invariant (not In_Critical)`
      in `Generic_Await.Exchange`'s poll loop -- turning "every Enter is
      matched by a Leave on every control-flow path" into a GNATprove
      obligation instead of a hand-checked claim. First attempt also added
      `Pre => not In_Critical` and an `In_Critical = In_Critical'Old`
      restatement to each Post; that version's *own* postconditions proved
      fine, but instantiating it through `Machine.Regmap.Generic_SPI_Binding`
      (spike2_avr's `avr_board.ads`, the `Regs` binding used by the BME280
      driver) produced two brand-new "precondition might fail" residuals there
      (confirmed absent on a baseline `gnatprove-spike2_avr` run of the
      pre-ghost-balance tree) -- a real collateral regression, since Regmap's
      `Write_Reg`/`Read_Regs` have no way to see or discharge a precondition
      about a ghost global private to one specific `Bus` actual. Fixed by
      resetting `In_Critical := False` as the first statement of each of the
      three top-level operations (rather than requiring the caller to prove
      it) and dropping the `Pre`/`'Old` restatement, keeping only the `Post =>
      not In_Critical` that actually matters -- this still catches the exact
      same bug (a future early return between an `Enter` and its `Leave`
      leaves `In_Critical` True at that return, failing the same
      postcondition), just without a caller-visible precondition to leak.
- **Done when:** the timeout-abort path can no longer interleave with `On_Interrupt`
      on the shared state, and spike 2 wires a real critical section, AND the
      ghost-balance postconditions added on top are proved with no new
      residual. **Met**: `make machine`, `make machine_async`,
      `make atmega328p_hal`, `make machine_tasking`, `make test` (host_test,
      all checks passed), and a real AVR cross-build (`make spike2_avr`,
      `make spike2_avr-i2c`) all pass; `make spike3_esp` (the tasking/DMA
      path) still builds too. `make gnatprove-machine_async`/
      `gnatprove-atmega328p_hal`/`gnatprove-spike2_avr` all exit clean (0),
      with only pre-existing "medium" residuals unrelated to this change
      (bme280's Bosch arithmetic, PAC address-specification warnings,
      `ATmega328P.SPI`'s own long-standing residuals) -- no new proof
      failures. The ghost-balance postconditions/loop invariant are only
      exercised through a *full* instantiation of `Machine.Async.SPI`, and
      spike2_avr's `avr_board.ads` is the only place in the tree that provides
      one (spike3_esp's SPI path uses the unrelated `Generic_DMA_SPI`, never
      `Machine.Async.SPI`; `machine_tasking`'s own instantiation is itself
      inside another, never-concretely-instantiated generic, so GNATprove can
      only do weaker contextual analysis on it, reported no failures either)
      -- `gnatprove-spike2_avr` is therefore the load-bearing evidence for
      this proof, and it now discharges clean, verified against a baseline
      run of the pre-ghost-balance tree to confirm no residual is new.

### 3. Close the "v1 signature list" gap or re-scope the claim — DONE
README §6.3 advertises v1 = `Digital_Out, Digital_In, UART, SPI_Master,
I2C_Master, Clock, Delays`. Shipped: `Digital_Out, Clock, Delays, I2C, SPI, UART`.
GPIO `Is_High` in every HAL still conforms to nothing because there is no `Digital_In`.

- [x] **Refine the GPIO shape first (review feedback, 2026-07-21), then add `Digital_In`
      under it — one unit of work.** Introduced `machine/src/machine-gpio.ads`
      (`Machine.GPIO`, `type Level is (Low, High)`); moved
      `machine-generic_digital_out.ads` → `machine/src/machine-gpio-generic_digital_out.ads`
      (now `Machine.GPIO.Generic_Digital_Out`, formal `Set (To : Level)`); added
      `machine/src/machine-gpio-generic_digital_in.ads` (`Machine.GPIO.Generic_Digital_In`,
      formal `Get return Level`) and instantiated it against each of `rp2040_hal`'s,
      `atmega328p_hal`'s and `esp32c3_hal`'s own `Is_High` via a thin `Get` wrapper in
      each HAL's `tests/conformance.ads/.adb`.
      *Honest feedback on the two suggestions that prompted this:*
      (1) the `(Low, High)` type is worth adopting — for **explicitness/type-safety** and to
      match embedded-hal's `PinState {Low, High}` (§3), **not** "more states in future": a
      digital *output* is two-state by definition, and Hi-Z / open-drain are
      *configuration/direction* concerns the contract deliberately keeps out of the data
      phase (D8, §6.1), so the enum stays binary.
      (2) moving it under `Machine.GPIO` is exactly what §6.3/D18's two-axis grid prescribes
      **once a companion type exists** — it removes the "standalone because no companion
      type" exception §6.3 currently grants `Generic_Digital_Out`, and lets
      `Digital_In`/`Digital_Out` share one `Level` (mirroring `Machine.I2C`/`Machine.UART`).
- [x] Rippled the rename/type change through every consumer found by
      `grep -rn "Generic_Digital_Out"`: `machine_regmap`'s `Generic_SPI_Binding` (the `CS`
      formal package and its `CS.Set (False/True)` calls → `CS.Set (Low/High)`); every
      `CS_Set` wrapper (`spike2_avr/src/spi/avr_board.{ads,adb}`,
      `spike3_esp/src/board.{ads,adb}`, and each HAL's `tests/conformance.{ads,adb}`
      including `stm32g474_hal`'s, a fourth consumer the grep also turned up) —
      `(High : Boolean)` → `(To : Machine.GPIO.Level)`, body compares `To = High`; plus
      the two `esp32c3_pac` header comments that named the old unit. Confirmed via
      `make all`/`make test` (every crate builds, host_test passes) and
      `make gnatprove-rp2040_hal`/`-atmega328p_hal`/`-esp32c3_hal`/`-spike2_avr`/
      `-spike3_esp` (all exit 0, checked byte-for-byte against a clean-`HEAD` baseline
      via `git stash`: identical residual sets on four crates, one *fewer* medium residual
      on `spike3_esp` — an unrelated bme280 Bosch-arithmetic check that proved this time,
      most likely prover-timing noise, not a regression). README updated too (§6.3's code
      block and "standalone direct children" sentence, §6.4's `CS_Set` example, D18).
- [x] Decide UART: either add a minimal `Machine.UART` + `Generic_Port` spike
      (README's showcase example), or explicitly mark UART out-of-scope for the
      spikes in the README so the v1 claim isn't overstated. Done via
      `Machine.UART`/`Machine.UART.Generic_Port`/`Machine.Blocking.Generic_UART`,
      instantiated against a real L2 UART in all three HALs (`RP2040.UART0`,
      `ATmega328P.USART0`, `ESP32C3.UART0`) and each HAL's own conformance unit —
      driven end-to-end by TODO #10's UART-backed logging facility, not just a
      standalone conformance check.
- **Done when:** every convention subprogram a HAL exposes has a signature it is
      checked against, or the README scopes the exception. **Met**: UART, SPI, I2C,
      Clock, Delays and now `Digital_Out`/`Digital_In` (via `Machine.GPIO`) all have a
      signature every claiming HAL is instantiated/conformance-checked against;
      `Is_High` no longer conforms to nothing.

---

## P1 — Spec ↔ implementation reconciliation (cheap, do alongside P0)

### 4. Amend the adapter dependency rule for `machine_tasking` — DONE
README §4 says "L3 adapters depend on `machine` only," but `machine_tasking`
legitimately wraps `machine_async` + `machine_blocking` (§8.3). The rule is what's
wrong, not the code.
Files: `README.md` §4/§16, `machine_tasking/alire.toml`, `spike3_esp/alire.toml`

- [x] Reworded §4 (adapters depend on `machine` and may compose other adapter crates
      — `machine_tasking → machine_async`, §8.3) and the §16 crate-map "Depends on" row.
- [x] Added a "tasking runtime is a genuine dependency, intentionally not pinned — none
      exists for the spike targets" note to `machine_tasking/alire.toml`, documenting the
      §5 gating mechanism (rather than leaving it silently absent).
- [x] Fixed `spike3_esp/alire.toml`'s stale "awaited through a protected entry" wording →
      "polling a plain protected function under an Ada.Real_Time deadline (not a protected
      entry — Ravenscar's No_Select_Statements bans timed entry calls)".
- **Done when:** the rule as written matches the shipped dependency graph and no
      manifest describes a mechanism the code doesn't use. **Met.**

### 5. Give abort/cleanup operations a defined status convention (§7.1) — DONE
`ESP32C3.SPI2.Cancel_Transfer` takes `Status : in out` but `pragma Unreferenced`s
it and always runs — a silent break of skip-if-pending. This is arguably correct
for teardown (it's called *because* an error is pending) but currently masquerades
as an ordinary chained op.
Files: `README.md` §7.1, `esp32c3_hal/src/esp32c3-spi2.adb`

- [x] Added §7.1 **rule 7 (abort/cleanup exception)**: teardown ops run regardless of a
      pending error and do NOT take a chained `in out Status` (they take no status, or an
      `out`-only status; the owner keeps its pending status across the call).
- [x] Re-typed `Cancel_Transfer` statusless across the board: `Machine.Tasking.
      Generic_DMA_SPI`'s formal, `ESP32C3.SPI2.Cancel_Transfer` (dropped the inert
      `in out Status` + its `pragma Unreferenced`), and the adapter's call site. No change
      needed at `spike3_esp/src/board.ads` (name-based association, both parameterless).
      Only teardown op in the tree; the STM32 `Pop`/`Push` `Status`-IN warnings are a
      *different* gap (data-phase bus-fault detection), tracked in #11.
- **Done when:** the spec names the exception explicitly and no op declares a `Status`
      parameter it ignores. **Met**: `make machine_tasking`/`esp32c3_hal`/`spike3_esp` +
      `make test` pass; `gnatprove-esp32c3_hal`/`-spike3_esp` exit 0 with only pre-existing
      residuals — the change *removed* `Cancel_Transfer`'s old "Status could be IN" smell
      rather than adding one.

---

## P2 — Conformance, config, and consistency

### 6. Fill the conformance-unit holes — DONE
- [x] DMA-SPI profiles: documented as **intentionally board-level**, not instantiated in
      `esp32c3_hal/tests/conformance.ads`. Instantiating `Machine.Tasking.Generic_DMA_SPI`
      (an L3c *adapter*) there would force this L2 HAL to depend on machine_tasking (L3),
      inverting the layering; the conformance is checked where both are visible —
      `spike3_esp/src/board.ads` instantiates it with exactly ESP32C3.SPI2's three
      procedures. Added a comment explaining this (a documented, architecturally-forced
      deferral, not a hole).
- [x] Defined `machine/src/machine-hal_info.ads` (`Machine.HAL_Info.Descriptor`): one
      presence flag per v1 class (GPIO/UART/SPI/I2C/Clock/Delays), fields defaulted so the
      console/boardgen descriptor (§10.3/§13) grows additively. Replaces the per-HAL ad-hoc
      `Has_X` constants — which were also **stale** (RP2040 said no UART though it has one;
      ATmega said no I2C though #1 added TWI).
- [x] Rewrote `RP2040.HAL_Info`/`ATmega328P.HAL_Info` to the standard shape and added the
      previously-missing `ESP32C3.HAL_Info`. Each mirrors its own `tests/conformance.ads`
      (every `True` has a matching conformance instantiation).
- **Done when:** each HAL has a `HAL_Info` of the standard shape and every signature it
      implements is instantiated in its own conformance unit. **Met**: `make machine`/
      `rp2040_hal`/`atmega328p_hal`/`esp32c3_hal` + `make test` pass, and the esp32c3_hal
      conformance unit compiles; DMA-SPI conformance is documented board-level.

### 7. Plumb the compile-time configuration mechanism end-to-end
"Everything the binary does is what the manifest says" (§14.5) is unproven: the
PAC/HAL `.gpr` files never include `config/` or `with` the generated
`*_config.gpr`, so `No_Elaboration_Code`, `Pure`, and `-O3 -gnatn` are dead.

- [x] Adopted the standard Alire gpr layout on `machine` as the reference (done under
      #10: `with "config/machine_config.gpr";`, `config` added to `Source_Dirs`).
      Rolled out to `atmega328p_hal` and all three PACs (`rp2040_pac`, `atmega328p_pac`,
      `esp32c3_pac`) -- each `.gpr` now `with`s its generated `config/<crate>_config.gpr`
      and lists `config` in `Source_Dirs`, mirroring `machine`'s pattern exactly (no
      layout invented). Verified the restrictions are actually live, not just present:
      every migrated crate's `<crate>_config.ali` records `RR NO_ELABORATION_CODE`, and
      the AVR cross-build's own compile log shows `atmega328p_hal_config.ads` (the
      generated one) being compiled for the real ATmega328P target, not just the host
      stand-in. **Still un-migrated, left for a follow-on** (out of this round's scope,
      not blocked by any violation): `rp2040_hal`, `esp32c3_hal`, `stm32g474_pac`,
      `stm32g474_hal`, `bme280`, `machine_async`, `machine_blocking`, `machine_regmap`,
      `machine_tasking`, `time_rng_target`, `host_test`, `avrada_rts`, and all four
      spikes -- each already has a generated `config/` dir waiting to be wired the same
      way.
- [x] Deleted the hand-authored duplicate `atmega328p_hal/src/atmega328p_hal_config.ads`.
      Confirmed *why* deleting it is load-bearing, not just hygiene: with both it and the
      newly-wired-in `config/atmega328p_hal_config.ads` (Alire-generated) present in
      `Source_Dirs` at once, `alr build` silently compiled the **stale hand-authored
      copy** and ignored the generated one -- no duplicate-source error or warning from
      gprbuild -- confirmed by comparing the compiled unit's recorded source timestamp
      (via the `.ali`) against both candidate files' mtimes. So wiring `config/` into
      `Source_Dirs` without removing the duplicate would have left `No_Elaboration_Code`
      still dead for this crate while *looking* wired. F_CPU unaffected: the deleted
      file's hardcoded `16_000_000` matches `alire.toml`'s `[configuration.variables]`
      default (`F_CPU = 16_000_000`) and the generated `config/atmega328p_hal_config.ads`
      carries the same value; `ATmega328P.Delays`/`.Clock`/`.I2C`/`.USART0`'s
      `ATmega328P_HAL_Config.F_CPU` references still resolve post-deletion (Ada's
      case-insensitivity makes this the same unit as the generated
      `Atmega328p_Hal_Config`).
- **Done when:** the generated config restrictions actually take effect and no crate
      carries a duplicate config unit. **Partially met**: true now for `machine`,
      `atmega328p_hal`, `rp2040_pac`, `atmega328p_pac`, `esp32c3_pac`. `make all` (all 21
      crates, including the real AVR cross-build) and `make test` (host_test, all checks
      passed) both pass clean -- no restriction was loosened to get there. The remaining
      crates listed above are still on the old hand-simplified layout; none of them hit a
      violation blocking migration, they were simply out of this round's scope.

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
Originally: every spike instantiated `bme280` with the default **null** `Log_Event`,
so the logging design was entirely unexercised. All three spikes should demonstrate
the architecture's logging facility, backed by a UART, end-to-end. (README §14.1
null-object formals, §14.2 deferred formatting + static thresholds, §10.3 the
diagnostic channel a log sink reuses.) Spike 1 now does; spikes 2 and 3 still use
the null default.

**Depends on the UART work in P0 #3** — a log sink backed by a UART presupposes a
`Machine.UART` signature and a `<MCU>.UARTx` L2 package in each HAL. Sequence this
after #3.

- [x] Extend `machine/src/machine-log.ads`: add `type Level is (Error, Warning,
      Info, Debug, Trace)` and the enabled threshold as an Alire config variable
      rendered to a static constant (so disabled `if L <= Enabled_Level` folds away —
      §14.2). Ties into the config plumbing in #7. Done via `machine/alire.toml`'s
      `Log_Level` `[configuration.variables]` entry, bridged into `Machine.Log.
      Enabled_Level` through `Machine_Config.Log_Level_Kind'Pos`/`Level'Val` (a static
      expression, so the fold still holds) — `machine` is the first crate wired
      end-to-end per #7's config plumbing; a dependent crate overrides it from its
      own `alire.toml` (`spike1_pico/alire.toml` does, as a working example).
- [x] Define the log-sink shape as a generic formal (deferred formatting: the sink
      receives `Level` + `Event_Id` + scalar `Arg`, never a formatted string — §14.2),
      defaulted `is null` so not wiring it still costs nothing (§14.1). Done via
      `Machine.UART`/`Machine.UART.Generic_Port`/`Machine.Blocking.Generic_UART` in
      `machine`, plus BME280's pre-existing `Log_Event ... is null` formal.
- [x] Provide a `machine_blocking`-based sink implementation that drains log events
      over an L2/L3 UART ("a log sink is just the §10.3 diagnostic channel wearing a
      different hat"). The spikes have no runtime FIFO (§10.3), so the pragmatic
      transport is a direct blocking UART drain — document that choice. Done via
      `machine_blocking`'s `Machine.Blocking.UART` (chained `Put`, §8.1) and
      `Machine.Blocking.Log_Sink` (the direct drain, generic over any
      `Machine.UART.Generic_Port` instance; documents the no-runtime-FIFO choice
      in its own header comment).
- [x] In each board wiring (`spike1_pico`, `spike2_avr`, `spike3_esp`), instantiate
      `bme280` with a real `Log_Event` bound to that UART sink instead of the null
      default; emit at least the existing driver events (`Wrong_Chip_Id`, `Bus_Fault`,
      `Timed_Out`) and a per-measurement Info/Trace line. Done for all three: RP2040
      UART0, ATmega328P USART0 (both the SPI and I2C bus variants share one
      `main.adb`), and ESP32-C3 UART0 each got a real PAC + L2 HAL package and a
      `Log_Event` wired at Warning severity, plus an Info-level per-measurement line
      emitted directly by each `main.adb`.
- [x] Keep the discipline from §14.2: log only decisions/state transitions/error
      paths — never per-byte data phases, never inside L2 primitives. Held
      throughout: the per-measurement trace is emitted once per `Measure` call
      from `main.adb`, never inside a UART L2 body.
- [x] Extend `host_test` to instantiate the driver with a recording log sink and
      assert on emitted events (the logging formals double as test probes — §14.5).
      Done via `host_test`'s `Recording_Log_Sink` + a bad-chip-id mock regmap,
      asserting the `Wrong_Chip_Id` path emits exactly the expected event/arg.
- **Done when:** all three spikes route their driver's log events through a
      UART-backed sink using the deferred-formatting + static-threshold facility, and
      `host_test` verifies emitted events via a recording sink. **Met.**

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

### 12. Chip-select semantics over Digital_Out (`Machine.SPI.Generic_Chip_Select`)
Proposal (review feedback, 2026-07-22): a zero-cost wrapper over
`Machine.GPIO.Generic_Digital_Out` that captures CS polarity
(`Active_Low`/`Active_High`) and exposes `Assert`/`Deassert`, living in SPI space
(SPI is the only CS user today). **Valid — and it corrects a real misplacement, not
just ergonomics.** `Machine.Regmap.Generic_SPI_Binding` currently **hardcodes
active-low** CS (`CS.Set (Low)` to assert, `CS.Set (High)` to deassert), baking
device/board polarity into the *bus-neutral* binding — the wrong layer (§6.1: CS
belongs to whoever owns the topology). The wrapper moves polarity to the wiring and
lets the binding speak in semantics, so an active-high-CS device stops being a silent
latent break.

- [ ] Add `Machine.SPI.Generic_Chip_Select` (child of the `Machine.SPI` class package
      — SPI *space*, but deliberately NOT part of the `Generic_Master` data-phase
      signature, per §6.1): generic over `with package Pin is new
      Machine.GPIO.Generic_Digital_Out (<>)` plus a **static** polarity formal, exposing
      `procedure Assert` / `procedure Deassert`, both `Inline_Always`. Static formal +
      inline ⇒ each folds to a single `Pin.Set` (one GPIO store) — zero-cost.
- [ ] Polarity: either a small `type CS_Polarity is (Active_Low, Active_High)` in
      `Machine.SPI` (reads best, matches the proposal) or reuse `Machine.GPIO.Level` as
      `Active : Level` to add no new type — pick one. Keep it binary (no tri-state/
      open-drain CS; same D8 discipline as `Level`).
- [ ] Retype `Machine.Regmap.Generic_SPI_Binding`'s `CS` formal from
      `Generic_Digital_Out` to the new wrapper (or to `Assert`/`Deassert` formal procs),
      and replace the hardcoded `CS.Set (Low)`/`(High)` with `CS.Assert`/`CS.Deassert`.
- [ ] Ripple the wiring: spike 2 (SPI variant) and spike 3 instantiate the CS wrapper
      (BME280 = `Active_Low`) and pass it to the binding; add a conformance instantiation;
      update README §6.1's CS note to mention the optional wrapper.
- Naming note: `Assert`/`Deassert` are the right verbs anyway — `Select`/`Deselect` is
      out because `select` is an Ada reserved word.
- Scope note (YAGNI): keep it CS-specific in SPI space for now. A *general*
      `Machine.GPIO`-level active-polarity output (reusable for enable/reset/active-low-LED
      lines) is the tempting generalization, but there is no second consumer in the spikes
      — generalize only when one appears (§3/§6.3, "standardize proven classes only").
- **Done when:** SPI CS polarity lives in the wiring via `Machine.SPI.Generic_Chip_Select`,
      `Generic_SPI_Binding` no longer hardcodes active-low, and it still compiles to the
      same single GPIO store as today (confirm `Inline_Always` + static fold).

---

## Not in scope here
- Formal-verification / GNATprove residuals (tracked separately; a GNATprove run
  was in progress at review time). Note the *architectural* observation that the
  SPARK-mandatory pillar (§6.6/D10) is unevenly realized — two of three HALs use
  volatile-function/expression patterns that flow analysis rejects while ESP32-C3
  is clean — but the specifics belong to the proof pass, not this plan.
- `machine_classes`, `machine_streams`, `machine_typed_io`, `boardgen`, `maker` —
  not yet spiked; out of scope until the P0/P1 contract questions settle.
