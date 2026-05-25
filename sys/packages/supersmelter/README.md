# supersmelter

A smart supersmelter.

This program is designed for a turtle managing a furnace array. The turtle should have the following upgrades:

- A chunk vial from Turtlematic in the left equipment slot.
- A crafting table in the right equipment slot.

The turtle should be connected, via wired modems, to:

- An advanced 2x1 display in the UI.
- An arbitrary count of furnaces, but at least one.
- An arbitrary count of blast furnaces, but at least one.
- An optional decorative furnace in the UI.
- 3 inventories containing input, output, and fuel respectively. Barrels located around the decorative furnace are an obvious choice.
- A "holding" inventory.
- One or more "SCRAM" inventories (chests or barrels), depending on the number of furnaces: one slot must per furnace must be available.

Run `supersmelter-setup` to detect and save the IDs of the peripherals once. You should then use the `supersmelter` executable, service, or target. Mod-specific extensions can be adjusted in `data.lua`.

The UI should be quite intuitive. Add items to the input inventory, tap the monitor, and wait for items in the output inventory. You will probably want to keep a lot of fuel. Tap the monitor again to cancel smelting, returning the unsmelted items. The supersmelter automatically recovers after forced unloads and server restarts. It automatically keeps the chunk loaded while smelting, but not in idle. It can handle raw metal (storage) blocks as input and outputs metal (storage) blocks. Ores are spread among both blast furnaces and normal furnaces in a 2:1 ratio, and other items are only spread among normal furnaces. Different types of items can be smelted at once, with the scheduler adapting almost optimally.
