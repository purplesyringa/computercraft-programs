# startup

Startup logic and system updater.


### Usage

The `resys` executable updates the system. `resys` fetches the latest initrd image from https://cc.purplesyringa.moe/initrd.lua (or another provided server) and safely replaces the active `startup.lua`.

In addition, the `startup` library exposes the following API:

- `startup.getScript()`: retrieve the startup script.
- `startup.setScript(code)`: modify the startup script.

These functions are different from just reading/writing `startup.lua` because they enforce atomicity: `setScript` creates the new script in `startup/svc-new.lua` before moving it to `startup.lua`, and `getScript` takes into account that the script may be located there if `startup.lua` is missing.
