# EHAL — An Opinionated Architecture Concept for an Ada Embedded HAL

**Status:** Draft 0.2 — 2026-07-14
**Author:** Manuel Stahl (with research assistance)
**In scope:** 8-bit (ATtiny/ATmega AVR) through 32-bit (RP2040-class Cortex-M) to 64-bit (PolarFire SoC-class RISC-V); [MPU](#g-mpu)-based memory protection; [SMP](#g-smp) and [AMP](#g-amp) multicore; two privilege levels (RISC-V M-/U-Mode, ARM privileged/unprivileged) — always on embedded runtime profiles (bare metal / [Ravenscar](#g-ravenscar)-class tasking).
**Out of scope:** [MMU](#g-mmu)-based virtual memory and IOMMU — the line where full OSes begin (§2) — and x86 targets.

---

## Glossary

- <a id="g-a0b"></a>**A0B** — Vadim Godunko's family of asynchronous, callback-based Ada driver crates ([github.com/godunko/a0b-i2c](https://github.com/godunko/a0b-i2c)); `A0B.Await` converts callbacks to blocking behavior with or without tasking.
- <a id="g-adl"></a>**ADL (Ada Drivers Library)** — AdaCore's monolithic embedded driver library ([github.com/AdaCore/Ada_Drivers_Library](https://github.com/AdaCore/Ada_Drivers_Library)); origin of the current [`hal` crate](#g-halcrate).
- <a id="g-alire"></a>**Alire** — the Ada LIbrary REpository, Ada's package manager and crate ecosystem ([alire.ada.dev](https://alire.ada.dev)).
- <a id="g-amp"></a>**AMP** — Asymmetric MultiProcessing: cores run separate programs/roles (e.g. PolarFire SoC's E51 monitor core + U54 application cores), as opposed to [SMP](#g-smp).
- <a id="g-bsp"></a>**BSP (Board Support Package)** — a crate naming a board's pins/devices and providing board init, on top of an MCU [HAL](#g-hal).
- <a id="g-chained"></a>**Chained status (sticky error)** — EHAL's error convention (§7.1): fallible operations take `Status : in out` and become no-ops while an error is pending, so multi-step transactions fail all-or-nothing with one handler at the end. Precedents: Go's `errWriter` pattern ([Errors are values](https://go.dev/blog/errors-are-values)), C stdio's sticky `ferror` stream state.
- <a id="g-crate"></a>**Crate** — an [Alire](#g-alire) package: sources + manifest, resolved by dependency solving.
- <a id="g-defmt"></a>**defmt (deferred formatting)** — Rust's embedded logging framework ([defmt.ferrous-systems.com](https://defmt.ferrous-systems.com/)): format strings are interned into a host-readable table and never occupy target flash; the target emits only compact event IDs + scalar arguments, the host renders text.
- <a id="g-devicetree"></a>**Devicetree** — Zephyr's/Linux's declarative hardware description ([docs](https://docs.zephyrproject.org/latest/build/dts/index.html)); in Zephyr it is compiled to C macros at build time and instantiates driver structs.
- <a id="g-dma"></a>**DMA** — Direct Memory Access: peripheral-to-memory transfers without CPU involvement, completion signaled by interrupt.
- <a id="g-eh"></a>**embedded-hal** — Rust's trait-based HAL contract ([github.com/rust-embedded/embedded-hal](https://github.com/rust-embedded/embedded-hal)); v1.0 design rationale [here](https://blog.rust-embedded.org/embedded-hal-v1/).
- <a id="g-generic"></a>**Generic package / instantiation** — Ada's compile-time parameterization; GNAT macro-expands each instantiation (monomorphization), enabling full inlining at the cost of code duplication.
- <a id="g-gnatprove"></a>**GNATprove** — the [SPARK](#g-spark) analysis tool: flow analysis and formal proof of Ada/SPARK code.
- <a id="g-hal"></a>**HAL (Hardware Abstraction Layer)** — API layer hiding register-level detail behind peripheral operations.
- <a id="g-halcrate"></a>**`hal` crate (1.x)** — the existing Alire crate of tagged limited interfaces (`HAL.GPIO`, `HAL.SPI`, …) extracted from [ADL](#g-adl) ([alire.ada.dev/crates/hal](https://alire.ada.dev/crates/hal.html)).
- <a id="g-htif"></a>**HTIF** — Berkeley Host-Target InterFace: RISC-V simulator console via magic `tohost`/`fromhost` memory words (Spike, QEMU `spike` machine); not present on real silicon.
- <a id="g-jorvik"></a>**Jorvik** — Ada 2022's relaxed [Ravenscar](#g-ravenscar) tasking profile (multiple entries, pure barriers).
- <a id="g-light"></a>**light runtime** — GNAT's minimal runtime profile (formerly [ZFP](#g-zfp)): no tasking, no exception propagation, no finalization/heap ([GNAT runtimes doc](https://docs.adacore.com/gnat_ugx-docs/html/gnat_ugx/gnat_ugx/gnat_runtimes.html)). **light-tasking** adds Ravenscar/Jorvik tasking; **embedded** adds full exception propagation.
- <a id="g-mmu"></a>**MMU** — Memory Management Unit: page-based virtual memory with address translation; the hardware feature that enables (and in practice implies) a full OS. Out of scope, as is the IOMMU (its DMA-side counterpart).
- <a id="g-mpu"></a>**MPU** — Memory Protection Unit: region-based access control without address translation; standard on Cortex-M and RISC-V (PMP), usable by embedded runtimes for stack guards and partitioning. In scope.
- <a id="g-nep"></a>**No_Exception_Propagation** — GNAT restriction: exceptions may only be handled in the frame that raises them; raising otherwise ends in the Last_Chance_Handler. In force on all light-class runtimes.
- <a id="g-pac"></a>**PAC (Peripheral Access Crate)** — a crate containing only register bindings for one MCU family (Rust convention via [svd2rust](https://docs.rust-embedded.org/book/design-patterns/hal/gpio.html); proposed for Ada by damaki in [thread 4364](https://forum.ada-lang.io/t/towards-a-hal-for-multiple-runtimes/4364)).
- <a id="g-ravenscar"></a>**Ravenscar** — the restricted, analyzable Ada tasking profile used by embedded runtimes.
- <a id="g-rtt"></a>**RTT (Real-Time Transfer)** — debug-probe console via a RAM ring buffer polled by the probe (SEGGER RTT and workalikes); no peripheral registers, no traps, works at full speed while running.
- <a id="g-semihosting"></a>**Semihosting** — ARM debug console: a breakpoint/trap instruction (`BKPT 0xAB`) the attached debugger services; very slow, and halts or faults when no debugger is attached.
- <a id="g-signature"></a>**Signature package** — a generic package with formal parameters and an empty visible part, used purely to name and type-check a set of operations; the Ada analog of a Rust trait declaration (formal-package pattern).
- <a id="g-smp"></a>**SMP** — Symmetric MultiProcessing: identical cores under one program/scheduler (Ravenscar task dispatching domains; `polarfiresoc-smp` runtime).
- <a id="g-spark"></a>**SPARK** — the formally analyzable Ada subset ([adacore.com/sparkpro](https://www.adacore.com/sparkpro)); notably excludes `access all T'Class`.
- <a id="g-svd"></a>**SVD** — CMSIS System View Description, vendor XML describing an MCU's registers.
- <a id="g-svd2ada"></a>**svd2ada** — AdaCore's [SVD](#g-svd)-to-Ada register binding generator ([github.com/AdaCore/svd2ada](https://github.com/AdaCore/svd2ada)).
- <a id="g-tagged"></a>**Tagged interface / dynamic dispatch** — Ada OOP: `limited interface` + class-wide types; calls through `'Class` dispatch via vtable at runtime.
- <a id="g-vfa"></a>**Volatile_Full_Access** — GNAT aspect forcing full-width register reads/writes; needed on buses that misbehave on sub-word access.
- <a id="g-wfi"></a>**WFI** — Wait For Interrupt: CPU sleep instruction until the next interrupt.
- <a id="g-zfp"></a>**ZFP** — Zero FootPrint runtime, the historical name of the [light](#g-light) profile; still the accurate label for [AVRAda](https://github.com/RREE/AVRAda_Lib)'s runtime.

---

## 1. Summary

EHAL is a layered hardware abstraction architecture for embedded Ada, designed as a set of small [Alire](#g-alire) [crates](#g-crate) rather than a monolithic library. Its central commitments:

1. **The portable contract is compile-time, not runtime.** On-chip peripherals are exposed through a *package-spec convention* (same spec shape, different body per MCU — the [TinyGo](https://tinygo.org/docs/reference/machine/)/[modm](https://modm.io) model). Portable device drivers are *[generic packages](#g-generic)* with narrow formal parameters, checked against *[signature packages](#g-signature)*. No [tagged types](#g-tagged), no access-to-class-wide, no dispatching in the core.
2. **The core API never blocks.** Every layer-2 operation either completes in bounded short time or returns immediately with status. Blocking, interrupt/[DMA](#g-dma)-driven, and tasking behavior are *adapters* layered on top, each compiled only when the runtime profile supports it.
3. **Register access lives in per-MCU [PAC](#g-pac) crates** — generated from [SVD](#g-svd), then hand-curated — separate from both the runtime and the HAL implementation.
4. **[SPARK](#g-spark) is mandatory, 8-bit viability is mandatory.** Every core crate carries `SPARK_Mode` specs and must pass [GNATprove](#g-gnatprove) flow analysis; any construct GNATprove rejects, or that costs RAM on an ATtiny (512 B), is excluded from the core contract. Non-provable conveniences are quarantined in one clearly marked optional crate.
5. **Initialization stays MCU-specific.** The contract abstracts only the data phase; configuration is native. On 32-bit-class targets, an optional *compile-time board description* (devicetree-like, resolved entirely at build time into ordinary Ada — §13) generates the wiring; it is a generator, never a runtime mechanism, and not offered for AVR.
6. **Beginner ergonomics are a separate layer** (`maker`), an Arduino-API clone where pins are integers — never a constraint on the HAL itself.

This resolves the tension identified in the forum threads ([4364](https://forum.ada-lang.io/t/towards-a-hal-for-multiple-runtimes/4364), [4296](https://forum.ada-lang.io/t/an-embedded-ecosystem-for-beginners/4296)): the [ADL](#g-adl)'s tagged-interface [`hal` crate](#g-halcrate) works well on Cortex-M with the [light runtime](#g-light) but is not SPARK-provable, effectively unusable on AVR, and forces one synchronous API onto runtimes with different capabilities. EHAL instead follows the path Rust's [embedded-hal](#g-eh) 1.0 validated — a tiny, stable, dependency-light contract with per-MCU implementations and execution-model variants in separate crates — translated into Ada's compile-time idioms.

## 2. Goals and non-goals

**Goals**

- One contract that a driver author targets once, and that runs unmodified from ATtiny to PolarFire SoC — always on **embedded runtime profiles** ([light](#g-light), light-tasking, embedded / [Ravenscar](#g-ravenscar)/[Jorvik](#g-jorvik)). This includes [MPU](#g-mpu)-partitioned systems, two privilege levels (M-/U-Mode, privileged/unprivileged), and [SMP](#g-smp) as well as [AMP](#g-amp) multicore.
- **Replace vendor driver libraries with SPARK-proven Ada over time.** The `<mcu>_hal` crates are intended to grow toward full-featured, formally analyzed peripheral coverage — taking over the role vendor C libraries (and [ADL](#g-adl)) play today. The EHAL *contract*, however, abstracts only the common minimum: full hardware features are native L2 surface of each `<mcu>_hal`, never contract.
- First-class [Alire](#g-alire) integration: everything is a crate; the runtime, [PAC](#g-pac), HAL, adapters, drivers and board support resolve through normal dependency resolution.
- [SPARK](#g-spark) as a hard requirement: all specs in `ehal`, PACs, L2 HALs, adapters and portable drivers are `SPARK_Mode`; the contract must never force a user program out of SPARK (see §6.6).
- Zero-cost on the smallest targets: a GPIO toggle through the HAL must compile to the same instructions as direct register access (`sbi`/`cbi` on AVR, single `str` on Cortex-M).
- Honest abstraction: standardize only what is actually common (data-phase operations); leave configuration MCU-specific, because "the abstraction is leaky by design" ([Grosser, thread 4364](https://forum.ada-lang.io/t/towards-a-hal-for-multiple-runtimes/4364)) — no two MCUs configure an I2C peripheral the same way.
- **Declarative, compile-time board/device configuration** as an optional top layer for 32-bit-class targets: a [devicetree](#g-devicetree)-like description resolved entirely at build time into ordinary Ada instantiations and init calls (§13). Explicitly not offered for AVR-class targets.

**Non-goals**

- **Full OS targets, and the hardware that implies them.** Linux (e.g. on PolarFire SoC) and other rich-OS environments are out of scope, and so are [MMU](#g-mmu)-based virtual memory, the IOMMU, and x86 — an EHAL program runs in a single physical address space, protected at most by an [MPU](#g-mpu). (A Linux-userspace L2 implementation remains *conceivable* — precedent: [linux_hal](https://alire.ada.dev/crates/linux_hal.html) — and would demonstrate that the contract abstracts behavior rather than silicon, but it is not designed for, tested, or maintained as a target.)
- Runtime-swappable / dynamically loaded drivers. If you need heterogeneous device lists behind one pointer, use the optional `ehal_classes` adapter (§8.4) and accept its costs.
- Runtime device discovery or a runtime devicetree: all configuration is resolved at compile time.
- Binary driver distribution ([CMSIS-Driver](https://arm-software.github.io/CMSIS_5/Driver/html/index.html) style). Out of scope for the core; the beginner layer may ship prebuilt board libraries as an optimization.
- A conformance test suite and a migration guide for existing crates — both valuable, both deliberately deferred to separate documents.

## 3. Lessons taken from prior art

| Source | Lesson adopted |
|---|---|
| [Rust embedded-hal 1.0](https://blog.rust-embedded.org/embedded-hal-v1/) | Separate the *contract* from implementations; keep it so small you can promise "no 2.0"; delete abstractions that don't work (their 1.0 removed ADC/timers) rather than freeze bad ones; split execution models into separate crates; standardize error *kinds*, not error types. |
| [Rust avr-hal](https://github.com/Rahix/avr-hal), [modm](https://modm.io), [TinyGo](https://tinygo.org/docs/reference/machine/) | Compile-time polymorphism is the only mechanism that scales down to 8-bit. Function-pointer designs ([Zephyr](https://docs.zephyrproject.org/latest/kernel/drivers/index.html), CMSIS-Driver) set a de-facto 32-bit floor. |
| [Zephyr device model](https://docs.zephyrproject.org/latest/kernel/drivers/index.html) | Even with runtime dispatch, configuration belongs at build time ([devicetree](#g-devicetree) → ROM structs). EHAL goes further: dispatch is build-time too, and the devicetree idea returns as a pure generator (§13). Also a warning: devicetree-scale machinery is why Zephyr can't go small. |
| [Arduino / ArduinoCore-API](https://github.com/arduino/ArduinoCore-API) | A tiny, stable, teachable API surface beats architectural sophistication for adoption — but `void` returns and integer pins are a floor for beginners, not a HAL. Hence layer 5, not layer 2. |
| [PlatformIO](https://pypi.org/project/platformio/) | One CLI, one registry, per-project reproducible environments — that developer experience won huge adoption and is what [Alire](#g-alire) must deliver for EHAL. But a meta-layer *wrapping* ecosystems it doesn't control [lags native toolchains and loses functionality in translation](https://peterbabic.com/blog/esp32-c6-platformio-fail/) — so EHAL owns its stack down to the register bindings instead of wrapping vendor frameworks. |
| [pioarduino](https://github.com/pioarduino) (PlatformIO's Espressif fork) | Governance is architecture: when a central gatekeeper's pace or licensing clashes with a vendor or its community, the community routes around it by forking. EHAL keeps every layer independently forkable — small decentralized crates, a spec crate with no owner-controlled services, no component whose maintainer can hold the ecosystem hostage. |
| [Mbed OS](https://os.mbed.com/blog/entry/Important-Update-on-Mbed/) (EOL July 2026) | A portable API, online IDE, registry and corporate backing are not survival traits if one owner's strategy change kills the platform ([Arm halted maintenance in 2024](https://blog.adafruit.com/2026/02/02/a-reminder-that-mbed-os-is-end-of-life-july-2026/), leaving the community to fork as [Mbed CE](https://github.com/mbed-ce/mbed-os)). Design for orphanability: no central mono-repo, no company-owned build service, a contract small enough for a community to maintain indefinitely. Its C++ virtuals-everywhere design also barred scaling down — the same lesson as [hal 1.x](#g-halcrate), at ecosystem scale. |
| [ADL `hal` 1.x](https://alire.ada.dev/crates/hal.html) | Interfaces + `'Class` access break SPARK ([ADL #401](https://github.com/AdaCore/Ada_Drivers_Library/issues/401)), cost vtables, and were never adopted by [AVRAda](https://github.com/RREE/AVRAda_Lib). Status-code error reporting (no exceptions) was right and is kept. Ambiguous I2C addressing (7 vs 8-bit) was a real interoperability bug and is fixed by construction (§7.4). |
| [Forum thread 4364](https://forum.ada-lang.io/t/towards-a-hal-for-multiple-runtimes/4364) | The four-layer model (registers / hw access / async buffered / sync tasking) is the backbone here, refined into §5. Grosser: low-level ops must be 4–8 inlinable instructions and never block; timer interrupts belong in the runtime; interrupt attachment is the application's decision, not the driver author's. damaki: distribute [PACs](#g-pac) Rust-style. godunko: one async core can serve both tasking and non-tasking runtimes via an await adapter ([A0B](#g-a0b)). SweetAda: don't force one universal generic signature onto genuinely weird hardware. |
| [Thread 4296](https://forum.ada-lang.io/t/an-embedded-ecosystem-for-beginners/4296) (Fabien Chouteau) | The beginner layer copies the [Arduino API](https://docs.arduino.cc/learn/programming/reference/), lives in a single package spec, supports exactly one runtime, and hides Alire/gpr complexity. It complements, never constrains, the HAL. |

## 4. Architecture overview

```
 L6  board description (opt.)       compile-time devicetree → generated Ada (§13)
 ─────────────────────────────────────────────────────────────────────────────
 L5  maker / maker_<board>          Arduino-like beginner framework (one pkg, pins are ints)
 ─────────────────────────────────────────────────────────────────────────────
 L4  device driver crates           Portable drivers: generic packages over L2/L3
     (bme280, st7789, neopixel …)   signatures. MCU-agnostic, SPARK-friendly.
 ─────────────────────────────────────────────────────────────────────────────
 L3  execution adapters             ehal_block (busy-wait) · ehal_async (IRQ/DMA,
                                    completion procedures) · ehal_task (Ravenscar/Jorvik)
 ─────────────────────────────────────────────────────────────────────────────
 L2  <mcu>_hal crates               THE CONTRACT: never-blocking package-spec
     e.g. rp2040_hal, avr_atmega328_hal   convention (MCU.GPIO, MCU.UART0 …)
     + native full-feature surface  (grows toward SPARK-proven vendor-lib replacement)
 ─────────────────────────────────────────────────────────────────────────────
 L1  <mcu>_pac crates               Register bindings: svd2ada-generated, curated
 ─────────────────────────────────────────────────────────────────────────────
 L0  runtime crates                 light / light_tasking / embedded_<soc>
     (damaki-style, avrada_rts,     owns: startup, traps, timekeeping interrupt,
      bare_runtime)                 tasking. NOT peripherals.
 ─────────────────────────────────────────────────────────────────────────────
     ehal (spec crate)              types, error kinds, signature packages —
                                    depended on by L2, L3, L4, L5. Pure/Preelaborate.
```

Dependency rules (enforced by crate manifests):

- `ehal` depends on nothing. All specs `Pure` or `Preelaborate`.
- L2 depends on `ehal` + its own L1 [PAC](#g-pac). It must build against the **[light](#g-light)** runtime — that is the floor.
- L3 adapters depend on `ehal` only (they are generic over L2 [signatures](#g-signature)). `ehal_task` additionally requires a tasking runtime; this is expressed in its manifest so Alire resolution fails early on a light-runtime project.
- L4 drivers depend on `ehal` **only**. Never on a PAC, an MCU HAL, or an adapter. That is the whole point.
- L5 depends on one board's L2 + `ehal_block`.
- L6 is a *tool*, not a library: its output depends on L2–L4; nothing depends on it.
- Nothing depends downward on L0 except through `Ada.*`/`System.*` semantics; L0 never depends on L1–L6 *as crates* — the timer/IRQ registers a runtime needs are duplicated-by-generation from the same source of truth as the PAC (see §10.1).

## 5. The layer model, refined from thread 4364

| # | Name | Blocking? | Interrupts? | Mechanism | Ships as |
|---|------|-----------|-------------|-----------|----------|
| L0 | Runtime | n/a | owns timekeeping + tasking traps | GNAT runtime crate | `light_*`, `embedded_*`, [`avrada_rts`](https://github.com/RREE/AVRAda_RTS) |
| L1 | Registers | never | none | records/arrays at addresses | `<mcu>_pac` |
| L2 | HW access | **never** | none installed; IRQ-status readable | package convention | `<mcu>_hal` |
| L3a | Blocking | busy-wait/[WFI](#g-wfi) | optional | generic adapter over L2 | `ehal_block` |
| L3b | Async buffered | never | yes (user-attached) | generic adapter + completion procs | `ehal_async` |
| L3c | Tasking | suspends task | yes | protected objects, [Ravenscar](#g-ravenscar) | `ehal_task` |
| L4 | Device drivers | inherits from formals | never directly | generics over signatures | one crate per device |
| L5 | Beginner | blocking only | hidden | plain package | `maker_<board>` |
| L6 | Board description | n/a (generator) | n/a | build-time codegen | `boardgen` tool |

Two refinements relative to the original four-layer proposal in [thread 4364](https://forum.ada-lang.io/t/towards-a-hal-for-multiple-runtimes/4364):

1. **L2 is strictly non-blocking.** The original layer 2 ("HW access") already gestured at this (`Is_Transmit_Ready`/`Transmit_Frame`); EHAL makes it a hard rule: every L2 subprogram completes in statically bounded time with no waiting loops. This is what makes one L2 serve *all three* execution models above it, and what keeps it callable from interrupt handlers.
2. **Layers 3 and 4 of the original proposal are execution *adapters*, not separate HAL levels.** They contain no hardware knowledge; they are generic units instantiated with L2 subprograms. Whether they compile is determined by the runtime profile, answering the original question "how to ensure higher layers compile only if the runtime supports them": `ehal_task` references `Ada.Synchronous_Task_Control` and protected types — on a [light](#g-light) runtime the dependency is simply not resolvable/compilable, and the Alire manifest states it up front.

## 6. The contract: package-spec convention (L2)

### 6.1 Convention rules

Every conforming `<mcu>_hal` crate provides a root package named after the crate (e.g. `RP2040`, `ATmega328P`) containing child packages with **standardized names, standardized subprogram profiles, and MCU-specific types**:

- `<Root>.GPIO` — pin configuration and digital I/O
- `<Root>.UART0`, `.UART1`, … — one package per on-chip instance
- `<Root>.SPI0`, `.I2C0`, `.ADC`, `.PWM0`, … — likewise
- `<Root>.Clock` — monotonic time
- `<Root>.HAL_Info` — static constants describing what is implemented

Fixed *names and profiles*, MCU-specific *types*: `Pin_Id` is `range 0 .. 29` on RP2040 and `range 0 .. 5` per port on ATmega — portable code never assumes a width, it instantiates generics with what the MCU offers. Instance packages (`UART0`, `UART1`) rather than objects sidestep the "which abstraction for multiplicity" problem entirely: multiplicity is naming, dispatch is `with`-ing.

Beyond the convention packages, `<mcu>_hal` exposes its **native surface**: everything the silicon can do (DMA channels, PIO, timers, clock trees), written to the same [SPARK](#g-spark) policy. This native surface is where the "replace the vendor library" goal (§2) lives; the convention packages are its portable subset.

Conformance is checked two ways:

- **At the use site** — a driver instantiation simply fails to compile against a non-conforming HAL. This is the everyday check and it is sufficient (a compile error naming the missing subprogram is a *good* error message).
- **Mechanically, in CI of the HAL crate** — each `<mcu>_hal` includes a non-shipped `conformance.ads` that instantiates every [signature package](#g-signature) from `ehal` (§6.3) against its own packages. If it compiles, the crate conforms. This answers the "nothing machine-checks convention D" objection at zero cost to users.

### 6.2 Example L2 spec (UART, shown for RP2040)

```ada
--  rp2040_hal:  rp2040-uart0.ads
package RP2040.UART0
  with Preelaborate, SPARK_Mode
is
   type Frame is mod 2**8;                     --  9-bit MCUs use mod 2**9

   --  Configuration: deliberately MCU-specific, NOT part of the
   --  portable contract beyond the required Enable with defaults.
   type Config is record
      Baud    : Natural  := 115_200;
      Bits    : Positive range 5 .. 8 := 8;
      Parity  : Parity_Kind := None;
      --  … RP2040-specific fields (FIFO thresholds, pins via GPIO)
   end record;
   procedure Enable  (Cfg : Config := (others => <>));
   procedure Disable;

   --  Portable data phase: never blocks, bounded time, IRQ-safe.
   function  Is_Tx_Ready return Boolean with Inline_Always;
   procedure Put_Frame (Data : Frame)
     with Inline_Always, Pre => Is_Tx_Ready;   --  proof obligation, no check
   function  Is_Rx_Ready return Boolean with Inline_Always;
   procedure Get_Frame (Data : out Frame; Status : in out Ehal.UART_Status)
     with Inline_Always;   --  chained (§7.1): no-op if Status /= Ok on entry
                           --  Status: Ok | Framing | Parity | Overrun

   --  Event plumbing for L3b — reads/clears flags, installs nothing:
   procedure Enable_Event  (E : Ehal.UART_Event);    --  Tx_Ready | Rx_Ready | Error
   procedure Disable_Event (E : Ehal.UART_Event);
   function  Pending_Event return Ehal.UART_Event_Set with Inline_Always;
   procedure Clear_Event   (E : Ehal.UART_Event);
end RP2040.UART0;
```

The preconditions are [SPARK](#g-spark)/proof artifacts and documentation; with checks suppressed (the norm on light runtimes with [`No_Exception_Propagation`](#g-nep)) they cost nothing. Misuse without proof is a hardware-defined no-op or overwrite — exactly the semantics the register itself has.

### 6.3 Signature packages (the machine-checkable contract)

The `ehal` spec crate defines, per peripheral class, a generic *[signature package](#g-signature)* — the Ada equivalent of a Rust [trait declaration](#g-eh):

```ada
--  ehal:  ehal-uart_signature.ads
generic
   type Frame is mod <>;
   with function  Is_Tx_Ready return Boolean;
   with procedure Put_Frame (Data : Frame);
   with function  Is_Rx_Ready return Boolean;
   with procedure Get_Frame (Data : out Frame; Status : in out UART_Status);
package Ehal.UART_Signature is end;
```

```ada
--  ehal:  ehal-digital_out_signature.ads
generic
   with procedure Set (High : Boolean);
package Ehal.Digital_Out_Signature is end;
```

Portable code (L3 adapters, L4 drivers) is generic over these:

```ada
--  a portable driver crate
generic
   with package UART is new Ehal.UART_Signature (<>);
   with package Time is new Ehal.Clock_Signature (<>);
package Modbus_RTU is …
```

Wiring on any target is mechanical and reads like a board schematic:

```ada
package My_UART is new Ehal.UART_Signature
  (Frame => RP2040.UART0.Frame,
   Is_Tx_Ready => RP2040.UART0.Is_Tx_Ready,
   Put_Frame   => RP2040.UART0.Put_Frame, …);
package Bus is new Modbus_RTU (UART => My_UART, Time => My_Clock);
```

Design rules for signatures, learned from [embedded-hal 1.0](#g-eh) and SweetAda's objection in [thread 4364](https://forum.ada-lang.io/t/towards-a-hal-for-multiple-runtimes/4364):

- **Narrow formals.** A signature captures the *data phase* only. Configuration, clocks, pin muxing stay out — they are done natively via L2 before instantiation. This is what defuses the Z8530 argument: weird devices get weird L2 packages; the signature only ever demands what a portable driver can genuinely use.
- **Standardize proven classes only.** v1 signatures: `Digital_Out`, `Digital_In`, `UART`, `SPI_Master`, `I2C_Master`, `Clock`, `Delays`. Explicitly *deferred*: ADC, PWM, timers-as-counters, watchdog, DAC — L2 convention names exist for them (portable *applications* can use `MCU.ADC`), but no signature/driver contract until designs are proven. [embedded-hal shipped 1.0 by deleting exactly these](https://blog.rust-embedded.org/embedded-hal-v1/).
- **Code-bloat discipline** (jere's pattern, [thread 4364](https://forum.ada-lang.io/t/towards-a-hal-for-multiple-runtimes/4364)): driver crates put shared logic in a non-generic backend package (byte-level protocol state machines, buffers) and keep the [generic](#g-generic) layer thin. The style guide in the `ehal` docs makes this normative for drivers expecting multiple instantiations per program.

### 6.4 GPIO

Two levels, both in L2:

```ada
package RP2040.GPIO with Preelaborate, SPARK_Mode is
   type Pin_Id is range 0 .. 29;
   type Direction is (Input, Output);
   type Pull is (Floating, Pull_Up, Pull_Down);
   procedure Configure (Pin : Pin_Id; Dir : Direction; P : Pull := Floating);
   procedure Set_High (Pin : Pin_Id) with Inline_Always;
   procedure Set_Low  (Pin : Pin_Id) with Inline_Always;
   procedure Toggle   (Pin : Pin_Id) with Inline_Always;
   function  Is_High  (Pin : Pin_Id) return Boolean with Inline_Always;
end RP2040.GPIO;
```

For drivers, a pin is delivered as one or two formal procedures (`Set`, or `Set`+`Get`), typically instantiation-wrapped:

```ada
procedure CS_Set (High : Boolean) is
begin
   if High then RP2040.GPIO.Set_High (5); else RP2040.GPIO.Set_Low (5); end if;
end CS_Set;
```

With `Inline_Always` this folds to a single store. No `GPIO_Point` objects, no port-vs-point mutation puzzle ([ADL issue #25](https://github.com/AdaCore/Ada_Drivers_Library/issues/25)) — the pin identity is bound at instantiation.

### 6.5 Time

The runtime owns the timekeeping interrupt (Grosser: ["just put it in the runtime"](https://forum.ada-lang.io/t/towards-a-hal-for-multiple-runtimes/4364) — delay statements and scheduling break otherwise). L2 exposes reading time, never owning it:

```ada
package RP2040.Clock with Preelaborate, SPARK_Mode is
   type Ticks is mod 2**64;                    --  ≥ 2**32 required; AVR uses 2**32
   Ticks_Per_Second : constant := 1_000_000;
   function Now return Ticks with Inline_Always;
end RP2040.Clock;
```

On tasking runtimes the body reads the same hardware as `Ada.Real_Time.Clock` (or delegates to it). `Ehal.Delays_Signature` (`Delay_Us`, `Delay_Ms`) is implemented by `ehal_block` (busy-wait over `Clock`) or `ehal_task` (`delay until`), so a driver needing pauses works identically on ATtiny and PolarFire.

### 6.6 SPARK policy (mandatory)

[SPARK](#g-spark) compatibility is a conformance requirement, not a bonus:

- **`ehal` (spec crate):** 100 % SPARK. Signature packages, error kinds and types contain nothing [GNATprove](#g-gnatprove) rejects — no access types at all.
- **`<mcu>_pac`:** specs `SPARK_Mode On`, registers annotated with precise volatility aspects (`Async_Readers`/`Async_Writers`/`Effective_Reads`/`Effective_Writes`) so user code over them is provable; blanket `Volatile` is a conformance defect.
- **`<mcu>_hal` (L2):** specs `SPARK_Mode On` always; bodies SPARK wherever feasible (register access is exactly what SPARK handles well). Non-SPARK bodies are allowed but must not leak into the spec. This applies to the native full-feature surface too — it is the substance of the "SPARK-proven vendor-lib replacement" goal (§2).
- **`ehal_block`, `ehal_async`:** SPARK specs; completion plumbing in `ehal_async` uses statically allocated, access-free mechanisms (generic formal completion procedures rather than access-to-subprogram) precisely so client code stays in SPARK.
- **`ehal_task`:** SPARK specs targeting the [Ravenscar](#g-ravenscar)/[Jorvik](#g-jorvik) SPARK subset (protected objects and suspension objects are SPARK-supported).
- **L4 drivers:** must have SPARK specs to carry the `ehal-` tag; full proof of bodies is encouraged and advertised in the crate description (a provable BME280 driver is an ecosystem selling point).
- **`ehal_classes`** is the single designated non-SPARK crate (`SPARK_Mode Off`), and the only place `'Class` and access types may appear. Depending on it moves that unit — and only that unit — outside the proof boundary.
- **CI:** conformance units (§6.1) run `gnatprove --mode=flow` in addition to compilation; proof-level checks are per-crate policy.

This is the direct answer to [ADL #401](https://github.com/AdaCore/Ada_Drivers_Library/issues/401): the reason the current [`hal` crate](#g-halcrate) cannot be proved (`access all …'Class`) is structurally impossible here, because the contract layer has no access types by construction.

## 7. Error model

Adopted from [embedded-hal 1.0's `ErrorKind`](https://blog.rust-embedded.org/embedded-hal-v1/), adapted to Ada:

1. **No exceptions in L1–L4.** The floor runtime is [`No_Exception_Propagation`](#g-nep). All fallible operations report via [*chained*](#g-chained) `in out Status` parameters (§7.1).
2. **Per-class error enumerations in `ehal`**, closed but with an `Other` value:
   `type I2C_Status is (Ok, Nack_Address, Nack_Data, Arbitration_Lost, Bus_Error, Other_Error);`
   `type UART_Status is (Ok, Framing_Error, Parity_Error, Overrun, Other_Error);`
   Implementations may expose richer native diagnostics in L2 (extra functions), but the signature carries the portable kind — HALs stay precise, drivers stay portable.
3. **No `Timeout` status in L2** — L2 never waits, so it cannot time out. Timeouts are a property of adapters: `ehal_block` operations take a `Deadline`/`Timeout_Ms` and add `Timed_Out` to their status type. (This fixes a muddle in [hal 1.x](#g-halcrate), where `Err_Timeout` sat in the port interface.)
4. **Infallible operations are procedures without status** (GPIO set, clock read). Arduino's lesson inverted: where failure is real (buses), it is impossible to ignore accidentally — the chained convention forces every transaction to end at a `Status` value, and [SPARK](#g-spark) flow analysis enforces its initialization.

### 7.1 Chained status — fail all-or-nothing

Every fallible operation takes its status as the **last parameter, mode `in out`**, with sticky-error semantics: if `Status /= Ok` on entry, the operation returns immediately without touching hardware. A multi-step transfer then reads as straight-line code with a single handling point — no `if Status /= Ok then return; end if;` boilerplate between calls:

```ada
--  inside a BME280 driver (L4), over an I2C signature:
procedure Start_Conversion (Status : in out I2C_Status) is
begin
   Write_Reg (Ctrl_Hum,  Osrs_H_X1,  Status);
   Write_Reg (Ctrl_Meas, Osrs_X2 or Mode_Forced, Status);
   Read_Reg  (Status_Reg, S, Status);
end Start_Conversion;

--  application:
Status := Ok;                       --  explicit transaction start
Sensor.Start_Conversion (Status);
Delays.Delay_Ms (10);
Sensor.Read_Measurement (M, Status);
case Status is                      --  handled exactly once
   when Ok           => Report (M);
   when Nack_Address => …           --  device missing: first failing step is
   when others       => …           --  irrelevant, the transaction failed
end case;
```

This is the moral equivalent of Rust's `?` operator without needing syntax, and a proven pattern elsewhere: Go's `errWriter` ([Rob Pike, "Errors are values"](https://go.dev/blog/errors-are-values)) and C stdio's sticky `ferror` state. The convention applies **uniformly at L2, L3 and L4** — uniformity is worth more than the one compare-and-branch it costs per call (2 instructions on AVR, predictable, and proportionally irrelevant even in an ISR pump).

Rules:

1. **Skip semantics:** on entry with `Status /= Ok`, return immediately; hardware untouched; all `out` data parameters set to defined null values (zeros / `'First`) so [SPARK](#g-spark) initialization obligations hold and no garbage propagates.
2. **Fail clean:** on detecting an error, the implementation sets `Status` *and* terminates the hardware transaction in a defined state (e.g. generate I2C STOP after a NACK) before returning. Subsequent skipped calls therefore never see a half-open bus.
3. **Explicit reset:** only the *owner* of the transaction assigns `Ok` — that assignment is the acknowledgment point and marks the transaction's lexical start. Drivers never reset a caller's status.
4. **Cross-class boundaries don't chain implicitly:** `I2C_Status` and `UART_Status` are distinct types by design. An L4 driver exposes its *own* chained status enum and maps bus kinds into it at its boundary; the convention (last parameter, `in out`, skip-if-pending) is identical at every level.
5. **Async variant:** in `ehal_async`, initiation calls (`Start_Write`, `Start_Read`) chain the same way — a pending error skips starting the transfer — and the completion procedure receives the final merged status.
6. **SPARK synergy:** `in out` requires a defined value on entry — flow analysis rejects transactions that forget `Status := Ok`; a status whose final value is never read is flagged as an ineffective computation. The pattern that is ergonomic is also the pattern that is provable.

Known cost, accepted: during debugging, skipped calls can surprise ("why did `Read_Reg` not execute?"). Mitigations: the transaction has exactly one status object to watch, statuses are plain values (breakpoint/trace-friendly, unlike unwinding), and rule 3 keeps transaction extent lexically visible.

#### Alternative considered: discriminated result records (Rust-style `Result`)

The idiomatic Ada rendering of Rust's `Result<T, E>` is a function returning a variant record whose discriminant *is* the status, making the payload structurally inaccessible on error:

```ada
type Read_Result (Status : UART_Status := Ok) is record
   case Status is
      when Ok     => Data : Frame;
      when others => null;
   end case;
end record;

function Get_Frame return Read_Result;
--  caller:
R := Get_Frame;
case R.Status is
   when Ok     => Consume (R.Data);   --  R.Data when Status /= Ok:
   when others => Handle (R.Status);  --  discriminant check fails
end case;
```

**Pros of the variant-record style:**

- **Type-level safety instead of convention-level.** Touching `R.Data` on error is a discriminant violation the compiler inserts a check for — and [GNATprove](#g-gnatprove) can *prove* absent. Chaining's rule 1 ("defined null values") is weaker: a caller that forgets to check status computes with zeros, legally.
- **Per-call explicitness.** Each outcome is inspected where it arises — no sticky state, no skipped-call debugging surprise.
- **Self-describing specs.** The result type documents exactly which payload accompanies which status.

**Cons, and why they dominate here:**

- **Ada has no `?`.** Rust's `Result` is ergonomic *because of* the `?` operator; without it, every call site pays a `case`/`if` before the next step — precisely the inter-call boilerplate this chapter exists to eliminate. A three-step transaction becomes three nested inspections or three early returns.
- **SPARK's volatile-function rules.** A fallible hardware read is *effectful* (popping a FIFO clears flags): in SPARK a function may not read a volatile object with `Effective_Reads` — the operation must be a procedure, or a function marked `Side_Effects`, which may then only be called as a standalone assignment statement. Either way the functional composability that motivates result types is lost; one is left holding the record without the idiom that makes it pleasant.
- **The safety check needs the very machinery the floor excludes.** On the light runtime with [`No_Exception_Propagation`](#g-nep), a failed discriminant check is a trip to the Last_Chance_Handler (with checks suppressed: erroneous execution). The type-level guarantee is only real when the code is *proved* — and under proof, the chained style achieves the same guarantee via postconditions (`Post => (if Status /= Ok then Data = Null_Frame)`) at no structural cost.
- **Object size and return cost.** A mutable-discriminant record is allocated at maximum size, and returning composites by value is measurable on 8-bit targets. Worse, bulk transfers would want `Data` as an unconstrained array — and unconstrained function results ride GNAT's secondary stack, a scarce, configured resource on light runtimes (63 bytes default on [AVRAda](https://github.com/RREE/AVRAda_RTS)). In practice buffers are passed as `out` parameters anyway, at which point the "result" degenerates to status-plus-count and the record buys nothing.

| Criterion | Chained `in out` status | Variant-record result |
|---|---|---|
| Inter-call boilerplate | none | inspection at every call |
| Data-on-error protection | defined nulls + contract (proof-level) | discriminant check (type-level, but = LCH trap on floor runtime unless proved) |
| SPARK volatile/effectful rules | procedures: no friction | functions restricted (`Side_Effects` ⇒ statement-only) |
| 8-bit cost | 1 compare/branch per call | max-size record, by-value return, secondary stack for unconstrained payloads |
| Bulk transfers | natural (`out` buffer + status) | degenerates to status + count |
| Debugging | skipped-call surprise | explicit per call |
| Precedent | [Go errWriter](https://go.dev/blog/errors-are-values), C `ferror` | Rust `Result` — viable *because of* `?` and move semantics |

**Verdict:** chained status remains the convention for *operations*. Discriminated records are welcome as *data carriers* where they travel in `in` mode and no effectful function is involved — e.g. the completion payload handed to an `ehal_async` completion procedure (final count + status arriving together) or small driver-level query results. The rule of thumb: variant records to *transport* an outcome, chained status to *sequence* outcomes.

### 7.2 I2C addressing, fixed by construction

```ada
type I2C_7_Bit_Address  is range 0 .. 16#7F#;   --  unshifted, as in datasheets
type I2C_10_Bit_Address is range 0 .. 16#3FF#;
```

Distinct types, explicitly documented as unshifted; conversion to wire format is the implementation's job. The 7-vs-8-bit ambiguity that bit rp2040_hal vs other implementations ([ADL #401](https://github.com/AdaCore/Ada_Drivers_Library/issues/401)) cannot recur.

## 8. Execution adapters (L3)

### 8.1 `ehal_block` — blocking over polling

```ada
generic
   with package UART is new Ehal.UART_Signature (<>);
   with package Time is new Ehal.Clock_Signature (<>);
package Ehal_Block.UART is
   procedure Put (Data    : Frame_Array;
                  Timeout : Milliseconds := 1000;
                  Status  : in out Block_Status);  --  chained (§7.1);
end Ehal_Block.UART;                               --  Ok | Timed_Out | UART kinds
```

Busy-waits (optionally [WFI](#g-wfi)-sleeps where the MCU HAL provides a `Sleep_Hint` hook). Works on every runtime including AVR [ZFP](#g-zfp). This is what L5 and most simple applications use.

### 8.2 `ehal_async` — interrupt/DMA-driven, completion-signaled

The [A0B](#g-a0b) insight, ported: operations *start* a transfer and signal completion; the same async core serves non-tasking targets (main loop polls or sleeps via `Await`, which does [WFI](#g-wfi) without tasking) and tasking targets (`Await` uses a suspension object). Unlike A0B, completion is delivered through a **generic formal procedure** (bound at instantiation), not an access-to-subprogram callback record — keeping the adapter access-free and [SPARK](#g-spark)-compatible (§6.6). Rules:

- All state is caller-provided and static — no heap, `No_Implicit_Heap_Allocations` holds; no access types.
- **The adapter never installs interrupt handlers.** It exports `procedure On_Interrupt` (data-phase pump over L2's `Pending_Event`/`Clear_Event`); *the application* attaches it — via `Attach_Handler`, a vector-table symbol, or an RTOS ISR shim. Both attachment styles have valid uses, "so this is not something a driver author should decide" ([Grosser](https://forum.ada-lang.io/t/towards-a-hal-for-multiple-runtimes/4364)). [BSPs](#g-bsp) or the board description (§13) may pre-wire it for convenience.
- [DMA](#g-dma) use is an implementation detail inside `<mcu>_hal`-provided async extensions; the portable async signature stays transfer-oriented (`Start_Write`, `Start_Read`, completion with count + status).
- On AVR, `ehal_async` is available but expected to be used sparingly (completion state costs RAM); nothing forbids it.

### 8.3 `ehal_task` — Ravenscar/Jorvik integration

Protected objects wrapping the event plumbing: interrupt handlers as protected procedures, entries for completion, `delay until` for timeouts. Requires light-tasking or embedded runtime; the manifest says so. Deliberately thin — applications with tasking may equally use `ehal_async` + suspension objects.

### 8.4 Optional: `ehal_classes` — tagged adapter for runtime polymorphism

For the cases where [dynamic dispatch](#g-tagged) is genuinely wanted (device menus, test harnesses), `ehal_classes` provides tagged wrappers *generated from the same signatures*:

```ada
type UART_Port is limited interface;
procedure Put_Frame (This : in out UART_Port; Data : UInt8) is abstract;
generic
   with package S is new Ehal.UART_Signature (<>);
package Ehal_Classes.UART_Impl is
   type Port is new UART_Port with null record;  --  calls S.Put_Frame
end Ehal_Classes.UART_Impl;
```

This inverts [hal 1.x](#g-halcrate)'s layering: interfaces become a convenience *on top of* the zero-cost contract instead of the foundation everyone pays for. It is explicitly non-SPARK and non-AVR, and that is fine — it's optional.

## 9. PAC crates (L1)

One `<mcu>_pac` crate per family (`rp2040_pac`, `atmega328p_pac`, `mpfs_pac` for PolarFire SoC), following damaki's Rust-[PAC](#g-pac) proposal with Grosser's curation rules (both from [thread 4364](https://forum.ada-lang.io/t/towards-a-hal-for-multiple-runtimes/4364)):

1. **Generated, then owned.** [svd2ada](#g-svd2ada) output is a starting point, committed and hand-edited; regeneration is a diff-reviewed maintenance event, not a build step. Vendor [SVDs](#g-svd) are too wrong (missing dimensioned groups, interleaved registers) for blind trust.
2. **Curation rules:** repetitive per-pin registers become arrays, not 32-field records (case-statement codegen is poor); registers on buses requiring full-width access get [`Volatile_Full_Access`](#g-vfa) + explicit `Object_Size`; packed sub-word arrays are restructured to respect 32-bit write granularity; [SPARK](#g-spark) volatility aspects (`Async_Readers`, `Async_Writers`, `Effective_Reads`, `Effective_Writes`) are added per register semantics instead of blanket `Volatile`. Where a plain `Unsigned_32` at an address generates better code than a record, use it.
3. **Runtimes keep only their own registers** (damaki's actual practice): the SysTick/timer/interrupt-controller definitions a runtime needs internally stay internal to it. No crate dependency between L0 and L1 — rationale and the resulting duplication management in §10.1.
4. PACs are `Preelaborate`, no subprograms beyond trivial accessors, no elaboration code.

AVR note: AVR has no SVD culture; `atmega*_pac` crates are hand-written (or adapted from [AVRAda](https://github.com/RREE/AVRAda_Lib)'s `avrada_mcu`), same conventions.

## 10. Runtime compatibility (L0)

| Runtime profile | Example crates | L2 | ehal_block | ehal_async | ehal_task | ehal_classes |
|---|---|---|---|---|---|---|
| AVR [ZFP](#g-zfp) ([`avrada_rts`](https://github.com/RREE/AVRAda_RTS)) | ATtiny, ATmega | ✔ | ✔ | ✔ (RAM-aware) | ✗ | ✗ |
| [light](#g-light) ([`light_rp2040`](https://alire.ada.dev/crates/light_rp2040.html), [`bare_runtime`](https://alire.ada.dev/crates/bare_runtime.html)) | RP2040, STM32 | ✔ | ✔ | ✔ | ✗ | ✗ (no proof/need) |
| light-tasking (`light_tasking_rp2040`) | RP2040, nRF52 | ✔ | ✔ | ✔ | ✔ | (✔) |
| embedded (`embedded_rp2350`) | RP2350, STM32G4 | ✔ | ✔ | ✔ | ✔ | ✔ |

The floor for the *contract* is the [light](#g-light) profile with [`No_Exception_Propagation`](#g-nep), `No_Implicit_Heap_Allocations`, `No_Finalization`. Everything in L1/L2/L4 must compile and run there.

**PolarFire SoC** (the top of the range) is served bare-metal: [bb-runtimes](https://github.com/AdaCore/bb-runtimes) carries `polarfiresoc` and `polarfiresoc-smp` targets, so light/light-tasking/embedded profiles are available; `mpfs_pac` + `mpfs_hal` follow the same rules as any MCU. The scope features above the single-core baseline are allocated as follows, none of them touching the HAL contract:

- **[SMP](#g-smp)** is a runtime concern (Ravenscar task dispatching domains; `polarfiresoc-smp`). L2 stays per-peripheral; concurrent access control is the application's protected objects, as on one core.
- **[AMP](#g-amp)** is a *system composition* concern: each partition (e.g. the E51 monitor core vs. the U54 application cores, or RP2040's core1) is its own EHAL program with its own runtime, sharing the SoC's PACs. Inter-core channels reuse the §10.3 pattern — SPSC RAM FIFOs are core-to-core links when the consumer is another core rather than a probe. Peripheral ownership across partitions is declared in the board description (§13), making cross-core double-assignment a build-time error like any other.
- **[MPU](#g-mpu)/PMP and privilege levels** are runtime/board-layer concerns (stack guards, U-Mode task partitions): the runtime configures regions; the board description declares which peripheral regions a U-Mode partition may touch, so L2 code — being plain statically-bound register access — runs unprivileged wherever its MPU window allows. Nothing in the contract assumes M-Mode.

### 10.1 The L0/L1 seam: why the runtime must not depend on the PAC

There is an apparent contradiction in the layer rules: L0 owns the timekeeping interrupt, tasking traps and interrupt masking — all register-level work — yet it may not depend on the [PAC](#g-pac) crates whose whole purpose is register access. The contradiction is resolved by distinguishing *crate dependency* from *source of truth*.

**What a runtime actually touches.** Take inventory before designing the seam:

| Profile | Hardware surface of the runtime |
|---|---|
| [light](#g-light) | Startup code, vector/trap table, memory init — **zero peripheral registers** ([`bare_runtime`](https://alire.ada.dev/crates/bare_runtime.html) + [startup_gen](https://github.com/AdaCore/startup-gen) prove this is fully target-independent already) |
| light-tasking / embedded | + alarm timer (source of `Ada.Real_Time.Clock` and `delay until`), interrupt controller (enable/priority/masking for ceiling locking), context-switch trap (PendSV on Cortex-M, software trap on RISC-V), [WFI](#g-wfi) idle |
| AVR [ZFP](#g-zfp) | Startup only. No tick: a tick would confiscate one of the application's few timers, so timing stays in L2/L3 (busy-wait on a calibrated clock) — [AVRAda](https://github.com/RREE/AVRAda_RTS)'s actual practice |

So the disputed surface is a handful of words: on Cortex-M, SysTick + NVIC + SCB — which are **architectural**, defined by ARM identically across all vendors; on RISC-V, CLINT (`mtime`/`mtimecmp`) + PLIC at vendor-chosen addresses; plus, occasionally, a vendor timer chosen over SysTick (e.g. a 64-bit vendor timer where SysTick's 24 bits are inconvenient).

**Why a crate dependency is still wrong**, even for those few registers:

1. **Build bootstrapping.** Every Alire crate — including a PAC — is compiled *against* a runtime. A runtime crate depending on the PAC crate creates a cycle (`runtime → pac → runtime`) that GPRbuild/Alire do not model; `Pure`/`No_Elaboration_Code` PACs would make it work only by accident of build ordering.
2. **Trusted computing base.** The runtime is the unit a safety auditor reads. Importing a 50 000-line generated PAC to reach five registers explodes the audit surface and couples certification evidence to PAC churn.
3. **Stability inversion.** PACs are *curated* — they get restructured for better codegen (§9). The runtime must be the most stable artifact in the system; a PAC record-layout improvement must be structurally unable to alter runtime behavior.
4. **Representation freedom.** A context-switch path wants raw word access with explicit barriers, not the user-friendly record views a PAC optimizes for. One shared representation would compromise both sides.
5. **Criticality of context.** Interrupt masking inside ceiling-locking critical sections must be inlined, elaboration-free code *within* the runtime; calling across a crate boundary there invites inlining and elaboration-order surprises.

**Resolution: duplicate by generation, not by hand.** The runtime keeps private, frozen copies of exactly the registers it needs (`System.BB.*`-style units, invisible to users) — but those copies are *generated from the same curated register description that produces the PAC*. One source of truth, zero build coupling, and the duplication is bounded (a handful of architecturally frozen registers) and auditable (regeneration is a diff-reviewed event, same as §9 rule 1). Divergence between what the runtime believes and what the PAC publishes becomes a CI check on the generator's data, not a linker surprise.

### 10.2 Consequence: generic runtimes with a thin board layer — yes, deliberately

Does this architecture encourage generic runtimes that delegate the per-MCU residue, instead of one runtime per MCU variant? **Yes — and EHAL should state it as a goal**, because two of its rules shrink the runtime's per-MCU surface to almost nothing:

- D6 gives the runtime *only* timekeeping — it owns no general peripherals, so it has no reason to track vendor peripheral diversity.
- §10.1 reduces its register knowledge to the architectural core (Cortex-M) or a small vendor block (RISC-V CLINT/PLIC).

What remains per MCU *variant* is: the linker script/memory map (already delegated to [startup_gen](https://github.com/AdaCore/startup-gen)-style generation), the clock frequency and IRQ-line count (plain Alire configuration variables), and on RISC-V the CLINT/PLIC addresses. That residue does not justify forked runtime code bases per chip.

The proposed structure makes the seam that [bb-runtimes](https://github.com/AdaCore/bb-runtimes) already has *internally* (`System.BB.Board_Support`) an explicit convention:

- **One generic runtime core per architecture profile** (e.g. `rt_core_armv6m`, `rt_core_armv7m`, `rt_core_riscv`): scheduler, protected-object semantics, exception handling — hardware-free except through the board-layer spec.
- **A per-MCU board layer** implementing a small fixed spec (`Alarm_Timer`, `Interrupt_Ops`, `Startup`): generated from the same register data as the PAC (§10.1), a few hundred lines, mostly mechanical. On Cortex-M, one board layer serves an entire architecture generation; a per-SoC layer exists only where a vendor timer replaces SysTick or (RISC-V) addresses differ.
- **Per-target runtime crates remain the packaging unit** — GNAT's `Runtime ("Ada")` attribute resolves to one concrete runtime directory, so Alire still ships `light_tasking_<soc>` crates — but their *content* becomes ~95 % shared core + generated board layer. damaki's runtime family already demonstrates the maintenance economics: per-SoC deltas over a shared bb-runtimes-derived core are small; EHAL's contribution is making the seam and the generation source-of-truth explicit rather than copy-paste.

Two delegation styles are explicitly **rejected**:

- *Delegating to L1 as a crate dependency* — for the five reasons in §10.1.
- *Delegating upward to application-provided hooks at link time* (weak symbols the app must fill in, FreeRTOS-port style): tasking primitives must work during elaboration, before any application code has a say, and link-seam contracts are invisible to both GNATprove and the reader. The one place link-level cooperation already exists — vector-table population — stays tightly specified (runtime owns the table; applications attach through `Attach_Handler` or documented symbol names, §8.2).

The limit cases confirm the direction: the light profile is *already* a fully generic runtime today (`bare_runtime` — zero peripheral registers, everything per-MCU delegated to generated startup/linker files), and AVR needs no seam at all because its floor excludes tasking. The generic-core + generated-board-layer model is the tasking-profile generalization of what the ecosystem's best current practice already does.

### 10.3 `Ada.Text_IO` and the console channel: a runtime FIFO, application-wired transport

`Ada.Text_IO` is the awkward exception to everything above: it lives in the runtime by language definition, yet its body ultimately needs a byte sink — and the traditional choices of sink all drag something unwelcome into L0. This is the one place embedded runtimes have historically smuggled a *peripheral driver* past the L0/L1 boundary: [bb-runtimes](https://github.com/AdaCore/bb-runtimes) routes a reduced `Ada.Text_IO` through a per-board `System.Text_IO` whose body is, on most targets, a polled UART driver with a hard-coded baud rate, clock assumption and pin choice. That violates §10.1 hygiene twice over: the runtime contains vendor peripheral knowledge, and it silently *owns* a UART instance the application might also claim through L2 — double initialization and interleaved output as a debugging bonus.

The available sinks, honestly compared:

| Backend | Registers needed | Works without debugger | Speed | Notes |
|---|---|---|---|---|
| [Semihosting](#g-semihosting) (ARM) | none | **no** — traps halt/fault | very slow | fine for CI under QEMU or probe-attached bring-up |
| [HTIF](#g-htif) (RISC-V) | none (magic RAM words) | simulator only | fast | Spike/QEMU; does not exist on real PolarFire silicon |
| [RTT](#g-rtt)-style RAM ring buffer | none — pure memory | yes (buffer wraps unread) | fast, non-blocking | pure Ada over `Volatile` RAM, zero peripheral knowledge; read by probe **or** drained by the application |
| Polled UART in the runtime | UART block + clocks | yes | wire speed | the historical default — and the only option that pulls peripheral + clock config into L0. **Excluded**; realized instead as a FIFO drain (below) |
| none (`No_IO`) | — | — | — | the AVR floor and the smallest-footprint option everywhere |

The comparison decides the design: only the RAM ring buffer works on real silicon, at speed, without a debugger halting the core *and* without any peripheral registers. EHAL therefore makes it load-bearing:

**The runtime's sink is a non-blocking RAM FIFO — who drains it is not the runtime's business.** The runtime produces bytes into a ring buffer; the consumer is either an attached debug probe reading memory directly, or *any application code* forwarding the bytes to whatever transport the product actually has — an L2 UART, USB CDC, a radio, a flash journal. A UART console still exists, but as an ordinary application loop over ordinary L2/L3 code; the console question turns from "which peripheral does the runtime own?" into "which RAM address does the consumer read?" — exactly the kind of dependency a runtime is allowed to have.

```ada
--  shipped by the runtime crate (ordinary user-visible package,
--  not under Ada.* / System.*):
package Console_FIFO
  with Preelaborate, SPARK_Mode
is
   --  Producer side is internal (Ada.Text_IO, Last_Chance_Handler, §14.2 logs).
   --  Consumer side, non-blocking, L2-rule-conformant:
   function  Available return Natural with Inline_Always;
   procedure Read (Into : out Byte_Array; Last : out Natural)
     with Inline_Always;                    --  never blocks, reads what's there
   function  Dropped return Natural;        --  bytes lost to overflow so far
end Console_FIFO;
```

**FIFO design rules:**

- **SPSC, lock-free, non-blocking on both sides.** Single producer (the runtime), single consumer; head/tail indices are atomic/`Volatile`, buffer size a power-of-two Alire configuration variable. The producer never waits: on overflow it drops and counts (`Dropped`) — a runtime must not stall the application because nobody is listening. No access types; [SPARK](#g-spark) throughout.
- **Probe compatibility for free.** The control block is laid out in SEGGER [RTT](#g-rtt) format (magic string, buffer descriptors, dedicated linker section), so J-Link/OpenOCD/probe-rs tooling reads it with no target cooperation. One binary serves both workflows — probe attached during bring-up, application drain in the field.
- **Exactly one consumer at a time.** A probe and an application drain would race on the read index; the drain mode is declared (config variable / `HAL_Info`) rather than discovered.
- **Consumer API obeys L2 rules** (bounded time, never blocks), so it composes with every execution adapter: poll it from the main loop on a [light](#g-light) runtime, drain on TX-ready events with `ehal_async`, or dedicate a low-priority task under `ehal_task`. `boardgen` (§13) can generate the drain wiring.
- **Crash semantics are honest.** `Last_Chance_Handler` writes are non-blocking like all others; if the drain died with the application, the message still sits in RAM for a post-mortem probe read — strictly better than a hung polled-UART loop in a crashed system. Products that need guaranteed crash delivery add it at application level (e.g. LCH-triggered flush to flash), where such policy belongs.
- **Input direction is symmetric and optional:** an RTT-style down-buffer gives `Get`-side data (host→target or application-fed), enabling interactive diagnostics without any runtime changes.

**Console policy:**

1. **The runtime console is a *diagnostic* channel, not the application console.** Application text output goes through L2/L3 like any other UART traffic — `maker`'s `Print` is implemented over the board's L2 UART, never over `Ada.Text_IO`, so beginner code neither depends on runtime IO presence nor fights the runtime over a peripheral. Portable L4/application code that wants logging takes a byte-sink [signature](#g-signature) (§14.2), not `Ada.Text_IO`.
2. **The sink is board-layer content (§10.2), selected at crate level:** `console := fifo | semihosting | htif | none`, resolved at build time into the `System.Text_IO`-equivalent body. Defaults: `fifo` on 32-bit targets, `htif` for simulator targets, `none` on AVR and for production builds that want silence.
3. **No UART driver in the runtime — ever.** The runtime's I/O register footprint is zero on every path, completing the §10.1 argument: the only hardware the runtime touches is the clock and the interrupt plumbing.
4. **Ownership is declared, not discovered.** The chosen drain (probe vs. application, and which peripheral it uses) is stated in the board description/`HAL_Info`; `boardgen` rejects descriptions that double-assign the drain peripheral. The interleaving/double-init failure mode becomes a build-time error.
5. **The `Last_Chance_Handler` uses the same sink** — a crash message that needs a *differently configured* channel than ordinary output is a classic bring-up trap.

## 11. Device driver crates (L4)

- One crate per device or close family (`ehal_bme280`, `ehal_ssd1306`), depending on `ehal` only.
- Generic over [signatures](#g-signature); narrow formals; non-generic backends for shared logic; no interrupt attachment; no delays except through `Delays_Signature`; no heap; [SPARK](#g-spark) per §6.6.
- Blocking drivers instantiate over `ehal_block`; async-capable drivers offer a second generic child over `ehal_async` completion types. Don't force async on driver authors — most sensor drivers are naturally blocking and short.
- Naming/discovery: `ehal-` topic tag in [Alire](#g-alire); the crate index becomes the driver registry (the Arduino Library Manager lesson: the *registry* is the ecosystem).

## 12. The beginner layer (L5): `maker`

Per Fabien Chouteau's design in [thread 4296](https://forum.ada-lang.io/t/an-embedded-ecosystem-for-beginners/4296), as a separate product with a hard dependency boundary:

- **API:** a near-literal [Arduino](https://docs.arduino.cc/learn/programming/reference/) port in one package spec: `Pin_Mode`, `Digital_Write/Read`, `Analog_Read`, `Delay_Ms`, `Millis`, `Print`/`Print_Line` over the default UART (via L2, never `Ada.Text_IO` — §10.3). Pins are integers (`subtype Pin is Natural range …` per board). Ada niceties appear only where free (named parameters, ranges).
- **One runtime** ([light](#g-light) / [`bare_runtime`](https://alire.ada.dev/crates/bare_runtime.html)), no tasking, no exception propagation, no interrupts visible. Application model: user writes a plain main procedure; no Setup/Loop hooks — a `loop` statement is not the hard part of embedded programming, and a real main teaches more.
- **But the Setup/Loop split is not only user convenience — credit where due.** Arduino's `loop()` returning to the framework once per iteration is a *scheduling hook*: the core and libraries run housekeeping invisible to the user between iterations (`serialEvent` dispatch, USB CDC keep-alive, network stack ticks). Dropping the hooks means EHAL must route that need elsewhere, and it does: every *blocking* `maker` primitive (`Delay_Ms`, blocking `Print`/reads) internally calls a board-defined `Housekeeping` procedure — draining the console FIFO (§10.3), pumping `ehal_async` completions (§8.2), feeding a watchdog — which is exactly the trick Arduino itself plays inside `delay()`. The failure mode is also the same as Arduino's (a tight loop that never blocks starves housekeeping), so `maker` exposes `Maker.Idle` as the explicit pump for busy loops, and the docs say so. What EHAL refuses is only the *inversion of control*, not the housekeeping.
- **Implementation:** `maker_<board>` (e.g. `maker_pico`) implements the spec by instantiating `ehal_block` over the board's `<mcu>_hal` — *not* a binary blob. Source-based keeps [SPARK](#g-spark), inlining, and single-toolchain builds; the "users never build the HAL" goal is met by [Alire](#g-alire) binary artifact caching and by the Hub IDE pre-building, which is where that complexity belongs.
- The graduation path is real and visible: a `maker` user opens `maker_pico`'s source and finds ordinary instantiations of the same HAL they'll use professionally. Arduino never offered that continuity; it is the pedagogical payoff of this architecture.

## 13. Board description (L6): a compile-time devicetree

Initialization is MCU-specific by design (§2, §6.1) — but *wiring a known board* is mechanical, and above the smallest targets it deserves tooling. L6 is an optional, declarative board/product description resolved **entirely at build time**, in the spirit of [Zephyr's devicetree](#g-devicetree) and [modm's lbuild](https://modm.io) but with a crucial difference: the output is ordinary, inspectable, SPARK-checkable Ada source — no runtime structs, no macros, no reflection.

- **Input:** a declarative file (TOML, Alire-friendly) describing the board and attached devices:

  ```toml
  [board]            # maps to a <board>_bsp or product crate
  mcu = "rp2040"
  [uart0]
  baud = 115200
  tx = 0            # GPIO pin mux
  rx = 1
  [i2c0]
  sda = 4
  scl = 5
  [devices.env_sensor]
  driver = "ehal_bme280"
  bus = "i2c0"
  address = 0x76
  ```

- **Output:** a generated Ada package (`Board`) containing the L2 `Enable`/`Configure` calls in correct order, the [signature](#g-signature) instantiations, and the driver instantiations (`Board.Env_Sensor` ready to use) — plus optionally pre-wired `On_Interrupt` attachments for `ehal_async` users. Precedent for gpr-metadata-driven generation: [startup_gen](https://github.com/AdaCore/startup-gen).
- **A tool crate (`boardgen`), not a library:** it runs before compilation (Alire pre-build action or explicit invocation); its output is committed or generated into the build tree. Nothing at runtime knows a devicetree existed. Generation-not-ifdef is the proven approach for covering hardware diversity ([svd2rust](https://docs.rust-embedded.org/book/design-patterns/hal/gpio.html), modm-devices).
- **Validation at generation time:** pin-mux conflicts, wrong bus assignments, address clashes are reported by the generator with board-schematic vocabulary — errors caught before the compiler runs, in terms a hardware person understands.
- **Scope:** 32-bit-class targets and up. Not offered for AVR: an ATmega program wires two or three instantiations by hand (§6.3) and gains nothing from a generator; keeping AVR out preserves the "no machinery below the floor" rule.
- **Relation to L5:** `maker_<board>` crates are natural consumers — a `maker` board port can be largely `boardgen` output.

## 14. Cross-cutting concerns

Ada's standard library has no logging, tracing, or diagnostics framework, and the desktop-world answers — global logger singletons, access-to-subprogram sink registries, runtime string formatting — are all excluded by the floor (no heap, no exceptions, no access types in the contract, [SPARK](#g-spark)). Rather than solving each concern ad hoc, EHAL standardizes **one pattern** and applies it homogeneously.

### 14.1 The uniform pattern: null-object formals

Every cross-cutting service is (a) a small set of types in `ehal`, (b) formal subprograms on the generic units that want the service, (c) **defaulted to a null implementation** so that not wiring the service costs nothing:

```ada
generic
   with package I2C is new Ehal.I2C_Master_Signature (<>);
   with procedure Log_Event (E : Ehal.Log.Event_Id;
                             A : Ehal.Log.Args := Ehal.Log.No_Args) is null;
package Ehal_BME280 is …
```

Ada's `is null` formal-procedure default (since Ada 2005) is the exact null-object idiom needed: an application that wires nothing gets calls to a null procedure, which the compiler eliminates — zero bytes on the ATtiny. An application that cares injects its sink *at instantiation*, so the wiring is visible in source, provable, and per-instance (two motor drivers can log to different channels). No global state exists anywhere.

This is the same move the rest of the architecture makes — behavior arrives through [generic](#g-generic) formals, selection is compile-time — extended from hardware access to services.

### 14.2 Logging and tracing

The main event, and where the pattern needs the most discipline:

- **Levels and static thresholds.** `type Level is (Error, Warning, Info, Debug, Trace)` in `ehal`; the enabled threshold is an Alire configuration variable rendered as a static constant. `if L <= Enabled_Level then …` against a static constant folds at compile time — disabled log statements vanish from the binary, which is the 8-bit requirement and also the release-build requirement.
- **Deferred formatting — the [defmt](#g-defmt) lesson.** L2–L4 code never formats strings. A log statement emits a discrete `Event_Id` plus scalar arguments; rendering to text happens on the host. This keeps format strings out of flash, keeps log calls bounded-time (callable from ISR pumps), and keeps SPARK happy (no secondary stack, no `'Image` machinery). Without Rust's proc macros, event IDs are ordinary enumerations declared per crate; a `boardgen`-style helper can harvest them into a host-side rendering table (open question §18). Human-readable `Put_Line`-style convenience remains available *at application level* over the byte sink — it is an application luxury, not a library facility.
- **Transport reuse.** A log sink is just the §10.3 diagnostic channel wearing a different hat: the runtime's non-blocking FIFO by default on 32-bit targets — read by a probe, or drained to any I/O peripheral by application/`boardgen` code — and `null` in production. One sink, three producers (`Ada.Text_IO` diagnostics, `Last_Chance_Handler`, logging), any transport: that is itself the homogeneity the ecosystem lacks.
- **What libraries may log:** state transitions, error paths, recovery actions. Never per-byte data phases (bandwidth and timing poison), never in L2 (L2 primitives are 4–8 instructions; logging belongs to the layers that have decisions to report).

### 14.3 Fault reporting

Contract violations and runtime-check failures funnel to the `Last_Chance_Handler` on the floor runtime ([`No_Exception_Propagation`](#g-nep)). Policy: the default handler writes the failure location through the same diagnostic sink and then parks or resets (board policy); applications may replace it. Because the sink is the §10.3 channel, a crash report needs no working peripheral configuration beyond what the console already established — a crash-only-visible-with-a-differently-wired-UART is a bring-up trap this rules out.

### 14.4 Critical sections

Adapters and drivers occasionally need a few instructions of atomicity against their own ISR pump (`ehal_async` completion state). The portable mechanism differs per target — PRIMASK masking on Cortex-M, the I-bit in `SREG` on AVR, protected objects under [Ravenscar](#g-ravenscar) — so it is a signature like everything else:

```ada
generic
   type Mask_State is private;
   with function  Enter return Mask_State;   --  disable, return previous state
   with procedure Leave (Prev : Mask_State); --  restore (supports nesting)
package Ehal.Critical_Signature is end;
```

implemented by each `<mcu>_hal` (and by `ehal_task` via a protected object where tasking semantics demand it). Portable code never touches interrupt-enable bits directly.

### 14.5 Configuration and test doubles

Two concerns the pattern absorbs for free:

- **Configuration:** every cross-cutting knob (log threshold, sink choice, buffer sizes) is an Alire crate configuration variable → generated static constants. No runtime configuration state exists; what the binary does is what the manifest says.
- **Testing:** because all dependencies arrive as formals, every L3/L4 unit instantiates against scripted or recording implementations on a native GNAT — host-side unit tests of embedded drivers with no hardware, no linker tricks, no mocking framework. The logging formals double as test probes (assert on emitted events). This is a deliberate payoff of D1, worth advertising as such.

## 15. Crate map and naming

| Crate | Layer | Contents | Depends on |
|---|---|---|---|
| `ehal` | spec | types, error kinds, signature packages | — |
| `ehal_block` / `ehal_async` / `ehal_task` | L3 | execution adapters (generic) | `ehal` (+tasking RT for `_task`) |
| `ehal_classes` | opt | tagged wrappers | `ehal` |
| `<mcu>_pac` | L1 | curated register bindings | — |
| `<mcu>_hal` | L2 | convention packages + native full-feature surface + CI conformance unit | `ehal`, `<mcu>_pac` |
| `<board>_bsp` | L2+ | pin names, board init, pre-wired instantiations | `<mcu>_hal` |
| `ehal_<device>` | L4 | portable device drivers | `ehal` |
| `maker`, `maker_<board>` | L5 | beginner API + board impls | `ehal`, `ehal_block`, `<mcu>_hal` |
| `boardgen` | L6 | board-description → Ada generator (tool) | — (its *output* uses L2–L4) |
| `light_*` / `embedded_*` / `avrada_rts` | L0 | runtimes (existing ecosystem) | — |

[Alire](#g-alire) specifics:

- **Versioning:** `ehal` follows [embedded-hal](#g-eh)'s discipline — reach 1.0 with few, proven signatures; additions are minor versions; the ambition is that 2.0 never happens. Everything else versions independently (the reason [hal 1.x](#g-halcrate) evolution is hard is that spec and implementations were born in one repo; EHAL is decentralized from day one).
- **Configuration:** static choices (buffer sizes, tick width, feature gates) use Alire crate configuration variables → generated config packages, keeping everything compile-time.
- **`provides`:** where useful, `<mcu>_hal` crates can declare `provides` on a virtual name so board-generic project templates depend on "some conforming HAL"; needs validation against current Alire semantics before relying on it (open question §18).
- Runtime selection stays the ecosystem norm: the project (or BSP template) depends on a runtime crate ([damaki-style](https://github.com/damaki/stm32g4xx-runtimes)) and inherits `Runtime ("Ada")` from it.

## 16. Positioning: EHAL compared with related ecosystems

Where EHAL sits relative to the platforms an embedded developer would actually choose between, and what was deliberately taken or refused from each.

| | Portable contract | Dispatch | Configuration | 8-bit floor | Error model | Formal proof | Packages / registry |
|---|---|---|---|---|---|---|---|
| **EHAL** | [signature packages](#g-signature) + spec convention | compile-time | [Alire](#g-alire) config vars + `boardgen` | **yes** (AVR) | [chained](#g-chained) status kinds | **SPARK mandatory** | Alire |
| [Arduino](https://github.com/arduino/ArduinoCore-API) | informal C++ core API | runtime pin tables | IDE / boards.txt | yes | none (`void`) | no | Library Manager |
| [PlatformIO](https://pypi.org/project/platformio/) | none — meta-build over other frameworks | n/a | `platformio.ini` | via frameworks | n/a | no | own registry |
| [Mbed OS](https://os.mbed.com/blog/entry/Important-Update-on-Mbed/) † | C++ classes, virtuals | runtime | JSON + build profiles | no | error codes | no | mbed registry (†) |
| [Zephyr](https://docs.zephyrproject.org/latest/kernel/drivers/index.html) | C vtable driver classes | runtime | [devicetree](#g-devicetree) + Kconfig | no (~32-bit floor) | `-errno` ints | no | west manifests |
| [Rust embedded-hal](#g-eh) / [Embassy](https://embassy.dev) | traits | compile-time (monomorphized) | Cargo features | yes ([avr-hal](https://github.com/Rahix/avr-hal)) | `ErrorKind` | no (strong type safety) | crates.io |
| [TinyGo](https://tinygo.org/docs/reference/machine/) | `machine` package convention | compile-time (build tags) | build tags | yes | Go errors | no | Go modules |
| [MicroPython](https://docs.micropython.org/en/latest/library/machine.html)/CircuitPython | runtime `machine` objects | runtime (interpreted) | runtime | no (~16 KB RAM floor) | exceptions | no | mip / bundles |
| [modm](https://modm.io) | generated C++ templates | compile-time | lbuild + device data | yes | varies | no | lbuild repos |
| Vendor HALs ([STM32Cube](https://www.st.com/en/embedded-software/stm32cube-mcu-mpu-packages.html), ESP-IDF, CMSIS) | none portable | mixed | GUI tools / Kconfig | per vendor | error codes | no | per vendor |

† Mbed OS reaches [end of life in July 2026](https://os.mbed.com/blog/entry/Important-Update-on-Mbed/); Arm halted maintenance in 2024, and continuation rests on the community fork [Mbed CE](https://github.com/mbed-ce/mbed-os).

**Arduino** optimizes for the first ten minutes; EHAL confines that optimization to L5 (`maker`) instead of letting it cap the whole stack. Taken: the tiny teachable API, the registry-is-the-ecosystem lesson, the hidden-housekeeping trick (§12). Refused: runtime pin tables, `void` error handling, and the ceiling — an Arduino user who outgrows the API leaves the ecosystem; a `maker` user who outgrows it opens `maker_pico` and finds the professional stack (§12).

**PlatformIO** is not a HAL but a meta-platform: a build system and registry wrapping other ecosystems' frameworks. Its lesson is double-edged. Positively: one CLI, one registry and per-project reproducible environments won it enormous adoption — that role is played natively by [Alire](#g-alire) in EHAL's stack, with the advantage that Alire resolves *the actual dependencies* (runtime, PAC, HAL) rather than shrink-wrapping foreign build systems. Negatively: an abstraction layer over ecosystems you don't control [lags the native toolchains and loses functionality in translation](https://peterbabic.com/blog/esp32-c6-platformio-fail/) — and when its governance clashed with a vendor's pace, the community had to fork ([pioarduino](https://github.com/pioarduino)). EHAL avoids the trap by owning its layers down to the register bindings instead of wrapping vendor frameworks.

**Mbed OS** is the cautionary tale the decentralization decisions answer. It had a real portable C++ API, an online IDE, a registry, corporate backing — and a single owner whose strategy changed. EHAL's counter-position: no central repo to abandon (independent crates, D1/§15), no company-owned build service (plain GNAT + Alire), and the spec crate small enough that a community can maintain it indefinitely. The runtime-virtuals-everywhere design also made Mbed unable to scale down; EHAL's compile-time contract is the opposite bet.

**Zephyr** is the strongest 32-bit C ecosystem and the closest thing to an industry default. EHAL takes its build-time configuration philosophy (devicetree → §13's `boardgen`) and its warning: the vtable device model plus devicetree machinery set a hard 32-bit floor and a heavyweight developer experience. Where Zephyr integrates dozens of subsystems (networking, filesystems, BLE), EHAL deliberately stays a HAL — those belong in L4-style crates on top. For Ada users, Zephyr is also a *host*: an [Ada-on-Zephyr integration](https://forum.ada-lang.io/t/add-ada-support-for-zephyr-rtos/4206) would sit beside EHAL (L2 over Zephyr drivers), not compete with it.

**Rust embedded-hal / Embassy** is the closest relative and the primary design source (§3): the tiny stable contract, the PAC/HAL/BSP layering, error *kinds*, the blocking/async split, compile-time dispatch down to AVR. The differences are where Ada changes the calculus. EHAL gets *formal proof* (SPARK) where Rust gets type safety; *language-standard tasking* ([Ravenscar](#g-ravenscar)/[Jorvik](#g-jorvik) in the runtime) where Embassy must ship an executor library and async machinery; *signature packages* where Rust has traits — less ergonomic (no `?`, no derive macros, explicit instantiation) but fully explicit and analyzable wiring. Rust's typestate GPIO has no zero-cost Ada equivalent; EHAL compensates at a different level (SPARK contracts on `Configure`/use, `boardgen` pin-conflict checks at build time).

**TinyGo and MicroPython/CircuitPython** validate two individual EHAL choices: TinyGo's `machine` package *is* the package-spec convention (D1) with build-tag selection, proving the model's developer experience at scale; CircuitPython owns the education niche `maker` targets — its REPL immediacy is something a compiled stack cannot match, so `maker` competes on the graduation path and on programs that keep running when the cable is pulled, not on interactivity.

**modm** is the philosophical sibling on the C++ side: curated machine-readable device data + a generator emitting a bespoke zero-cost HAL, down to AVR. It validates both the "generate, don't ifdef" rule (§9, §13) and the viability of compile-time HALs across thousands of devices. EHAL differs in having a *stable portable contract* on top (modm code is portable only across modm's own generated API surface) and proof obligations.

**Vendor HALs** (STM32Cube, ESP-IDF, nRF Connect, CMSIS-Driver) are what D13 targets for replacement, not coexistence: full-featured, authoritative for their silicon, unportable by construction, and of famously uneven quality. EHAL's `<mcu>_hal` native surface takes their role with SPARK behind it; their configuration GUIs are answered by `boardgen`; CMSIS-Driver's binary vtable interfaces are answered by `ehal_classes` — as an option, not a foundation.

**The position in one sentence:** EHAL is the only proposal in this field that combines a compile-time zero-cost contract (Rust's lesson), build-time declarative configuration (Zephyr's lesson), an 8-bit-to-64-bit range (modm/TinyGo's lesson), a protected beginner tier with a graduation path (Arduino's lesson), *and* mandatory formal verifiability — the one property none of the others offer at any price. The honest costs of that position: a single-vendor toolchain (GNAT), an ecosystem starting from tens of crates where competitors have thousands, and Ada's smaller talent pool — which is why the beginner layer and the forum-driven RFC process (§18 roadmap) are part of the architecture rather than afterthoughts.

## 17. Decision record

| # | Decision | Chosen | Rejected because |
|---|---|---|---|
| D1 | Abstraction mechanism | [Generics](#g-generic) over package-spec convention; [signatures](#g-signature) as contract; [tagged](#g-tagged) wrappers optional | Interfaces: not [SPARK](#g-spark)-provable, vtable/RAM cost, AVR-hostile. Interfaces-as-foundation inverted into wrappers-on-top. |
| D2 | Execution model | Never-blocking L2 core + blocking/async/tasking adapters | Blocking-first forbids power-efficient + tasking designs portably; async-first too heavy for 8-bit and beginners. |
| D3 | Register layer | Per-MCU [PAC](#g-pac) crates, generated + curated | In-runtime registers couple HAL to runtime maintenance; hand-written-only doesn't scale; generation-only trusts broken [SVDs](#g-svd). |
| D4 | Errors | Status enums (kinds) per class, no exceptions, no L2 timeout; [chained](#g-chained) `in out Status` with skip-if-pending semantics (§7.1) | Exceptions violate floor runtime; rich error types break portability; Arduino-style `void` loses information; `out`-only status forces handler boilerplate between every pair of calls; discriminated result records lose to SPARK's effectful-function rules and 8-bit return costs without `?`-style sugar (§7.1). |
| D5 | Interrupts | L2 exposes event flags; adapters export `On_Interrupt`; application attaches | Driver-installed handlers preempt the application's choice of attachment style and break composability. |
| D6 | Timekeeping | Runtime owns the tick interrupt; L2 exposes monotonic `Now` | HAL-owned timers conflict with `delay`/scheduling on tasking runtimes. |
| D7 | Multiplicity | One package per peripheral instance (`UART0`, `UART1`) | Object/handle models reintroduce indirection or generics-per-instance for no gain on fixed silicon. |
| D8 | Scope of signatures | Data phase only; config native; ADC/PWM/timers deferred | Universal configuration abstraction is leaky by design; unproven signatures freeze mistakes ([embedded-hal 0.2 lesson](https://blog.rust-embedded.org/embedded-hal-v1/)). |
| D9 | Beginner layer | Source-based `maker` over `ehal_block`, single runtime, integer pins | Binary blob sacrifices SPARK/inlining/graduation path; solving "don't build the HAL" belongs to tooling (Alire artifacts, Hub IDE). |
| D10 | SPARK | Mandatory: SPARK specs everywhere, access-free contract, one designated non-SPARK crate (`ehal_classes`), flow analysis in CI | SPARK-as-aspiration decays; [hal 1.x](#g-halcrate) shows one access-to-class-wide type in the foundation poisons provability of the whole ecosystem. |
| D11 | Scale ceiling | Embedded runtime profiles only (light → embedded); no full OS targets | OS targets drag in dynamic memory, processes, `/dev` semantics and double the test matrix; the OS world has its own ecosystems. |
| D12 | Init & wiring | Init is native L2; optional compile-time board description (`boardgen`, L6) generates wiring for 32-bit-class targets | Runtime devicetree ([Zephyr model](https://docs.zephyrproject.org/latest/build/dts/index.html)) costs ROM/RAM structs and indirection; abstracting init in the contract is leaky by design (D8); AVR excluded — hand-wiring 3 instantiations needs no tool. |
| D13 | Vendor-lib ambition | `<mcu>_hal` native surface grows toward SPARK-proven full peripheral coverage; contract stays minimal | Putting full coverage *into* the contract reproduces ADL's unportability; abandoning full coverage cedes the safety argument that motivates Ada/SPARK adoption. |
| D14 | L0/L1 seam | No crate dependency runtime→PAC; runtime keeps private register copies generated from the PAC's source-of-truth data; generic runtime core + thin generated board layer per architecture (§10.1–10.2) | PAC dependency: build cycle, audit-surface explosion, stability inversion. App-provided link hooks: tasking must work before application elaboration, invisible to proof. Per-MCU runtime forks: unjustified once the residue is a linker script + 2 config values. |
| D15 | Runtime console | `Ada.Text_IO` = diagnostic channel only; sink is a non-blocking SPSC RAM FIFO in RTT-compatible layout (`console := fifo`, §10.3), probe-read or application-drained through L2 to any transport; drain ownership declared in `HAL_Info`/`boardgen`; application console goes through L2 | UART driver inside the runtime: peripheral knowledge in L0, hidden UART ownership, double-init conflicts with L2 users; blocking sinks: a runtime must not stall because nobody listens; making `Ada.Text_IO` the application console couples portable code to runtime IO presence (absent on AVR). |
| D16 | Cross-cutting services | Null-object formals (`is null` defaults) + [deferred-formatting](#g-defmt) event logging with static thresholds; one sink shared by console, LCH and logs; critical sections via signature (§14) | Global logger singleton / sink registries: global state, access types, unprovable; runtime string formatting: flash cost, unbounded time, secondary stack; per-crate bespoke logging hooks: heterogeneity is the disease, not a symptom. |

## 18. Open questions and roadmap

**Open questions**

1. Root package naming: strictly crate-derived (`RP2040.GPIO`) vs. a fixed alias (`MCU.GPIO` via project-level renaming) for copy-paste-portable *application* code — leaning crate-derived + BSP-provided renames, needs prototyping.
2. [Alire](#g-alire) `provides` semantics for virtual "conforming HAL" dependencies — validate with current Alire.
3. Async signature details (scatter-gather? completion status payload?) — prototype on RP2040 (IRQ + [DMA](#g-dma)) and ATmega328 (IRQ only) before freezing.
4. 9-bit UART frames, SPI 16-bit words: separate signatures vs. formal `Frame is mod <>` — sketch says formal type; verify codegen on AVR.
5. Board description format (§13): TOML schema vs. an Ada-based DSL vs. gpr metadata ([startup_gen](https://github.com/AdaCore/startup-gen) precedent); how driver crates declare their instantiation template to `boardgen`; where pin-mux validity data comes from (PAC metadata?).
6. Conformance test suite (hardware-in-the-loop, per [ADL #401](https://github.com/AdaCore/Ada_Drivers_Library/issues/401) discussion) — separate concept document.
7. Relationship to existing crates: coexistence is automatic (different namespaces); active migration guidance deferred.
8. Runtime composition tooling (§10.2): can GNAT/Alire assemble a runtime from a core crate + board-layer crate cleanly, or does generation-into-one-crate remain the practical route? `Runtime ("Ada")` expects a single directory tree; coordinate with damaki and the [bb-runtimes](https://github.com/AdaCore/bb-runtimes) maintainers (see also [Porting the GNAT RTS](https://forum.ada-lang.io/t/porting-the-gnat-rts/4397)).
9. Log event interning (§14.2): how to assemble the host-side rendering table for [defmt](#g-defmt)-style deferred formatting without proc macros — convention (enum + comment pragma harvested by a tool), a `boardgen` sibling, or plain per-crate event documentation? Also: wire format of `Ehal.Log.Args` (fixed scalar tuple vs. per-event record).

**Roadmap sketch**

1. `ehal` 0.x with `Digital_Out/In`, `UART`, `Clock`, `Delays` signatures + `ehal_block`.
2. Two proving-ground implementations far apart: [`rp2040_hal`](https://github.com/JeremyGrosser/rp2040_hal)-based L2 (Cortex-M0+, light + light-tasking) and `atmega328p_hal` (AVR [ZFP](#g-zfp)) — port one real driver (e.g. SSD1306) across both; measure code size vs. hand-written.
3. Add `SPI_Master`, `I2C_Master`; add `ehal_async` prototype on RP2040; [A0B](#g-a0b) interop review with godunko.
4. `maker` + `maker_pico`; Hub IDE integration ([thread 4296](https://forum.ada-lang.io/t/an-embedded-ecosystem-for-beginners/4296)).
5. `boardgen` prototype: TOML → generated `Board` package for the Pico, consumed by `maker_pico`.
6. PolarFire SoC bare-metal: `mpfs_pac` + `mpfs_hal` on the [bb-runtimes](https://github.com/AdaCore/bb-runtimes) `polarfiresoc` targets to validate the top of the range (SMP stays a runtime concern).
7. `ehal` 1.0 freeze; RFC on [forum.ada-lang.io](https://forum.ada-lang.io) with this document.

---

## Appendix A — Spike: BME280 on RP2040 (specs only)

A vertical slice through the stack for one concrete case: a Bosch BME280 environment sensor on I2C0 of a Raspberry Pi Pico, blocking style, light runtime. Specs only — bodies, register work and the compensation math are implementation; the point is to check that the shapes of D1/D2/D4 compose. Layer per package: `ehal` (contract) → `RP2040.I2C0`/`RP2040.Clock` (L2) → `Ehal_Block.*` (L3a) → `BME280` (L4) → `Board` (wiring).

### A.1 Contract excerpts (`ehal` crate)

```ada
--  ehal.ads
package Ehal
  with Pure, SPARK_Mode
is
   type Byte is mod 2**8;
   type Byte_Array is array (Positive range <>) of Byte;

   type I2C_7_Bit_Address is range 0 .. 16#7F#;   --  unshifted (§7.2)

   --  L2 status: no Timed_Out — L2 never waits (§7):
   type I2C_Status is
     (Ok, Nack_Address, Nack_Data, Arbitration_Lost, Bus_Error, Other_Error);

   --  L3a status: adapters add the timeout outcome (§7 rule 3):
   type I2C_Block_Status is
     (Ok, Timed_Out,
      Nack_Address, Nack_Data, Arbitration_Lost, Bus_Error, Other_Error);
end Ehal;
```

```ada
--  ehal-log.ads   (§14.2, deferred formatting: ids + scalars, no strings)
package Ehal.Log
  with Pure, SPARK_Mode
is
   type Event_Id is mod 2**16;
   type Arg is mod 2**32;
   No_Arg : constant Arg := 0;
end Ehal.Log;
```

```ada
--  ehal-clock_signature.ads
generic
   type Ticks is mod <>;                       --  >= 2**32 (§6.5)
   Ticks_Per_Second : Positive;
   with function Now return Ticks;
package Ehal.Clock_Signature is end;
```

```ada
--  ehal-delays_signature.ads
generic
   with procedure Delay_Us (Us : Natural);
   with procedure Delay_Ms (Ms : Natural);
package Ehal.Delays_Signature is end;
```

```ada
--  ehal-i2c_master_signature.ads
--  The never-blocking L2 data phase (§5, §6.3): command/data FIFO
--  primitives, chained on Ehal.I2C_Status (§7.1).
generic
   with procedure Set_Target (Address : I2C_7_Bit_Address);
   with function  Can_Push return Boolean;
   with procedure Push_Write (Data : Byte; Stop : Boolean;
                              Status : in out I2C_Status);
   with procedure Push_Read_Request (Stop : Boolean;
                                     Status : in out I2C_Status);
   with function  Can_Pop return Boolean;
   with procedure Pop (Data : out Byte; Status : in out I2C_Status);
package Ehal.I2C_Master_Signature is end;
```

```ada
--  ehal-i2c_blocking_signature.ads
--  What blocking L4 drivers program against (§11): whole transactions,
--  chained on Ehal.I2C_Block_Status.
generic
   with procedure Write (Address    : I2C_7_Bit_Address;
                         Data       : Byte_Array;
                         Timeout_Ms : Natural;
                         Status     : in out I2C_Block_Status);
   with procedure Write_Read (Address    : I2C_7_Bit_Address;
                              Command    : Byte_Array;
                              Response   : out Byte_Array;
                              Timeout_Ms : Natural;
                              Status     : in out I2C_Block_Status);
package Ehal.I2C_Blocking_Signature is end;
```

### A.2 L2 excerpts (`rp2040_hal` crate)

```ada
--  rp2040-clock.ads
package RP2040.Clock
  with Preelaborate, SPARK_Mode
is
   type Ticks is mod 2**64;                    --  the 64-bit TIMER peripheral
   Ticks_Per_Second : constant := 1_000_000;
   function Now return Ticks with Inline_Always;
end RP2040.Clock;
```

```ada
--  rp2040-i2c0.ads
with Ehal;
package RP2040.I2C0
  with Preelaborate, SPARK_Mode
is
   --  Configuration: deliberately RP2040-specific (D8) — pins, pad
   --  options, bus speed. Not part of the portable contract.
   type Config is record
      Baud_Hz : Positive range 1 .. 1_000_000 := 100_000;
      SDA_Pin : Pin_Id := 4;
      SCL_Pin : Pin_Id := 5;
      --  … pull-ups, slew, RP2040 pad controls
   end record;
   procedure Enable  (Cfg : Config := (others => <>));
   procedure Disable;
   procedure Set_Target (Address : Ehal.I2C_7_Bit_Address);

   --  Never-blocking data phase over the DW_apb_i2c command FIFO;
   --  Stop => True sets the STOP bit on that FIFO entry:
   function  Can_Push return Boolean with Inline_Always;
   procedure Push_Write (Data : Ehal.Byte; Stop : Boolean;
                         Status : in out Ehal.I2C_Status)
     with Inline_Always, Pre => Can_Push;
   procedure Push_Read_Request (Stop : Boolean;
                                Status : in out Ehal.I2C_Status)
     with Inline_Always, Pre => Can_Push;
   function  Can_Pop return Boolean with Inline_Always;
   procedure Pop (Data : out Ehal.Byte; Status : in out Ehal.I2C_Status)
     with Inline_Always;

   --  Event plumbing for L3b (§6.2), unused in this blocking spike:
   --  Enable_Event / Disable_Event / Pending_Event / Clear_Event …
end RP2040.I2C0;
```

### A.3 L3a adapters (`ehal_block` crate)

```ada
--  ehal_block-delays.ads    (busy-wait over any Clock; §6.5, §8.1)
with Ehal.Clock_Signature, Ehal.Delays_Signature;
generic
   with package Clock is new Ehal.Clock_Signature (<>);
package Ehal_Block.Delays
  with SPARK_Mode
is
   procedure Delay_Us (Us : Natural);
   procedure Delay_Ms (Ms : Natural);

   --  Adapter exports its own conformance — the normative pattern:
   package As_Signature is new Ehal.Delays_Signature
     (Delay_Us => Delay_Us, Delay_Ms => Delay_Ms);
end Ehal_Block.Delays;
```

```ada
--  ehal_block-i2c.ads    (blocking transactions over the L2 data phase)
with Ehal.Clock_Signature, Ehal.I2C_Master_Signature,
     Ehal.I2C_Blocking_Signature;
generic
   with package Port  is new Ehal.I2C_Master_Signature (<>);
   with package Clock is new Ehal.Clock_Signature (<>);
package Ehal_Block.I2C
  with SPARK_Mode
is
   procedure Write (Address    : Ehal.I2C_7_Bit_Address;
                    Data       : Ehal.Byte_Array;
                    Timeout_Ms : Natural;
                    Status     : in out Ehal.I2C_Block_Status);
   procedure Write_Read (Address    : Ehal.I2C_7_Bit_Address;
                         Command    : Ehal.Byte_Array;
                         Response   : out Ehal.Byte_Array;
                         Timeout_Ms : Natural;
                         Status     : in out Ehal.I2C_Block_Status);

   package As_Signature is new Ehal.I2C_Blocking_Signature
     (Write => Write, Write_Read => Write_Read);
end Ehal_Block.I2C;
```

### A.4 L4 driver (`ehal_bme280` crate)

```ada
--  bme280.ads
with Ehal.I2C_Blocking_Signature, Ehal.Delays_Signature, Ehal.Log;
generic
   with package Bus  is new Ehal.I2C_Blocking_Signature (<>);
   with package Wait is new Ehal.Delays_Signature (<>);
   Device_Address : Ehal.I2C_7_Bit_Address := 16#76#;   --  16#77# variant
   with procedure Log_Event (E : Ehal.Log.Event_Id;
                             A : Ehal.Log.Arg := Ehal.Log.No_Arg) is null;
package BME280
  with SPARK_Mode
is
   --  Driver-level chained status (§7.1 rule 4): bus kinds are mapped,
   --  not re-exported.
   type Status_Kind is
     (Ok, Wrong_Chip_Id, Bus_Fault, Timed_Out, Not_Initialized);
   function Last_Bus_Status return Ehal.I2C_Block_Status;  --  detail escape

   type Oversampling is (Skipped, X1, X2, X4, X8, X16);

   --  Compensated readings as fixed-point, per datasheet ranges:
   type Celsius     is delta 0.01 range -40.00 .. 85.00;
   type Hectopascal is delta 0.01 range 300.00 .. 1100.00;
   type Percent_RH  is delta 0.01 range 0.00 .. 100.00;
   type Measurement is record
      Temperature : Celsius;
      Pressure    : Hectopascal;
      Humidity    : Percent_RH;
   end record;

   --  Soft-reset, probe chip id (16#60#), load calibration coefficients.
   --  Calibration state lives in the package body — one device per
   --  instantiation, no access types, no heap.
   procedure Initialize (Status : in out Status_Kind);

   procedure Configure
     (Temperature_Oversampling : Oversampling := X2;
      Pressure_Oversampling    : Oversampling := X16;
      Humidity_Oversampling    : Oversampling := X1;
      Status                   : in out Status_Kind);

   --  Forced-mode cycle: trigger, Wait.Delay_Ms (max conversion time for
   --  the configured oversampling), burst-read 16#F7#..16#FE#, compensate.
   procedure Measure (Result : out Measurement;
                      Status : in out Status_Kind);
end BME280;
```

### A.5 Wiring (application or `boardgen` output; §6.3, §13)

```ada
--  board.ads — pure declarations; reads like the schematic.
with Ehal.Clock_Signature, Ehal.I2C_Master_Signature;
with RP2040.Clock, RP2040.I2C0;
with Ehal_Block.Delays, Ehal_Block.I2C, BME280;
package Board is

   package Clock_Sig is new Ehal.Clock_Signature
     (Ticks            => RP2040.Clock.Ticks,
      Ticks_Per_Second => RP2040.Clock.Ticks_Per_Second,
      Now              => RP2040.Clock.Now);

   package I2C0_Sig is new Ehal.I2C_Master_Signature   --  conformance check
     (Set_Target        => RP2040.I2C0.Set_Target,     --  of RP2040.I2C0,
      Can_Push          => RP2040.I2C0.Can_Push,       --  §6.1, for free
      Push_Write        => RP2040.I2C0.Push_Write,
      Push_Read_Request => RP2040.I2C0.Push_Read_Request,
      Can_Pop           => RP2040.I2C0.Can_Pop,
      Pop               => RP2040.I2C0.Pop);

   package Delays is new Ehal_Block.Delays (Clock => Clock_Sig);
   package I2C    is new Ehal_Block.I2C (Port => I2C0_Sig, Clock => Clock_Sig);

   package Env_Sensor is new BME280
     (Bus            => I2C.As_Signature,
      Wait           => Delays.As_Signature,
      Device_Address => 16#76#);

   --  Native configuration stays native (D8): the (not shown) main or a
   --  boardgen-generated Initialize body calls
   --    RP2040.I2C0.Enable ((Baud_Hz => 400_000, SDA_Pin => 4, SCL_Pin => 5));
   --  before first use of Env_Sensor.
end Board;
```

Usage, for flavor: `S := Ok; Env_Sensor.Initialize (S); Env_Sensor.Configure (Status => S); Env_Sensor.Measure (M, S);` — one status inspection at the end (§7.1).

### A.6 What the spike surfaces

1. **The adapter-exports-signature pattern (`As_Signature`) works and should be normative** — adapters instantiate their own conformance, so wiring never repeats subprogram lists that already exist.
2. **Whole-stack property check:** no access types, no tagged types, no heap, every spec `SPARK_Mode` — the D1/D10 claims hold in the concrete shapes, and every layer is instantiated exactly once per program (jere's bloat rule trivially satisfied).
3. **Three chained status types coexist cleanly** (`I2C_Status` → `I2C_Block_Status` → `BME280.Status_Kind`) with mapping at each boundary and `Last_Bus_Status` as the detail escape — §7.1 rule 4 survives contact with a real driver.
4. **`Ticks_Per_Second` must be a formal object** of the clock signature, or delays can't be computed portably — a detail §6.5's prose glossed over.
5. **The command-FIFO shape of the L2 I2C data phase** (`Push_Write`/`Push_Read_Request` with per-entry `Stop`) matches RP2040's DW_apb_i2c but needs validation against at least one controller with a different transaction model (STM32, AVR TWI) before the `I2C_Master_Signature` freezes — this is open question 3 made concrete.

---

*Prepared 2026-07-14, revised same day. Sources: [Towards a HAL for multiple runtimes (thread 4364)](https://forum.ada-lang.io/t/towards-a-hal-for-multiple-runtimes/4364); [An embedded ecosystem for beginners (thread 4296)](https://forum.ada-lang.io/t/an-embedded-ecosystem-for-beginners/4296); [Ada_Drivers_Library](https://github.com/AdaCore/Ada_Drivers_Library) and issues [#25](https://github.com/AdaCore/Ada_Drivers_Library/issues/25)/[#401](https://github.com/AdaCore/Ada_Drivers_Library/issues/401); [Alire crate index](https://alire.ada.dev/crates.html); [embedded-hal 1.0 announcement](https://blog.rust-embedded.org/embedded-hal-v1/) and [migration notes](https://github.com/rust-embedded/embedded-hal/blob/master/docs/migrating-from-0.2-to-1.0.md); [Zephyr device model](https://docs.zephyrproject.org/latest/kernel/drivers/index.html) and [devicetree](https://docs.zephyrproject.org/latest/build/dts/index.html); [ArduinoCore-API](https://github.com/arduino/ArduinoCore-API); [TinyGo machine package](https://tinygo.org/docs/reference/machine/); [modm](https://modm.io); [A0B](https://github.com/godunko/a0b-i2c) (godunko); [rp2040_hal](https://github.com/JeremyGrosser/rp2040_hal) (JeremyGrosser); [AVRAda](https://github.com/RREE/AVRAda_Lib) (RREE); [damaki runtime crates](https://github.com/damaki/stm32g4xx-runtimes); [bb-runtimes](https://github.com/AdaCore/bb-runtimes) (PolarFire SoC targets); [svd2ada](https://github.com/AdaCore/svd2ada); [startup_gen](https://github.com/AdaCore/startup-gen).*
