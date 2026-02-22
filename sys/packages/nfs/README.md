# nfs

Network file system.

## Usage

The server needs to run `nfsd <share root path>`. This announces the existence of the share to the network and allows clients to mount it in read-only mode. Consider using the `nfsd` service for this.

NFS clients are based on [virtual file systems](../vfs), and thus can be mounted either from shell or from Lua:

```shell
nfs-mount <mountpoint> [<server hostname OR computer id>]
```

```lua
local nfs = require "nfs"
nfs.mount(mountpoint, [server_hostname OR computer_id])
```

Multiple servers can co-exist, as long as they have different hostnames or referenced by computer id. The default server hostname for connections is `fileserver`.
