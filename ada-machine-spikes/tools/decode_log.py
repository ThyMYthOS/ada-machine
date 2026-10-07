#!/usr/bin/env python3
"""Decode the raw UART stream of an Ada Machine spike (Python 3, stdlib only).

Usage:  decode_log.py [--quiet] [FILE | -]      (default: stdin)

The stream mixes two things, both written by firmware:

1. Deferred-format log records (README 14.2), exactly as
   Machine.Blocking.Log_Sink.Emit writes them -- 7 bytes, no framing:

       Level'Pos (1 B) | Event_Id big-endian (2 B) | Arg big-endian (4 B)

   Level'Pos: 0 Error, 1 Warning, 2 Info, 3 Debug, 4 Trace.
   The library emits ids + scalars only; this tool does the rendering.

2. In test-mode builds (ADA_MACHINE_TEST_MODE=on, TODO.md #15 Step 2) one
   final ASCII verdict line, written directly by the application:

       ADA-MACHINE-TEST: PASS\\r\\n
       ADA-MACHINE-TEST: FAIL <reason-code>\\r\\n

Resynchronisation: a record's first byte is a Level (0..4), the verdict
starts with 'A' (0x41), so at every record boundary the two cannot be
confused. A byte that is neither is reported as stray and skipped (a
stream that starts mid-record, UART noise).

Exit status: 0 verdict PASS, 1 verdict FAIL, 2 no (complete) verdict found.

RENDERING TABLE: EVENTS below is the seed of README 19 open question 9
(event interning / host-side rendering). It is hand-maintained from the
Event_Id constants in the crates that emit them (bme280.adb Ev_*,
spike boards' Ev_Measured); unknown ids are shown numerically. Add an entry
per new event: (name, argument renderer).
"""
import sys

LEVELS = ["ERROR", "WARNING", "INFO", "DEBUG", "TRACE"]
RECORD_LEN = 7
VERDICT_PREFIX = b"ADA-MACHINE-TEST:"


def _signed32(arg):
    return arg - (1 << 32) if arg & 0x8000_0000 else arg


def _hex(arg):
    return "arg=0x%08x" % arg


EVENTS = {
    # bme280.adb: Ev_Wrong_Id (Arg = chip id read; 0x60 is a real BME280)
    0x0001: ("BME280.Wrong_Chip_Id",
             lambda a: "chip_id=0x%02x" % (a & 0xFF)),
    0x0002: ("BME280.Bus_Fault", lambda a: "" if a == 0 else _hex(a)),
    0x0003: ("BME280.Timed_Out", lambda a: "" if a == 0 else _hex(a)),
    # board.ads / avr_board.ads: Ev_Measured (Arg = 1/100 degC, two's
    # complement in 32 bits for negative temperatures)
    0x1000: ("Measured",
             lambda a: "temperature=%.2f degC" % (_signed32(a) / 100.0)),
}


def decode(data):
    """Return (lines, verdict) where verdict is None, 'PASS' or 'FAIL <code>'
    (a FAIL line without code is 'FAIL ')."""
    lines = []
    verdict = None
    i = 0
    n = len(data)
    while i < n:
        b = data[i]
        if data.startswith(VERDICT_PREFIX, i):
            end = data.find(b"\r\n", i)
            if end < 0:
                lines.append("TRUNCATED verdict line: %r" % data[i:])
                break
            text = data[i:end].decode("ascii", "replace")
            lines.append(text)
            what = text[len(VERDICT_PREFIX):].strip()
            if what == "PASS":
                verdict = "PASS"
            elif what.startswith("FAIL"):
                verdict = "FAIL " + what[4:].strip()
            else:
                lines.append("UNRECOGNISED verdict: %r" % text)
                verdict = None
            i = end + 2
        elif b < len(LEVELS):
            if i + RECORD_LEN > n:
                lines.append("TRUNCATED record at offset %d (%d of %d bytes)"
                             % (i, n - i, RECORD_LEN))
                break
            ev = (data[i + 1] << 8) | data[i + 2]
            arg = int.from_bytes(data[i + 3:i + 7], "big")
            name, render = EVENTS.get(ev, ("event 0x%04x" % ev, _hex))
            detail = render(arg)
            lines.append("[%-7s] %s%s" % (LEVELS[b], name,
                                          " " + detail if detail else ""))
            i += RECORD_LEN
        else:
            lines.append("stray byte 0x%02x at offset %d" % (b, i))
            i += 1
    return lines, verdict


def main(argv):
    args = [a for a in argv if a != "--quiet"]
    quiet = len(args) != len(argv)
    if len(args) > 1 or (args and args[0] in ("-h", "--help")):
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        return 2
    if not args or args[0] == "-":
        data = sys.stdin.buffer.read()
    else:
        with open(args[0], "rb") as f:
            data = f.read()
    lines, verdict = decode(data)
    if not quiet:
        for line in lines:
            print(line)
    if verdict == "PASS":
        return 0
    if verdict is not None:
        return 1
    if not quiet:
        print("no ADA-MACHINE-TEST verdict found", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
