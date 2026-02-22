# netboot

Boot `svc` over the network. This enables easy global updates of not just data, but also packages, services, and targets.

## Usage

The server needs to run `nfsd` with a directory containing a sysroot that clients will boot from. Use `netbootd <path of sysroot relative to nfs share>` to host a system. Look at the `nfsd` and `netbootd` service definitions for inspiration.

To boot from network, clients need to run the [boot.lua](boot.lua) script from this directory. You can either copy it to clients manually, or use `wget` to load it from the internet:

```shell
wget run https://cc.purplesyringa.moe/netboot.lua
```

To persist this across reboots, save the file as `startup.lua`:

```shell
wget https://cc.purplesyringa.moe/netboot.lua startup.lua
```
