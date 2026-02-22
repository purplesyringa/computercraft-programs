# msh

*msh* (short for meow shell) is an improved version of the built-in `shell` and related scripts. It is operationally a direct replacement of `shell`, but has to be named differently due to PATH conflicts.

Use `msh` to start the shell, or `multishell` to start a multishell instance with `msh`. The `msh` service does this automatically on boot, so you're most likely already using it.

## Features

- `msh` supports configurable shell prompts with the `shell.prompt` setting. The hostname and the current directory are shown by default.
- `multishell`, `fg`, and `bg` are available in PATH on non-advanced computers. Tabs can be switched by pressing (Shift+)Pause.
- Custom `motd`.
