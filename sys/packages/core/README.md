# core

The "kernel" of the system.

`core` is not a normal library: while it can be `require`d to access APIs for controlling the running system, its main purpose is to provide an entrypoint for the system.

To start the OS, you can either run [`boot.lua`](boot.lua) from this directory or [`startup.lua`](../../startup.lua) from the sysroot (which basically just `require`s `boot.lua`):

```shell
> <sysroot>/packages/core/boot
or
> <sysroot>/startup
```

Upon booting, you should be facing a familiar ([but improved](../msh)) shell.

To configure the OS to start automatically, save `shell.run("<sysroot>/startup")` to `startup.lua` in the disk root.

## Processes

Processes are coroutines that are automatically polled by `core`. Anything that doesn't have a parent or that shouldn't be cancelled when its parent is stopped is a process. A process *can* run a program, e.g. that's how some services host their daemons and how [`rshd`](../rsh) runs a [detached background task](../rsh/bin/rsh-serve-session.lua), but it doesn't *have* to -- it can run any function, like in [RedRun](https://gist.github.com/MCJack123/473475f07b980d57dd2bd818026c97e8).

Notably, commands manually run from the shell are not processes -- those are polled by the shell and die with it.

Processes are a low-level mechanism, and you typically don't need to be aware of them. Most aspects of the system should be controlled with [`svc`](../svc) instead. You might primarily be interested in processes to kill hung [`rsh`](../rsh) sessions or to start temporary [`getty`](../getty) sessions.

The list of running processes can be viewed with `proc`:

```shell
> proc
PID Name
3   service named
4   service getty-default
5   service netbootupd
6   service rshd
7   service rednetd
8   rsh-serve-session 0:189222384
```

Processes can be killed with `proc stop <pid>` and started with `proc start <program> <args...>`. `core` exposes the following API for programmatic usage:

- `core.startProcess(name, f[, on_killed])` -- run the function `f` in a new process named `name`, registering `on_killed` to run if it's killed. Returns the PID. `f()` will not be called immediately, but only after the current process yields. The process lifetime is guaranteed to end either by the process terminating normally or by calling `on_killed`. `on_killed` should never fail or yield.

- `core.stopProcess(pid)` -- send a `terminate` event to the process with the given PID. The event will be delivered soon after the current process yields.

- `core.killProcess(pid)` -- immediately cancel the process with the given PID, and call its `on_killed` handler.

- `core.listProcesses()` -- get the list of processes in format `{ { pid = ..., name = ... }, ... }`.

Each process runs in the global environment. It receives unprocessed native events, and it's `term` refers to the native terminal. This means that [keyboard events won't be layout-mapped](../keyboard), events from all keyboards will be delivered, the `terminate` event won't be delivered, and [non-default seats](../getty) will be unsupported. For these reasons, foreground programs should typically run under [`getty`](../getty) instead of being run directly.

## Imminent handlers

In addition to handling the main event loop, `core` has special handling for `os.shutdown` and `os.reboot`, allowing programs to run quick last-chance handlers.

`core.withImminentHandler(handler, f, ...)` registers `handler(reason)` to run when the computer is about to shutdown (`reason = "shutdown"`) or reboot (`reason = "reboot"`), and runs `f(...)`. When `f` returns, the handler is unregistered. The handler is also removed if the current coroutine is dropped.

This is a `try`..`catch` of sorts, but it differs from a hypothetical `pcall`-based solution in that the handler is invoked correctly regardless of who triggered the shutdown/reboot: `f` itself, another coroutine in the same process, or a different process.

## Hooks

`core` by itself does not know how to bring up the system -- it defers to [`svc`](../svc). Upon booting, it runs the `svc-boot` command in a background process.

In addition, `core` has a "recovery" hook: pressing <kbd>Alt+Terminate</kbd> starts a recovery shell by running `svc-recovery -f`. This hotkey can be entered only on internal keyboard. It typically brings down most services and spawns a shell on the main seat.
