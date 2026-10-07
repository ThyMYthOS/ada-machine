#!/usr/bin/env python3
"""Judge a wokwi-cli serial capture of spike1_pico's test-mode ELF.

Usage: check_capture.py CAPTURE EXPECTED-VERDICT   ("PASS" or "FAIL <code>")

The capture mixes binary deferred-format log records with the ASCII verdict
line (see tools/decode_log.py), which it renders. It then checks

  * the verdict equals EXPECTED-VERDICT, and
  * PASS: three `Measured temperature=25.08 degC` events (the compensated
    result of the fixed BME280 sample, same as sim/avr);
    FAIL: the `BME280.Wrong_Chip_Id chip_id=0x58` warning before the verdict.

wokwi-cli's serial log may not be byte-exact: if it text-decodes the stream,
bytes >= 0x80 (e.g. 0xCC of the argument 2508 = 0x09CC) become U+FFFD
(EF BF BD) and the event arguments cannot be recovered. That is detected: the
verdict check stays strict, the event checks are then skipped with a warning
that names the limitation, rather than failing on data the transport lost.

Exit status: 0 all checks passed, 1 a check failed.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "..", "tools"))
import decode_log  # noqa: E402

REPLACEMENT = b"\xef\xbf\xbd"


def main(argv):
    if len(argv) != 2:
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        return 1
    capture, expected = argv
    with open(capture, "rb") as f:
        data = f.read()
    lines, verdict = decode_log.decode(data)
    for line in lines:
        print(line)

    ok = True
    if verdict != expected:
        print("check_capture: verdict %r, expected %r" % (verdict, expected))
        ok = False

    lossy = REPLACEMENT in data
    want_event = ("Measured temperature=25.08 degC" if expected == "PASS"
                  else "BME280.Wrong_Chip_Id chip_id=0x58")
    want_count = 3 if expected == "PASS" else 1
    got = sum(1 for line in lines if line.endswith(want_event))
    if got == want_count:
        pass
    elif lossy:
        print("check_capture: WARNING: the capture is not byte-exact "
              "(U+FFFD found: the CLI text-decoded the serial stream); "
              "event check '%s' x%d skipped, saw %d" %
              (want_event, want_count, got))
    else:
        print("check_capture: expected %d x '%s', saw %d" %
              (want_count, want_event, got))
        ok = False

    print("check_capture: %s (%s)" % ("OK" if ok else "FAILED", capture))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
