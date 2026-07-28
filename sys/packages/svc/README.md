# svc

A service manager.

`svc` is not a normal library: while it can be `require` to access APIs for controlling services, those APIs are only available when the system has booted from [`svc-boot`](bin/svc-boot.lua), which in general is not required.

The main two nouns of `svc` are *services* and *targets*.

## Services

Services define the runtime properties of the system. They control what the user-facing program is (the [`msh`](../msh) shell by default), what programs are run in the background (e.g. [`rshd`](../rshd)), and what hooks are run when the system is started (e.g. [`named`](../named)). Services are referred to by a short name and are not otherwise configurable. You can view the list of declared and running services by running `svc`, start services with `svc start <name>`, and stop them with `svc stop <name>`:

```shell
> svc
Target: fileserver (up)

Service         Status
getty-default   up
named           up
netbootd        up
netbootupd      up
nfsd@pub        up
rednetd         up
rshd            up
...and 10 stopped service(s)
```

A service definition is a Lua file stored in `packages/*/services/*.lua`. It is run with an empty environment and is not supposed to have local variables or do anything except returning a table literal, for example:

```lua
-- rshd.lua
return {
    description = "Hosts remote shell server",
    type = "process",
    command = { "rshd" },
}
```

`description` is a string that declares the purpose of the service and is shown by `svc status <name>`.

`type` declares what kind of runtime behavior the service has, and can be one of two values:

- `process` means that a command specified in the `command` field should be run. The first element is the name of the program (automatically resolved according to `PATH`), and the rest are arguments. The service is considered to be up as soon as the command starts executing, and is considered down when it exits or errors. Since [processes receive unprocessed events](../core), user-facing applications, like shells, should typically be run under [`getty`](../getty), which filters events from a specific seat and redirects the terminal if necessary. For example, take a look at the [`getty-default`](../getty/services/getty-default.lua) service that shows an interactive shell on boot:

```lua
return {
    description = "Shell on default seat",
    type = "process",
    command = { "getty", "default", "multishell" },
}
```

- `oneshot` services define actions that should be performed to start or stop the service, but do not run any code in the background. `command` is absent, and instead `start` must contain a function that is run when the service is started, and `stop` (optional) is run when it's stopped. `start` can be asynchronous, and the service is only considered to be up when it finishes. `stop`, if present, must be synchronous. Consider [`netbootupd`](../netboot/services/netbootupd.lua) for example:

```lua
return {
    description = "Updates netboot script in startup.lua",
    type = "oneshot",
    start = function()
        local core = require "core"
        local vfs = require "vfs"
        local startup = require "startup"

        local old_startup = startup.getScript()
        local new_startup = vfs.read(fs.combine(core.sysroot, "packages", "netboot", "boot.lua"))
        if (
            old_startup
            and #old_startup < 4096 -- don't override unpacked initrd
            and old_startup:match('"=netboot"')
            and old_startup ~= new_startup
        ) then
            startup.setScript(new_startup)
        end
    end,
}
```

## Targets

Targets specify the sets of services that are started when the system boots. For example, the target `base` includes services like `msh`, `named`, and `rshd`. You can start services according to a target temporarily with `svc reach <name>`, or make it the default boot target with `svc reach <name> --persist`.

Targets can *inherit* from smaller targets, like `base`, so that you don't need to repeat yourself. For example, in a kiosk-like application, you might define the target `kiosk` that inherits from `base` and adds a `kiosk` service.

Targets are defined outside of `packages` at [`<sysroot>/targets`](../../targets). These are meant to be modified by the end user as necessary. Much like services, targets are pure Lua files that return a table literal with the following properties:

- `services` (optional): a list of services to start when this target is booted.
- `inherits` (optional): a list of targets to pull services from, in addition to the `services` field in the current target. For example, writing `inherits = { "base" }` will bring up `named` regardless of whether it's present in `services`. Pulling is performed recursively.

A hypothetical `kiosk` target might look like this:

```lua
return {
    inherits = { "base" },
    services = { "kiosk" },
}
```
