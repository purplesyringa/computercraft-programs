local svc = require "svc"
local tableui = require "tableui"

local service_status_to_color = {
    stopped = colors.gray,
    starting = colors.yellow,
    up = colors.green,
    failed = colors.red,
}

local target_status_to_color = {
    starting = colors.yellow,
    up = colors.green,
    degraded = colors.red,
}

local function showSystemStatus()
    local status = svc.status()

    term.setTextColor(colors.white)
    write("Target: " .. status.target.name)
    term.setTextColor(target_status_to_color[status.target.status])
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
    local n_stopped_services = 0
    for _, name in pairs(service_names) do
        local service_status = status.services[name]
        if service_status.status == "stopped" then
            n_stopped_services = n_stopped_services + 1
        else
            term.setTextColor(service_status_to_color[service_status.status])
            writeRow({
                name = name,
                status = service_status.status,
            })
        end
    end
    term.setTextColor(colors.gray)
    print("...and", n_stopped_services, "stopped service(s)")
end

local function showServiceStatus(service)
    local status = svc.serviceStatus(service)
    if not status then
        error("Service " .. service .. " does not exist", 0)
    end

    term.setTextColor(colors.white)
    write("Service: " .. service)
    term.setTextColor(service_status_to_color[status.status])
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

local function reachTarget(target, persist)
    svc.reach(target, false, persist)
    if persist then
        print("Reached and persisted", target)
    else
        print("Reached", target)
    end
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
    reachTarget(args[2], false)
elseif #args == 3 and args[1] == "reach" and args[3] == "--persist" then
    reachTarget(args[2], true)
elseif #args == 1 and args[1] == "shutdown" then
    os.shutdown()
elseif #args == 1 and args[1] == "reboot" then
    os.reboot()
else
    printError("Usage:")
    printError("    svc")
    printError("    svc reload")
    printError("    svc status <service>")
    printError("    svc start <service>")
    printError("    svc stop <service>")
    printError("    svc kill <service>")
    printError("    svc reach <target> [--persist]")
    printError("    svc shutdown")
    printError("    svc reboot")
end
