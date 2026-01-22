-- Can't use the implementation from `util` because `util` requires `names`.
function parForEach(tbl, callback)
	local closures = {}
	for _, element in pairs(tbl) do
		table.insert(closures, function()
			return callback(element)
		end)
	end
	return parallel.waitForAll(unpack(closures))
end

local inventories = nil
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
		parForEach(inventories, function(check_inventory)
			local name = peripheral.getName(check_inventory)
			local is_direct = (
				name == "front"
				or name == "back"
				or name == "left"
				or name == "right"
				or name == "top"
				or name == "bottom"
			)
			if not is_direct and next(check_inventory.list()) then
				inventory = check_inventory
			end
		end)
	end
	local name = peripheral.getName(inventory)

	print(string.format("Located inventory %s, remove item", name))
	while next(inventory.list()) do
		os.sleep(1)
	end

	return name
end

local function locate_unique_furnaces(furnaces, out, decorative_furnace)
	local turtle_modem_name = peripheral.find("modem").getNameLocal()

	turtle.select(1)
	turtle.equipLeft()

	local duplicates = {}
	for _, furnace in pairs(furnaces) do
		local name = peripheral.getName(furnace)
		if name ~= decorative_furnace and not duplicates[name] then
			furnace.pullItems(turtle_modem_name, 1, nil, 1)
			parForEach(furnaces, function(furnace2)
				if next(furnace2.list()) then
					duplicates[peripheral.getName(furnace2)] = true
				end
			end)
			furnace.pushItems(turtle_modem_name, 1, nil, 1)
			table.insert(out, name)
		end
	end

	turtle.equipLeft() -- unequip
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

	inventories = { peripheral.find("inventory") }
	parForEach(inventories, function(inventory)
		local name = peripheral.getName(inventory)
		check(not next(inventory.list()), string.format("Inventory %s must be empty", name))
	end)

	if not ok then
		return
	end

	print("Sanity checks passed")

	local decorative_furnace = nil
	io.write("Would you like to set up a decorative furnace? [y/N] ")
	if io.read() == "y" then
		decorative_furnace = queryInventoryName("decorative furnace")
	end

	print("Discovering working furnaces")
	local furnaces = {}
	locate_unique_furnaces({ peripheral.find("minecraft:furnace") }, furnaces, decorative_furnace)
	locate_unique_furnaces(
		{ peripheral.find("minecraft:blast_furnace") },
		furnaces,
		decorative_furnace
	)

	local holding_inventory = queryInventoryName("holding inventory")
	local scram_inventory = queryInventoryName("scram inventory")
	local input_inventory = queryInventoryName("input inventory")
	local fuel_inventory = queryInventoryName("fuel inventory")
	local output_inventory = queryInventoryName("output inventory")

	local config = {
		decorative_furnace = decorative_furnace,
		holding_inventory = holding_inventory,
		scram_inventory = scram_inventory,
		input_inventory = input_inventory,
		fuel_inventory = fuel_inventory,
		output_inventory = output_inventory,
		furnaces = furnaces,
	}

	local file = fs.open(shell.resolve("config.txt"), "w")
	file.write(textutils.serialize(config))
	file.close()

	print("Config saved to config.txt")
end

main()
