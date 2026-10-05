#!/usr/bin/env python3
# Copyright (C) 2026, PureDarwin Project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

"""Extract named functions from local/disasm/Foundation.full.disasm.

The disassembly is jtool2 output: every instruction line is
    <addr>\t<hex bytes>\t<mnemonic>\t<operands>
and each function starts with a bare label line, e.g.
    -[NSAutoreleasePool init]:

Usage:
    extract_fn.py 'NSAutoreleasePool'        # every function whose label
                                             # mentions NSAutoreleasePool
    extract_fn.py '-[NSAutoreleasePool drain]:' out.dis
"""
import sys

DISASM = "local/disasm/Foundation.full.disasm"


def labels(lines):
    """Yield (index, label) for every bare label line."""
    for i, line in enumerate(lines):
        if line and line[0] not in " \t0123456789" and line.rstrip().endswith(":"):
            yield i, line.rstrip()[:-1]


def main():
    needle = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else None
    with open(DISASM, "r", errors="replace") as fh:
        lines = fh.read().splitlines()

    marks = list(labels(lines))
    chunks = []
    for n, (idx, name) in enumerate(marks):
        if needle not in name:
            continue
        end = marks[n + 1][0] if n + 1 < len(marks) else len(lines)
        chunks.append("\n".join(lines[idx:end]).rstrip())

    if out:
        with open(out, "w") as fh:
            fh.write("\n\n".join(chunks) + "\n")
        print("%s: %d function(s)" % (out, len(chunks)))
    else:
        print("\n\n".join(chunks))


main()
