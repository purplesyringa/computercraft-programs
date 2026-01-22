local data = require("data")
local names = require("names")
local util = require("util")

local input = {}

local rev_input_storage_blocks = {}
for _, info in pairs(data.input_storage_blocks) do
	rev_input_storage_blocks[info.storage_block_name] = info
end

function input.queueInputs()
	-- The scram inventories should always be empty during stopping to be able to contain all
	-- inputs, ergo they should always be smelted first.
	util.parForEach(input._getFurnaceScramMapping(), function(mapping)
		util.moveItems(mapping.scram_inventory, mapping.furnace, mapping.scram_slot, nil, 1)
	end)
	util.parForEach(names.scram_inventories, function(scram_inventory)
		assert(not next(scram_inventory.list()), "Full scram")
	end)

	local schedule = input._computeSchedule()
	if not schedule then
		return nil
	end

	local holding_inventory_list = names.holding_inventory.list()

	-- This loop has to be sequential due to crafting. Iterations that touch non-existing ores or
	-- filled queues don't take time.
	for slot, item in pairs(names.input_inventory.list()) do
		local storage_block_info = rev_input_storage_blocks[item.name]
		if not storage_block_info then
			goto continue
		end
		local holding_inventory_item = holding_inventory_list[storage_block_info.item_slot]
		-- Don't decraft if there's already many items queued -- it'd just waste time. Recovery
		-- requires this bound to be somewhat smaller than 64, so 32 is good enough.
		local count_holding_inventory = 0
		if holding_inventory_item then
			count_holding_inventory = holding_inventory_item.count
		end
		local count_to_move = math.floor((32 - count_holding_inventory) / 9)
		if count_to_move <= 0 then
			goto continue
		end
		local count_moved_storage_blocks = util.moveItems(
			names.input_inventory,
			turtle,
			slot,
			count_to_move,
			1
		)
		turtle.select(1)
		local craft_ok, _ = turtle.craft()
		assert(craft_ok, "Craft failed/de")
		local count_moved_items = util.moveItems(
			turtle,
			names.holding_inventory,
			1,
			nil,
			storage_block_info.item_slot
		)
		assert(count_moved_items == count_moved_storage_blocks * 9, "Item slot full")
		holding_inventory_list[storage_block_info.item_slot] = {
			name = item.name,
			count = count_holding_inventory + count_moved_items,
		}
		::continue::
	end

	local inputs = {}
	util.parForEach(input._getInputSlots({ "input_inventory", "holding_inventory" }), function(slot)
		local item = slot.inventory.getItemDetail(slot.slot)
		if item and not rev_input_storage_blocks[item.name] then
			table.insert(inputs, {
				inventory = slot.inventory,
				slot = slot.slot,
				name = item.name,
				count = item.count,
				is_blast_smeltable = util.isBlastSmeltable(item),
			})
		end
	end)
	input._populateFurnaceInputs(names.normal_furnaces, schedule.populate_normal, inputs)
	input._populateFurnaceInputs(names.blast_furnaces, schedule.populate_blast, inputs)
	input._populateFurnaceInputs(names.all_furnaces, schedule.populate_all, inputs)

	return schedule.eta
end

function input._getFurnaceScramMapping()
	local mapping = {}
	for _, furnace in pairs(names.all_furnaces) do
		table.insert(mapping, { furnace = furnace })
	end

	local j = 1
	for _, scram_inventory in pairs(names.scram_inventories) do
		for scram_slot = 1, scram_inventory.size() do
			if j <= #mapping then
				mapping[j].scram_inventory = scram_inventory
				mapping[j].scram_slot = scram_slot
			end
			j = j + 1
		end
	end

	return mapping
end

function input._computeSchedule()
	local counts = {
		normal = 0,
		blast = 0,
	}
	local slots = input._getInputSlots({ "input_inventory", "holding_inventory", "furnaces" })
	util.parForEach(slots, function(slot)
		item = slot.inventory.getItemDetail(slot.slot)
		if not item then
			-- pass
		elseif rev_input_storage_blocks[item.name] then
			counts.blast = counts.blast + item.count * 9
		elseif util.isBlastSmeltable(item) then
			counts.blast = counts.blast + item.count
		else
			counts.normal = counts.normal + item.count
		end
	end)
	counts.total = counts.normal + counts.blast
	if counts.total == 0 then
		return nil
	end

	local speeds = {
		normal = #names.normal_furnaces / 10,
		blast = #names.blast_furnaces / 5,
	}
	speeds.total = speeds.normal + speeds.blast

	local durations = {
		normal = counts.normal / speeds.normal,
		blast = counts.blast / speeds.blast,
		total = counts.total / speeds.total,
	}
	-- Spread normal items and then blast-smeltable items -- either over blast furnaces exclusively,
	-- or over all furnaces if normal furnaces become empty before all blast-smeltable items are
	-- smelted.
	if durations.blast < durations.normal then
		return {
			populate_normal = durations.normal,
			populate_blast = durations.blast,
			populate_all = 0,
			eta = durations.normal,
		}
	else
		return {
			populate_normal = durations.normal,
			populate_blast = 0,
			populate_all = durations.total,
			eta = durations.total,
		}
	end
end

function input._getInputSlots(categories)
	local slots = {}
	for _, category in pairs(categories) do
		if category == "input_inventory" then
			for slot = 1, names.input_inventory.size() do
				table.insert(slots, { inventory = names.input_inventory, slot = slot })
			end
		elseif category == "holding_inventory" then
			for _, info in pairs(data.input_storage_blocks) do
				table.insert(slots, { inventory = names.holding_inventory, slot = info.block_slot })
				table.insert(slots, { inventory = names.holding_inventory, slot = info.item_slot })
			end
		elseif category == "furnaces" then
			for _, furnace in pairs(names.all_furnaces) do
				table.insert(slots, { inventory = furnace, slot = 1 })
			end
		elseif category == "scram_inventories" then
			for _, inventory in pairs(names.scram_inventories) do
				for slot = 1, inventory.size() do
					table.insert(slots, { inventory = inventory, slot = slot })
				end
			end
		else
			assert(false, "Invalid category")
		end
	end
	return slots
end

function input._populateFurnaceInputs(furnaces, wanted_duration_per_furnace, inputs)
	if wanted_duration_per_furnace <= 0 then
		return
	end

	util.parForEach(furnaces, function(furnace)
		local is_blast_furnace = peripheral.getType(furnace) == "minecraft:blast_furnace"
		if is_blast_furnace then
			duration_per_item = 5
		else
			duration_per_item = 10
		end

		local count_to_add = math.ceil(wanted_duration_per_furnace / duration_per_item)
		local item = furnace.getItemDetail(1)
		if item then
			count_to_add = math.min(count_to_add - item.count, item.maxCount - item.count)
		end

		for _, input in pairs(inputs) do
			if count_to_add <= 0 then
				break
			end

			local is_input_eligible = input.is_blast_smeltable or not is_blast_furnace
			if (not item or input.name == item.name) and input.count > 0 and is_input_eligible then
				local count_to_move = math.min(input.count, count_to_add)
				-- Decrease count before yielding so that multiple furnaces don't try to move from
				-- the same slot.
				input.count = input.count - count_to_move
				-- This may move less than count_to_move on race, but this will fix itself on the
				-- next iteration of work.
				count_to_add = count_to_add - util.moveItems(
					input.inventory,
					furnace,
					input.slot,
					count_to_move,
					1
				)
				-- We could've raced and moved a non-blast-smeltable item into a blast furnace, or
				-- a raw metal block. We'll fix this on a later stage during work.
			end
		end
	end)
end

function input.fixInputs()
	-- We can accidentally place non-blast-smeltable items in blast furnaces, or place raw metal
	-- blocks as inputs due to a race between checking the item type and moving it into the furnace.
	-- Fix it post-factum.
	local ok = true
	util.parForEach(names.all_furnaces, function(furnace)
		local item = furnace.getItemDetail(1)
		if not item then
			return
		end
		local is_blast_furnace = peripheral.getType(furnace) == "minecraft:blast_furnace"
		local is_invalid = (
			rev_input_storage_blocks[item.name]
			or (is_blast_furnace and not util.isBlastSmeltable(item))
		)
		if is_invalid and util.moveItems(furnace, input_inventory, 1) < item.count then
			ok = false
		end
	end)
	return ok
end

function input.returnInput()
	-- Move items from furnaces into the scram inventories. This ensures that a) the items are not
	-- smelted and lost because the input inventory is full, b) the number of items cannot change in
	-- runtime, racing with crafting.
	util.parForEach(input._getFurnaceScramMapping(), function(mapping)
		util.moveItems(mapping.furnace, mapping.scram_inventory, 1, nil, mapping.scram_slot)
		assert(not mapping.furnace.getItemDetail(1), "Full scram")
	end)

	-- Flush items and recrafted storage blocks.
	local ok = true
	local by_name = {}
	-- Pull from the holding inventory before the scram inventory to reduce the number of items in
	-- the item slot. Recovery requires that if crafting is underway, the item slot has some free
	-- space.
	local slots = input._getInputSlots({ "holding_inventory", "scram_inventories" })
	util.parForEach(slots, function(slot)
		local item = slot.inventory.getItemDetail(slot.slot)
		if not item then
			return
		end
		if data.input_storage_blocks[item.name] then
			if not by_name[item.name] then
				by_name[item.name] = {
					count = 0,
					slots = {},
				}
			end
			by_name[item.name].count = by_name[item.name].count + item.count
			table.insert(by_name[item.name].slots, {
				count = item.count,
				inventory = slot.inventory,
				slot = slot.slot,
			})
		else
			local count_moved = util.moveItems(slot.inventory, names.input_inventory, slot.slot)
			if count_moved < item.count then
				ok = false
			end
		end
	end)

	local holding_inventory_list = names.holding_inventory.list()

	-- Craft new storage blocks. Has to be done sequentially.
	for name, info in pairs(by_name) do
		local count_recipes = math.floor(info.count / 9)

		while count_recipes > 0 do
			-- Don't try to craft more blocks than we're guaranteed to have space for.
			local block_slot = data.input_storage_blocks[name].block_slot
			local count_taken = 0
			if holding_inventory_list[block_slot] then
				count_taken = holding_inventory_list[block_slot].count
			end
			local current_count = math.min(count_recipes, 64 - count_taken)

			-- Move items into the turtle inventory uniformly.
			local slots_to = {}
			for x = 1, 3 do
				for y = 1, 3 do
					table.insert(slots_to, (y - 1) * 4 + x)
				end
			end
			util.parForEach(slots_to, function(slot_to)
				local count_to_add = current_count
				for _, slot_from in pairs(info.slots) do
					if count_to_add <= 0 then
						break
					end
					if slot_from.count > 0 then
						local count_to_move = math.min(slot_from.count, count_to_add)
						-- Decrease count before yielding so that we don't try to move from the same
						-- slot in parallel.
						slot_from.count = slot_from.count - count_to_move
						count_to_add = count_to_add - util.moveItems(
							slot_from.inventory,
							turtle,
							slot_from.slot,
							count_to_move,
							slot_to
						)
					end
				end
				assert(count_to_add == 0, "Move failed/re")
			end)
			turtle.select(1)
			local craft_ok, _ = turtle.craft()
			assert(craft_ok, "Craft failed/re")
			local count_moved = util.moveItems(turtle, names.input_inventory, 1)
			if count_moved < current_count then
				count_moved = count_moved + util.moveItems(
					turtle,
					names.holding_inventory,
					1,
					nil,
					block_slot
				)
				assert(count_moved == count_recipes, "Block slot full/re")
				ok = false
				goto next_item
			end

			count_recipes = count_recipes - current_count
		end

		util.parForEach(info.slots, function(slot)
			util.moveItems(slot.inventory, names.input_inventory, slot.slot)
			ok = ok and not slot.inventory.getItemDetail(slot.slot)
		end)

		::next_item::
	end

	return ok
end

return input
