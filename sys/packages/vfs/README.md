# vfs

Virtual file system. Monkey-patches the `fs` API to add support for pluggable filesystems, such as [NFS](../nfs) and [tmpfs](../tmpfs).

## Usage

The VFS driver is installed by running `install.lua`. `svc` does this automatically on boot.

Filesystems can be mounted with commands for respective drivers or provided by Lua code with a FUSE-like API.

## Making a filesystem

The simplest implementation of a flat read-only file system goes like this:

```lua
local vfs = require("vfs")

local files = {
    ["a.txt"] = "contents of file a.txt",
    ["b.txt"] = "contents of file b.txt",
}

vfs.mount(mountpoint, {
    drive = "example",
    description = "example://",
    -- Simulates `fs.list`.
    list = function(rel_path)
        if rel_path ~= "" then
            error("/" .. rel_path .. ": not a directory")
        end
        local files = {}
        for name, _ in files do
            table.insert(files, name)
        end
        return files
    end,
    -- Simulates `fs.attributes`, but returns `nil` for absent files.
    attributes = function(rel_path)
        -- Some attributes have defaults, so we can omit them.
        if rel_path == "" then
            return { isDir = true }
        elseif files[rel_path] then
            return { size = #files[rel_path], isDir = false }
        else
            return nil
        end
    end,
    -- Returns the contents of a given file.
    read = function(rel_path)
        if not files[rel_path] then
            error("/" .. rel_path .. ": not a file")
        end
        return files[rel_path]
    end,
})
```

You might notice that some functions have a slightly different API from `fs`. For example, `attributes` returns `nil` on non-existing files, while `fs.attributes` throws an error. This is an intentional change for optimization. `fs.attributes` implemented on top of VFS transparently translates `nil` to an error, so this does not affect user-visible API, but it does allow e.g. `fs.exists` and `fs.isDir` to be implemented without ugly `pcall`. If you want to rely on the same optimizations, you can call `vfs.attributes` instead of `fs.attributes`, which does not perform this translation. This is the case for all methods with different semantics.

A read-write file system would need the following changes:

- Implement `isReadOnly(rel_path)`: determines if a path is read-only. `rel_path` is not guaranteed to exist; if it doesn't, the FS should consider a path read-only if its closest existing ancestor is read-only.
- Add `isReadOnly` field to `attributes(rel_path)`.
- Implement `makeDir(rel_path)` and `delete(rel_path)`. `makeDir` should create all non-existing ancestors, and `delete` should delete directories recursively.
- Implement `write(rel_path, contents)`.

A file system can be made more optimal in the number of requests with the following changes (this is useful for e.g. NFS):

- Instead of returning lists of names from `list`, return lists of `{ name = ..., attributes = ... }`.
- Implement `find(rel_pattern)`.
- Implement `move(src_rel_path, dst_rel_path)`.
- Implement `copy(src_rel_path, dst_rel_path)`.

A feature-complete file system can also support the following:

- Implement `getFreeSpace(rel_path)`.
- Implement `getCapacity(rel_path)`.
- Implement `open(rel_path, mode)`.
- Return `created` and `modified` attributes.

Check implementations of existing file systems for inspiration: [bind](../bind), [nfs](../nfs), [tmpfs](../tmpfs), [svcbin](../svc/env.lua).

## Other APIs

- `vfs.list(path)`: like `fs.list`, but returns a list of `{ name = ..., attributes = ... }`.
- `vfs.attributes(path)`: like `fs.attributes`, but returns `nil` if the file is absent.
- `vfs.read(path)`: returns the contents of the file as a string.
- `vfs.write(path, contents)`: overwrites the file with the given string.
- `vfs.unmount(root)`: unmounts the filesystem at the given path. Returns `true` on success and `false` if `root` is not a mountpoint.
- `vfs.listMounts()`: returns a list of `{ root = ..., drive = ..., description = ..., shadowed = ... }`.
