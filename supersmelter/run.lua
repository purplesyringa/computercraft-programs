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
	assert(names.holding_inventory.size() >= max_slot, "holding inventory too small")

	if recovery.recover() then
		work.mainLoop()
	else
		names.monitor.setTextColor(colors.red)
		util.print("Recovery failed")
		util.print("Call Alisa")
	end
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
	local file = fs.open(shell.resolve("error.log"), "w")
	file.write(err .. "\n")
	file.close()
	util.clear()
	names.monitor.setTextColor(colors.red)
	util.print("Crash")
	util.print("Call Alisa")
	print("Crashed, stacktrace written to error.log")
end
