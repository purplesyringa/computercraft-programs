# X-raying turtle

A turtle that uses the universal scanner from UnlimitedPeripheralWorks to X-ray for ancient debris. Automatically mines the debris and returns to its starting point.


## Usage

This is non-trivial, so read till the end.

The turtle's inventory should be set up as follows:

- Slot 1: universal scanner
- Slot 2: ender modem (for logging)
- Slots 3-16: output slots. Must be pre-filled with 1 ancient debris in each slot as filter.
- Left equipment slot: diamond pickaxe
- Right equipment slot: chunk vial

The turtle must be run as `main X Y Z D C`, where:

- `X`, `Y`, `Z` are the coordinates of the block the turtle is initially in. `X` and `Z` are used only for logging, so that the listener receives absolute coordiantes. You can specify `0` here if you're lazy and don't care about logs. `Y` should be specified exactly right so that the turtle doesn't get stuck in the bedrock floor. You should most likely place the turtle at `Y = 16`.
- `D` is the direction the turtle is facing, that is, the direction you're facing when placing the turtle. It can be either of `east`, `north`, `west`, or `south`. This is very critical to specify correctly.
- `C` is the approximate number of ancient debris the turtle should mine. The maximum reasonable value is `850`, since there isn't enough space for more ancient debris in the turtle inventory.

The turtle must be populated with fuel and cannot refuel while digging. Collecting 1 ancient debris requires moving about 25 blocks on average, so for `C = 850`, you need about 21250 units of fuel; I recommend giving it some more just in case. That's above the limit for normal turtles, so you'll need to use advanced turtles if you need this much debris.

Due to [a bug in Turtlematic](https://github.com/SirEdvin/Turtlematic/issues/27), chunk loading in the nether does not work properly, and this *will* break the turtle. You *need* to apply vanutp's patches ([1](https://github.com/SirEdvin/Turtlematic/pull/30), [2](https://github.com/vanutp-forks/Turtlematic/commit/d7cca61e50f2783e588a4674740e5b8b27e36f30)) to the mod to fix it.

The turtle will dig in the direction it's facing. It scans a 49-block-wide area centered around the turtle, so you want to put turtles every 49 blocks if you have several. I have encountered issues with turtles getting unloaded if two turtles go in the same chunk, at least without the second patch, so you might want to make some more space to prevent this from happening.

The turtle automatically broadcasts its location via the ender modem, using its label as a key. You can use `listen.lua` to listen to these messages and log them. You'll probably want to chunk-load the logger.
