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
      stand-in. **Were left for a follow-on, now completed** (2026-07-22, see the bullet below): `rp2040_hal`, `esp32c3_hal`, `stm32g474_pac`,
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
- [x] **Follow-up rollout (2026-07-22): remaining crates migrated + Alire compiler
      switches now actually applied.** Wired `config/<crate>_config.gpr` into `rp2040_hal`,
      `esp32c3_hal`, `stm32g474_pac`, `stm32g474_hal`, `bme280`, `machine_async`,
      `machine_blocking`, `machine_regmap`, `machine_tasking`, `time_rng_target`,
      `host_test`, and the four spikes -- each `.gpr` now `with`s its config project, lists
      `config` in `Source_Dirs`, AND applies `<Crate>_Config.Ada_Compiler_Switches` in
      `package Compiler`. That last part fixes **Alire's compiler switches previously being
      ignored** (the hand-simplified gprs bypassed them); every crate now builds under its
      Alire build-profile switches. Also disabled Alire's C-header generation repo-wide
      (`[configuration] generate_c = false` in all 21 `alire.toml`s; no `*_config.h` was
      tracked, nothing to `git rm`).
- **Done when:** the generated config restrictions actually take effect and no crate
      carries a duplicate config unit. **Met**: the config layout + Alire compiler switches
      are live across every crate, and C-header generation is off repo-wide. `make all`
      (21 crates incl. the AVR cross-build) + `make test` pass clean, and a
      `gnatprove-rp2040_hal` spot-check shows only pre-existing read-to-clear flow warnings
      -- no restriction loosened, no proof regression.

### 8. Canonicalize PAC volatility encoding — DONE
Representation is meant to be svd2ada *policy* (§9), so decide once and apply
uniformly. Converge on the ESP32-C3 encoding (the review's model). Coupled with
the proof pass the "Not in scope here" section deferred (two of three HALs
using volatile-function/expression patterns flow analysis rejects) — both
closed together since the PAC encoding and the HAL flow contracts over it are
one seam.

- [x] Replaced the blanket `Volatile` on `rp2040_pac` `IO_Bank0.Pin_Regs`/
      `Pin_Regs_Array` and `Pads_Bank0.Pad_Array` with explicit
      `Async_Readers, Async_Writers` (ordinary MMIO read/write, matching
      ESP32C3_PAC.GPIO's plain registers) — §6.6/§9's conformance defect.
      No `Volatile_Full_Access` on these: every field/element is a whole
      32-bit word at its own offset (no sub-word bit-field decomposition),
      so a component store already compiles to one full-width write; said
      so explicitly in a comment rather than leaving it implicit.
- [x] `rp2040_pac-sio.ads`'s SET/CLR/XOR/OE_SET/OE_CLR: `Effective_Reads =>
      False` (a narrower claim — only that reading these back has no side
      effect) → ESP's `Async_Readers, Effective_Writes => True` (each write
      is individually significant, matching what the hardware actually
      does with these write-1/pulse aliases).
- [x] Added `Volatile_Full_Access` + explicit `Size => 32` to every register
      in `rp2040_pac-sio.ads` (RP2040's single-cycle IO block: the
      datasheet defines only full 32-bit access on this bus) and, for
      uniformity across all three PACs per this item's own "Done when,"
      to `esp32c3_pac-gpio.ads`'s GPIO matrix registers (RISC-V-bus
      analogue of the same requirement). `atmega328p_pac` gets a header
      comment instead of any VFA: AVR's 8-bit I/O bus has only one access
      width to begin with, so VFA has nothing to rule out there — a
      genuine "does not apply," not an oversight, and said so explicitly
      rather than silently adding nothing. No register anywhere needed the
      "leave and note why" carve-out for bit-manipulated fields: every
      register in all three PACs is either an opaque scalar (masks/shifts
      combined in software) or, for `ESP32C3_PAC.GDMA.Descriptor`, only
      ever assigned as a whole aggregate — so VFA was never at risk of
      breaking anything, it was simply absent everywhere until now.
- [x] Proof-coupling (the deferred item from "Not in scope here"): audited
      `rp2040_hal`'s `rp2040-{gpio,i2c0,clock}.ads/.adb` and
      `atmega328p_hal`'s `atmega328p-{spi,gpio}.ads/.adb` against
      `esp32c3_hal`'s clean model. Found `Volatile_Function` on every
      hardware-reading function, the read-alone-into-a-local pattern (RM
      7.1.3(9)), and the no-`Pre`-on-a-volatile-function-call pattern
      already in place on both HALs (evidently from earlier sessions'
      work, not newly added here) — the one real gap left was `Global`
      classifying `RP2040_PAC.IO_Bank0.Pins`/`Pads_Bank0.Pads` as `Output`
      in `RP2040.GPIO.Configure`, `RP2040.I2C0.Enable` and
      `RP2040.UART0.Enable` when each call only ever writes the one
      array element at its target pin — a real "partial update claimed as
      Output" defect (this item's own point 3), reclassified to `In_Out`
      in all three. `atmega328p_hal`'s `spi.ads`/`gpio.ads` needed no
      change at all — already conformant.
- **Done when:** one documented volatility encoding per register-kind,
      applied across all three PACs, **and** `rp2040_hal`/`atmega328p_hal`
      are flow-clean like `esp32c3_hal`. **Met**: `make all` (21 crates) and
      `make test` (host_test, all checks passed) pass; `make
      gnatprove-rp2040_hal`/`-atmega328p_hal`/`-esp32c3_hal`/
      `-spike1_pico`/`-spike2_avr`/`-spike2_avr-i2c`/`-spike3_esp` all exit
      0. Checked byte-for-byte against a clean-`HEAD` baseline via `git
      stash`: `rp2040_hal`/`spike1_pico` each lost exactly the 6 "might not
      be set" low-severity flow findings the `Output`→`In_Out` fix
      addresses and gained nothing new (two PAC address-spec warnings
      picked up a "correct volatile properties" clause, same warning
      class, not a new one); `atmega328p_hal`/`esp32c3_hal`/`spike2_avr`
      identical; `spike2_avr-i2c`/`spike3_esp` each showed one bme280
      Bosch-arithmetic residual swap for a different one in the same
      accepted category (confirmed prover-timing noise by rerunning
      `gnatprove-spike3_esp` a second time, not a regression) — no new
      residual class anywhere, and the two array-Global fixes actually
      *removed* real (if low-severity) flow findings rather than adding
      any.

### 9. Smaller cleanups
- [x] **Naming rule:** decide whether a single-instance peripheral is `SPI` or `SPI0`
      and state it in §6.1. `ATmega328P.SPI` currently diverges from `RP2040.I2C0` /
      `ESP32C3.SPI2`; copy-paste-portable app code depends on the answer.
      (Documented, not renamed: §6.1 now states the rule — name after the MCU's own
      datasheet designation, bare where the silicon has one unnumbered instance
      [`ATmega328P.SPI`], numbered where the silicon numbers them [`RP2040.I2C0`,
      `ESP32C3.SPI2` — SPI0/1 are flash-reserved]. `ATmega328P.SPI` was already
      correct; no code changed.)
- [x] **Regmap auto-increment assumption:** `Regmap.Generic_Device.Read_Regs` bakes
      "auto-incrementing burst read" into the *bus-neutral* seam. Document the
      assumption and plan how a non-auto-increment device is expressed before the
      next non-BME280 driver lands.
      (README §15.4 now states the assumption plus the plan for a non-auto-increment
      device: prefer a binding that issues one addressed single-register read per
      byte behind the same `Read_Regs` profile; fall back to a non-burst
      `Generic_Device` variant with a `Read_Reg` single-register formal only if that
      framing doesn't fit. One-line caveat comment added at the `Read_Regs` formal in
      `machine/src/machine-regmap-generic_device.ads`. Plan only, no new code.)
- [x] **esp32c3_pac GDMA over-curation:** a whole interrupt/config/peri-sel block is
      0-referenced and self-labelled "for completeness" — tensions with §9 rule 1.
      Trim, or confirm the DMA path isn't silently relying on reset defaults.
      (Trimmed the genuinely dead registers/constants: `GDMA_INT_RAW/ENA/CLR_CH0` +
      their done/EOF bit constants [driver polls SPI2's own `SPI_DMA_INT_RAW`
      instead], and the unused AUTO_RET/RESTART/AUTO_WRBACK/EOF_MODE bit-position
      constants on registers that are otherwise kept. Kept, with an explicit
      reset-default-dependency comment: `GDMA_IN/OUT_CONF0_CH0` and
      `GDMA_IN/OUT_PERI_SEL_CH0` — these route/configure the DMA channel and are
      left unwritten by this spike, so correctness genuinely depends on their POR
      default; real hardware bring-up must audit them [same "compiles, doesn't run
      yet" caveat as README Appendix C finding 4]. `esp32c3_pac`/`esp32c3_hal`/
      `spike3_esp` still build; gnatprove shows no new residuals, GDMA's own proved-
      check count dropped 9→6 from the trim.)
- [x] **Alire tag hygiene:** dropped the `"hal"` tag from the four PACs (`rp2040_pac`,
      `atmega328p_pac`, `esp32c3_pac`, `stm32g474_pac`) and the `machine` spec crate; the
      four `*_hal` crates keep it. (Done in the 2026-07-22 config sweep.)
- [x] **Demo main:** `spike3_esp/src/main.adb` is a tight unpaced retry loop that
      re-measures a never-initialized device on Initialize failure. Add pacing/guard —
      it's the example people copy.
      (Added a 500 ms `Machine.Tasking.Delays.Delay_Ms` pace at the end of the loop,
      and a guard: on any non-`Ok` `Status` the loop now re-attempts
      `Initialize`/`Configure` before the next `Measure`, instead of resetting
      `Status` straight to `Ok` and re-measuring a possibly-never-initialized
      device.)

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

### 11. Close spike 4's open items (I²C target + RNG, Appendix D) — DONE
Spike 4 (`spike4_g474`, STM32G474) introduced two new `machine` signatures --
`Machine.I2C.Generic_Target` and `Machine.RNG.Generic_Source` -- plus a
spike-local responder (`time_rng_target`), proven against one real HAL
(`stm32g474_hal`, GNATprove-clean) and a scripted `host_test` mock (latch
consistency, repeated-START register-pointer persistence, settable-epoch
write, all passing). Several things were deliberately deferred rather than
silently glossed over (README §18 D19, Appendix D). All closed:

- [x] **Verify `stm32g474_pac`'s RCC enable-bit positions against a primary
      source -- and it found a real bug.** Checked against ST's `cmsis-device-g4`
      `stm32g474xx.h` (read in the browser pane and grepped for the `*_Pos`
      macros, not from search-result summaries, several of which were
      contradictory or invented): `AHB2ENR.RNGEN` was **bit 18 (the L4
      position) but is bit 26 on the G4** -- the RNG would have been unclocked
      on silicon while every test passed. Fixed in `stm32g474_pac-rcc.ads`;
      `GPIOAEN`/`GPIOBEN` (0/1), `TIM2EN` (0), `I2C1EN` (21), the RCC register
      offsets and `RNG_BASE` were right. Not RM0440 itself (the PDF was not
      read) -- the CMSIS header is ST's own machine-readable source for the
      same facts. Also surfaced and fixed: the RNG's 48 MHz clock comes from
      HSI48, which is **off after reset** (`CRRCR`, offset 0x98, `HSI48ON`
      bit 0 -- added to the PAC; `STM32G474.RNG.Enable` now starts it with a
      plain write, no wait: L2 never waits and `Is_Ready` already gates on
      DRDY). `CCIPR.CLK48SEL` reset-to-HSI48 is relied on, not rewritten --
      that default is from search results, not the CMSIS header.
- [x] **Recompute `STM32G474.I2C1`'s `TIMINGR`.** Replaced the placeholder
      `0x2000_090E` (SCLDEL = 0, which violates the setup-time constraint)
      with `0x30420F13` (standard mode, I2CCLK = 16 MHz = HSI16 = PCLK1, the
      reset-default clock this HAL runs on), with the arithmetic in
      `stm32g474-i2c1.adb`: tPRESC 250 ns, SCLDEL 1250 ns, SDADEL 500 ns,
      SCLL 5.0 us, SCLH 4.0 us against the I2C v2 timing constraints.
      **Derived by hand, not run through STM32CubeMX and not copied from
      RM0440's example table** (the survey could not retrieve it) -- the
      value matches my recollection of ST's 16 MHz standard-mode example but
      that is not a verification. **Trap found:** the Alire runtime
      `embedded_stm32g4xx` defaults to a 170 MHz PLL clock, which would make
      this value wrong; a real-runtime build must pin `SYSCLK_Src = HSI16`
      (below).
- [x] **Bus-fault detection in `STM32G474.I2C1.Pop`/`.Push`.** `BERR` (ISR
      bit 8) -> `Bus_Error`, `ARLO` (bit 9) -> `Arbitration_Lost`, bit
      positions from the CMSIS header; `OVR` deliberately not mapped
      (cannot occur with clock stretching on, `NOSTRETCH = 0`). Skip-if-pending
      and `Data := 0` preserved. First attempt cleared the flag in `Pop`/`Push`
      and GNATprove rightly objected (`"ICR" might not be written` on the
      skip path); the flags are now cleared at the transaction boundary
      (`Ack_Address`/`Clear_Stop` write `ICR` with the error-clear bits too),
      keeping `Pop`/`Push` write-free on the error path (fail clean, §7.1
      rule 2). The "Status not modified, could be IN" notes are gone.
- [x] **Second structurally different target-mode controller, and the
      promotion decision.** Added `ATmega328P.I2C_Target`
      (`atmega328p_hal/src/atmega328p-i2c_target.ads/.adb`, TWI slave mode:
      one `TWINT` flag plus a `TWSR` status code, versus STM32's separate
      flags) -- instantiates `Machine.I2C.Generic_Target` unchanged
      (`tests/conformance.ads`), flow/proof clean, `spike2_avr` (both bus
      variants) still cross-builds. It needed three documented
      contortions, none a signature change: `Ack_Address` cannot always
      release the stretch (a read phase needs `TWDR` loaded first, costing
      one bit of L2 state, `Acked`); a read phase ends with the master's NACK
      status, not a STOP event; clock stretching is intrinsic, so there is no
      overrun to report. The signature's comments now say so. **Decision:
      `Generic_Target` promoted to the v1 list.** Likewise a second RNG:
      `ESP32C3.RNG` (a bare `SYSCON` data register, `0x6002_6000 + 0xB0`,
      checked against esp-idf `reg_base.h`/`syscon_reg.h`) has no ready or
      health flags at all and instantiates `Machine.RNG.Generic_Source`
      unchanged; the signature's comment now says `Ok` never means "true
      random" (entropy-source enabling is native config -- esp-idf documents
      RF/ADC noise sources). **Decision: `Generic_Source` promoted.** Also
      added `Has_I2C_Target`/`Has_RNG` to `Machine.HAL_Info.Descriptor`
      (HALs close aggregates with `others => False`) and moved
      `STM32G474.HAL_Info` onto the Descriptor. **Evidence level, plainly:**
      the second instances are compiled, flow/proof-checked and
      conformance-instantiated, not run on silicon or against a TWI model; the
      decision is reversible. README §6.3, D19 and Appendix D updated.
- [x] **`Machine.I2C.Generic_Target_Regfile`: decided not to generalise.**
      `Time_RNG_Target` is still the only target-mode application; the
      mirror of `Regmap.Generic_Device` waits for a second one (§6.3, same
      one-data-point rule). It stays spike-local.
- [x] **Real cross-build attempted -- and it works.** In a scratch copy
      (repo manifests untouched), adding `gnat_arm_elf` 15.3.1 (already
      installed) and `embedded_stm32g4xx` 16.0.0 (fetched by Alire) plus the
      runtime project-file lines links a Cortex-M4 (`7E-M`) ELF, ~67 kB text.
      Recipe and the `SYSCLK_Src = HSI16` requirement are recorded in
      `spike4_g474/alire.toml`; not made the default build so `make` needs no
      runtime download. Not flashed or run.
- **Done when:** the RCC/TIMINGR facts are checked against RM0440, `Pop`/
      `Push` either detect bus faults or the deferral is reflected in a
      signature-level comment (not just a HAL-body one), and the
      v1-promotion/generalization questions have an explicit answer either way.
      **Met**, with the qualifications above (CMSIS header rather than RM0440;
      `TIMINGR` hand-derived). `make all` (21 crates + spike2_avr's I2C
      variant) and `make test` pass; `gnatprove` on `stm32g474_hal` (+ its
      conformance project) proves all checks, `spike4_g474` is residual-for-
      residual identical to the pre-change baseline, `atmega328p_hal`'s new
      package and `esp32c3_hal`'s new `ESP32C3.RNG` add no residual beyond
      the expected "Status not modified" on the health-less RNG. The two
      pre-existing `tests/conformance.adb` SPARK errors (a volatile call in
      `GPIO*_Get`) in the ATmega/ESP32 conformance projects are unrelated and
      untouched.

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

- [x] Add `Machine.SPI.Generic_Chip_Select` (child of the `Machine.SPI` class package
      — SPI *space*, but deliberately NOT part of the `Generic_Master` data-phase
      signature, per §6.1): generic over `with package Pin is new
      Machine.GPIO.Generic_Digital_Out (<>)` plus a **static** polarity formal, exposing
      `procedure Assert` / `procedure Deassert`, both `Inline_Always`. Static formal +
      inline ⇒ each folds to a single `Pin.Set` (one GPIO store) — zero-cost. Landed as
      `machine/src/machine-spi-generic_chip_select.ads/.adb`. Confirmed structurally:
      `Assert`/`Deassert` carry `Inline_Always`; `Polarity : CS_Polarity` is a plain
      (non-generic-package) static formal object, so the `if Polarity = Active_Low`
      folds at instantiation. GNATprove on spike2_avr/spike3_esp even flags the
      untaken branch ("statement has no effect, in instantiation at board.ads:...")
      -- direct evidence the fold happens.
- [x] Polarity: added `type CS_Polarity is (Active_Low, Active_High)` to `Machine.SPI`
      (`machine/src/machine-spi.ads`) -- reads best, matches the proposal, keeps the
      binary D8 discipline (no tri-state/open-drain CS).
- [x] Retyped `Machine.Regmap.Generic_SPI_Binding`'s `CS` formal from
      `Machine.GPIO.Generic_Digital_Out` to `Machine.SPI.Generic_Chip_Select`, and
      replaced the hardcoded `CS.Set (Low)`/`(High)` with `CS.Assert`/`CS.Deassert`
      (`machine_regmap/src/machine-regmap-generic_spi_binding.ads/.adb`). Fail-clean
      preserved unchanged: CS is still deasserted right after `Bus.Exchange` on both
      the write and read paths, error or not.
- [x] Rippled the wiring: `spike2_avr/src/spi/avr_board.ads` and `spike3_esp/src/
      board.ads` each instantiate the digital-out pin as `CS_Pin`, then wrap it as
      `CS is new Machine.SPI.Generic_Chip_Select (Pin => CS_Pin, Polarity =>
      Machine.SPI.Active_Low)` (BME280 CS is active-low on both spikes) and pass that
      `CS` to `Generic_SPI_Binding`. These two instantiations are themselves the
      conformance proof (§6.1's own pattern for this kind of wrapper); no separate
      conformance unit added. Updated README §6.1's CS paragraph (the spike2_avr SPI
      walkthrough) to describe the wrapper and the zero-cost fold.
- Naming note: `Assert`/`Deassert` are the right verbs anyway — `Select`/`Deselect` is
      out because `select` is an Ada reserved word.
- Scope note (YAGNI): keep it CS-specific in SPI space for now. A *general*
      `Machine.GPIO`-level active-polarity output (reusable for enable/reset/active-low-LED
      lines) is the tempting generalization, but there is no second consumer in the spikes
      — generalize only when one appears (§3/§6.3, "standardize proven classes only").
- **Done when:** SPI CS polarity lives in the wiring via `Machine.SPI.Generic_Chip_Select`,
      `Generic_SPI_Binding` no longer hardcodes active-low, and it still compiles to the
      same single GPIO store as today (confirm `Inline_Always` + static fold). **Done**:
      `make all` (21 crates + spike2_avr's I2C variant) and `make test` both pass;
      `gnatprove-spike2_avr`/`-spike3_esp` exit 0 with no new residual class versus a
      `git stash` baseline (the one bme280 Bosch-arithmetic overflow check that seemed
      to differ between runs was confirmed, by rerunning the unmodified baseline
      itself, to be ordinary prover-timing flakiness inherent to that already-accepted
      residual bucket, not something this change introduced).

### 13. Bus claims for shared buses (README §8.5, D20)
README §8.5 adds exclusive bus tenure ("bus claim") as an L3 concern: a
`Machine.Generic_Bus_Claim` signature, per-execution-model arbiters, `Acquire`/`Release`
as `is null` driver formals, and common `Config` records. Nothing is implemented, and
**no spike exercises contention** -- every spike has exactly one device per bus, so the
design is unvalidated (same one-data-point bar as #1 and #11). Ties into #2 (the arbiter
reuses `Machine.Generic_Critical_Section`) and #12 (`Generic_SPI_Binding`/the I²C
binding are where a driver's transfers get bracketed).

- [ ] Add `Busy` to `Machine.I2C.Transaction_Status` / `Machine.SPI.Transaction_Status`
      (beside `Timed_Out`; **not** to the L2 `Bus_Status`), and the minimal
      `Machine.I2C.Config` (speed) / `Machine.SPI.Config` (mode, clock, bit order)
      records. Settle the record contents (README §19 open question 12) before
      freezing.
- [ ] Add `machine/src/machine-generic_bus_claim.ads` (formals: `Config`, `Acquire
      (Cfg, Status : in out)`, `Release`, plus an ISR-safe `Try_Acquire` form).
- [ ] Implement the arbiter in `machine_blocking` first (critical-section-guarded flag,
      timeout → `Timed_Out`, non-recursive), with the ghost `Held` and `Post => not
      Held` on its operations, in the style of #2's `In_Critical`; verify with
      GNATprove. Then `machine_async` (grant completion via generic formal procedure)
      and `machine_tasking` (protected object) once the blocking shape is settled.
- [ ] Thread `Acquire`/`Release` (defaulted `is null`, README §14.1) through `bme280`
      and the `machine_regmap` bindings, with `Acquire` ordered before CS assertion
      and `Release` after deassertion (CS itself needs no claim). Confirm the
      single-device AVR build is byte-identical to today's (null formals fold away).
- [ ] Prove it under contention: add a `host_test` case with two drivers (e.g. two
      scripted mock devices, or `bme280` plus `time_rng_target`'s register file) on
      one mock I²C bus; assert no interleaving, `Busy`/`Timed_Out` on a held bus, and
      `Release` running after a failed transaction (§7.1 rule 8). Optionally a real
      second device on a spike's I²C bus.
- [ ] `boardgen` (§13) is not spiked, so the `shared = true` bus declaration is design
      only; record it there when `boardgen` is prototyped.
- **Done when:** two drivers share one bus through one arbiter in `host_test` with
      the exclusion and fail-clean-release properties asserted, the arbiter's ghost
      postconditions are proved with no new residual, and the single-device AVR
      build is unchanged.

### 14. Peripherals with several interfaces (README §6.1, §6.3, §8.6, D21)
README §8.6 specifies how a peripheral that supports several interfaces (USART as UART,
modem-line UART, IrDA or SPI master; SSP as Motorola/TI/Microwire) is packaged and
switched: parent package per instance, child package per interface with its own data
phase, `Config` for framing, a companion signature for modem lines, Tier A static
exclusion via SPARK preconditions, Tier B within-class switching through the #13 claim,
cross-class switching static only. Nothing is implemented, and no spike has more than
one interface on a peripheral. Depends on #13 for Tier B.

- [ ] Settle the Microwire question first (README §19 open question 13): read the PL022
      TRM / RP2040 datasheet for how Microwire uses the Tx/Rx FIFOs and decide whether
      it is a variant of `Machine.SPI.Generic_Master` or its own signature. The
      online survey only established "half-duplex with a control phase".
- [ ] Add `Machine.UART.Generic_Modem_Lines` (polled `Set_RTS`/`Set_DTR`,
      `Get_CTS`/`Get_DSR`/`Get_DCD`/`Get_RI`; changes through the existing UART
      `Event_Set`; RI trailing-edge only) and add `Frame_Format` (Motorola/TI) to
      `Machine.SPI.Config` (#13).
- [ ] Restructure `atmega328p_hal`: `ATmega328P.USART0` becomes the parent (shared
      `Is_Idle`, `Disable`), the current UART body moves to `ATmega328P.USART0.UART`
      with `Enable (Config)`/`Is_Active` (a volatile read of the mode-select bits, no
      RAM mirror), and add `ATmega328P.USART0.MSPIM` as the second, structurally
      different interface (the cheapest real data point; checks that the SPI settings
      can go into the same write that selects MSPIM, and whether TX/RX must be disabled
      before changing UMSEL — not confirmed by the survey). Update `HAL_Info`, the
      conformance unit and the UART log sink wiring (#10) for the new names.
- [ ] Prove Tier A exclusion: `Enable` with `Pre => not Is_Active (Any)`, data-phase
      operations with `Pre => Is_Active (This)`, `Disable` as a statusless teardown
      (§7.1 rule 7); GNATprove must discharge a UART-then-MSPIM switch sequence and
      reject using an interface that is not enabled.
- [ ] Tier B in `host_test`: a scripted mock with two interfaces behind the #13 arbiter,
      asserting `Busy` while a transfer is active, switching only after `Is_Idle`, and
      `Disable` running after a failed transaction.
- [ ] `boardgen` (§13) is not spiked: the `interface =` key and its pin check are design
      only until it is prototyped.
- **Done when:** AVR USART0 runs the unchanged UART driver path and an MSPIM-based SPI
      path as two interface children, the exclusion is proved, the Microwire question
      has an explicit answer, and Tier B switching is exercised in `host_test`.

### 15. Cross-compile every spike and run it in a simulator in CI
Today only `spike2_avr` really cross-builds; spikes 1, 3 and 4 are compiled for the
*native host* as stand-ins, and nothing ever runs outside `host_test`'s mocks. There is
no GitHub workflow at all (`.github/` does not exist). Goal: every push builds each
spike for its real target, and where a usable simulator exists, runs it against a
simulated BME280 (or, for spike 4, an I²C master) and asserts on its UART log. This is
the "breadth of validation" the guiding principle above asks for, one level closer to
silicon than `host_test`. State of the art as surveyed 2026-10-07 (details per step):

| Spike | Target | Runtime for a real build | Simulator candidate | Gap |
|---|---|---|---|---|
| 1 `spike1_pico` | RP2040 | `light_rp2040` / `embedded_rp2040` (Alire) | Wokwi (Pico; custom chips for BME280) | Wokwi is a hosted service needing a token; Renode/QEMU have no mainline RP2040 |
| 2 `spike2_avr` | ATmega328P | `avrada_rts` (local fork, builds today) | simavr (open source, TWI/SPI/USART models) | BME280 model to write in C |
| 3 `spike3_esp` | ESP32-C3 | `espidf_gnat_runtime` (Jorvik on ESP-IDF/FreeRTOS, `gnat_riscv64_elf` 16.1) -- see the evaluation below | Espressif QEMU fork (UART, no GPSPI listed; `idf.py qemu`); Wokwi ESP32-C3 | needs ESP-IDF 6.x in the build and an IDF-project restructure; QEMU cannot model the SPI sensor |
| 4 `spike4_g474` | STM32G474 | `embedded_stm32g4xx` (verified under #11) | none out of the box (Renode, Wokwi, QEMU list no G4) | custom Renode platform, or build-only |

**Step 0 -- CI skeleton (host only), no new risk.**
- [x] Add `.github/workflows/ada-machine-spikes.yml` on `ubuntu-latest`:
      `alire-project/setup-alire@v6` plus `alr install gnatprove=16.1.0` (setup-alire
      brings only `gnat_native`/`gprbuild`), then `make all`, `make test`,
      `make gnatprove` from `ada-machine-spikes/`. One
      `actions/cache` step over `~/.local/share/alire`, `~/.cache/alire` and `~/.alire`, keyed on
      `hashFiles('**/alire.toml')`; the action's own cache is switched off
      (`cache: false`) because its key only changes with the Alire version, so
      toolchains fetched during the build (`gnat_avr_elf`, ...) would never be saved.
      The Makefile gained `ALR ?= alr` (all `alr` calls go through it); CI passes
      `ALR="alr -n"` for non-interactive runs, local behaviour is unchanged.
- [x] Proof gate: **GNATprove's exit code only** (user decision, 2026-10-07): the
      build fails on GNATprove errors, not on unproved medium checks. No residual
      baseline.
- **Done when:** a PR shows green/red for build, `host_test` and proof on Linux.
      **Met** (2026-10-07: build, `host_test` and GNATprove green on GitHub). The
      runner is pinned to `ubuntu-24.04` (`ubuntu-latest` moves to Ubuntu 26 from
      2026-10-19) and the actions are on their Node 24 majors (`checkout@v7`,
      `cache@v6`, `upload-artifact@v7`).

**Step 1 -- real cross-builds as first-class targets.** Alire cannot make a
dependency conditional on a user switch (only on OS/distribution), so a runtime
dependency cannot hide behind a GPR scenario the way `BME280_BUS` does. Proposal:
one thin *board crate* per spike next to the host one (e.g. `spike4_g474_board/`),
whose `.gpr` reuses `../spike4_g474/src` via `Source_Dirs`, `with`s the runtime
projects, and pins the runtime config; the host crate stays the stand-in.
- [x] `spike4_g474_board`: the #11 recipe made permanent, but on `light_stm32g4xx`
      16.0.0 (spike 4 uses no tasking, so the light runtime fits; no fallback to
      `embedded_stm32g4xx` was needed) with `SYSCLK_Src = HSI16` and `DIV1`
      prescalers pinned. Links a Cortex-M4 ELF (`readelf -A`: v7E-M, VFPv4-D16),
      5852 B text / 204 B data / 4388 B bss (`arm-eabi-size`). Not flashed or run.
- [x] `spike1_pico_board`: `light_rp2040` 16.0.0 + `gnat_arm_elf` 15.3.1, `Board =
      rpi_pico`. Links a Cortex-M0+ ELF (v6S-M), 17248 B text / 272 B data / 2224 B
      bss. **boot2:** supplied by the runtime (`.boot2` section, 256 B at
      0x10000000, from `boot2-w25qxx.S` for the Pico's W25Q flash). **Clocks:** the
      runtime's defaults (12 MHz XOSC, pll_sys 12 * 125 / 6 / 2 = 125 MHz, 1 MHz
      watchdog tick from XOSC) match `rp2040_hal`'s hard-coded 125 MHz
      (`I2C0`, `UART0`) and 1 MHz `Clock.Ticks_Per_Second`; they are pinned
      explicitly in the board crate's `[configuration.values]`. **`clk_peri`:** the
      runtime's `Setup_Clocks` never enables it (reset `CLK_PERI_CTRL.ENABLE = 0`),
      so `RP2040.UART0` had no baud clock on silicon; `RP2040.UART0.Enable` now
      enables it from clk_sys (`RP2040_PAC.Clocks`, offsets/bits checked against
      pico-sdk's `clocks.h`). I2C0 runs from clk_sys and was unaffected. Not run
      on hardware. No UF2 (no Alire tool, none installed).
- [x] `spike2_avr`: already a real build; both bus variants are in `make cross`
      (SPI 6956 B text / 148 B data, I2C 7270 B / 144 B data; `readelf`: Atmel AVR,
      `avr:5`). Compiled and linked with `-mmcu=atmega328p` from avrada_rts's
      `AVR_Tool_Options` (`Linker_Switches`): the ATmega328P startup file with its
      vector table and the 32 KB linker script.
- [~] `spike3_esp`: **compile-checked, runtime pending.** The fallback below is
      implemented as `esp32c3_hal_check/`: `esp32c3_pac`, `esp32c3_hal` (and
      `machine`) compile for RISC-V with `gnat_riscv64_elf` 15.3.1 and its stock
      `light-rv32imac` runtime (ELF32 RISC-V, rv32imac objects; the C3 is rv32imc).
      Nothing is linked and `spike3_esp` is not built for the target. The
      `espidf_gnat_runtime` route below is still open.
      Plan: build on **`espidf_gnat_runtime`** (Vadim Godunko, the A0B
      author; evaluated 2026-10-07, not yet built here). What it is: a GNAT runtime
      generated by `a0b-runtime` (crate `a0b_tools`) for ESP32, ESP32-S3 and
      **ESP32-C3**, with the **Jorvik** profile (tasks, protected objects,
      exceptions, secondary stack), ACATS-validated per its README, running *inside an
      ESP-IDF application*: the Ada code is an Alire-built static library linked by
      ESP-IDF's CMake build (`idf.py build`), so FreeRTOS and the IDF own startup,
      clocks and the tick. Requirements: `gnat^16`, i.e. `gnat_riscv64_elf` 16.1.0
      for the C3 (in the Alire index; only 15.x is installed locally today), and
      ESP-IDF 6.x. The project is meant to start from `godunko/esp32c3_template`.
      **Fit with `spike3_esp`:** it needs `pragma Profile (Ravenscar)`,
      `Ada.Real_Time`, `delay until` and protected objects, and *no*
      `Attach_Handler` (its DMA completion is polled, `board.ads`). Jorvik is a
      superset of Ravenscar, so the language side should fit. To check before
      committing to it:
      (1) **UART0 ownership.** UART0 is the IDF console, and `ESP32C3.UART0` writes
          its registers directly. Move the log sink to UART1, or route it through the
          IDF console/§10.3 FIFO.
      (2) **Peripheral clocks.** `esp32c3_pac` assumes the ROM bootloader's reset
          state. Under IDF, SPI2/GDMA clocks must be enabled explicitly (native
          config) or through IDF calls.
      (3) **`Ada.Real_Time` resolution.** The IDF's default FreeRTOS tick is 100 Hz.
          If the runtime's `delay until` rides on that tick, `Delay_Us` gets 10 ms
          granularity. Check how the runtime implements its clock.
      (4) **Architecture fit.** The L0 becomes "Jorvik on an RTOS framework", not a
          bare-metal runtime: D11 excludes full OSes, not RTOSes, but the IDF owning
          interrupts, clocks and the console touches D5/D6/§10.3. Record the outcome as
          a decision, not silently.
      (5) **Layout.** `spike3_esp` becomes an IDF project (CMake + `main` component)
          wrapping an Alire library crate, i.e. this spike's "board crate" is an IDF
          project.
      **`gnat_xtensa_esp32_elf` (16.1.0) is not an option for this spike.** It
      targets Xtensa (ESP32 and, with the same runtime, ESP32-S3), and the ESP32-C3 is
      RISC-V. It would matter only for a new ESP32/S3 spike with its own PAC/HAL.
      Fallback if the runtime does not fit: cross-*compile* `esp32c3_pac`/`_hal`
      with `gnat_riscv64_elf` without linking `spike3_esp`. A bare-metal rv32imc
      light-tasking port stays a large separate project. Record the outcome in
      README Appendix C.
- [x] `make cross` target building all board crates, the spike2_avr variants and
      the ESP32-C3 compile check; the CI `cross` job (own cache key) runs it and
      uploads the ELFs as artifacts (one per board). Passes locally on macOS; the
      Linux CI run itself has not happened yet.
- **Done when:** CI produces real-target ELFs for spikes 1, 2 and 4, and spike 3's
      status is either "linked" or "compile-checked, runtime pending" -- stated, not
      implied.

**Step 2 -- a test mode that terminates.** Simulators need a pass/fail signal, not an
endless main loop.
- [x] Test-mode switch + verdict + halt for the BME280 spikes (`spike1_pico`,
      `spike2_avr` SPI and I2C, `spike3_esp`); `spike4_g474` deliberately without.
      **Mechanism:** the GPR external `ADA_MACHINE_TEST_MODE` (`off` default / `on`),
      declared once in `test_support/test_mode.gpr` and imported by every spike and
      board project (`alr build -- -XADA_MACHINE_TEST_MODE=on`, or `make cross-test`).
      Not an Alire config variable: the board crates compile the host crates' sources
      under other crate names (a `Spike1_Pico_Config.Test_Mode` would not exist
      there), and Alire has no command-line override of `[configuration.values]`. The
      switch picks source dirs: `test_off/` has a null `Test_Run` whose `Enabled`
      constant is `False` (the `if Test_Run.Enabled` in `main.adb` folds away, nothing
      is compiled); `test_on/` instantiates the shared generic
      `test_support/common/spike_test_runner` over the crate's own wiring. Test
      builds use separate `obj/test` and `bin/test` dirs (`bin/{spi,i2c}/test` for
      spike 2), so the normal build and its GNATprove session are untouched. **Normal
      build unchanged:** `arm-eabi-size`/`avr-size` are identical to before the change
      (spike1 17272 B text / 280 data; spike2 SPI 7254 / 294, I2C 7382 / 276); test mode
      adds 836 B text (RP2040), 346 / 510 B text and 192 / 198 B data (AVR SPI / I2C).
      **Run:** `Initialize` + `Configure`, then 3 `Measure` cycles
      (`Spike_Test_Runner.Cycles`); each must be `Ok` and temperature, pressure and
      humidity inside the BME280 datasheet operating ranges (-40..85 degC,
      300..1100 hPa, 0..100 %RH; the driver's fixed-point types carry the same
      bounds, so this guards against them diverging). Each good cycle still emits the
      deferred-format `Ev_Measured` event.
      **Verdict:** `ADA-MACHINE-TEST: PASS` or `ADA-MACHINE-TEST: FAIL <code>` + `\r\n`,
      written by the application straight through the UART L2 port (14.2 allows it at
      application level); codes `INIT-<S>`, `MEASURE-<S>` (`<S>` = `OK`,
      `WRONG_CHIP_ID`, `BUS_FAULT`, `TIMED_OUT`, `NOT_INITIALIZED`),
      `RANGE-TEMP|PRESS|HUM`. **Drain:** no L2 "TX empty" query exists, so a bounded
      20 ms delay follows the last byte (deepest TX FIFO is the ESP32-C3's 128 B =
      ~11 ms at 115200); gap noted, no HAL touched. **Halt** (`test_support/halt_*`,
      shared `Spike_Halt` spec): AVR `cli` + `sleep` loop built from the existing
      `ATmega328P.Critical_Section.Enter` and `Delays.Sleep_Idle` (no new asm);
      Cortex-M `cpsid i` + `wfi` loop (no `bkpt`); RISC-V `csrci mstatus, 8` + `wfi`
      loop (`halt_riscv`, assembled with `gnat_riscv64_elf` but not linked: `spike3_esp`
      is a host stand-in and uses `halt_host`, a plain loop, until it is linked).
      **Not run anywhere yet:** only built (RP2040, AVR) and exercised on the host
      (`host_test`'s `dump_log_stream` drives the same runner over mocks); the
      simulators are Step 3. **Side findings, both fixed in their own commits:** (a) `spike2_avr` was
      compiled and linked without `-mmcu` (generic avr2, ELF `avr:2`): no vector
      table, so `machine_async`'s SPI interrupt could never have been dispatched,
      and an 8 KB text limit; it now uses avrada_rts's `-mmcu=atmega328p` switches.
      (b) `main.adb`'s `Integer (M.Temperature * 100)` overflowed `Celsius` above
      0.85 degC; it now divides by the type's Small and converts with `Arg'Mod`.
      **`spike4_g474`:** no test mode: `stm32g474_hal` has no UART at all (the log
      sink cannot be wired) and the spike has no sensor to judge; a `READY` line would
      need a new HAL unit, and no simulator can drive the target yet (Step 3).
- [x] Host-side decoder `tools/decode_log.py` (Python 3 stdlib): reads a file or stdin,
      renders the 7-byte `Machine.Blocking.Log_Sink` records (Level, Event_Id BE,
      Arg BE) with event names (table `EVENTS`: the `bme280.adb` ids and `Ev_Measured`;
      unknown ids numeric), recognises the ASCII verdict line and resynchronises on
      it, exit 0 = PASS, 1 = FAIL, 2 = no (complete) verdict. Its `EVENTS` table is the
      seed of README 19 open question 9's rendering table. Self-test
      `tools/test_decode_log.py` (part of `make test`, so the CI host job): the Ada
      program `host_test/bin/dump_log_stream` instantiates `Log_Sink` and the test
      runner over a mock UART and writes real PASS and FAIL byte streams, which the
      script decodes and checks (events, negative temperature, exit codes, truncation,
      garbage prefix).

**Step 3 -- simulators, cheapest and most open first.**
- [x] **AVR / simavr (first).** Open source, runs headless on Linux, models the
      ATmega328P's TWI, SPI and USART. Write a BME280 model in C on simavr's IRQ API
      (one model, both buses: chip-ID register, calibration block, one fixed raw
      sample so the compensated result is known), plus a harness that loads the ELF,
      attaches the model, captures USART0 and checks the `PASS` record. Run both
      `spike2_avr` bus variants. Also test the error path: a model answering the
      wrong chip ID must produce `Wrong_Chip_Id` -- the on-target twin of
      `host_test`'s bad-ID case. `yasimavr` (Python) is the fallback if the C API is
      too awkward.
      **Done.** `sim/avr/`: `avr_harness.c` loads the ELF as atmega328p at 16 MHz,
      attaches `bme280_model.c` (SPI: CS = PB2 active low, mode 0; TWI: address 0x76),
      captures USART0 TX, stops on the `cli` + `sleep` halt (simavr's `cpu_Done`,
      verified) or after 10 simulated s, and exits 0 PASS / 1 FAIL / 2 no verdict /
      3 PASS without the expected bus traffic; `tools/decode_log.py` renders each
      capture. The model covers chip id 0xD0 (0x60, or 0x58 = a BMP280 for the bad
      case), reset, ctrl/status/config, both calibration blocks and the data block,
      with SPI (7-bit address, auto-increment) and I2C (pointer write, repeated
      start) framing, and serves `host_test`'s `Mock_Regmap` bytes: expected
      **25.08 degC (`Ev_Measured` arg 2508), 1006.53 hPa, 20.78 %RH**, as the
      driver computes on the host. `make sim-avr` (simavr 1.7 via
      `sim/avr/shell.nix` locally; the same v1.7 built from source in CI, since Ubuntu only packages 1.6, whose TWI model breaks the I2C cases): SPI and I2C with the
      good sensor -> `PASS` with three 25.08 degC events; with chip id 0x58 ->
      `FAIL INIT-WRONG_CHIP_ID`. `make sim-avr-diag` relaxes the model on purpose
      and is diagnostic only. The simulation found two HAL bugs that would hang on
      silicon too, both fixed: the SPI vector clears SPIF, so `Can_Pop` never held
      inside the ISR (`ATmega328P.SPI.Mark_Transfer_Complete`, called by the ISR
      stub); and `ATmega328P.I2C.Enable` awaited TWINT after a STOP, which never
      sets it (priming removed, `Can_Push` ready when no transaction is open).
- [~] **RP2040 / Wokwi.** The practical option: Wokwi simulates the Pico and has a
      custom-chip API (C compiled to WASM) with I²C and SPI, so the BME280 becomes a
      custom chip; Wokwi's built-in sensors include a BMP180, not a BME280.
      `wokwi-cli` runs in GitHub Actions with a `WOKWI_CLI_TOKEN` secret. Decision
      (user, 2026-10-07): use Wokwi, accepting that it is a hosted, non-open-source
      service with usage limits (free plan: 50 simulated minutes per rolling 30 days)
      and that secrets are not available to PRs from forks, so the job skips cleanly
      without the token. Open alternative: the community Renode RP2040 work (not in
      mainline Renode).
      **Implemented, not yet run:** `sim/rp2040/` holds the Wokwi project
      (`wokwi.toml` loading the test-mode ELF as firmware, `diagram.json` and
      `diagram-bad-id.json`: Pico, BME280 chip on GP4 SDA / GP5 SCL, serial monitor
      on GP0/GP1), the custom chip `bme280-chip.c` (register file byte-identical to
      `sim/avr/bme280_model.c`, chip id from the `chipId` attribute, compiled by
      `wokwi-cli chip compile`), and `check_capture.py` (renders the capture with
      `tools/decode_log.py`, expects three 25.08 degC events for PASS and the
      `Wrong_Chip_Id` warning for the bad id). `make sim-rp2040` (needs
      `WOKWI_CLI_TOKEN`, fails with a message without it) runs `PASS` for chip id
      0x60 and `FAIL INIT-WRONG_CHIP_ID` for 0x58. CI job `sim-rp2040` (pinned
      wokwi-cli v0.28.1, run through the Makefile) skips the simulation with a
      notice when the secret is absent; the chip compile and the chip's host unit
      test (`make -C sim/rp2040 test-chip`, 119 checks) run regardless. Verified
      locally: the test-mode ELF builds, the chip compiles to WASM, the unit test
      passes, `wokwi-cli lint` accepts both diagrams. **Not yet verified:** the
      simulation itself (needs the token): whether rp2040js boots this ELF and
      `light_rp2040`'s clock setup, whether the I²C/UART0 traffic reaches the
      chip and serial monitor, and whether `--serial-log-file` keeps the binary
      log records byte-exact (if it text-decodes, `check_capture.py` skips the
      event check with a warning; the verdict check stays strict).
- [ ] **ESP32-C3 (after its runtime).** With `espidf_gnat_runtime` the firmware is a
      normal ESP-IDF image, so ESP-IDF's own QEMU integration (`idf.py qemu`, or the
      `espressif/idf` container in CI) is the natural runner. Espressif's QEMU fork
      emulates the ESP32-C3 with UART, timers, SPI flash and crypto, but its docs list
      no GPSPI or I²C, so
      the BME280-over-SPI path cannot run there: QEMU can check boot, runtime,
      tasking and the UART log, and the sensor path would end in a bus-fault event
      (assert on that instead). Full path: Wokwi's ESP32-C3 with the same custom
      chip as the Pico, under the same token decision.
- [ ] **STM32G474 (stretch).** No ready simulator: Renode's board list has no G4
      (nor RP2040, AVR or ESP32-C3), Wokwi's STM32 list is C031/L031/F103, QEMU has
      no G4. Options: (a) a custom Renode platform description built from existing
      STM32 models (Cortex-M4, GPIO, timer, the "I2C v2" peripheral model used for
      other families) plus a small RNG model -- whether Renode's I2C v2 model supports
      *target* mode is unverified and decides feasibility; spike 4 also needs a
      simulated *external master* driving the bus (a Renode script or C# peripheral);
      (b) stay build-only and leave behaviour to `host_test`. Recommend (b) in CI
      until (a) is shown to work locally.
- **Done when:** `spike2_avr` (both variants) runs in simavr in CI with good-ID and
      bad-ID BME280 models asserted; RP2040 runs under Wokwi, or the decision
      against a hosted simulator is recorded; ESP32-C3 and STM32G474 have an explicit
      status (simulated / build-only / blocked) in README Appendices C and D.

**Workflow shape (target).** Jobs: `host` (build, `host_test`, proof) ·
`cross` (matrix over board crates, ELF artifacts) · `sim-avr` (simavr) ·
`sim-rp2040` (Wokwi, only when the token is present) · later `sim-esp32c3`.
Simulator jobs depend on `cross` and download its artifacts instead of rebuilding.

**Order and rough size.** Step 0 (small) → Step 1 for G4, AVR, RP2040 (small to
medium, recipes mostly known) → Step 2 (small) → simavr (medium: the BME280 model is
the work) → Wokwi decision → ESP32-C3 on `espidf_gnat_runtime` (medium: IDF-project
restructure plus checks 1–5; large only if it falls back to a bare-metal port) → Renode G4
(stretch).

---

## Not in scope here
- Formal-verification / GNATprove residuals (tracked separately; a GNATprove run
  was in progress at review time). Note the *architectural* observation that the
  SPARK-mandatory pillar (§6.6/D10) is unevenly realized — two of three HALs use
  volatile-function/expression patterns that flow analysis rejects while ESP32-C3
  is clean — but the specifics belong to the proof pass, not this plan.
  **Closed under #8:** by the time the proof pass actually ran this, `rp2040_hal`/
  `atmega328p_hal` already carried `Volatile_Function`, the read-alone-into-a-local
  pattern, and no illegal `Pre` on a volatile-function call (apparently landed
  incidentally in earlier sessions' work, e.g. #1's AVR TWI spike and #2's critical-
  section proof) — the one real remaining gap was a `Global` `Output`/`In_Out`
  misclassification on `RP2040_PAC.IO_Bank0.Pins`/`Pads_Bank0.Pads` in three
  `rp2040_hal` units, fixed under #8. Both HALs are flow-clean like `esp32c3_hal`
  now (`gnatprove-rp2040_hal`/`-atmega328p_hal`/`-esp32c3_hal` all exit 0, no new
  residuals versus a `git stash` baseline).
- `machine_classes`, `machine_streams`, `machine_typed_io`, `boardgen`, `maker` —
  not yet spiked; out of scope until the P0/P1 contract questions settle.
