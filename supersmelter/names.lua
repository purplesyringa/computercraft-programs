local config_file = fs.open(shell.resolve("config.txt"), "r")
assert(config_file, "config not available -- run setup")
local config_text = config_file.readAll()
config_file.close()
local config = textutils.unserialize(config_text)
assert(config, "failed to deserialize config")

local decorative_furnace = nil
if config.decorative_furnace ~= nil then
	decorative_furnace = peripheral.wrap(config.decorative_furnace)
end

local normal_furnaces = {}
local blast_furnaces = {}
for _, name in pairs(config.furnaces) do
	local furnace = peripheral.wrap(name)
	if peripheral.hasType(furnace, "minecraft:blast_furnace") then
		table.insert(blast_furnaces, furnace)
	else
		table.insert(normal_furnaces, furnace)
	end
end

return {
	decorative_furnace = decorative_furnace,
	holding_inventory = peripheral.wrap(config.holding_inventory),
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
