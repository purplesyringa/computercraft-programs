local names = require("names")
local util = require("util")
local input = require("input")
local fuel = require("fuel")
local output = require("output")
local chunk_vial = require("chunk_vial")

local is_active = false
local stopping_triggered = true -- if initially inactive, show the stopping status immediately

local work = {}

function work.mainLoop()
	local file = fs.open("/state.txt", "r")
	if file then
		is_active = file.readAll() == "active"
		file.close()
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
				os.pullEvent("redstone")
				if names.redstone_relay.getInput("front") then
					is_active = not is_active
					if not is_active then
						stopping_triggered = true
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
	local fuel_list = names.fuel_barrel.list()

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
		if stopping_triggered then
			-- We can't log errors or provide output yet, since flushing will take a while, but we
			-- should react immediately for responsibility.
			work._showStopping(true)
			stopping_triggered = false
		end

		local input_ok = input.returnInput()
		if input_ok then
			fuel.returnFuel()
			local has_input = next(names.input_barrel.list()) ~= nil
			local output_ok = output.flushOutput(true)
			local has_output = next(names.output_barrel.list()) ~= nil
			if output_ok then
				chunk_vial.unequip()
			end
			if output_ok and not has_output then
				work._showReady()
			else
				work._showDone(has_input, output_ok)
			end
		else
			work._showStopping(false)
		end
	end

	names.monitor.setTextColor(colors.red)
	fuel.printInvalidFuels(fuel_list)
	if next(names.decorative_furnace.list()) then
		util.print("Decorative furnace")
	end
end

function work._showSmelting(eta, input_ok, fuel_ok, output_ok)
	util.clear()
	names.monitor.setTextColor(colors.yellow)
	util.print("Smelting")
	names.monitor.setTextColor(colors.white)
	util.print(string.format("ETA: %s", util.formatTime(eta)))
	names.monitor.setTextColor(colors.red)
	if not input_ok then
		util.print("Declutter input")
	end
	if not fuel_ok then
		util.print("Out of fuel")
	end
	if not output_ok then
		util.print("Output barrel full")
	end
end

function work._showStopping(input_ok)
	util.clear()
	names.monitor.setTextColor(colors.yellow)
	util.print("Stopping")
	names.monitor.setTextColor(colors.red)
	if not input_ok then
		util.print("Input barrel full")
	end
end

function work._showReady()
	util.clear()
	names.monitor.setTextColor(colors.green)
	util.print("Ready")
	names.monitor.setTextColor(colors.white)
	util.print("Put items in and")
	util.print("press \"Start\"")
end

function work._showDone(has_input, output_ok)
	util.clear()
	names.monitor.setTextColor(colors.green)
	util.print("Done")
	names.monitor.setTextColor(colors.white)
	util.print("Take items out")
	if has_input then
		util.print("Press \"Start\"")
		util.print("to keep going")
	end
	names.monitor.setTextColor(colors.red)
	if not output_ok then
		util.print("Output barrel full")
	end
end

return work
