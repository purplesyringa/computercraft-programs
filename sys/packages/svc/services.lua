local env = require "svc.env"
local configs = require "svc.configs"
local proc = require "svc.proc"

-- Runtime service info. Services that never ran during the current boot are absent.
-- {
--     [name] = {
--         -- Present only if a process is actively running.
--         pid? = ...,
--         -- The runtime status of the process, not the logical status of the service. For example,
--         -- a running oneshot service that's already been initialized will have `finished` here.
--         status = "stopped" | "running" | "finished" | "failed",
--         error? = ...,
--     },
--     ...
-- }
local instances = {}

local services_api = {}

local function waitForStatusChange(name)
    assert(configs.tryGetConfig(name), name .. ": unknown service")
    local _, updated_name
    repeat
        _, updated_name = os.pullEvent("service_status")
    until updated_name == name
end

function services_api.waitUp(name)
    assert(configs.tryGetConfig(name), name .. ": unknown service")
    while true do
        local status = services_api.status(name)
        if status.status == "stopped" then
            error(name .. ": service stopped")
        elseif status.status == "failed" then
            error(name .. ": " .. status.error)
        elseif status.status == "up" then
            return
        end
        waitForStatusChange(name)
    end
end

function services_api.waitDown(name)
    assert(configs.tryGetConfig(name), name .. ": unknown service")
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
    local config = configs.getConfig(name)

    local function checkStatus()
        local status = services_api.status(name)
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

    local closures = {}
    for _, dependency in ipairs(config.requires or {}) do
        table.insert(closures, function() services_api.start(dependency) end)
    end
    parallel.waitForAll(table.unpack(closures))

    -- By the time the dependencies are started, the service might have already been started by
    -- another instance of `services.start`, so check again.
    if checkStatus() then
        return
    end
    -- The config at this point might differ from the one we used to check dependencies. We can't
    -- detect this without deep comparison, and that's not possible for closures (if we don't want
    -- `svc reload` to break all ongoing `svc start` commands). For now we just use the old config
    -- for consistency.

    local start = nil
    if config.type == "oneshot" then
        start = function()
            local ok, err = pcall(runHook, config.start)
            if not ok then
                local ok_stop, err_stop = pcall(runHook, config.stop)
                if not ok_stop then
                    err = err .. "\nwhile stopping:\n" .. err_stop
                end
                error(err, 0)
            end
        end
    elseif config.type == "process" then
        start = function()
            local ok, err = pcall(env.execIsolated, table.unpack(config.command))
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
    local pid = proc.start("service " .. name, function()
        local ok, err = pcall(start)
        if not ok and err == "Terminated" then
            instances[name] = { status = "stopped" }
        elseif ok then
            instances[name] = { status = "finished" }
        else
            instances[name] = { status = "failed", error = err }
        end
        os.queueEvent("service_status", name)
    end, function()
        instances[name] = { status = "failed", error = "Killed" }
        os.queueEvent("service_status", name)
    end)

    instances[name] = {
        pid = pid,
        status = "running",
        error = nil,
    }
    os.queueEvent("service_status", name)

    if config.type == "oneshot" then
        services_api.waitUp(name)
    end
end

function services_api.stop(name)
    local config = configs.getConfig(name)

    local instance = instances[name]
    if not instance then
        -- Hasn't ever started.
        return
    end

    local function assertNotRequired()
        for name2, _ in pairs(instances) do
            local status2 = services_api.status(name2).status
            if status2 == "starting" or status2 == "up" then
                local ok, config2 = pcall(configs.getConfig, name2)
                if ok then
                    for _, name3 in pairs(config2.requires or {}) do
                        if name3 == name then
                            error(name .. ": required by running service " .. name2)
                        end
                    end
                end
            end
        end
    end

    if instance.status == "running" then
        assertNotRequired()
        proc.stop(instance.pid)
        -- For oneshot services, `stop` throws an error, which `pcall` in `start` catches and stops
        -- the service, so there is no need to call `config.stop` or update the status here.
        services_api.waitDown(name)
    elseif config.type == "oneshot" and instance.status == "finished" then
        assertNotRequired()
        local ok, err = pcall(runHook, config.stop)
        if ok then
            instance.status = "stopped"
        else
            instance.status = "failed"
            instance.error = err
        end
        os.queueEvent("service_status", name)
        if not ok then
            error(name .. ": " .. err)
        end
    end
end

function services_api.kill(name)
    local config_result = configs.tryGetConfig(name)
    assert(config_result, name .. ": unknown service")
    local config = config_result.config

    local instance = instances[name]
    if not instance then
        -- Hasn't ever started.
        return
    end

    if instance.status == "running" then
        proc.kill(instance.pid)
    elseif config and config.type == "oneshot" and instance.status == "finished" then
        instance.status = "failed"
        instance.error = "Killed"
        os.queueEvent("service_status", name)
    end
end

local function copyTable(t)
    return table.move(t, 1, #t, 1, {})
end

function services_api.status(name)
    local result = configs.tryGetConfig(name)
    if not result then
        return nil
    end

    local config = result.config
    if not config then
        return {
            status = "failed",
            error = result.error,
            requires = {},
            description = nil,
        }
    end

    local instance = instances[name] or {
        status = "stopped",
        error = nil,
    }

    local status
    if config.type == "oneshot" then
        status = ({
            stopped = "stopped",
            running = "starting",
            finished = "up",
            failed = "failed",
        })[instance.status]
    elseif config.type == "process" then
        status = ({
            stopped = "stopped",
            running = "up",
            finished = "stopped",
            failed = "failed",
        })[instance.status]
    end

    local err = nil
    if instance.status == "failed" then
        err = instance.error
    end

    return {
        status = status,
        error = err,
        requires = copyTable(config.requires or {}),
        description = config.description,
    }
end

function services_api.allStatus()
    local status = {}
    for _, name in ipairs(configs.getConfigList()) do
        status[name] = services_api.status(name)
    end
    return status
end

return services_api
