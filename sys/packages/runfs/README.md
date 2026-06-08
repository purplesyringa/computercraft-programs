# runfs

This file system is automatically mounted by [`svc`](../svc) at `<sysroot>/run`. It acts as a source of truth about all packages, binaries, and targets available in the system.

There are two major parts to this file system:

- The `bin` directory includes wrappers for all binary files declared in all available packages. The wrappers configure `require` to allow the binary to import libraries before passing control to the correct Lua script. This directory is added to the `PATH` environment variable.
- The `packages` and `target` subdirectories are read-only mirrors of the corresponding directories of the sysroot.


## Usage

- `runfs.mount(path)`: Mount `runfs` at a given path.
