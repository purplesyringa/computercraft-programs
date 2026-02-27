# Programs for ComputerCraft

This repository contains a number of programs me and my friends made and found useful while playing with [CC: Tweaked](https://tweaked.cc). On the functional side, it includes:

- [Instant storage](sys/packages/storage), which can deliver items from a single server to multiple interactive clients. As you write the search query in the client, 1 stack of each matching item is almost instantly pulled into its inventory for preview and quick pulling, producing very nice UX. If you install Turtlematic, UnlimitedPeripheralWorks, and Create, you'll also get wireless clients that you can carry in your inventory to deposit or withdraw items from any point in the world.

- [A smart supersmelter](sys/packages/supersmelter) that can spread items across blast furnaces and normal furnaces, automatically crafting and decrafting storage blocks.

Since this requires quite a few computers on a large scale, we made tools to ease maintenance:

- [`rsh`](sys/packages/rsh), a remote shell that can connect to any computer that runs a corresponding server.
- [`nfs`](sys/packages/nfs), a network file system to quickly deploy updates to multiple computers.
- [`netboot`](sys/packages/netboot), a mechanism to boot computers via network from an `nfs` server, so that core components can be updated remotely.
- [`svc`](sys/packages/svc), a service manager akin to systemd to automatically start programs on boot, depending on system configuration.
- [`msh`](sys/packages/msh), an improved (multi)shell with support for non-advanced computers.
- ...and many more low-level modules.

This basically amounts to a full-blown operating system, and all the "actually" useful programs here, like the instant storage, assume that they're running under this OS. Don't worry, though -- we tried to make setup as straightforward as possible.

## Setting up

Start by downloading an `initrd` image. It includes all the files in this repo (except images) in a compressed format, so you don't need to copy anything manually or use a git client.

```shell
> wget https://cc.purplesyringa.moe/initrd.lua
```

When executed, this script automatically sets up a virtual file system driver, unpacks the files into a temporary filesystem at `sys`, and boots the OS from there. You should be facing a familiar (but improved) shell prompt. (The number shows the computer ID, which you can replace with a human-readable hostname by running `hostname <name>`. `/` is the current directory.) To automatically load the OS when the computer is started, simply rename `initrd.lua` to `startup.lua`.

The computer is already running some services in the background, like `rshd`. You can verify that it's working correctly by running `rsh localhost`. You can also run `svc` to show the entire list of active services and their status.

More to the point, say you want to run the server of the instant storage. To do that, you need to run the `storage-server` program. You can run it directly from shell, but that prevents you from typing more commands. Instead, you can start the `storage-server` service in the background with `svc start storage-server`. To make this persistent, you can configure the OS to automatically start a given set of services at startup. We call these sets *targets*, and there is an identically named target `storage-server` that you can use with `svc reach storage-server --persist`.

This might seem like overengineering, but it enables orthogonal configuration. Running `storage-server` directly is useful for debugging, easy log access, and termination. Isolating commands into a service allows multiple targets to include one service, which is how you get `rshd` on each device.

At this point, you can either call it a day and just install the OS on each device (nothing wrong with that if you have just a few computers), or set up an NFS + netboot combination for easier redeployment. The `fileserver` target sets up the server: just run `svc reach fileserver --persist` on a server booted from `initrd` and you're set. You can then fetch this script to boot clients:

```shell
> wget https://cc.purplesyringa.moe/netboot.lua
```

As with `initrd.lua`, you can either run this script manually to boot temporarily, or rename it to `startup.lua` for persistency.
