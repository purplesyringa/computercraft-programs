import json
import sys
from pathlib import Path
import string

if len(sys.argv) < 2:
    print("Usage: python3 make-initrd.py <output path>")
    raise SystemExit()
output_path = sys.argv[1]

valid_identifier_chars = set(string.digits + string.ascii_letters + "_")
reserved_words = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "global", "goto",
    "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}

def serialize(obj) -> bytes:
    if isinstance(obj, (int, float)):
        return str(obj).encode()
    elif isinstance(obj, str):
        return serialize(obj.encode())
    elif isinstance(obj, bytes):
        if b"\\" not in obj and b"\n" not in obj:
            if b"\"" not in obj:
                return b"\"" + obj + b"\""
            elif b"'" not in obj:
                return b"'" + obj + b"'"
        assert b"\r" not in obj, "cannot serialize byte sequence with CR"
        level = 0
        while b"]" + b"=" * level + b"]" in obj:
            level = level + 1
        if obj.startswith(b"\n"):
            obj = "\n" + obj
        return b"[" + b"=" * level + b"[" + obj + b"]" + b"=" * level + b"]"
    elif isinstance(obj, list):
        if not obj:
            return b"{}"
        return b"{ " + b", ".join(map(serialize, obj)) + b" }"
    elif isinstance(obj, dict):
        if not obj:
            return b"{}"
        return b"{ " + b", ".join(
            serialize_key(k) + b" = " + serialize(v)
            for k, v in obj.items()
        ) + b" }"
    else:
        raise TypeError(f"Cannot serialize type {type(obj).__name__}")


def serialize_key(obj) -> bytes:
    if isinstance(obj, bytes):
        try:
            obj = obj.decode()
        except UnicodeDecodeError:
            return b"[" + serialize(obj) + b"]"
    if (
        isinstance(obj, str)
        and obj
        and all(c in valid_identifier_chars for c in obj)
        and not obj[0].isdigit()
        and obj not in reserved_words
    ):
        return obj.encode()
    return b"[" + serialize(obj) + b"]"


def build_tree(path):
    stat = path.stat()
    try:
        created = stat.st_birthtime_ns
    except AttributeError:
        created = stat.st_ctime_ns
    attributes = {
        "created": int(created / 1e6),
        "modified": int(stat.st_mtime_ns / 1e6),
    }
    if path.info.is_dir():
        return {
            "attributes": attributes,
            "entries": {
                child.name: build_tree(child)
                for child in path.iterdir()
                if not child.name.endswith(".png")
            },
        }
    elif path.info.is_file():
        return {
            "attributes": attributes,
            "contents": path.read_bytes(),
        }
    else:
        raise ValueError(f"Unknown file type at {path}")


tree = serialize(build_tree(Path("sys")))

# The tree already contains `vfs`, `tmpfs`, and other modules, so it'd be redundant to also add them
# via `pack`. It'd also be difficult, since `pack` assumes a ComputerCraft environment, which is
# non-trivial to simulate outside of CC. So we patch `require` to fetch files directly from the tree
# instead. Since we're using `shell.run` instead of `os.run`, `svc` will get a new
# `require`/`package` pair, so this won't break anything later on.
code = b"""local tree = TREE

local function readFile(path)
    local ptr = tree
    for part in path:gmatch("[^/]+") do
        ptr = ptr and ptr.entries and ptr.entries[part]
    end
    return ptr and ptr.contents
end

local function loadFromTree(name)
    local name_as_path = name:gsub("%.", "/")
    local contents = (
        readFile("packages/" .. name_as_path .. "/init.lua")
        or readFile("packages/" .. name_as_path .. ".lua")
    )
    if contents then
        return load(contents, "=initrd:" .. name, nil, _ENV)
    end
end
table.insert(package.loaders, loadFromTree)

require "vfs.install"
local vfs = require "vfs"
local tmpfs = require "tmpfs"
vfs.unmount("sys")
fs.makeDir("sys")
tmpfs.mount("sys", tree, true)
shell.run("sys/startup")
""".replace(b"TREE", tree)

with open(output_path, "wb") as f:
    f.write(code)
