#!/usr/bin/env python3
"""fetched-check.py -- RTS-PRODUCTION.md B1's exit criterion, as a command.

    python3 fetched-check.py [--work DIR] [--qemu] [LEAF ...]

Proves that a leaf runtime builds when it is CONSUMED, not when it is built in
place. For each LEAF (default: all four) it

  1. packs the leaf and the tier crates it path-pins into release tarballs,
  2. publishes them to a throwaway, file-based Alire index (index/, below),
  3. copies the leaf's in-tree application into a different directory with its
     [[pins]] AND its [[depends-on]] removed, then `alr with`s the leaf from
     the throwaway index -- no pin anywhere, no sibling directory in reach,
  4. `alr build`s it, so Alire fetches every crate into its own build cache,
     runs their actions, and gprbuild compiles the runtime and links the image,
  5. checks that what it got is what it claims to be (see check_* below).

ISOLATION. Nothing here touches the user's Alire configuration, index list or
cache. Everything lives under --work (default: a fresh temp dir, printed, and
kept -- delete it yourself):

    settings/   alr -s: settings.toml + a private copy of the community index
    cache/      cache.dir: releases/ and builds/ -- where the fetched crates land
    dist/       the release tarballs          index/   the throwaway index
    app/        the consuming applications, one directory per leaf

The one thing shared with the real installation is the compiler directory
(`toolchain.dir`): the cross compilers are ~1.5 GB and are pinned to exactly
15.1.2, and this check is about the runtime sources, not about downloading GNAT.
If the compiler is not there yet, Alire installs it there -- which is what
`make toolchains` would have done.

Needs: alr, python3, the populated tier-1 sources (`make populate`).
POSIX and Windows-agnostic apart from running `sh` for the leaf's own action.
"""
import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

SPIKES = os.path.dirname(os.path.abspath(__file__))

#  leaf -> the in-tree application that consumes it (and its image name)
LEAVES = {
    "light_mpfs": "hello_mpfs",
    "light_tasking_mpfs": "tasking_mpfs",
    "embedded_mpfs": "embedded_app",
    "light_tasking_pico": "hello_rp2040",
}
#  Only the applications that print under QEMU can be smoke-tested.
QEMU_EXPECT = {"hello_mpfs": "Hello from PolarFire SoC"}

VERSION_RE = re.compile(r'^version\s*=\s*"([^"]+)"', re.M)


def die(msg):
    print("fetched-check: FAIL: " + msg, file=sys.stderr)
    sys.exit(1)


def say(msg):
    print("==> " + msg, flush=True)


def run(argv, cwd=None, env=None, check=True):
    """Run a command, echo it, stream its output, die on failure."""
    print("    $ " + " ".join(argv), flush=True)
    r = subprocess.run(argv, cwd=cwd, env=env)
    if check and r.returncode != 0:
        die("command failed (exit %d): %s" % (r.returncode, " ".join(argv)))
    return r.returncode


def capture(argv, cwd=None, env=None):
    r = subprocess.run(argv, cwd=cwd, env=env, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, universal_newlines=True)
    return r.returncode, r.stdout


# ---------------------------------------------------------------- manifests --

def read(path):
    with open(path) as f:
        return f.read()


def strip_tables(text, header):
    """Remove every `[[header]]` / `[header]` table (up to the next table header)."""
    pat = r'^\[\[?%s\]\]?[ \t]*$.*?(?=^\[|\Z)' % re.escape(header)
    return re.sub(pat, "", text, flags=re.S | re.M)


def pinned_crates(manifest_text):
    """Crate names under [[pins]] -- the source-only tier crates of a leaf."""
    m = re.search(r'^\[\[pins\]\][ \t]*$(.*?)(?=^\[|\Z)', manifest_text, re.S | re.M)
    if not m:
        return []
    return re.findall(r'^([A-Za-z0-9_]+)[ \t]*=[ \t]*\{', m.group(1), re.M)


# ----------------------------------------------------------------- packing --

def skip_member(rel):
    """What a released tarball must not carry: this machine's build output and
    Alire's per-workspace state, none of which belongs to the crate. That
    includes a generated ada_source_path: a stale one full of this machine's
    paths must never be mistaken for the real thing."""
    parts = rel.split("/")
    top = parts[0]
    if top in ("alire", "config", "gnat_config", "bin", "ada_source_path") \
            or top.startswith(("obj", "adalib")):
        return True
    return parts[-1] == ".DS_Store" or parts[-1].endswith((".o", ".ali"))


def pack(crate, dist, index):
    src = os.path.join(SPIKES, crate)
    manifest = read(os.path.join(src, "alire.toml"))
    version = VERSION_RE.search(manifest).group(1)
    top = "%s-%s" % (crate, version)
    tgz = os.path.join(dist, top + ".tgz")

    with tarfile.open(tgz, "w:gz") as tf:
        for root, dirs, files in os.walk(src):
            rel_root = os.path.relpath(root, src)
            dirs[:] = sorted(d for d in dirs
                             if not skip_member(os.path.normpath(os.path.join(rel_root, d))))
            for name in sorted(files):
                rel = os.path.normpath(os.path.join(rel_root, name))
                if skip_member(rel):
                    continue
                tf.add(os.path.join(root, name), arcname=top + "/" + rel, recursive=False)
    with open(tgz, "rb") as f:
        digest = hashlib.sha512(f.read()).hexdigest()

    #  The index manifest is the crate's own manifest minus the in-tree-only
    #  [[pins]] (a pin is a development convenience and has no business in a
    #  released manifest), plus the origin.
    released = strip_tables(manifest, "pins")
    released += '\n[origin]\nurl = "file://%s"\nhashes = ["sha512:%s"]\n' % (tgz, digest)
    d = os.path.join(index, "index", crate[:2], crate)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "%s-%s.toml" % (crate, version)), "w") as f:
        f.write(released)
    return version, os.path.getsize(tgz)


# ------------------------------------------------------------------- alr ----

class Alr:
    def __init__(self, settings):
        self.base = ["alr", "-s", settings, "-n"]
        self.env = dict(os.environ)

    def run(self, args, cwd=None, check=True):
        return run(self.base + args, cwd=cwd, env=self.env, check=check)

    def capture(self, args, cwd=None):
        return capture(self.base + args, cwd=cwd, env=self.env)


def global_setting(key):
    """Read (never write) a setting from the user's own configuration."""
    rc, out = capture(["alr", "settings", "--global", "--get", key])
    return out.strip() if rc == 0 and out.strip() else None


def alire_cache_toolchains():
    rc, out = capture(["alr", "version"])
    m = re.search(r'^cache folder:\s*(\S.*)$', out, re.M)
    base = m.group(1).strip() if m else os.path.expanduser("~/.local/share/alire")
    return os.environ.get("ALIRE_TC_DIR") or os.path.join(base, "toolchains")


def write_settings(work, tc_dir):
    settings = os.path.join(work, "settings")
    os.makedirs(settings, exist_ok=True)
    lines = [
        '[cache]', 'dir = "%s"' % os.path.join(work, "cache"),
        '[index]', 'auto_update = 0', 'auto_update_asked = true',
        '[toolchain]', 'assistant = false', 'dir = "%s"' % tc_dir,
        '[toolchain.external]', 'gnat = false', 'gprbuild = false',
    ]
    #  The tools the user's own Alire builds with -- gprbuild must come from
    #  somewhere, and which gnat/gprbuild is a property of the machine.
    use = [(k, global_setting("toolchain.use." + k)) for k in ("gnat", "gprbuild")]
    use = [(k, v) for k, v in use if v]
    if use:
        lines.append('[toolchain.use]')
        lines += ['%s = "%s"' % (k, v) for k, v in use]
    lines += ['[user]', 'email = "fetched-check@example.invalid"', 'name = "fetched-check"']
    with open(os.path.join(settings, "settings.toml"), "w") as f:
        f.write("\n".join(lines) + "\n")
    return settings


def seed_community_index(settings):
    """Give the private settings dir the community index (the cross compilers
    are resolved from it). Copy the user's, read-only, when there is one --
    no network; otherwise let Alire clone its own."""
    rc, out = capture(["alr", "version"])
    m = re.search(r'^indexes folder:\s*(\S.*)$', out, re.M)
    src = os.path.join(m.group(1).strip(), "community") if m else None
    dst = os.path.join(settings, "indexes", "community")
    if src and os.path.isdir(src):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copytree(src, dst)
        return True
    return False


# ----------------------------------------------------------------- checks ----

def tool(tc_dir, name):
    for d in sorted(os.listdir(tc_dir)):
        p = os.path.join(tc_dir, d, "bin", name)
        if os.path.exists(p):
            return p
    return None


def check_built(work, leaf, app, appdir, tc_dir):
    """Everything claimed by the exit criterion, asserted rather than assumed."""
    cache_builds = os.path.realpath(os.path.join(work, "cache", "builds"))
    problems = []

    #  (a) the consumer carries no pin and names no path.
    manifest = read(os.path.join(appdir, "alire.toml"))
    if "[[pins]]" in manifest:
        problems.append("the consuming application still has a [[pins]] table")
    if re.search(r'\bpath\s*=', manifest):
        problems.append("the consuming application's manifest contains a path =")

    #  (b) the leaf was fetched into the isolated build cache, not found in place.
    leaf_dirs = [os.path.join(cache_builds, d, h)
                 for d in os.listdir(cache_builds) if d.startswith(leaf + "_")
                 for h in os.listdir(os.path.join(cache_builds, d))]
    if len(leaf_dirs) != 1:
        problems.append("expected exactly one fetched %s build, found %r" % (leaf, leaf_dirs))
        return problems
    leaf_dir = leaf_dirs[0]

    #  (c) the generated ada_source_path: complete, absolute where it must be,
    #      and every foreign entry inside the isolated cache -- i.e. not a
    #      relative path that happens to reach a sibling of the source tree.
    path_file = os.path.join(leaf_dir, "ada_source_path")
    if not os.path.isfile(path_file):
        problems.append("%s was not generated" % path_file)
        return problems
    entries = read(path_file).splitlines()
    print("    generated ada_source_path (%d entries):" % len(entries))
    for e in entries:
        print("      " + e)
    for e in entries:
        if e.startswith("/"):
            if not os.path.realpath(e).startswith(cache_builds + os.sep):
                problems.append("entry outside the isolated cache: " + e)
        elif ".." in e.split("/"):
            problems.append("relative entry climbing out of the crate: " + e)
        if not os.path.isdir(e if e.startswith("/") else os.path.join(leaf_dir, e)):
            problems.append("entry is not a directory: " + e)

    #  (d) the image exists and links as the in-tree one does.
    exe = os.path.join(appdir, "bin", app)
    if not os.path.isfile(exe):
        problems.append("no image at " + exe)
        return problems
    size_tool = tool(tc_dir, "arm-eabi-size" if leaf.endswith("pico") else "riscv64-elf-size")
    ref = os.path.join(SPIKES, app, "bin", app)
    if size_tool:
        _, got = capture([size_tool, exe])
        print("    fetched image: " + got.splitlines()[-1].strip())
        if os.path.isfile(ref):
            _, want = capture([size_tool, ref])
            same = got.splitlines()[-1].split()[:4] == want.splitlines()[-1].split()[:4]
            print("    in-tree image: %s  -> text/data/bss %s" %
                  (want.splitlines()[-1].strip(), "IDENTICAL" if same else "DIFFERENT"))
            if not same:
                problems.append("fetched image differs in size from the in-tree build "
                                "(not necessarily wrong -- the configuration may differ -- but look)")
    return problems


def boot(appdir_parent, app, exp):
    sh = os.path.join(SPIKES, "smoke.sh")
    ef = os.path.join(appdir_parent, "smoke.expected")
    with open(ef, "w") as f:
        f.write("app\tstring\n%s\t%s\n" % (app, exp))
    env = dict(os.environ, SMOKE_EXPECTED=ef)
    return run(["sh", sh], cwd=appdir_parent, env=env, check=False) == 0


# ------------------------------------------------------------------ main -----

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("leaves", nargs="*", default=list(LEAVES), metavar="LEAF")
    ap.add_argument("--work", help="scratch directory (default: a new temp dir)")
    ap.add_argument("--qemu", action="store_true",
                    help="also boot the fetched light_mpfs image under QEMU (needs QEMU >= 10.1)")
    args = ap.parse_args()
    for l in args.leaves:
        if l not in LEAVES:
            die("unknown leaf %r (known: %s)" % (l, ", ".join(LEAVES)))

    if not shutil.which("alr"):
        die("alr is not on PATH")
    if not os.path.isdir(os.path.join(SPIKES, "rts_sources_gcc15", "libgnat")):
        die("tier 1 is not populated -- run `make populate` first")

    work = os.path.abspath(args.work) if args.work else tempfile.mkdtemp(prefix="fetched-check.")
    os.makedirs(work, exist_ok=True)
    if os.listdir(work):
        die("%s is not empty; give --work an empty or new directory" % work)
    say("scratch directory: " + work + "  (kept; delete it yourself)")

    tc_dir = alire_cache_toolchains()
    settings = write_settings(work, tc_dir)
    dist, index = (os.path.join(work, "dist"), os.path.join(work, "index"))
    os.makedirs(dist)
    os.makedirs(os.path.join(index, "index"))
    with open(os.path.join(index, "index", "index.toml"), "w") as f:
        f.write('version = "1.4.0"\n')

    crates = []
    for leaf in args.leaves:
        for c in [leaf] + pinned_crates(read(os.path.join(SPIKES, leaf, "alire.toml"))):
            if c not in crates:
                crates.append(c)
    say("publishing %d crates to the throwaway index" % len(crates))
    for c in crates:
        v, n = pack(c, dist, index)
        print("    %-22s %s  %8d bytes" % (c, v, n))

    alr = Alr(settings)
    if not seed_community_index(settings):
        alr.run(["index", "--add", "git+https://github.com/alire-project/alire-index#stable-1.4.0",
                 "--name", "community"])
    alr.run(["index", "--add", "file://" + index, "--name", "scratch", "--before", "community"])

    failures = []
    for leaf in args.leaves:
        app = LEAVES[leaf]
        say("%s: consumed by a copy of %s, no pins" % (leaf, app))
        appdir = os.path.join(work, "app", app)
        os.makedirs(os.path.dirname(appdir), exist_ok=True)
        shutil.copytree(os.path.join(SPIKES, app), appdir,
                        ignore=shutil.ignore_patterns("alire", "config", "bin", "obj", ".DS_Store"))
        m = strip_tables(strip_tables(read(os.path.join(appdir, "alire.toml")), "pins"), "depends-on")
        with open(os.path.join(appdir, "alire.toml"), "w") as f:
            f.write(m)
        alr.run(["with", leaf], cwd=appdir)
        #  gprbuild lists every unit it compiles (~500 lines per runtime); keep that
        #  in a log and show only the tail when the build fails.
        log = os.path.join(work, "logs", leaf + ".build.log")
        os.makedirs(os.path.dirname(log), exist_ok=True)
        print("    $ alr build   (full output: %s)" % log, flush=True)
        rc, out = alr.capture(["build"], cwd=appdir)
        with open(log, "w") as f:
            f.write(out)
        if rc != 0:
            print("\n".join(out.splitlines()[-40:]), file=sys.stderr)
            failures.append("%s: alr build failed (exit %d); see %s" % (leaf, rc, log))
            continue
        print("\n".join(l for l in out.splitlines() if l.startswith(("Note:", "Success:"))))
        problems = check_built(work, leaf, app, appdir, tc_dir)
        #  Idempotence: the actions run again on every build and must leave an
        #  unchanged ada_source_path alone (not even its mtime). NOT checked by
        #  "nothing recompiled": gprbuild 26 recompiles every runtime unit on every
        #  build here regardless ("GNAT version changed: ALI version = GNAT 15;
        #  expected version = GNAT 15.0", measured, unrelated to this mechanism).
        leaf_dir = [os.path.join(r, h) for r in
                    [os.path.join(work, "cache", "builds", d)
                     for d in os.listdir(os.path.join(work, "cache", "builds")) if d.startswith(leaf + "_")]
                    for h in os.listdir(r)][0]
        asp = os.path.join(leaf_dir, "ada_source_path")
        before = (read(asp), os.stat(asp).st_mtime_ns)
        rc, out = alr.capture(["build"], cwd=appdir)
        after = (read(asp), os.stat(asp).st_mtime_ns)
        if rc != 0 or "Running pre-build actions for %s" % leaf not in out:
            problems.append("a second `alr build` failed or did not run the pre-build action (exit %d)" % rc)
        elif before != after:
            problems.append("a second `alr build` rewrote an unchanged ada_source_path")
        else:
            print("    second `alr build`: pre-build action ran, ada_source_path untouched")
        if args.qemu and app in QEMU_EXPECT:
            say("%s: booting the fetched image under QEMU" % leaf)
            if not boot(os.path.dirname(appdir), app, QEMU_EXPECT[app]):
                problems.append("QEMU boot did not print %r" % QEMU_EXPECT[app])
        for p in problems:
            failures.append("%s: %s" % (leaf, p))
        print("    %s: %s" % (leaf, "FAILED" if problems else "OK"))

    print()
    if failures:
        for f in failures:
            print("fetched-check FAILED: " + f, file=sys.stderr)
        sys.exit(1)
    print("fetched-check OK: %s -- each built and linked from a fetched, unpinned dependency "
          "closure (work dir %s)" % (", ".join(args.leaves), work))


if __name__ == "__main__":
    main()
