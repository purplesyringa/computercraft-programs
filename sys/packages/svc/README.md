# svc

A service, process, system, and package manager. This is basically systemd on steroids.

## Booting the OS

`svc` is not a normal library: while it can be included to access APIs for controlling the running system, those APIs are only available when the entire system is running under `svc`.

To start the OS, you can either run [`boot.lua`](boot.lua) from this directory or [`startup.lua`](../../startup.lua) from the sysroot (which basically just `require`s `boot.lua`):

```shell
> <sysroot>/packages/svc/boot
or
> <sysroot>/startup
```

Upon booting, you should be facing a familiar ([but improved](../msh)) shell.

To configure the OS to start automatically, save `shell.run("<sysroot>/startup")` to `startup.lua` in the disk root.

## Services and processes

`svc` mainly manages two core things: services and processes.

Services define the runtime properties of the system. Services control what the user-facing program is (the [`msh`](../msh) shell by default), what programs are run in the background (e.g. [`rshd`](../rshd)), and what hooks are run when the system is started (e.g. [`named`](../named)). Services are referred to by a short name and are not otherwise configurable. You can view the list of declared and running services by running `svc`, start services with `svc start <name>`, and stop them with `svc stop <name>`:

```shell
> svc
Target: base (up)

Service         Status
msh             up
named           up
netbootd        stopped
nfsd            stopped
rshd            up
```

Processes are tasks that are automatically polled by `svc`. Anything that doesn't have a parent or that shouldn't be cancelled when its parent is stopped is a process. This includes all commands configured by servives, e.g. `msh` and `rshd`, as well as detached background tasks, like [`rsh-serve-session`](../rsh/bin/rsh-serve-session.lua). It does not include commands manually run from the shell. The list of running processes can be viewed with `proc`, and processes can be stopped with `proc stop <name>`:

```shell
> proc
PID Name
5   service rshd
6   service msh
```

Processes are a more low-level mechanism than services, and you typically don't need to be aware of them. You might mainly be interested in processes to kill hung `rsh` sessions.

## Targets

Targets specify the sets of services that are started when the system boots. The default target is `base`, which includes services like `msh`, `named`, and `rshd`. You can define custom targets that *inherit* from smaller targets, like `base`, so that you don't need to repeat yourself. For example, in a kiosk-like application, you might define the target `kiosk` that inherits from `base` and adds a foreground `kiosk` service.

You can start services according to a target temporarily with `svc reach <name>`, or make it the default boot target with `set svc.target <name>`.

## Packages

Packages are units of applications. A package can define:

- A library that can be imported from other packages with `require` (Lua files in the package directory, with `init.lua` as root).
- One or more executables that are automatically made available in `PATH` and can use any packages (`bin` subdirectory of the package directory).
- One or more services that are automatically visible to `svc` and can be started manually or via targets (`services` subdirectory of the package directory).

For example:

- `svc` declares a library, programs like `svc` and `proc`, and no services.
- `rsh` declares no library, but has two programs `rsh` and `rshd` and the `rshd` service.

Packages are stored in the [`packages`](..) subdirectory of the sysroot. They cannot be installed otherwise or located elsewhere: whatever is in `packages` declares the entire environment.

When booting, `svc` mounts a [virtual filesystem](../vfs) called `svcbin` at `<sysroot>/run/bin` that contains a wrapper for each declared executable. This directory is added to `PATH` on boot. When invoked, wrappers configure the `require` function to look for imports in the `<sysroot>/packages` directory, so that executables can `require` libraries from packages.

Since this configured is propagated to all modules imported within a program, it means that each `require` is relative to the `packages` directory, rather then the directory of the package:

```lua
-- <sysroot>/packages/foo/init.lua
assert(require "foo.submodule" == "foo_submodule")
assert(require "bar" == "bar")

-- <sysroot>/packages/foo/submodule.lua
return "foo_submodule"

-- <sysroot>/packages/bar/init.lua
return "bar"
```

## Configuration

Now that you understand the moving pieces, we can look at how services, targets, and packages are set up. Let's look at the `rsh` package for example:

```
sys
└── packages
   └── rsh
      ├── events.lua
      ├── vt.lua
      ├── bin
      │  ├── rsh-serve-session.lua
      │  ├── rsh.lua
      │  └── rshd.lua
      └── services
         └── rshd.lua
...
```

`rsh` does not declare a library directly since it doesn't have `init.lua`, so `require "rsh"` won't work. However, since it has `events.lua` and `vt.lua`, using `require "rsh.events"` and `require "rsh.vt"` will load the corresponding files. This allows `rsh` to have private modules shared by multiple executables.

The `bin` contains three files that can be executed from shell by their name without the `.lua` suffix: `rsh-serve-session`, `rsh`, `rshd`. `rsh-serve-session` is an internal binary and is not supposed to be invoked directly, hence an unwieldy name. `rsh` is supposed to be invoked by clients, and `rshd` hosts the server. Each file is loaded directly via `dofile` and is no different from a normal CraftOS application, except for require paths being set up differently.

To avoid having to run `rshd` in a multishell by hand, the `rsh` package also declares the `rshd` service:

```lua
return {
    description = "Hosts remote shell server",
    type = "process",
    command = { "rshd" },
}
```

A service definition is a normal Lua file. It is run with an empty environment and is not supposed to have local variables or do anything except returning a table literal. `description` is a string that declares the purpose of the service and is shown by `svc status <name>`. `type` declares what kind of runtime behavior the service has, and can be one of three values:

- `process` means that a background command should be run, as specified in the `command` field. The first element is the name of the program (automatically resolved according to `PATH`), and the rest are arguments. The service is considered to be up as soon as the command starts executing, and is considered down when it exits or errors.
- `foreground` is similar to `process`, but denotes that the command should be run in foreground. For example, this is used by the [`msh`](../msh/services/msh.lua) service to show an interactive shell on boot. Errors in foreground services are shown to screen to ease debugging. You most likely want this over `process` for user-facing applications.
- `oneshot` services, unlike `process` or `foreground`, define actions that should be performed to start or stop the service, but do not run any code in the background. `command` is absent, and instead `start` must contain a function that is run when the service is started, and `stop` (optional) is run when it's stopped. `start` can be asynchronous, and the service is only considered to be up when it finishes. `stop`, if present, must be synchronous. Consider [`named`](../named/services/named.lua) for example:

```lua
return {
    description = "Configures rednet.host",
    type = "oneshot",
    start = function()
        settings.define("named.hostname", {
            description = "Unique hostname",
            type = "string",
        })
        local hostname = settings.get("named.hostname")

        if hostname ~= nil then
            peripheral.find("modem", rednet.open)
            rednet.host("named", hostname)
        end
    end,
}
```

Finally, let's look at targets. Targets are defined outside of `packages` at [`<sysroot>/targets`](../../targets) by the end user. Much like services, targets are pure Lua files that should return a table literal with the following properties:

- `services`: a list of services to start when this target is booted.
- `inherits` (optional): a list of targets to pull services from, in addition to the `services` field in the current target. For example, writing `inherits = { "base" }` will bring up `named` regardless of whether it's present in `services`. Pulling is performed recursively.
- `inherent_services` (optional): similar to `services`, contains a list of services to start, but this field is not pulled when inheriting other targets. Services listed here will only be started if this target is booted, but not if the booted target inherits from it. For example, `base` lists `msh` here, so that inheriting from `base` lets you specify your own foreground service.

A hypothetical `kiosk` target might look like this:

```lua
return {
    inherits = { "base" },
    inherent_services = { "kiosk" },
}
```
