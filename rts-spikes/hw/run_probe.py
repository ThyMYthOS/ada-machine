#!/usr/bin/env python3
"""Assemble a probe (probe_*.S), run it on one hart and print the result words at 0x08102000.

    run_probe.py probe_irq.S 1 [--words N]

Probes are linked at 0x08104000 and signal completion with a non-zero word in their result block.
The board must be in boot mode 0 with OpenOCD running (start_openocd.sh).
"""
import argparse, glob, os, subprocess, sys, tempfile, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ocd import OCD

HERE = os.path.dirname(os.path.abspath(__file__))
TC = sorted(glob.glob(os.path.expanduser("~/.local/share/alire/toolchains/gnat_riscv64_elf_*/bin/")))[-1]

ap = argparse.ArgumentParser()
ap.add_argument("source")
ap.add_argument("hart", type=int)
ap.add_argument("--words", type=int, default=8)
ap.add_argument("--secs", type=float, default=2)
a = ap.parse_args()

tmp = tempfile.mkdtemp()
elf, binf = os.path.join(tmp, "p.elf"), os.path.join(tmp, "p.bin")
subprocess.run([TC + "riscv64-elf-gcc", "-march=rv64imac_zicsr", "-mabi=lp64", "-nostdlib", "-Wl,-e,_start",
                "-Wl,-Ttext=0x08104000", "-o", elf, os.path.join(HERE, a.source)], check=True)
subprocess.run([TC + "riscv64-elf-objcopy", "-O", "binary", elf, binf], check=True)
data = open(binf, "rb").read()
open(binf, "wb").write(data + bytes(-len(data) % 64))

o = OCD()
o.hart(a.hart)
o.cmd("halt")
o.cmd("riscv set_prefer_sba off")
for i in range(a.words):
    o.cmd(f"mwd 0x{0x08102000 + 8 * i:x} 0")
o.cmd(f"load_image {binf} 0x08104000 bin")
o.cmd("reg mcause 0; reg mie 0; reg pc 0x08104000")
o.cmd("resume")
time.sleep(a.secs)
o.cmd("halt")
for i in range(a.words):
    print(f"[{8 * i:2d}] = {o.rd64(0x08102000 + 8 * i):#x}")
