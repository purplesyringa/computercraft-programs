# getty

A seat manager.

A seat is a pair of a monitor and a keyboard. Running `getty <seat> <command...>` executes the command while redirecting input and output to a specific monitor and keyboard, similarly to the built-in [`monitor`](https://github.com/cc-tweaked/CC-Tweaked/blob/4bc04f14162aac62cb26dd6792fcd46413beb526/projects/core/src/main/resources/data/computercraft/lua/rom/programs/monitor.lua) program. All services with UI, e.g. [`getty-default`](services/getty-default.lua), which brings up the default shell, are set up in this way.

`getty` acts as a proxy, filtering and rewriting events delivered to the computer to events that GUI programs can understand:

- Keyboard events from [Ducky Peripherals](https://modrinth.com/mod/ducky-periphs) are limited to a single keyboard (either external or built-in).
- The OS doesn't deliver presses of the Terminate button in the computer UI to all processes by default, since it'd just bring down the system. `getty` opts the GUI program into this.

The seat can either be `default`, indicating the built-in monitor and keyboard, or a device name. In the latter case, peripherals named `<seat>.monitor` and `<seat>.keyboard` must be configured with [hw](../hardware).
