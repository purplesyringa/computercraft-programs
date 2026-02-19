# rsh

Remote shell.

The server should have a hostname configured with [`named`](../named) and run `rsh/server`. Clients can connect to online servers with `rsh/client <hostname>` to start the shell, or `rsh/client <hostname> <program> <args...>` to run a particular program.
