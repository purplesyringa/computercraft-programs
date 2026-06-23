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

With `netboot`, the process is slightly different: `startup.lua` requests and `eval`s a boot script from the netboot server, which includes `vfs`, some file system drivers, and boots either an `initrd` image sent by the netboot server, or from NFS if the `initrd` image is unavailable.

When developing the core OS, you have a choice between rebuilding the `initrd` image after each modification or symlinking the `sys` directory to the CC computer directory:

- Rebuilding `initrd` is easier: it can be done with `pypy3 -m initrd path/to/startup.lua`, but requires `pypy` to be installed and is a little slow. You'll need to reboot after each modification.
- Symlinking `sys` requires you to create a `startup.lua` file in the FS root containing `shell.run("sys/startup")`. You don't need to reboot after modification, unless you modify core parts of the OS. However, you'll need to [enable symlinks in Minecraft configuration](https://help.minecraft.net/hc/en-us/articles/16165590199181). This also allows you to modify the code in-game, though DX might suffer.

If your goal is only to modify or create userland applications or libraries, you have another option: impure environments. If the directory `/impure` exists in the computer FS, it acts as a kind of overlay on `/sys`. For example, packages declared in `impure/packages` exist in addition to or override built-in packages at `sys/packages`, so you can develop software in-game, at the cost of being unable to use an IDE, push commits to Git, or share the programs between computers. This feature is explained in more detail near the end of this guide.


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

To make this work, `svc` implements a virtual file system called `runfs` that, among other things, merges all `bin` directories present inside `packages`. This FS is mounted at `<sysroot>/run`, and its `bin` subdirectory is added to `PATH`.

However, the binary files inside `runfs` are not just copies of the files in `bin`, since that would break `require` paths: we want `require "async"` in a program to load a *library* from `<sysroot>/packages/async/init.lua`, while the default `require` implementation would attempt to load `<sysroot>/run/bin/async.lua`, which is a (non-existent) *program*. Since there is no analogue of `PATH` for `require`, `runfs` binaries are wrappers that reconfigure `require` to load libraries from `<sysroot>/packages/*/init.lua`, before passing control to the actual program.

Overall, this design allows packages to refer to each other, and enables changes to `packages` to be visible immediately. However, it does so at the cost of breaking compatibility with CraftOS: while in CraftOS, `require` is relative to the directory within which the current file is located, in this OS `require` is always relative to `<sysroot>/packages`. So imports from the same library have to repeat the library name.

Note that since `require` is only patched by `runfs` wrappers, it doesn't apply to programs invoked not through `runfs`. For example, running `<sysroot>/packages/*/bin/*.lua` directly can break imports. Crucially, this also requires the OS to override the built-in `lua` program, so that `require` works as expected in the REPL.


## Services and targets

The nominal function of the `svc` package is to manage *services* and *targets*.

Services correspond to units that can be "up" or "down" (usually background programs, but also possibly start/stop scripts) and have dependencies, targets are groups of services. On boot, `svc` parses package and target definitions from `packages/*/services/*.lua` and `targets/*.lua` respectively, retrieves the name of the boot target from the `svc.target` [setting](https://tweaked.cc/module/settings.html) (defaulting to `base`), and queues the services of the boot target to be brought up.

`svc` uses *processes* to handle background operations. Processes are background threads polled by `svc`. Most services start processes, but they can also be started in other circumstances if an action needs to be performed to completion if the program that triggered it quits midway. For example, `svc reach <target-name>` may need to bring down some services (e.g. if there's a foreground shell, but the target has another foreground program), which can include the service that is polling the `svc reach` command. To make sure that `svc reach` can complete its goal, it wraps the service start/stop logic in a process. Active processes can be listed with `proc`.

The specifics of service, target, and process management are covered in [the `svc` documentation](sys/packages/svc).


## Seats

Programs running as services receive (almost) all events directed to the computer. Notably, this includes keyboard events from *all* keyboards (from [Ducky Peripherals](https://modrinth.com/mod/ducky-periphs)) connected to the computer. Since you can't use an external keyboard and the internal screen at the same time, you need to add an external monitor, and managing this setup quickly gets messy. Bonus points for QoL features like supporting right-clicking via the monitor.

The [`getty`](sys/packages/getty) program translates events and monitor operations between the computer I/O and interactive programs. This translation includes limiting input to a single keyboard, handling `terminate`, and applying [custom keyboard layouts](sys/packages/keyboard).

All services that start interactive programs should run the program under `getty` with `getty default <program> <args...>`. The `default` option causes `getty` to drop events from external keyboards and set `term` to the internal terminal.

You can also use `getty` to run programs on an external monitor and keyboard by providing a custom *seat name* instead of `default`. The seat name is opaque, but often called `seatN`. You can assign a monitor to a seat with `hw add <seat-name>.monitor <id>` and a keyboard with `hw add <seat-name>.keyboard <id>`. Alternatively, run `hw add <seat-name>.monitor/keyboard` and then plug in the corresponding peripheral. This process is documented in more detail in [the `hardware` docs](sys/packages/hardware).

`getty` also applies a subtle rewrite to make `terminate` work as intended. `svc` rewrites all incoming `terminate` events to `fg_terminate` so that pressing the terminate button doesn't bring down all services. `getty`, in turn, rewrites `fg_terminate` back to `terminate` (filtering the event based on the originating keyboard), so that the event is delivered to the foreground service.

Keyboard layouts are implemented by passing the native `key`, `key_up`, and `char` events to [the `keyboard` package](sys/packages/keyboard), which replaces `char` events with custom ones as necessary.

All of this means that running `getty` within `getty` doesn't really work: the outer `getty` filters out all keyboard events except for one source, including the source the nested `getty` listens to, and nested layouts can quickly get broken. Output will still likely work, but this configuration is unsupported.

Also note that currently, services are started with `term` pointing to the internal display, so using `print` from a service works as is, but we plan to change this so that `term` points to a log file. Don't rely on the current behavior.


## Packages

This covers the "kernel"-adjacent parts of the OS. The "userland" of the OS is composed of packages.

A package called `<name>` is represented by the directory `<sysroot>/packages/<name>`. Creating a directory is sufficient to create the package. Each package can include:

- An optional library that can be imported from elsewhere via `require "<name>"`. The source code for this library is stored in the `init.lua` file in the package directory. Other Lua files can be imported as `require "<name>.<file>"`, with `.` used as a separator for files nested in subdirectories.

- Zero or more binaries, stored in `bin/<binary>.lua` within the package directory. The binary name doesn't have to be tied to the package name. Binaries have access to all libraries, including the library of the current package, if it's present (via `require "<name>"`).

- Zero or more services, stored in `services/<service>.lua` within the package directory. Again, the name can be arbitrary. Service definitions are explained in more detail in [the `svc` docs](sys/packages/svc).

To create a package or modify an existing one, you would typically clone the Git repo locally, modify the code, and either rebuild the `initrd` as necessary or symlink the `sys` directory. This process is explained in more detail in the "`initrd` and virtual file systems" section of this guide, and it is the preferred way to write code.


## Impure environments

If you cannot develop software locally for some reason (e.g. if you cannot run server-side mods or want a more authentic experience), you can use *impure environments* instead. With impure environments, packages are loaded from `/impure/packages` in addition to `<sysroot>/packages`. You can also use this for targets. Packages and targets named identically to built-in packages/targets override the latter completely, so e.g. an empty directory at `/impure/packages/async` effectively deletes the `async` package.

This development workflow is a bit more dangerous than a sysroot-oriented workflow, since overriding a built-in package with a buggy one can break important programs. This is further complicated by the fact that we don't offer API stability, so updating the OS can break out-of-tree packages. For this reason, this feature is hidden behind a flag. Use `impure enable` to enable the impure environment and `impure disable` to disable it. The setting applies to libraries and binaries immediately, while services and targets need to be reloaded with `svc reload`. The setting persists across reboots. If the system is broken so much that it doesn't even show a shell, you can use `set svc.impure false` from CraftOS or manually modify the `/.settings` file to recover control.

The impure environment cannot modify all aspects of the system, since it is only enabled after the core of the OS is loaded. Specifically, `svc` and its dependencies always load from the sysroot.

Impure packages are local to the computer they are installed on. It is technically possible to mount `nfs` over `/impure`, but this is not the intended usage. If you need to share a package across computers, you're likely better off building an `initrd`, possibly after debugging the package on one computer.


## Packaging guidelines

There is some obvious mechanical advice. Use descriptive package/binary/service/target names with kebab-case. If the application is supposed to run in background, create a service and an identically named target for it. When in doubt, copy the design of the closest existing package.

The subtle thing that I believe is most useful, especially if you're coming from pure ComputerCraft, is that files are cheap. In CC, you might be tempted to put all the logic in one file because that's easier to distribute. In this repo, you're expected to build reasonable abstractions and split reused code into multiple files, since the OS is distributed as a whole. As a rule of thumb, if you're writing a program with a CLI, the corresponding library should export APIs to perform the same actions programmatically, and the CLI should be a small wrapper around the library (see [`hardware`](sys/packages/hardware) for a short example).

Note also that dependencies are free as well. If there's something that might be useful to other programs, extract it to a separate package. That's why [`async`](sys/packages/async) and [`tableui`](sys/packages/tableui) exist, both purely userland libraries.

Finally, don't keep your code to yourself. We don't offer API stability, so out-of-tree packages can break at any point. This OS is constantly evolving for our needs, and we're likely to break addons outside this repository. There's a reason why it's a monorepo!

Some libraries you need to be aware of to avoid reinventing the wheel are:

- Userland: [`async`](sys/packages/async) (async runtime).
- Virtual I/O: [`vfs`](sys/packages/vfs) (the underlying API), [`bytesio`](sys/packages/bytesio) (in-memory files), [`wakeywakey`](sys/packages/wakeywakey) (asynchronous monkey-patching).
- Terminal I/O: [`redirect`](sys/packages/redirect) (`term` and event source redirection), [`svc` shell APIs used by `rsh`](sys/packages/rsh/bin/rsh-serve-session.lua).
- System: [`hardware`](sys/packages/hardware) (hardware assignments), [`startup`](sys/packages/startup) (startup script manipulation), [`svc`](sys/packages/svc) (services, targets, processes).
- Networking: [`named`](sys/packages/named) (hostname management and resolution), [`rsh`](sys/packages/rsh) (remote shell), [`pack`](sys/packages/pack) (webpack for Lua).
