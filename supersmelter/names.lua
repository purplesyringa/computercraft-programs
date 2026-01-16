local config_file = fs.open("config.txt", "r")
assert(config_file, "config not available -- run setup")
local config_text = config_file.readAll()
config_file.close()
local config = textutils.unserialize(config_text)
assert(config, "failed to deserialize config")

local decorative_furnace = nil
if config.decorative_furnace ~= nil then
	decorative_furnace = peripheral.wrap(config.decorative_furnace)
end

local normal_furnaces = { peripheral.find("minecraft:furnace", function(name, furnace)
	return name ~= config.decorative_furnace
end) }
local blast_furnaces = { peripheral.find("minecraft:blast_furnace", function(name, furnace)
	return name ~= config.decorative_furnace
end) }

return {
	decorative_furnace = decorative_furnace,
	helper_inventory = peripheral.wrap(config.helper_inventory),
	scram_inventory = peripheral.wrap(config.scram_inventory),
	input_inventory = peripheral.wrap(config.input_inventory),
	fuel_inventory = peripheral.wrap(config.fuel_inventory),
	output_inventory = peripheral.wrap(config.output_inventory),

	monitor = peripheral.find("monitor"),
	normal_furnaces = normal_furnaces,
	blast_furnaces = blast_furnaces,
	all_furnaces = table.move(
		blast_furnaces,
		1,
		#blast_furnaces,
		#normal_furnaces + 1,
		{ unpack(normal_furnaces) }
	),
}
