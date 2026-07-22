# netboot

Boot `svc` over the network. This enables easy global updates of not just data, but also packages, services, and targets.

## Usage

`netbootd` hosts current sysroot over `nfs` (or serves the initrd image directly), and it expects `pub` to be the `nfs` share. `fileserver` target provides out-of-the-box solution for creating a netboot server.

To boot from network, clients need to run the [boot.lua](boot.lua) script from this directory. You can either copy it to clients manually, or use `wget` to load it from the internet:

```shell
wget run https://cc.purplesyringa.moe/netboot.lua
```

To persist this across reboots, save the file as `startup.lua`:

```shell
wget https://cc.purplesyringa.moe/netboot.lua startup.lua
```

This script waits for the netbootd server to provide an initrd indefinitely. This process can be aborted by pressing the Terminate key.
