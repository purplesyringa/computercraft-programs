# getty

A seat manager.

By default, all services and processes run in a vacuum, where they directly receive all events delivered to the computer (with the exception of `terminate`). That is not always correct for programs with UI:

- You might want to set up [a terminal redirect](https://tweaked.cc/module/term.html#v:redirect) so that the program outputs to a monitor.
- If you're playing with [Ducky Peripherals](https://modrinth.com/mod/ducky-periphs), you most certainly want to filter for `key`/`key_up`/`char` events from a single keyboard (either external or built-in).
- When the Terminate button is pressed in the computer UI, the `terminate` event is by default not passed to all processes, since it'd just bring down the system. Instead, it's rewritten to `fg_terminate`. Programs with UI most likely expect a normal `terminate` event.

`getty` performs this filtering and rewriting for you. When invoked as `getty <seat-configuration> <command...>`, it runs the command while redirecting input and output according to the seat configuration, similarly to the [`monitor`](https://github.com/cc-tweaked/CC-Tweaked/blob/4bc04f14162aac62cb26dd6792fcd46413beb526/projects/core/src/main/resources/data/computercraft/lua/rom/programs/monitor.lua) program. All services with UI, e.g. [`getty-default`](services/getty-default.lua), which brings up the default shell, are set up in this way.

`seat-configuration` has the following syntax:

- The most generic form is `<monitor-id>/<keyboard-id>`, where the IDs are from the wired names of the peripherals `monitor_N` and `keyboard_N`.
- `default` can be used as the ID to indicate either the built-in computer terminal ([`term.native`](https://tweaked.cc/module/term.html#v:native)) or the built-in keyboard.
- `default` can also be used as the entire configuration as a shorthand for `default/default`.
