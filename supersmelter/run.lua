local data = require("data")
local names = require("names")
local util = require("util")
local recovery = require("recovery")
local work = require("work")

local function main()
	util.clear()
	names.monitor.setTextColor(colors.yellow)
	util.print("Booting")

	-- Sanity checks.
	assert(names.scram_inventory.size() >= #names.all_furnaces, "Scram too small for #furnaces")
	local max_slot = 0
	for _, info in pairs(data.input_storage_blocks) do
		max_slot = math.max(max_slot, math.max(info.block_slot, info.item_slot))
	end
	for _, info in pairs(data.output_storage_blocks) do
		max_slot = math.max(max_slot, math.max(info.block_slot, info.item_slot))
	end
	assert(names.helper_inventory.size() >= max_slot, "Helper too small")

	if recovery.recover() then
		work.mainLoop()
	else
		names.monitor.setTextColor(colors.red)
		util.print("Recovery failed")
		util.print("Call Alisa")
	end
end

local ok, err = pcall(main)
if not ok then
	print(err)
	util.clear()
	names.monitor.setTextColor(colors.red)
	util.print("Crash")
	util.print("Call Alisa")
end
