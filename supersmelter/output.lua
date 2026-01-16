local data = require("data")
local names = require("names")
local util = require("util")

local helper_inventory_queue_updates = {}

local output = {}

function output.flushOutput(immediate)
	local now = os.epoch("ingame")

	::retry::

	local ok = true
	local incomplete_crafting = false
	util.parForEach(names.all_furnaces, function(furnace)
		local item = furnace.getItemDetail(3)
		if not item then
			return
		end

		local storage_block_info = data.output_storage_blocks[item.name]
		if not storage_block_info then
			ok = ok and util.moveItems(furnace, names.output_inventory, 3) >= item.count
			return
		end

		-- The helper inventory queues output items that can be converted into storage blocks. If no
		-- new items of a given type arrive for 15s, the slot is flushed to the output inventory. If
		-- the flow is constant, we wait for 9 items to craft into a storage block.
		--
		-- Since the helper inventory is constantly flushed due to crafting, there should be enough
		-- space in the allocated slot for the whole output, as long as the turtle doesn't shut down
		-- and the output inventory isn't filled up. If either happens, it'll take multiple
		-- iterations to flush.
		--
		-- Overflowing here is not considered as lack of space, since it can be resolved
		-- automatically, but it does mean that we have to retry in a loop if we want to complete
		-- the smelting process completely.
		local count_moved = util.moveItems(
			furnace,
			names.helper_inventory,
			3,
			nil,
			storage_block_info.item_slot
		)
		incomplete_crafting = incomplete_crafting or count_moved < item.count
		helper_inventory_queue_updates[item.name] = now
	end)

	local helper_inventory_list = names.helper_inventory.list()
	assert(not helper_inventory_list[1], "Helper full/precr")

	-- This loop has to be sequential due to crafting. Iterations that touch non-existing metals
	-- don't take time.
	for _, info in pairs(data.output_storage_blocks) do
		-- Flush output storage blocks that we didn't have space for.
		local item = helper_inventory_list[info.block_slot]
		if item then
			local count_moved = util.moveItems(
				names.helper_inventory,
				names.output_inventory,
				info.block_slot
			)
			item.count = item.count - count_moved
			if item.count > 0 then
				ok = false
			end
			if item.count >= 32 then
				-- There is little enough space that we shouldn't craft new output storage blocks.
				goto continue
			end
		end

		-- Craft items into storage blocks.
		local item = helper_inventory_list[info.item_slot]
		if not item then
			goto continue
		end

		-- If the queue was populated during a previous run, pessimistically assume it's recent.
		if not helper_inventory_queue_updates[item.name] then
			helper_inventory_queue_updates[item.name] = now
		end

		-- Prefer to wait for at least 5 blocks, since crafting takes a long while.
		local force_flush = immediate or helper_inventory_queue_updates[item.name] < now - 15
		local count_recipes = math.floor(item.count / 9)
		if count_recipes >= 5 or (force_flush and count_recipes > 0) then
			-- Turtles can only suck from the first slot, so move the items there.
			local count_moved = util.moveItems(
				names.helper_inventory,
				names.helper_inventory,
				info.item_slot,
				count_recipes * 9,
				1
			)
			assert(count_moved == count_recipes * 9, "Move failed/cr")
			for x = 1, 3 do
				for y = 1, 3 do
					turtle.select((y - 1) * 4 + x)
					turtle.suck(count_recipes)
				end
			end
			turtle.select(1)
			local craft_ok, _ = turtle.craft()
			assert(craft_ok, "Craft failed/cr")
			turtle.drop()
			assert(turtle.getItemCount(1) == 0, "Helper full/cr")
			local count_moved = util.moveItems(names.helper_inventory, names.output_inventory, 1)
			if count_moved < count_recipes then
				ok = false
			end
			count_moved = count_moved + util.moveItems(
				names.helper_inventory,
				names.helper_inventory,
				1,
				nil,
				info.block_slot
			)
			assert(count_moved == count_recipes, "Block slot full/cr")
			item.count = item.count - count_recipes * 9
			-- Crafting frees up space for new items, so we don't flush the remaining items
			-- immediately, since perhaps the furnace was just full and we'll get new items soon.
			helper_inventory_queue_updates[item.name] = now
		end

		if force_flush then
			-- No items have arrived recently -- flush as-is.
			local count_moved = util.moveItems(
				names.helper_inventory,
				names.output_inventory,
				info.item_slot
			)
			ok = ok and count_moved >= item.count
		end

		::continue::
	end

	if ok and immediate and incomplete_crafting then
		goto retry
	end

	return ok
end

return output
