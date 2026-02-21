# Name daemon

`rednet` allows computers to use different hostnames on different protocols. This means that there is no single per-computer hostname setting, which is an issue if you're trying to deploy the same code to multiple computers.

In this scenario, `named` becomes the source of truth for hostnames: hostnames can be configured from shell with `hostname <hostname>` or from Lua with `named.setHostname(hostname)`, and retrieved from shell with `hostname` and from Lua with `named.hostname()`. If the hostname is not configured, `named.hostname()` errors.

Example:

```lua
local named = require "named"

rednet.host("myprotocol", named.hostname())
```

The `named` service automatically opens modems and announces the hostname to the network, so you don't need to do anything else.
