local data = require("data")
local names = require("names")
local util = require("util")

local all_storage_blocks = {}
for k, v in pairs(data.input_storage_blocks) do
	all_storage_blocks[k] = v
end
for k, v in pairs(data.output_storage_blocks) do
	all_storage_blocks[k] = v
end

local recovery = {}

function recovery.recover()
	-- If we were unloaded in the middle of something, our inventory could be in an unexpected state
	-- and break crafting -- recover from that failure.
	if recovery._rebalanceItemsForCrafting() then
		turtle.select(1)
		turtle.craft()
	end
	if not recovery._moveStorageBlocksToBlockSlot() then
		-- If there isn't enough space in the block slot, we must have pulled input storage blocks
		-- to smelt them, so there should be enough space in the item slot after decrafting.
		turtle.select(1)
		turtle.craft()
		recovery._moveItemsToItemSlot()
	end
	return recovery._isPristine()
end

function recovery._rebalanceItemsForCrafting()
	local slots = {}
	for x = 1, 3 do
		for y = 1, 3 do
			local slot = (y - 1) * 4 + x
			table.insert(slots, slot)
		end
	end

	local count_total = 0
	local expected_name = nil
	for _, slot in pairs(slots) do
		local item = turtle.getItemDetail(slot)
		if item then
			if expected_name and item.name ~= expected_name then
				return false
			end
			expected_name = item.name
			count_total = count_total + item.count
		end
	end
	if count_total == 0 then
		return false
	end

	local info = data.input_storage_blocks[expected_name]
	if not info then
		info = data.output_storage_blocks[expected_name]
	end
	if not info then
		return false
	end
	local count_blocks_present = 0
	local item = names.holding_inventory.getItemDetail(info.block_slot)
	if item then
		count_blocks_present = item.count
	end

	local count_recipe = math.min(math.floor(count_total / 9), 64 - count_blocks_present)

	-- Move items from slots with too many items to slots with too few items.
	for _, slot_from in pairs(slots) do
		local item = turtle.getItemDetail(slot_from)
		if item and item.count > count_recipe then
			turtle.select(slot_from)
			for _, slot_to in pairs(slots) do
				local item_to = turtle.getItemDetail(slot_to)
				local count_to = 0
				if item_to then
					count_to = item_to.count
				end
				if count_to < count_recipe then
					local count = math.min(item.count - count_recipe, count_recipe - count_to)
					turtle.transferTo(slot_to, count)
					item.count = item.count - count
				end
			end
			local count_to_move = item.count - count_recipe
			local count_moved = util.moveItems(
				turtle,
				names.holding_inventory,
				slot_from,
				count_to_move,
				info.item_slot
			)
			if count_moved ~= count_to_move then
				return false
			end
		end
	end

	return true
end

-- Returns `false` if there isn't space in the block slot, `true` on success or if unapplicable.
function recovery._moveStorageBlocksToBlockSlot()
	local item = turtle.getItemDetail(1)
	if not item then
		return true
	end
	for _, info in pairs(all_storage_blocks) do
		if item.name == info.storage_block_name then
			local count_moved = util.moveItems(
				turtle,
				names.holding_inventory,
				1,
				nil,
				info.block_slot
			)
			return count_moved == item.count
		end
	end
	return true
end

function recovery._moveItemsToItemSlot()
	local item = turtle.getItemDetail(1)
	if not item then
		return
	end
	local info = all_storage_blocks[item.name]
	if info then
		util.moveItems(turtle, names.holding_inventory, 1, nil, info.item_slot)
	end
end

function recovery._isPristine()
	for x = 1, 3 do
		for y = 1, 3 do
			local slot = (y - 1) * 4 + x
			if turtle.getItemDetail(slot) then
				return false
			end
		end
	end
	return true
end

return recovery
