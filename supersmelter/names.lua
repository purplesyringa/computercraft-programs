local decorative_furnace = peripheral.wrap("minecraft:furnace_13")
local normal_furnaces = { peripheral.find("minecraft:furnace", function(name, furnace)
	return name ~= peripheral.getName(decorative_furnace)
end) }
local blast_furnaces = { peripheral.find("minecraft:blast_furnace", function(name, furnace)
	return name ~= peripheral.getName(decorative_furnace)
end) }

return {
	decorative_furnace = decorative_furnace,
	helper_chest = peripheral.wrap("minecraft:chest_1"),
	scram_chest = peripheral.wrap("minecraft:chest_2"),
	input_barrel = peripheral.wrap("minecraft:barrel_2"),
	fuel_barrel = peripheral.wrap("minecraft:barrel_3"),
	output_barrel = peripheral.wrap("minecraft:barrel_4"),

	monitor = peripheral.find("monitor"),
	redstone_relay = peripheral.find("redstone_relay"),
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
