#!/usr/bin/env python3
"""Correct a confirmed svd2ada 0.1.0 code-generation bug, run as a
deterministic step of generate_pac.sh (never a one-off hand-edit of the
generated files -- see alire.toml).

The bug: Find_Common_Types/Similar_Type (descriptors-register.adb) decides
two no-field, same-prefix registers in one peripheral "share a type" by
comparing only their field lists and Dim, never their declared <size>.
Two registers that are genuinely different widths but share a name prefix
(e.g. the real case this was found against: FLUSH64 at size 64 and FLUSH32
at size 32 in PolarfireSoC.svd's CACHE_CTRL peripheral) then get the SAME
Ada base type (borrowed from whichever register svd2ada visits first),
while each keeps its own correct bit-range representation clause. GNAT
catches the resulting one -- "size for "UInt64" too small, minimum allowed
is 64" -- but a corrected register that happens to be wider than its
sibling (not narrower) would compile silently wrong: a declared UInt32
field actually sitting at a 64-bit-wide offset reads/writes only half the
register.

The fix, scoped narrowly to the exact failure mode: for each
"type X is record ... end record" + its paired "for X use record ...
end record;" representation clause (matched by X), find fields declared
as a bare "MPFS_MSS.UIntNN" with no sub-fields, and correct NN to the
width the representation clause's own bit range says it must be --
which is the authoritative figure, since it comes straight from each
register's own <addressOffset>/<size> and never crosses a register
boundary the way the type-sharing heuristic does.
"""

import re
import sys
import glob

FIELD_DECL_RE = re.compile(
    r'^(?P<indent>[ \t]*)(?P<name>\w+)(?P<pad>[ \t]*):(?P<mid>[ \t]*)'
    r'(?P<aliased>aliased[ \t]+)?MPFS_MSS\.UInt(?P<width>\d+)(?P<tail>[ \t]*;.*)$'
)
REP_CLAUSE_RE = re.compile(
    r'^[ \t]*(?P<name>\w+)[ \t]+at[ \t]+16#[0-9A-Fa-f]+#[ \t]+range[ \t]+'
    r'(?P<lo>\d+)[ \t]*\.\.[ \t]*(?P<hi>\d+)[ \t]*;'
)
TYPE_RECORD_START_RE = re.compile(r'^\s*type\s+(\w+)\s+is\s+record\b')
REP_RECORD_START_RE = re.compile(r'^\s*for\s+(\w+)\s+use\s+record\b')
RECORD_END_RE = re.compile(r'^\s*end\s+record\b')


def extract_blocks(lines, start_re):
    """Yield (name, first_line_index, last_line_index) for each matched
    block, where the block runs from the "type X is record"/"for X use
    record" line through its "end record" line, inclusive."""
    i = 0
    while i < len(lines):
        m = start_re.match(lines[i])
        if m:
            name = m.group(1)
            j = i + 1
            while j < len(lines) and not RECORD_END_RE.match(lines[j]):
                j += 1
            yield name, i, j
            i = j + 1
        else:
            i += 1


def fix_file(path):
    with open(path) as f:
        lines = f.read().split('\n')

    rep_widths = {}  # record name -> {field name: width}
    for name, start, end in extract_blocks(lines, REP_RECORD_START_RE):
        widths = {}
        for line in lines[start + 1:end]:
            m = REP_CLAUSE_RE.match(line)
            if m:
                lo, hi = int(m.group('lo')), int(m.group('hi'))
                widths[m.group('name')] = hi - lo + 1
        rep_widths[name] = widths

    fixes = []
    for name, start, end in extract_blocks(lines, TYPE_RECORD_START_RE):
        widths = rep_widths.get(name)
        if not widths:
            continue
        for idx in range(start + 1, end):
            m = FIELD_DECL_RE.match(lines[idx])
            if not m:
                continue
            field = m.group('name')
            declared = int(m.group('width'))
            actual = widths.get(field)
            if actual is not None and actual != declared:
                lines[idx] = (
                    f"{m.group('indent')}{field}{m.group('pad')}:{m.group('mid')}"
                    f"{m.group('aliased') or ''}MPFS_MSS.UInt{actual}{m.group('tail')}"
                )
                fixes.append((name, field, declared, actual))

    if fixes:
        with open(path, 'w') as f:
            f.write('\n'.join(lines))
    return fixes


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 fix_mistyped_registers.py <dir-or-files...>")
        sys.exit(1)

    paths = []
    for arg in sys.argv[1:]:
        import os
        if os.path.isdir(arg):
            paths.extend(sorted(glob.glob(os.path.join(arg, '*.ads'))))
        else:
            paths.append(arg)

    total = 0
    for path in paths:
        fixes = fix_file(path)
        for record, field, declared, actual in fixes:
            print(f"  {path}: {record}.{field} UInt{declared} -> UInt{actual} "
                  f"(svd2ada Similar_Type ignored differing register size)")
        total += len(fixes)

    if total == 0:
        print("  no mistyped registers found")


if __name__ == "__main__":
    main()
