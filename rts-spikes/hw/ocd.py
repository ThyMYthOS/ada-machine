"""OpenOCD telnet client and CP2108 serial capture for the Icicle Kit (RTS-PRODUCTION.md A5)."""
import glob, os, re, select, socket, termios, time

HART = {0: "mpfs.hart0_e51"} | {n: f"mpfs.hart{n}_u54_{n}" for n in range(1, 5)}


def serial_path(n):
    """/dev/serial/by-id path of CP2108 interface n; if0N is MMUARTN (measured, A5)."""
    found = glob.glob(f"/dev/serial/by-id/usb-Silicon_Labs_CP2108_*-if0{n}-port0")
    if not found:
        raise SystemExit(f"no CP2108 interface {n} under /dev/serial/by-id")
    return found[0]


class OCD:
    # Each command costs ~0.35 s of JTAG round trip; batch with "; " or Tcl loops.
    def __init__(self, port=4444):
        self.s = socket.create_connection(("localhost", port), timeout=30)
        self._read()

    def _read(self):
        buf = b""
        while not buf.endswith(b"> "):
            buf += self.s.recv(65536)
        return re.sub(rb"[\xff][\xfb-\xfe].", b"", buf).decode("latin1").replace("\r", "")

    def cmd(self, c):
        self.s.sendall(c.encode() + b"\n")
        lines = self._read().split("\n")
        return "\n".join(lines[1:-1]).strip() if len(lines) > 1 else ""

    def hart(self, n):
        self.cmd(f"targets {HART[n]}")

    def reg(self, name):
        return int(re.search(r"0x([0-9a-fA-F]+)", self.cmd(f"reg {name}")).group(1), 16)

    def rd32(self, addr):
        return int(self.cmd(f"mdw 0x{addr:x}").split()[1], 16)

    def rd64(self, addr):
        return int(self.cmd(f"mdd 0x{addr:x}").split()[1], 16)

    def wr32(self, addr, val):
        self.cmd(f"mww 0x{addr:x} 0x{val:x}")


class Serial:
    """Open all four CP2108 ports at 115200 8N1 and collect what arrives."""

    def __init__(self):
        self.fds = {}
        for i in range(4):
            fd = os.open(serial_path(i), os.O_RDONLY | os.O_NONBLOCK | os.O_NOCTTY)
            a = termios.tcgetattr(fd)
            a[0] = a[1] = a[3] = 0
            a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
            a[4] = a[5] = termios.B115200
            a[6][termios.VMIN] = 0
            a[6][termios.VTIME] = 0
            termios.tcsetattr(fd, termios.TCSANOW, a)
            termios.tcflush(fd, termios.TCIFLUSH)
            self.fds[i] = fd
        self.data = {i: b"" for i in range(4)}

    def pump(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            ready, _, _ = select.select(list(self.fds.values()), [], [], 0.05)
            for i, fd in self.fds.items():
                if fd in ready:
                    self.data[i] += os.read(fd, 4096)
