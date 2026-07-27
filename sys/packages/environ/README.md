# environ

ComputerCraft's [`shell.execute`](https://tweaked.cc/module/shell.html#v:execute) function grants the executed program control over the current shell, including its working directory. This makes running multiple shell programs in parallel unsafe. CraftOS offers no clean workaround for this; the most obvious solution, `shell.execute("shell", ...)`, mangles arguments.

`environ` offers a configurable way to create nested and isolated environments, control their `require` behavior, and run programs or functions inside them. It's used by [`svc`](../svc) to run services and by [`runfs`](../runfs) to implement wrappers.

## API

### `environ.make(opts)`

Create a nested environment (as in `_ENV`) according to the options:

- If `opts.env` is present, that environment is reused and mutated. Otherwise, a new environment is created with an isolated shell that inherits from `opts.base_shell`, or the root `shell` if that value is absent.

- If `opts.reload` is set to `true`, the shell configuration (like the program path and completion rules) is updated. This affects, for instance, whether advanced-computer-only commands are visible, according to the value of `term` at the time of call.

- If `opts.sysroot_require` is set to `true`, `require` is initialized to load files from the sysroot. Otherwise, if `opts.path` is present, CraftOS-style `require` is initialized relative to the directory of `opts.path`. (Running a program from the shell manually always uses the CraftOS behavior, which is why [`runfs`](../runfs) generates wrappers that re-execute the correct binary with `sysroot_require = true`.) If neither option is set, `require` is not populated.

### `environ.exec(opts, command, ...)`

Run the command `command` with arguments `...` in a custom environment, constructed as if by `environ.make(opts)`.

The code for the command is loaded from `opts.path`. If missing, `opts.path` defaults to [`shell.resolveProgram(command)`](https://tweaked.cc/module/shell.html#v:resolveProgram) run in the new environment. (This counts as `opts.path` being present for the purposes of `sysroot_require = false` semantics.)

If the program throws an error, that error is surfaced without being caught, unlike `shell.execute`.

A typical usage pattern looks like this:

```lua
-- Execute an isolated command.
environ.exec({}, "ls")

-- Execute a command normally, inheriting properties from the current shell.
environ.exec({ base_shell = shell }, "ls")

-- Execute a command with a virtual terminal (assume the terminal is already set up).
environ.exec({ base_shell = shell, reload = true }, ...)

-- Simulate a wrapper.
environ.exec({ env = _ENV, sysroot_require = true, path = "<path to wrapper>" }, arg[0], ...)
```
