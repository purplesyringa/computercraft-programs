from pathlib import Path
from .ser import serialize


def build_tree(path: Path) -> dict:
    stat = path.stat()
    try:
        created = stat.st_birthtime_ns
    except AttributeError:
        created = stat.st_ctime_ns
    attributes = {
        "created": int(created / 1e6),
        "modified": int(stat.st_mtime_ns / 1e6),
    }
    if path.is_dir():
        return {
            "attributes": attributes,
            "entries": {
                child.name: build_tree(child)
                for child in path.iterdir()
                if not (child / ".rdignore").exists()
            },
        }
    elif path.is_file():
        return {
            "attributes": attributes,
            "contents": path.read_bytes(),
        }
    else:
        raise ValueError(f"Unknown file type at {path}")


def build_uncompressed_initrd(sys_path: Path) -> bytes:
    tree = build_tree(sys_path)

    # The tree already contains `vfs`, `tmpfs`, and other modules, so it'd be redundant to also add
    # them via `pack`. It'd also be difficult, since `pack` assumes a ComputerCraft environment,
    # which is non-trivial to simulate outside of CC. So we patch `require` to fetch files directly
    # from the tree instead. Since we're using `shell.run` instead of `os.run`, `svc` will get a new
    # `require`/`package` pair, so this won't break anything later on.
    return b"""local tree = TREE

    if mounting then return tree end

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
    """.replace(b"TREE", serialize(tree))
