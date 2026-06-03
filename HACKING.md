# Hacking guide

There are two parts to any OS: kernel and userland. There is no real kernel forming a security boundary in this OS, but there is still obvious separation between shared technical libraries and user-facing applications. This guide starts by covering the former: how the OS boots, how programs are loaded, in which environment they are run, and so on. Even if your goal is only to build or debug an app, this will give you a clean picture of how things are interconnected. This guide then gives advice on maintaining userland.


## Boot process

Here's a high-level overview of the boot process of a typical application-hotsing computer. This process involves multiple steps:

1. Unpacking `initrd`.
2. Setting up `vfs` and `tmpfs` drivers.
3. Setting up `PATH` and process environment.
4. Loading service and target configuration from the sysroot.
5. Bringing up services of the boot target.
6. Configuring foreground process seats with `getty`.

Let's go over these points in order.


## `initrd` and virtual file systems

Most operating systems have a length installation process that involves downloading packages to the local file system with the package manager. This OS is different: it fits in a single `startup.lua` file, leaves no other trace in the file system, and is immediately feature-complete without network access.

The base that makes this possible is [the `vfs` driver](sys/packages/vfs), which monkey-patches the built-in `fs` API to support mountpoints for virtual file systems. One example is [the `tmpfs` file system](sys/packages/tmpfs), which creates a file system from a Lua table.

The default `startup.lua` file downloaded from https://cc.purplesyringa.moe/initrd.lua includes a [compressed](initrd) dump of the [`sys`](sys) directory from this repo, which contains `vfs` and `tmpfs` drivers, as well as the rest of the OS. The `initrd.lua` script unpacks the dump, activates `vfs`, and exposes the dump as a read-only FS at `/sys`. The rest of the OS then boots as if `/sys` is a real directory, even though it doesn't exist on disk.

With `netboot`, the process is slightly different: `startup.lua` requests and `eval`s a boot script from the netboot server, which includes the `vfs` and `nfs` drivers, mounts a network file system at `/nfs`, and boots from `/nfs/sys`.

When developing, you have a choice between rebuilding the `initrd` image after each modification or symlinking the `sys` directory to the CC computer directory:

- Rebuilding `initrd` is easier: it can be done with `pypy3 -m initrd path/to/startup.lua`, but requires `pypy` to be installed and is a little slow. You'll need to reboot after each modification.
- Symlinking `sys` requires you to create a `startup.lua` file in the FS root containing `shell.run("sys/startup")`. You don't need to reboot after modification, unless you modify core parts of the OS. However, you'll need to [enable symlinks in Minecraft configuration](https://help.minecraft.net/hc/en-us/articles/16165590199181). This also allows you to modify the code in-game, though DX might suffer.


## `PATH` and process environment

After the sysroot becomes available at `/sys` or `/nfs/sys`, the entry point of the OS at `<sysroot>/packages/svc/boot.lua` is executed.

The first thing it does is reconfigure the shell and the `require` function to a *package-based hierarchy*.

Typical Unix and CraftOS systems group files of the same format together, while keeping files related to a specific purpose apart:

```
├── bin
│  ├── hw.lua
│  ├── tmpfs-mount.lua
│  ├── getty.lua
│  └── ...
├── lib
│  ├── hardware.lua
│  └── tmpfs.lua
│  └── ...
└── services
   ├── getty-default.lua
   └── ...
```

This simplifies name resolution, but the few directory become cluttered and uncomfortable to maintain. In contrast, package-based hierarchy groups together files by topic:

```
├── hardware
│  ├── bin
│  │  └── hw.lua
│  └── init.lua
├── tmpfs
│  ├── bin
│  │  └── tmpfs-mount.lua
│  └── init.lua
├── getty
│  ├── bin
│  │  └── getty.lua
│  └── services
│     └── getty-default.lua
└── ...
```

(You may be familiar with this design from distributions like NixOS. Given that this OS is typically installed from `initrd.lua` and thus has a read-only `sys`, it can be argued to be an immutable store-based distribution.)

To make this work, `svc` implements a virtual file system called `svcbin` that effectively merges all `bin` directories present inside `packages`. This FS is mounted at `<sysroot>/run/bin`, and this directory is added to `PATH`.

However, the files inside `svcbin` are not just copies of the files in `bin`, since that would break `require` paths: we want `require "async"` in a program to load a *library* from `<sysroot>/packages/async/init.lua`, while the default `require` implementation would attempt to load `<sysroot>/run/bin/async.lua`, which is a (non-existent) *program*. Since there is no analogue of `PATH` for `require`, `svcbin` files are wrappers that reconfigure `require` to load libraries from `<sysroot>/packages/*/init.lua`, before passing control to the actual program.

Overall, this design allows packages to refer to each other, and enables changes to `packages` to be visible immediately. However, it does so at the cost of breaking compatibility with CraftOS: while in CraftOS, `require` is relative to the directory within which the current file is located, in this OS `require` is always relative to `<sysroot>/packages`. So imports from the same library have to repeat the library name.

Note that since `require` is only patched by `svcbin` wrappers, it doesn't apply to programs invoked not through `svcbin`. For example, running `<sysroot>/packages/*/bin/*.lua` directly can break imports. Crucially, this also requires the OS to override the built-in `lua` program, so that `require` works as expected in the REPL.


## Services and targets

The nominal function of the `svc` package is to manage *services* and *targets*.

Services correspond to units that can be "up" or "down" (usually background programs, but also possibly start/stop scripts) and have dependencies, targets are groups of services. On boot, `svc` parses package and target definitions from `packages/*/services/*.lua` and `targets/*.lua` respectively, retrieves the name of the boot target from the `svc.target` [setting](https://tweaked.cc/module/settings.html) (defaulting to `base`), and queues the services of the boot target to be brought up.

`svc` uses *processes* to handle background operations. Processes are background threads polled by `svc`. Most services start processes, but they can also be started in other circumstances if an action needs to be performed to completion if the program that triggered it quits midway. For example, `svc reach <target-name>` may need to bring down some services (e.g. if there's a foreground shell, but the target has another foreground program), which can include the service that is polling the `svc reach` command. To make sure that `svc reach` can complete its goal, it wraps the service start/stop logic in a process. Active processes can be listed with `proc`.

The specifics of service, target, and process management are covered in [the `svc` documentation](sys/packages/svc).


## Seats

Programs running as services receive (almost) all events directed to the computer. Notably, this includes keyboard events from *all* keyboards (from [Ducky Peripherals](https://modrinth.com/mod/ducky-periphs)) connected to the computer. Since you can't use an external keyboard and the internal screen at the same time, you need to add an external monitor, and managing this setup quickly gets messy. Bonus points for QoL features like supporting right-clicking via the monitor.

The [`getty`](sys/packages/getty) program is built to translate events and monitor operations between the computer I/O and interactive programs. All services that start interactive programs should run the program under `getty` with `getty default <program> <args...>`. The `default` option causes `getty` to drop events from external keyboards and set `term` to the internal terminal.

You can also use `getty` to run programs on an external monitor and keyboard by providing a custom *seat name* instead of `default`. The seat name is opaque, but often called `seatN`. You can assign a monitor to a seat with `hw add <seat-name>.monitor <id>` and a keyboard with `hw add <seat-name>.keyboard <id>`. Alternatively, run `hw add <seat-name>.monitor/keyboard` and then plug in the corresponding peripheral. This process is documented in more detail in [the `hardware` docs](sys/packages/hardware).

There is another subtle rewrite `getty` applies. `svc` rewrites all incoming `terminate` events to `fg_terminate` so that pressing the terminate button doesn't bring down all services. `getty`, in turn, rewrites `fg_terminate` back to `terminate` (filtering the event based on the originating keyboard), so that the event is delivered to the foreground service.

Note that running `getty` within `getty` doesn't quite work, since the outer `getty` filters out all keyboard events except for one source, including the source the nested `getty` listens to. Output will still likely work, but this configuration is unsupported.

Also note that currently, services are started with `term` pointing to the internal display, so using `print` from a service works as is, but we plan to change this so that `term` points to a log file. Don't rely on the current behavior.


## Packages

This covers the core parts of the OS. Assuming you're here to figure out how to create and modify packages, not the core OS, you'll need a bit more knowledge about how packages are designed around this block.

There is some obvious mechanical advice. Create a well-named directory, place the library entry code in `init.lua`, place binaries in `bin/*`, place services in `services/*`. If the application is supposed to run in background, create a service and an identically named target for it. When in doubt, copy the design of the closest existing package.

The subtle thing that I believe is most useful, especially if you're coming from pure ComputerCraft, is that files are free. In CC, you might be tempted to put all the logic in one file because that's easier to distribute. In this repo, you're expected to build reasonable abstractions and split reused code into multiple files. As a rule of thumb, if you're writing a program with a CLI, the corresponding library should export APIs to perform the same actions programmatically, and the CLI should be a small wrapper around the library (see [`hardware`](sys/packages/hardware) for a short example).

Note also that dependencies are free as well. If there's something that might be useful to other programs, extract it to a separate package. That's why [`async`](sys/packages/async) and [`tableui`](sys/packages/tableui) exist, both purely userland libraries.

Finally, don't keep your code to yourself. We don't support out-of-tree modules and offer no API stability guarantees. This OS is constantly evolving for our needs, and we're likely to break addons outside this repository. There's a reason why it's a monorepo!

Some packages you need to be aware of to avoid reinventing the wheel are:

- Userland: [`async`](sys/packages/async) (async runtime).
- Virtual I/O: [`vfs`](package/vfs) (the underlying API), [`bytesio`](sys/packages/bytesio) (in-memory files), [`wakeywakey`](sys/packages/wakeywakey) (asynchronous monkey-patching).
- Terminal I/O: [`redirect`](sys/packages/redirect) (`term` and event source redirection), [`svc` shell APIs used by `rsh`](sys/packages/rsh/bin/rsh-serve-session.lua).
- System: [`hardware`](sys/packages/hardware) (hardware assignments), [`startup`](sys/packages/startup) (startup script manipulation), [`svc`](sys/packages/svc) (services, targets, processes).
- Networking: [`named`](sys/packages/named) (hostname management and resolution), [`rsh`](sys/packages/rsh) (remote shell), [`pack`](sys/packages/pack) (webpack for Lua).
