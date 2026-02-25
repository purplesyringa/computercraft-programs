import hashlib
import json
from pathlib import Path
import subprocess

def minify(key: str, code: str) -> str:
    # Cache results so that `initrd` can be compiled on systems without `luamin`.
    cache_path = Path(f"initrd/snippets/{key}.json")
    code_hash = hashlib.sha256(code.encode()).hexdigest()
    try:
        with open(cache_path, "r") as f:
            cache = json.load(f)
            if cache["hash"] == code_hash:
                return cache["minified"]
    except (FileNotFoundError, json.decoder.JSONDecodeError):
        pass

    minifed = subprocess.run(["luamin", "-c", code], capture_output=True, check=True).stdout.decode().strip()
    with open(cache_path, "w") as f:
        json.dump({
            "hash": code_hash,
            "minified": minifed,
        }, f)

    return minifed
