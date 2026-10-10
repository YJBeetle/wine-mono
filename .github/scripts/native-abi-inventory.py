#!/usr/bin/env python3
"""Inventory only; implicit Winapi is valid for Windows APIs, not a bug verdict."""
import collections
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1]) / "mcs" / "class"
counts = collections.Counter()
for path in sorted(root.rglob("*.cs")):
    source = path.read_text(errors="replace")
    for match in re.finditer(r"\[\s*DllImport\s*\((.*?)\)\s*\]", source, re.S):
        declaration = match.group(1)
        library = declaration.split(",", 1)[0].strip()
        convention = "explicit" if "CallingConvention" in declaration else "implicit"
        counts[(library, convention)] += 1
        if convention == "implicit" and any(word in library.lower() for word in
                                            ("mono", "btls", "zlib", "libc", "libname", "library", "lib")):
            line = source.count("\n", 0, match.start()) + 1
            print(f"CANDIDATE {path.relative_to(root)}:{line} {declaration.strip()}")
print("\nSUMMARY library convention count")
for (library, convention), count in sorted(counts.items()):
    print(library, convention, count)
