# X-raying turtle

A turtle that uses the universal scanner from UnlimitedPeripheralWorks to X-ray for ancient debris. Automatically mines the debris and returns to its starting point.


## Usage

This is non-trivial, so read till the end.

The turtle's inventory should be set up as follows:

- Slot 1: universal scanner
- Slot 2: (char)coal blocks as fuel (the turtle assumes a specific fuel quality, and you'll need a lot of fuel anyway, so this is the best option)
- Slot 3: ender modem (for logging)
- Slots 4-16: output (pre-initialized with 1 ancient debris in each as filter)
- Left equipment slot: diamond pickaxe
- Right equipment slot: chunk vial

The turtle must be run as `main X Y Z C`, where `X`, `Y`, `Z` are the coordinates of the block the turtle is initially in, and `C` is the approximate number of ancient debris the turtle should mine.

- `X` and `Z` are used only for logging, so that the listener receives absolute coordiantes. You can specify `0` here if you're lazy and don't care about logs.
- `Y` should be specified exactly right so that the turtle doesn't get stuck in the bedrock floor. You should most likely place the turtle at `Y = 16`.
- The maximum reasonable value for `C` is `800`, since there isn't enough space for more ancient debris in the turtle inventory.

Due to [a bug in Turtlematic](https://github.com/SirEdvin/Turtlematic/issues/27), chunk loading in the nether does not work properly, and this *will* break the turtle. You *need* to apply [a patch](https://github.com/SirEdvin/Turtlematic/pull/30) to the mod to fix it.

The turtle will dig in the direction it's facing, that is, the direction you're facing when placing the turtle. It scans a 49-block-wide area, so you want to put turtles every 49 blocks if you have several.

The turtle automatically broadcasts its location via the ender modem, using its label as a key. You can use `listen.lua` to listen to these messages and log them. You'll probably want to chunk-load the logger.
