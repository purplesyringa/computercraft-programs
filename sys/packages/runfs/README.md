# runfs

This file system is automatically mounted by [`svc`](../svc) at `<sysroot>/run`. It acts as a source of truth about all packages, binaries, and targets available in the system.

There are two major parts to this file system:

- The `bin` directory includes wrappers for all binary files declared in all available packages. The wrappers configure `require` to allow the binary to import libraries before passing control to the correct Lua script. This directory is added to the `PATH` environment variable.
- The `packages` and `target` subdirectories merge the corresponding directories of the sysroot and the impure environment (if enabled).


## Impure environment

The `/impure` directory is called the *impure environment*. It offers a way to create or modify packages locally without rebuilding the `initrd` or unpacking `sys`. Packages in `/impure/packages` override packages in `<sysroot>/packages` or add new ones (and similarly for targets). They are local to the computer and are not shared by [`netboot`](../netboot), cannot override `svc` and a couple other core packages, and may break on OS updates if not updated accordingly. They are intended to be purely a development aid, not a distribution mechanism.

The impure environment is disabled by default: even if `/impure` exists, packages and targets are not imported from it. Use `impure enable` to change that. Libraries and binaries become available automatically, service and target updates are only realized on `svc reload`.


## Usage

From shell:

- `impure` -- show whether the impure environment is enabled, along with its packages and targets, and the system taint status.
- `impure enable`/`impure disable` -- enable or disable the impure environment.

From Lua:

- `runfs.mount(path)` -- mount `runfs` at a given path.
- `runfs.getImpure()` -- check if the impure environment is enabled.
- `runfs.setImpure(value)` -- enable (`true`) or disable (`false`) the impure environment.
