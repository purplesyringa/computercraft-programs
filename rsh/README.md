# rsh

Remote shell.

The server should have a hostname configured with [`named`](../named) and run `rsh/server`. Clients can connect to online servers with `rsh/client <hostname>` to start the shell, or `rsh/client <hostname> <program> <args...>` to run a particular program.

When running without arguments, the shell is always `shell` and not `multishell`, since `multishell` does not retain the scrollback. You can always use `rsh/client <hostname> multishell` to open a multishell immediately upon connecting. Note that you might get nested multishells this way.

The rsh server patches the shell to add the hostname to the prompt, so that it's a bit easier to not get lost.
