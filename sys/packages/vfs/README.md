# vfs

Virtual file system. Monkey-patches the `fs` API to add support for pluggable filesystems, such as [NFS](../nfs).

## Usage

The VFS driver is installed by running `install.lua`. `svc` does this automatically on boot.

Filesystems can be mounted with commands for respective drivers or provided by Lua code with a FUSE-like API. The simplest implementation is like this:

```lua
local vfs = require("vfs")

vfs.mount(mountpoint, {
    drive = "example",
    description = "example://",
    find = call("find"),
    list = call("list"),
    attributes = call("attributes"),
    read = call("read"),
})
```