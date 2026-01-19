local names = require("names")
local data = require("data")

local util = {}

function util.parForEach(tbl, callback)
	local closures = {}
	for _, element in pairs(tbl) do
		table.insert(closures, function()
			return callback(element)
		end)
	end
	return parallel.waitForAll(unpack(closures))
end

function util.clear(s)
	names.monitor.clear()
	names.monitor.setCursorPos(1, 1)
end

function util.print(s)
	names.monitor.write(s)
	_, y = names.monitor.getCursorPos()
	names.monitor.setCursorPos(1, y + 1)
end

function util.formatTime(seconds)
	seconds = math.ceil(seconds)
	if seconds < 60 then
		return string.format("%ds", seconds)
	else
		return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
	end
end

function util.isBlastSmeltable(item)
	for _, tag in pairs(data.blast_smeltable_tags) do
		if item.tags[tag] then
			return true
		end
	end
	return false
end

local turtle_modem_name = peripheral.find("modem").getNameLocal()

function util.moveItems(from, to, fromSlot, count, toSlot)
	if from == turtle then
		return to.pullItems(turtle_modem_name, fromSlot, count, toSlot)
	elseif to == turtle then
		return from.pushItems(turtle_modem_name, fromSlot, count, toSlot)
	else
		return from.pushItems(peripheral.getName(to), fromSlot, count, toSlot)
	end
end

return util
