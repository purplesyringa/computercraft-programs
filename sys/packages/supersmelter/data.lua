return {
	fuel_capacity = {
		["minecraft:lava_bucket"] = 100,
		["minecraft:coal_block"] = 80,
		["minecraft:dried_kelp_block"] = 20,
		["minecraft:coal"] = 8,
		["minecraft:charcoal"] = 8,
		["minecraft:bamboo"] = 0.25,
	},
	input_storage_blocks = {
		["minecraft:raw_iron"] = {
			block_slot = 1,
			item_slot = 2,
			storage_block_name = "minecraft:raw_iron_block",
		},
		["minecraft:raw_copper"] = {
			block_slot = 3,
			item_slot = 4,
			storage_block_name = "minecraft:raw_copper_block",
		},
		["minecraft:raw_gold"] = {
			block_slot = 5,
			item_slot = 6,
			storage_block_name = "minecraft:raw_gold_block",
		},
		["create:raw_zinc"] = {
			block_slot = 7,
			item_slot = 8,
			storage_block_name = "create:raw_zinc_block",
		},
	},
	output_storage_blocks = {
		["minecraft:iron_ingot"] = {
			block_slot = 10,
			item_slot = 11,
			storage_block_name = "minecraft:iron_block",
		},
		["minecraft:copper_ingot"] = {
			block_slot = 12,
			item_slot = 13,
			storage_block_name = "minecraft:copper_block",
		},
		["minecraft:gold_ingot"] = {
			block_slot = 14,
			item_slot = 15,
			storage_block_name = "minecraft:gold_block",
		},
		["create:zinc_ingot"] = {
			block_slot = 16,
			item_slot = 17,
			storage_block_name = "create:zinc_block",
		},
	},
	blast_smeltable_tags = { "c:ores", "c:raw_materials", "create:crushed_raw_materials" },
}
