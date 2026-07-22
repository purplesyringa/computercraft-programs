# netboot

Boot the OS over the network. This enables easy global updates of not just data, but also packages, services, and targets.

## Usage

To set up the netboot server, reach the `fileserver` target. Alternatively, you can run `netbootd` by hand. Both ways expose the packages of the currently running system to other clients, either [over `nfs`](../nfs) or by serving [the `initrd` image](../../../initrd-ng) directly.

To boot from the file server, clients need to run the [boot.lua](boot.lua) script from this directory. You can either copy it to clients manually, or use `wget` to load it from the internet:

```shell
wget run https://cc.purplesyringa.moe/netboot.lua
```

To persist this across reboots, save the file as `startup.lua`:

```shell
wget https://cc.purplesyringa.moe/netboot.lua startup.lua
```

Hung netboot can be aborted by pressing the Terminate key.

## Data files

Network-booted clients have a read-only [`nfs` share](../nfs) mounted at `/nfs`, exposing to the `/pub` directory on the file server. You can use this to share files between multiple computers in a centralized manner.

## Multiple netboot servers

You can set up multiple `netbootd` servers in a single network, and configure which deployment each client should boot from case-by-case. For example, this can be used to set up a staging environment (or multiple) without interfering with the primary net.

This mechanism is implemented with a *tag* system. Each file server can be assigned a tag, and each client will only try to boot from file servers with a specific tag. If more than one server uses a given tag, the client chooses randomly (this can be used for better reliability).

The default tag is `primary`. Use `set netbootd.tag <tag>` to change the tag announced by the server, and `set netboot.upstream <tag>` to change the tag used on the end device.

Note that if no server matches a given tag, the client does not fall back to `primary`, so at least one server per tag must always be available.
