import sys
from pathlib import Path
from .fs import build_uncompressed_initrd
from .bz import compress
from .snippets import generate_sfx

if len(sys.argv) < 2:
    print("Usage: python3 -m initrd <output path>")
    raise SystemExit()
output_path = sys.argv[1]

with open(output_path, "wb") as f:
    f.write(generate_sfx(*compress(build_uncompressed_initrd(Path("sys")))))
