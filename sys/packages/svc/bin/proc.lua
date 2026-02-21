local svc = require "svc"
local tableui = require "tableui"

local function showProcessList()
	term.setTextColor(colors.green)
	local writeRow = tableui.header({
		{ key = "pid", heading = "PID", width = 4 },
		{ key = "name", heading = "Name" },
	})
	for _, process in pairs(svc.listProcesses()) do
		if process.is_foreground then
			term.setTextColor(colors.yellow)
		else
			term.setTextColor(colors.white)
		end
		writeRow({
			pid = tostring(process.pid),
			name = process.name,
		})
	end
end

local function showServiceStatus(service)
	local status = svc.serviceStatus(service)

	term.setTextColor(colors.white)
	write("Service: " .. service)
	if status.status == "failed" then
		term.setTextColor(colors.red)
	elseif status.up then
		term.setTextColor(colors.green)
	else
		term.setTextColor(colors.gray)
	end
	print(" (" .. status.status .. ")")
	term.setTextColor(colors.gray)
	if status.description then
		print(status.description)
	end
	if status.error then
		term.setTextColor(colors.red)
		print(status.error)
	end
end

local args = { ... }

if #args == 0 then
	showProcessList()
elseif #args == 2 and args[1] == "stop" then
	local pid = tonumber(args[2])
	assert(pid ~= nil, "Invalid PID " .. args[2])
	svc.terminateProcess(pid)
elseif #args == 2 and args[1] == "kill" then
	local pid = tonumber(args[2])
	assert(pid ~= nil, "Invalid PID " .. args[2])
	svc.killProcess(pid)
else
	printError("Usage:")
	printError("    proc")
	printError("    proc stop <pid>")
	printError("    proc kill <pid>")
end
