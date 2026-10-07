#!/usr/bin/env python3
"""Self-test for decode_log.py, no hardware needed.

Usage: test_decode_log.py <path to host_test/bin/dump_log_stream>

dump_log_stream (Ada) writes the real bytes Machine.Blocking.Log_Sink and
the test-mode runner (test_support/common/spike_test_runner) produce over a
mock UART; this script decodes them and checks the rendering and exit codes.
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DECODER = os.path.join(HERE, "decode_log.py")
failures = 0


def check(name, ok, detail=""):
    global failures
    print(("PASS  " if ok else "FAIL  ") + name + (": " + detail if detail
                                                    and not ok else ""))
    if not ok:
        failures += 1


def run(path=None, data=None):
    p = subprocess.run([sys.executable, DECODER] + ([path] if path else ["-"]),
                       input=data, capture_output=True)
    return p.returncode, p.stdout.decode(), p.stderr.decode()


def main():
    exe = sys.argv[1]
    with tempfile.TemporaryDirectory() as tmp:
        ok_file = os.path.join(tmp, "pass.bin")
        bad_file = os.path.join(tmp, "fail.bin")
        subprocess.run([exe, ok_file, bad_file], check=True)

        rc, out, _ = run(ok_file)
        check("pass stream: exit 0", rc == 0, "rc=%d\n%s" % (rc, out))
        check("pass stream: verdict line shown",
              "ADA-MACHINE-TEST: PASS" in out, out)
        check("pass stream: error-level unknown event numeric",
              "[ERROR  ] event 0x7fff arg=0xdeadbeef" in out, out)
        check("pass stream: negative temperature",
              "temperature=-5.23 degC" in out, out)
        check("pass stream: 3 measured records from the runner",
              out.count("temperature=25.08 degC") == 3, out)
        check("pass stream: nothing stray", "stray" not in out
              and "TRUNCATED" not in out, out)

        rc, out, _ = run(bad_file)
        check("fail stream: exit 1", rc == 1, "rc=%d\n%s" % (rc, out))
        check("fail stream: driver event named",
              "[WARNING] BME280.Wrong_Chip_Id chip_id=0x00" in out, out)
        check("fail stream: reason code",
              "ADA-MACHINE-TEST: FAIL INIT-WRONG_CHIP_ID" in out, out)

        # Events only (run died before the verdict): exit 2.
        with open(ok_file, "rb") as f:
            raw = f.read()
        cut = raw.index(b"ADA-MACHINE-TEST")
        rc, out, err = run(data=raw[:cut])
        check("no verdict: exit 2", rc == 2, "rc=%d" % rc)
        check("no verdict: events still decoded", "Measured" in out, out)

        # Verdict cut mid-line: not a verdict.
        rc, out, _ = run(data=raw[:-3])
        check("truncated verdict: exit 2", rc == 2, "rc=%d\n%s" % (rc, out))
        check("truncated verdict: reported", "TRUNCATED verdict" in out, out)

        # Stream starting mid-record resynchronises on the verdict.
        rc, out, _ = run(data=b"\x99\xfe" + raw)
        check("garbage prefix: still PASS", rc == 0, "rc=%d\n%s" % (rc, out))
        check("garbage prefix: stray bytes reported",
              out.count("stray byte") == 2, out)

        rc, _, _ = run(data=b"")
        check("empty input: exit 2", rc == 2, "rc=%d" % rc)

    print("decode_log self-test: %s" % ("FAILED" if failures else "OK"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
