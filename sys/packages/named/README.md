# Name daemon

`rednet` allows computers to use different hostnames on different protocols. This means that there is no single per-computer hostname setting, which is an issue if you're trying to deploy the same code to multiple computers.

In this scenario, `named` becomes the source of truth for hostnames: hostnames can be configured from shell with `hostname <hostname>` or from Lua with `named.setHostname(hostname)`, and retrieved from shell with `hostname` and from Lua with `named.hostname()`. (If the hostname is not configured, `named.hostname()` errors.)

`named` is also responsible for hosting services and resolving hostnames to computer IDs. The `named` service automatically calls `rednet.host` with the configured hostname, so you most likely don't need to call `rednet.host` manually. Since all protocols use the same hostname in this model, you can use `named.lookup(hostname)` instead of `rednet.lookup(..., hostname)`. This also handles the case where `hostname` is (a stringification of) a number, allowing connection to unnamed computers by computer ID.

Example:

```lua
local named = require "named"

local computer_id = named.lookup(hostname)
```

The `named` service automatically opens modems and announces the hostname to the network.
