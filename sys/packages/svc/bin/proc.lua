local svc = require "svc"
local tableui = require "tableui"

local function showProcessList()
    term.setTextColor(colors.green)
    local writeRow = tableui.header({
        { key = "pid", heading = "PID", width = 4 },
        { key = "name", heading = "Name" },
    })
    for _, process in pairs(svc.listProcesses()) do
        term.setTextColor(colors.white)
        writeRow({
            pid = tostring(process.pid),
            name = process.name,
        })
    end
end

local function startProcess(is_detached, ...)
    local args = { ... }

    -- This needs to be split into two statements so that `pid` is a bound variable in the callback.
    local pid
    pid = svc.startProcess(table.concat(args, " ", first_arg), function()
        local ok, err = pcall(svc.execIsolated, table.unpack(args))
        if not is_detached then
            os.queueEvent("proc_stopped", pid, not ok and err)
        end
    end, function()
        if not is_detached then
            os.queueEvent("proc_stopped", pid, "Killed")
        end
    end)

    if is_detached then
        print("Started PID " .. pid .. " (detached)")
    else
        print("Started PID " .. pid)
        while true do
            local event = { os.pullEventRaw() }
            if event[1] == "terminate" then
                svc.stopProcess(pid)
            elseif event[1] == "proc_stopped" and event[2] == pid then
                if event[3] then
                    printError(event[3])
                end
                break
            end
        end
    end
end

local args = { ... }

if #args == 0 then
    showProcessList()
elseif #args == 2 and args[1] == "stop" then
    local pid = tonumber(args[2])
    assert(pid ~= nil, "Invalid PID " .. args[2])
    svc.stopProcess(pid)
elseif #args == 2 and args[1] == "kill" then
    local pid = tonumber(args[2])
    assert(pid ~= nil, "Invalid PID " .. args[2])
    svc.killProcess(pid)
elseif args[1] == "start" and #args >= 2 + (args[2] == "-d" and 1 or 0) then
    local is_detached = args[2] == "-d"
    local first_arg = is_detached and 3 or 2
    startProcess(is_detached, table.unpack(args, first_arg))
else
    printError("Usage:")
    printError("    proc")
    printError("    proc stop <pid>")
    printError("    proc kill <pid>")
    printError("    proc start [-d] <program> <args...>")
end
