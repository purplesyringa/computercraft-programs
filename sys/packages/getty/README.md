# getty

A seat manager.

A seat is a pair of a monitor and a keyboard. Running `getty <seat> <command...>` executes the command while redirecting input and output to a specific monitor and keyboard, similarly to the built-in [`monitor`](https://github.com/cc-tweaked/CC-Tweaked/blob/4bc04f14162aac62cb26dd6792fcd46413beb526/projects/core/src/main/resources/data/computercraft/lua/rom/programs/monitor.lua) program. All services with UI, e.g. [`getty-default`](services/getty-default.lua), which brings up the default shell, are set up in this way.

`getty` acts as a proxy, filtering and rewriting events delivered to the computer to events that GUI programs can understand:

- Keyboard events from [Ducky Peripherals](https://modrinth.com/mod/ducky-periphs) are limited to a single keyboard (either external or built-in).
- The OS doesn't deliver presses of the Terminate button in the computer UI to all processes by default, since it'd just bring down the system. `getty` opts the GUI program into this.

The seat name `default` indicates the built-in monitor and keyboard. Other seats can be configured with [hw](../hardware), using peripherals named `<seat>.monitor` and `<seat>.keyboard`. `monitor` can be either `default` (denoting the built-in monitor) or a monitor peripheral name. `keyboard` may be absent (denoting no input device), `default` (denoting the built-in keyboard), or a keyboard peripheral name.

`getty` also integrates with [`keyboard`](../keyboard) and supports switching layouts.

Seats can be configured programmatically to change their default or actual scale and palette.

## CLI

`seat` program allows tweaking current seat.

- `seat [+seat] reset --scale`: Reset monitor scale on seat `seat` (or current seat) to configured. Does nothing on internal monitors or if the configured scale is "keep" (default).
- `seat [+seat] reset --palette`: Reset monitor palette on seat `seat` (or current seat) to configured.
- `seat [+seat] reset`: Resets everything on seat `seat` (or current seat) that can be reset.
- `seat [+seat] scale [scale|'keep']`: Prints current configured scale or configures the scale.
- `seat [+seat] color <index|name> [rgb|'native']`: Prints configured palette color or sets it. RGB values are supplied in hex form, e.g. `102030` would be 16 red, 32 green, 48 blue.


## `getty.Defaults`

`Defaults` configures default seat settings, namely scale and palette.

### `Defaults.new(name)`

Creates a new `Defaults` for seat `name`. The seat does not need to actually exist.

### `defaults.name`

Seat name.

### `defaults:getScale()`

Returns the configured scale, or `nil` if the scale should be kept unchanged.

### `defaults:setScale(scale)`

Updates the default scale.

### `defaults:getPalette[format]()`

Returns the configured palette.

### `defaults:setPalette[format](palette)`

Updates the default palette.


## `getty.Seat`

`Seat` allows getting and setting actual setting values, and not defaults. Multiple `Seat` per seat can be created.

### `Seat.new(name)`

Creates a new `Seat` for seat `name`. The seat monitor must be connected.

### `getty.current()` and `Seat.current()`

If the current program is launched under a seat, returns the `Seat` object for the seat. Otherwise, returns `nil`.

Currently, only `getty` creates seats, e.g. this would return `nil` under `rsh`.

### `seat.defaults`

`Defaults` associated with the seat.

### `seat.names.monitor`

Resolved monitor name.

### `seat.names.keyboard`

Resolved keyboard name, if any.

### `seat.monitor`

Wrapped `monitor` peripheral or `term`.

### `seat:getScale()`

Returns the current scale. Returning value may be different from the default.

### `seat:setScale(scale)`

Set the current scale to `scale` without changing the default.

### `seat:resetScale()`

Resets the current scale to the configured one.

### `seat:getPalette[format](palette, show_native)`

Returns the current palette. Returning value may be different from the default.

Unless `show_native` is `true`, this function replaces unchanged native colors with `nil`.

### `seat:setPalette[format](palette, apply_current)`

Sets the current palette to `palette` without changing the default.

If `apply_current` is `true`, sets the current `term` palette to `palette`.

### `seat:resetPalette(apply_current)`

Resets the current palette to the configured one.

If `apply_current` is `true`, applies the seat palette to the current `term`.

### `seat:reset(apply_current)`

Reset scale and palette to the configured values. `apply_current` is passed to `resetPalette`.


## Palette formats

`[format]` part of the function name determines the input or output format of palettes.

Use `getty.palettes.[from]To[To]` functions, e.g. `palettes.stringToList`, to convert between formats. Only adjacent formats can be converted between: `String` to `Map` conversion requires an extra step.

### `String` format

Comma-separated list of hex colors in [`colors` order](https://tweaked.cc/module/colors.html). Empty string means "use native color". Examples:

- (empty string): Native palette
- `009900` or `9900`: Hacker style (change white to greenish)
- `,,,,,,,,,,,,,,,0` (15 commas): Full-black black

### `List` format

Map from blit-style indexes (0-based) to 24-bit integers representing color. Examples:

- `{}`: Native palette
- `{ [0] = 0x009900 }`: Hacker style (change white to greenish)
- `{ [15] = 0 }`: Full-black black

### `Map` format

Map from `colors.COLOR` to 24-bit integers representing color. Examples:

- `{}`: Native palette
- `{ [colors.white] = 0x009900 }`: Hacker style (change white to greenish)
- `{ [colors.black] = 0 }`: Full-black black


## `getty.Controller`

`Controller` allows running programs on the seat it was created for. Only one `Controller` object per seat should be used at a time. If running multiple commands on the same seat is desired, use `multishell` or another terminal multiplexer.

### `Controller.new(name)`

Creates a `Controller` for seat `name`. The seat monitor must be connected. Intended for `getty` use.

### `controller.seat`

`Seat` instance associated with the seat.

### `controller:run(command)`

Runs `command` inside the seat until its completion. Intended for `getty` use.

### `controller.deliver(event)`

Send an event to the running program. The event won't be processed, and will be sent as is. Internal use only.

### `controller.keyboard`

If the seat has a running program, its [keyboard handler](../keyboard) object
