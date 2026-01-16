local data = require("data")
local names = require("names")
local util = require("util")

local fuel = {}

function fuel.printInvalidFuels(fuel_list)
	local printed_error = {}
	for _, item in pairs(fuel_list) do
		if not data.fuel_capacity[item.name] then
			if not next(printed_error) then
				util.print("Invalid fuel")
			end
			if not printed_error[item.name] then
				util.print(item.name)
			end
			printed_error[item.name] = true
		end
	end
end

function fuel.fillFuel()
	local fuel = {}
	for slot, item in pairs(names.fuel_inventory.list()) do
		capacity = data.fuel_capacity[item.name]
		if capacity then
			fuel[slot] = capacity
		end
	end

	local ok = true
	util.parForEach(names.all_furnaces, function(furnace)
		local slots = furnace.list()
		local input_item = slots[1]
		local fuel_item = slots[2]
		if not input_item then
			return
		end

		local count_unfueled = input_item.count
		if fuel_item then
			local fuel_capacity = data.fuel_capacity[fuel_item.name]
			if fuel_capacity then
				count_unfueled = count_unfueled - fuel_item.count * fuel_capacity
			end
		end

		for slot, capacity in pairs(fuel) do
			if count_unfueled <= 0 then
				break
			end
			local count_fuel_moved = util.moveItems(
				names.fuel_inventory,
				furnace,
				slot,
				math.ceil(count_unfueled / capacity),
				2
			)
			count_unfueled = count_unfueled - count_fuel_moved * capacity
		end

		if count_unfueled > 0 then
			ok = false
		end
	end)
	return ok
end

function fuel.returnFuel()
	util.parForEach(names.all_furnaces, function(furnace)
		util.moveItems(furnace, names.fuel_inventory, 2)
	end)
end

return fuel
