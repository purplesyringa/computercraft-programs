local proc = require "svc.proc"
local env = require "svc.env"

local sysroot = os._svc.sysroot

-- {
--     [name] = {
--         config? = ...,
--         config_error? = ...,
--         pid? = ...,
--         runtime_status = "stopped" | "running" | "finished" | "failed",
--         runtime_error? = ...,
--     },
--     ...
-- }
local services = {}

local services_api = {
    services = services,
}

function services_api.reload()
    local name_to_paths = {}
    for _, path in pairs(fs.find(fs.combine(sysroot, "packages", "*", "services", "*.lua"))) do
        local name = fs.getName(path):gsub(".lua$", "")
        if not name_to_paths[name] then
            name_to_paths[name] = {}
        end
        table.insert(name_to_paths[name], path)
    end

    for name, paths in pairs(name_to_paths) do
        local ok, config_or_err = pcall(function()
            if #paths > 1 then
                error("Multiple manifests: " .. table.concat(paths, ", "), 0)
            end
            local module, err = loadfile(paths[1], nil, {})
            if not module then
                error(err, 0)
            end
            return module()
        end)
        if not services[name] then
            services[name] = {
                pid = nil,
                runtime_status = "stopped",
                runtime_error = nil,
            }
        end
        local service = services[name]
        if ok then
            service.config, service.config_error = config_or_err, nil
        else
            service.config, service.config_error = nil, config_or_err
        end
    end

    for name, service in pairs(services) do
        if not name_to_paths[name] then
            service.config = nil
            service.config_error = "Manifest deleted"
        end
    end
end

local function waitForStatusChange(name)
    local service = services[name]
    assert(service, name .. ": unknown service")
    local _, updated_name
    repeat
        _, updated_name = os.pullEventRaw("service_status")
    until updated_name == name
end

function services_api.waitUp(name)
    assert(services[name], name .. ": unknown service")
    while true do
        local status = services_api.status(name)
        if status.status == "stopped" then
            error(name .. ": service was stopped")
        elseif status.status == "failed" then
            error(name .. ": " .. status.error)
        elseif status.status == "up" then
            return
        end
        waitForStatusChange(name)
    end
end

function services_api.waitDown(name)
    assert(services[name], name .. ": unknown service")
    while true do
        local status = services_api.status(name)
        if status.status == "stopped" then
            return
        elseif status.status == "failed" then
            error(name .. ": " .. status.error)
        end
        waitForStatusChange(name)
    end
end

local function runHook(hook)
    if hook then
        debug.setfenv(hook, env.make())
        hook()
    end
end

function services_api.start(name)
    local function checkStatus()
        local status = services_api.status(name)
        if not status then
            error(name .. ": unknown service")
        end
        if status.status == "up" then
            return true
        elseif status.status == "starting" then
            services_api.waitUp(name)
            return true
        else
            return false
        end
    end

    if checkStatus() then
        return
    end

    local service = services[name]
    local closures = {}
    for _, dependency in ipairs(service.config.requires or {}) do
        table.insert(closures, function() services_api.start(dependency) end)
    end
    parallel.waitForAll(table.unpack(closures))

    -- By the time the dependencies are started, the service might have already been started by
    -- another instance of `services.start` or its config might be changed, so check again.
    if checkStatus() then
        return
    end

    service.runtime_status = "running"
    service.runtime_error = nil
    os.queueEvent("service_status", name)

    local start = nil
    if service.config.type == "oneshot" then
        start = function()
            local ok, err = pcall(runHook, service.config.start)
            if not ok then
                local ok_stop, err_stop = pcall(runHook, service.config.stop)
                if not ok_stop then
                    err = err .. "\nwhile stopping:\n" .. err_stop
                end
                error(err, 0)
            end
        end
    elseif service.config.type == "process" then
        start = function()
            env.execIsolated(table.unpack(service.config.command))
        end
    elseif service.config.type == "foreground" then
        start = function()
            local ok, err = pcall(env.execIsolated, table.unpack(service.config.command))
            if not ok then
                -- Log the error to screen, since the user won't be able to observe it without
                -- a working shell otherwise.
                printError(err)
                error(err, 0)
            end
        end
    end

    -- Run even oneshot services in a background process, since we don't want them to be cancelled
    -- if `services.start` is cancelled.
    service.pid = proc.start("service " .. name, function()
        local ok, err = pcall(start)
        if not ok and err == "Terminated" then
            service.runtime_status = "stopped"
        elseif ok then
            service.runtime_status = "finished"
        else
            service.runtime_status = "failed"
            service.runtime_error = err
        end
        service.pid = nil
        os.queueEvent("service_status", name)
    end, function()
        service.runtime_status = "failed"
        service.runtime_error = "Killed"
        service.pid = nil
        os.queueEvent("service_status", name)
    end, service.config.type == "foreground")

    if service.config.type == "oneshot" then
        services_api.waitUp(name)
    end
end

function services_api.stop(name)
    local service = services[name]
    assert(service, name .. ": unknown service")
    if not service.config then
        error(name .. ": " .. service.config_error)
    end

    local function assertNotRequired()
        for name2, service2 in pairs(services) do
            local status2 = services_api.status(name2).status
            if (
                (status2 == "starting" or status2 == "up")
                and service2.config and service2.config.requires
            ) then
                for _, name3 in pairs(service2.config.requires) do
                    if name3 == name then
                        error(name .. ": required by running service " .. name2)
                    end
                end
            end
        end
    end

    if service.runtime_status == "running" then
        assertNotRequired()
        proc.terminate(service.pid)
        -- For oneshot services, `terminate` throws an error, which `pcall` in `start` catches and
        -- stops the service, so there is no need to call `service.config.stop` or update the status
        -- here.
        services_api.waitDown(name)
    elseif service.config.type == "oneshot" and service.runtime_status == "finished" then
        assertNotRequired()
        local ok, err = pcall(runHook, service.config.stop)
        if ok then
            service.runtime_status = "stopped"
        else
            service.runtime_status = "failed"
            service.runtime_error = err
        end
        os.queueEvent("service_status", name)
        if not ok then
            error(name .. ": " .. err)
        end
    end
end

function services_api.kill(name)
    local service = services[name]
    assert(service, name .. ": unknown service")
    if service.runtime_status == "running" then
        proc.kill(service.pid)
    elseif (
        service.config
        and service.config.type == "oneshot"
        and service.runtime_status == "finished"
    ) then
        local ok, err = pcall(runHook, service.config.stop)
        if ok then
            service.runtime_status = "stopped"
        else
            service.runtime_status = "failed"
            service.runtime_error = err
        end
        os.queueEvent("service_status", name)
    end
end

local function copyTable(t)
    return table.move(t, 1, #t, 1, {})
end

function services_api.status(name)
    local service = services[name]
    if not service then
        return nil
    end
    if not service.config then
        return {
            status = "failed",
            error = service.config_error,
            requires = {},
            description = nil,
        }
    end

    local status, err
    if service.config.type == "oneshot" then
        status = ({
            stopped = "stopped",
            running = "starting",
            finished = "up",
            failed = "failed",
        })[service.runtime_status]
        if service.runtime_status == "failed" then
            err = service.runtime_error
        end
    elseif service.config.type == "process" or service.config.type == "foreground" then
        status = ({
            stopped = "stopped",
            running = "up",
            finished = "failed",
            failed = "failed",
        })[service.runtime_status]
        if service.runtime_status == "finished" then
            err = "Process exited"
        elseif service.runtime_status == "failed" then
            err = service.runtime_error
        end
    end

    return {
        status = status,
        error = err,
        requires = copyTable(service.config.requires or {}),
        description = service.config.description,
    }
end

function services_api.allStatus()
    local status = {}
    for service, _ in pairs(services) do
        status[service] = services_api.status(service)
    end
    return status
end

function services_api._getServices()
    return services
end

return services_api
