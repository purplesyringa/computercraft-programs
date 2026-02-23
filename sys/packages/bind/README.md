# bindfs

Symlinks off steroids.

## Usage

Bind mount is a [virtual file system](../vfs), and thus can be mounted either from shell or from Lua:

```shell
bind-mount <origin> <mountpoint>
bind-mount-ro <origin> <mountpoint>
```

```lua
local bind = require "bindfs"
bind.mount(origin, mountpoint, read_only)
```

Bind mount allows to access files under `origin` as files under `mountpoint`, and restricting write access to them.

Note that bind-mounting over self, that is calling `bind.mount` with `origin == mountpoint` is currently not supported.
