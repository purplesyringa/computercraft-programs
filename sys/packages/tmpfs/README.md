# tmpfs

> Did you know that computers have infinite RAM? Try it out with tmpfs!

Extend computer disk space with temporary file system.

## Usage

tmpfs is based on [virtual file systems](../vfs), and thus can be mounted either from shell or from Lua:

```shell
tmpfs-mount <mountpoint>
```

```lua
local tmpfs = require "tmpfs"
tmpfs.mount(mountpoint, [filesystem tree, [read_only]])
```

tmpfs can mount a filesystem with a given filesystem tree to prepopulate the filesystem.

tmpfs can also be mounted read-only to prevent filesystem image from changing. Note that this does not prevent the passed tree object from changing, and tmpfs driver *will* modify it to save inferred attributes.

## Filesystem tree structure

Filesystem tree is just an entry for root of the filesystem.

Each entry in the tree is a table that has `attributes` key, and `contents` or `entries` keys, depending on file type.

`contents` is a string that is file contents. Is present only for regular files. Empty files have `contents` set to `""`.

`entries` is a table that stores files in a directory. Is present only for directories. Empty directories have `entries` set to `{}`.

`attributes` is an optional table of file attributes, exactly as returned by [`fs.attributes`](https://tweaked.cc/module/fs.html#v:attributes). The one exception is `modification` key: it is added by vfs for fs compatibility and there is no need to provide it manually. Missing keys are synthesized out of other data:
- `isDir` is inferred from `entries` being present,
- `size` is inferred from `contents`,
- `isReadOnly` is inferred as true,
- `created` is inferred as unix epoch,
- `modified` is inferred as `created`.

Minimal entries look like `{ contents = "" }` for regular file and `{ entries = {} }` for directory.

### Example

```lua
local tmpfs = require "tmpfs"

local tree = {
    attributes = { isReadOnly = false, },
    entries = {
        dir = {
            attributes = { isReadOnly = false, },
            entries = {
                emptydir = { attributes = { isReadOnly = false, }, entries = {} },
                file1 = { attributes = { isReadOnly = false, }, contents = "one" },
                file2 = { attributes = { isReadOnly = false, }, contents = "two" },
                file3 = { attributes = { isReadOnly = false, }, contents = "three" },
            },
        },
        test = { contents = "Hello, world\n" },
    },
}

fs.makeDir("tmp")
tmpfs.mount("tmp", tree)
```

This creates the following file hierarchy:

```
tmp/
tmp/dir/
tmp/dir/emptydir/
tmp/dir/file1      -- "one"
tmp/dir/file2      -- "two"
tmp/dir/file3      -- "three"
tmp/test           -- "Hello, world\n"; read-only
```

## Where's the catch

As the name implies, this filesystem is not persistent. Rebooting a device with this filesystem mounted will forever destroy the files stored inside. Unmounting the filesystem also destroys all of its contents.
