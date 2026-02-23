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
tmpfs.mount(mountpoint, [filesystem tree])
```

tmpfs can mount a filesystem with a given filesystem tree to prepopulate the filesystem.

Currently, this filesystem is always mounted in read-write mode, and no read-only protections are implemented.

## Filesystem tree structure

Filesystem tree is just an entry for root of the filesystem.

Each entry in the tree is a table that has `attributes` key, and `contents` or `entries` keys, depending on file type.

`attributes` is a table of file attributes, exactly as returned by [`fs.attributes`](https://tweaked.cc/module/fs.html#v:attributes). The one exception is `modification` key: it is added by vfs for fs compatibility and there is no need to provide it manually.

`contents` is a string that is file contents. Is present only for regular files. Empty files have `contents` set to `""`.

`entries` is a table that stores files in a directory. Is present only for directories. Empty directories have `entries` set to `{}`.

### Example

```lua
local tmpfs = require "tmpfs"

local tree = {
    attributes = { size = 0, isDir = true, isReadOnly = false, created = 0, modified = 0 },
    entries = {
        dir = {
            attributes = { size = 0, isDir = true, isReadOnly = false, created = 0, modified = 0 },
            entries = {
                emptydir = {
                    attributes = { size = 3, isDir = true, isReadOnly = false, created = 0, modified = 0 },
                    entries = {},
                },
                file1 = {
                    attributes = { size = 3, isDir = false, isReadOnly = false, created = 0, modified = 0 },
                    contents = "one",
                },
                file2 = {
                    attributes = { size = 3, isDir = false, isReadOnly = false, created = 0, modified = 0 },
                    contents = "two",
                },
                file3 = {
                    attributes = { size = 5, isDir = false, isReadOnly = false, created = 0, modified = 0 },
                    contents = "three",
                }
            }
        },
        test = {
            attributes = { size = 13, isDir = false, isReadOnly = false, created = 0, modified = 0 },
            contents = "Hello, world\n"
        }
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
tmp/test           -- "Hello, world\n"
```

## Where's the catch

As the name implies, this filesystem is not persistent. Rebooting a device with this filesystem mounted will forever destroy the files stored inside. Unmounting the filesystem also destroys all of its contents.
