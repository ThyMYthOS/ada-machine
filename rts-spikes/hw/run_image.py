#!/usr/bin/env python3
"""Load an ELF onto one hart of an Icicle Kit over JTAG, run it, capture the four UARTs, report the first trap.

    run_image.py ELF HART [--secs N] [--no-uart] [--div D]

Needs OpenOCD running (start_openocd.sh). The board is expected in boot mode 0 (idle, no HSS).
That boot stage is what the runtime's console driver assumes exists but nothing provides, so unless
--no-uart is given this script stands in for it: it clocks and releases MMUART0..4 and programs
divisor D (22 gives 115200 at the ~40 MHz APB clock of an unconfigured MSS, measured).

The trap recorder (trap.S) lives at 0x08100000, above any image here, and logs the first trap.
Segments load with 64-bit stores in whole 64-byte lines: LIM is ECC memory, uninitialised at
power-up, and fetching a line that was only partly written faults (mcause 1).
"""
import argparse, glob, os, re, struct, subprocess, sys, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ocd import OCD, Serial

HERE = os.path.dirname(os.path.abspath(__file__))
TC = sorted(glob.glob(os.path.expanduser("~/.local/share/alire/toolchains/gnat_riscv64_elf_*/bin/")))[-1]
SYSREG = 0x20002000
UARTS = (0x20000000, 0x20100000, 0x20102000, 0x20104000, 0x20106000)
REC = 0x08101000

ap = argparse.ArgumentParser()
ap.add_argument("elf")
ap.add_argument("hart", type=int)
ap.add_argument("--secs", type=float, default=4)
ap.add_argument("--no-uart", action="store_true")
ap.add_argument("--div", type=int, default=22)
a = ap.parse_args()

tmp = tempfile.mkdtemp()
elf = os.path.join(tmp, "trap.elf")
subprocess.run([TC + "riscv64-elf-gcc", "-march=rv64imac_zicsr", "-mabi=lp64", "-nostdlib", "-Wl,-e,_trap",
                "-Wl,-Ttext=0x08100000", "-o", elf, os.path.join(HERE, "trap.S")], check=True)
subprocess.run([TC + "riscv64-elf-objcopy", "-O", "binary", elf, os.path.join(tmp, "trap.bin")], check=True)

img = open(a.elf, "rb").read()
entry, phoff = struct.unpack_from("<QQ", img, 0x18)[0], struct.unpack_from("<Q", img, 0x20)[0]
phentsize, phnum = struct.unpack_from("<HH", img, 0x36)
segs = []
for i in range(phnum):
    ptype, _, off, _, paddr, filesz, _, _ = struct.unpack_from("<IIQQQQQQ", img, phoff + i * phentsize)
    if ptype == 1 and filesz:
        segs.append((paddr, img[off:off + filesz]))


def load(o, name, addr, data):
    path = os.path.join(tmp, name)
    open(path, "wb").write(data)
    o.cmd(f"load_image {path} 0x{addr:x} bin")
    print(f"loaded {len(data):#x} bytes at {addr:#x}")


def line_runs(segs):
    """Merge segments into runs of whole 64-byte lines, zero-filled, so no cache line is half-written."""
    mem = {}
    for paddr, data in segs:
        for k, byte in enumerate(data):
            mem[paddr + k] = byte
    lines = sorted({addr // 64 for addr in mem})
    runs = []
    for ln in lines:
        if runs and runs[-1][1] == ln:
            runs[-1][1] = ln + 1
        else:
            runs.append([ln, ln + 1])
    return [(lo * 64, bytes(mem.get(lo * 64 + k, 0) for k in range((hi - lo) * 64))) for lo, hi in runs]


o, s = OCD(), Serial()
o.hart(a.hart)
o.cmd("halt")
if not a.no_uart:
    o.wr32(SYSREG + 0x84, o.rd32(SYSREG + 0x84) | (0x1F << 5))
    o.wr32(SYSREG + 0x88, o.rd32(SYSREG + 0x88) & ~(0x1F << 5))
    for b in UARTS:
        o.cmd("mww 0x%x 0x83; mww 0x%x %d; mww 0x%x 0; mww 0x%x 3; mww 0x%x 7" % (b + 0xC, b, a.div, b + 4, b + 0xC, b + 8))
for i in range(8):
    o.cmd(f"mwd 0x{REC + 8 * i:x} 0")
load(o, "trap.bin", 0x08100000, open(os.path.join(tmp, "trap.bin"), "rb").read())
for n, (paddr, data) in enumerate(line_runs(segs)):
    load(o, f"seg{n}.bin", paddr, data)
o.cmd("reg mcause 0; reg mepc 0; reg mtval 0; reg mtvec 0x08100000")
o.cmd(f"reg pc 0x{entry:x}")
print(f"hart {a.hart}: entry {entry:#x}, running {a.secs}s")
s.pump(0.2)
o.cmd("resume")
s.pump(a.secs)
o.cmd("halt")
pc, mcause, mepc, mtval = (o.reg(r) for r in ("pc", "mcause", "mepc", "mtval"))
rec = [o.rd64(REC + 8 * i) for i in range(4)]
print(f"after: pc={pc:#x} mcause={mcause:#x} mepc={mepc:#x} mtval={mtval:#x}")
print("first trap:", "none" if rec[0] == 0 else f"mcause={rec[1]:#x} mepc={rec[2]:#x} mtval={rec[3]:#x}")
for i in range(4):
    if s.data[i]:
        print(f"MMUART{i} (if0{i}): {s.data[i]!r}")
if not any(s.data.values()):
    print("no serial output on any port")
