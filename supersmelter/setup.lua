local ok = true

local function check(cond, message)
	ok = ok and cond
	if not cond then
		print(message)
	end
	return cond
end

local function queryInventoryName(description)
	print("Put an item into the", description)

	local inventory = nil
	while not inventory do
		os.sleep(1)
		inventory = peripheral.find("inventory", function(name, inventory)
			local is_direct = (
				name == "front"
				or name == "back"
				or name == "left"
				or name == "right"
				or name == "top"
				or name == "bottom"
			)
			return not is_direct and next(inventory.list())
		end)
	end
	local name = peripheral.getName(inventory)

	print(string.format("Located inventory %s, remove item", name))
	while next(inventory.list()) do
		os.sleep(1)
	end

	return name
end

local function main()
	local monitor = peripheral.find("monitor")
	if check(monitor, "No monitor found") then
		local width, height = monitor.getSize()
		check(
			width >= 18 and height >= 5,
			"Monitor too small, needs to be at least 18x5 chars = 2x1 blocks"
		)
	end

	local left = turtle.getEquippedLeft()
	check(
		left and left.name == "turtlematic:chunk_vial",
		"No chunk vial found in left equipment slot"
	)
	local right = turtle.getEquippedRight()
	check(
		right and right.name == "minecraft:crafting_table",
		"No crafting table found in right equipment slot"
	)

	local is_turtle_inventory_empty = true
	for slot = 1, 16 do
		is_turtle_inventory_empty = is_turtle_inventory_empty and turtle.getItemCount(slot) == 0
	end
	check(is_turtle_inventory_empty, "All slots in turtle inventory must be empty")

	peripheral.find("inventory", function(name, inventory)
		check(not next(inventory.list()), string.format("Inventory %s must be empty", name))
	end)

	check(peripheral.hasType("front", "inventory"), "No helper inventory in front of the turtle")
	local helper_inventory = peripheral.wrap("front")

	local helper_inventory_wired = nil
	if left and is_turtle_inventory_empty and not next(helper_inventory.list()) then
		turtle.select(1)
		turtle.equipLeft()
		turtle.drop()
		helper_inventory_wired = peripheral.find("inventory", function(name, inventory)
			local item = inventory.getItemDetail(1)
			return name ~= "front" and item and item.name == left.name
		end)
		turtle.suck()
		turtle.equipLeft()
		check(helper_inventory_wired, "Helper inventory not connected to wired network")
	end

	if not ok then
		return
	end

	print("Sanity checks passed")

	local decorative_furnace = nil
	io.write("Would you like to set up a decorative furnace? [y/N] ")
	if io.read() == "y" then
		decorative_furnace = queryInventoryName("decorative furnace")
	end

	local scram_inventory = queryInventoryName("scram inventory")
	local input_inventory = queryInventoryName("input inventory")
	local fuel_inventory = queryInventoryName("fuel inventory")
	local output_inventory = queryInventoryName("output inventory")

	local config = {
		decorative_furnace = decorative_furnace,
		helper_inventory = peripheral.getName(helper_inventory_wired),
		scram_inventory = scram_inventory,
		input_inventory = input_inventory,
		fuel_inventory = fuel_inventory,
		output_inventory = output_inventory,
	}

	local file = fs.open(shell.resolve("config.txt"), "w")
	file.write(textutils.serialize(config))
	file.close()

	print("Config saved to config.txt")
end

main()
