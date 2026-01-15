local names = require("names")
local util = require("util")
local recovery = require("recovery")
local work = require("work")

local function main()
	util.clear()
	names.monitor.setTextColor(colors.yellow)
	util.print("Booting")
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
