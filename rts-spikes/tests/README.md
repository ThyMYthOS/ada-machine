# tests/ -- the runtime's own test suite (`make test`)

RTS-PRODUCTION.md A4. `make verify` checks what the images *are* and `make
smoke` checks what three of them *print*; this directory checks what the runtime
*does*. Two kinds of test, both run by `make test` (and by `make all`, after
`smoke`).

## Positive: applications booted under QEMU

| Test | Profile | Covers |
|---|---|---|
| `tasking_test` | light-tasking | two tasks released by `delay until`, ordering, priority tie-break, `Clock` monotonicity, elapsed time vs `Ada.Real_Time` |
| `protected_test` | light-tasking | an entry barrier released by another task; one released from the alarm interrupt (a `Timing_Event` handler); a cancelled event |
| `exceptions_test` | embedded | raise across frames, re-raise, `Exception_Name`/`Message`/`Information`, `Reraise_Occurrence`, predefined checks, finalization during propagation |
| `textio_test` | light | `Ada.Text_IO` output (asserted by the host against `console.expected`) and a line of **input** fed through the serial port (`console.in`) |
| `console_test`, `console_mmuart2_test`, `_3_`, `_4_` | light, `Console => mmuart1..4` | that the `Console` configuration value selects the UART: the verdict must appear on QEMU's serial 1..4 (= MMUART1..4) **and no output on any other port** (MMUART0 is `textio_test`'s) |

Each prints `TEST <name>: START`, one line per check, and `TEST <name>: PASS` or
`FAIL` (`common/test_report.ads`). `run_tests.sh` boots it and passes it only
on a PASS line with no failed check, no missing START and, if there is a
`console.expected`, every line of it on the serial port. A hang, a crash or
silence is a failure (30 s watchdog). A `pass` test must also leave every serial port but its own empty.

`tests.list` is the list. A row may be **`xfail`**: a documented runtime defect
that must keep failing *in exactly the documented way* (`observe` is a regexp
that must match QEMU's trace or the serial output) and that turns the build red
if it starts to pass. See the list's header, and RTS-PRODUCTION.md A4 for which
rows are xfail today and why.

## Negative: builds that must fail

`negative/cases.list`, run by `negative/run_negative.sh` in a scratch copy of
the tree (nothing committed is touched). Every case names the diagnostic that
must appear on an error line; a build that succeeds, or fails with another
message, fails the case. Covers the `light` floor rejecting tasking constructs
and every `pragma Compile_Time_Error` in `mpfs_config_checks.ads`, on each of
the three leaves where reachable. Each leaf group starts with a *control* that
must build.

## Adding a test

1. A directory under `tests/` with `alire.toml` (pin `../../<leaf>`), a `.gpr`
   whose `Source_Dirs` includes `../common`, and a main that calls
   `Test_Report.Start`, `Check` and `Finish`.
2. A row in `tests.list`. The harness must be able to fail: break the test on
   purpose and watch `make test` go red before you trust it.
3. Never add a test application to the Makefile's `APPS` -- that would put it in
   `metrics.golden`.
