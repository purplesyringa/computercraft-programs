local svc = require "svc"
local tableui = require "tableui"

local function showSystemStatus()
    local status = svc.status()

    term.setTextColor(colors.white)
    write("Target: " .. status.target.name)
    if status.target.status == "running" then
        term.setTextColor(colors.green)
    else
        term.setTextColor(colors.red)
    end
    print(" (" .. status.target.status .. ")")

    if status.target.error then
        term.setTextColor(colors.red)
        print(status.target.error)
    end

    term.setTextColor(colors.white)

    print()

    local service_names = {}
    for service, _ in pairs(status.services) do
        table.insert(service_names, service)
    end
    table.sort(service_names)
    local writeRow = tableui.header({
        { key = "name", heading = "Service", width = 16 },
        { key = "status", heading = "Status" },
    })
    for _, name in pairs(service_names) do
        local service_status = status.services[name]
        if service_status.status == "failed" then
            term.setTextColor(colors.red)
        elseif service_status.up then
            term.setTextColor(colors.green)
        else
            term.setTextColor(colors.gray)
        end
        writeRow({
            name = name,
            status = service_status.status,
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

local function reload()
    svc.reload()
    showSystemStatus()
end

local function startService(service)
    svc.start(service)
    print("Started", service)
end

local function stopService(service)
    svc.stop(service)
    print("Stopped", service)
end

local function killService(service)
    svc.kill(service)
    print("Killed", service)
end

local function reachTarget(target)
    svc.reach(target)
    print("Reached", target)
end

local args = { ... }

if #args == 0 or (#args == 1 and args[1] == "status") then
    showSystemStatus()
elseif #args == 1 and args[1] == "reload" then
    reload()
elseif #args == 2 and args[1] == "status" then
    showServiceStatus(args[2])
elseif #args == 2 and args[1] == "start" then
    startService(args[2])
elseif #args == 2 and args[1] == "stop" then
    stopService(args[2])
elseif #args == 2 and args[1] == "kill" then
    killService(args[2])
elseif #args == 2 and args[1] == "reach" then
    reachTarget(args[2])
else
    printError("Usage:")
    printError("    svc")
    printError("    svc reload")
    printError("    svc status <service>")
    printError("    svc start <service>")
    printError("    svc stop <service>")
    printError("    svc kill <service>")
    printError("    svc reach <target>")
end
