local names = require("names")
local util = require("util")
local input = require("input")
local fuel = require("fuel")
local output = require("output")
local chunk_vial = require("chunk_vial")

local is_active = false

local work = {}

function work.mainLoop()
	local file = fs.open("/state.txt", "r")
	if file then
		is_active = file.readAll() == "active"
		file.close()
	end

	if not is_active then
		work._showStopping(true)
	end

	parallel.waitForAll(
		function()
			while true do
				work.work()
				os.sleep(1)
			end
		end,
		function()
			while true do
				local  _, monitor = os.pullEvent("monitor_touch")
				if monitor == peripheral.getName(names.monitor) then
					is_active = not is_active
					if not is_active then
						-- We can't log errors or provide output yet, since flushing will take
						-- a while, but we should react immediately for responsibility.
						work._showStopping(true)
					end
					local file = fs.open("/state.txt", "w")
					if is_active then
						file.write("active")
					else
						file.write("inactive")
					end
					file.close()
				end
			end
		end
	)
end

function work.work()
	local fuel_list = names.fuel_inventory.list()

	if is_active then
		chunk_vial.equip()
		local eta = input.queueInputs()
		if eta == nil then
			is_active = false
		else
			local input_ok = input.fixInputs()
			local fuel_ok = fuel.fillFuel()
			local output_ok = output.flushOutput(false)
			work._showSmelting(eta, input_ok, fuel_ok, output_ok)
		end
	else
		local input_ok = input.returnInput()
		if input_ok then
			fuel.returnFuel()
			local has_input = next(names.input_inventory.list()) ~= nil
			local output_ok = output.flushOutput(true)
			local has_output = next(names.output_inventory.list()) ~= nil
			if output_ok then
				chunk_vial.unequip()
			end
			if output_ok and not has_output then
				work._showReady(has_input)
			else
				work._showDone(has_input, output_ok)
			end
		else
			work._showStopping(false)
		end
	end

	names.monitor.setTextColor(colors.red)
	fuel.printInvalidFuels(fuel_list)
	if names.decorative_furnace and next(names.decorative_furnace.list()) then
		util.print("Decorative furnace")
	end
end

function work._showSmelting(eta, input_ok, fuel_ok, output_ok)
	util.clear()
	names.monitor.setTextColor(colors.yellow)
	util.print("Smelting")
	names.monitor.setTextColor(colors.white)
	util.print(string.format("ETA: %s", util.formatTime(eta)))
	util.print("Tap to cancel")
	names.monitor.setTextColor(colors.red)
	if not input_ok then
		util.print("Declutter input")
	end
	if not fuel_ok then
		util.print("Out of fuel")
	end
	if not output_ok then
		util.print("Output full")
	end
end

function work._showStopping(input_ok)
	util.clear()
	names.monitor.setTextColor(colors.yellow)
	util.print("Stopping")
	names.monitor.setTextColor(colors.red)
	if not input_ok then
		util.print("Input full")
	end
end

function work._showReady(has_input)
	util.clear()
	names.monitor.setTextColor(colors.green)
	util.print("Ready")
	names.monitor.setTextColor(colors.white)
	util.print("Load items")
	if has_input then
		util.print("Tap to start")
	end
end

function work._showDone(has_input, output_ok)
	util.clear()
	names.monitor.setTextColor(colors.green)
	util.print("Done")
	names.monitor.setTextColor(colors.white)
	util.print("Take items out")
	if has_input then
		util.print("Tap to resume")
	end
	names.monitor.setTextColor(colors.red)
	if not output_ok then
		util.print("Output full")
	end
end

return work
