local env = require "svc.env"
local configs = require "svc.configs"
local proc = require "svc.proc"

-- Runtime service info. Services that never ran during the current boot are absent.
-- {
--     [name] = {
--         -- Present only if a process is actively running.
--         pid? = ...,
--         -- The logical state of the service.
--         status = "stopped" | "starting" | "up" | "failed",
--         -- Present only if the status is `failed`.
--         error? = ...,
--     },
--     ...
-- }
local instances = {}

local services_api = {}

local function notifyStatusChange(name)
    os.queueEvent("service_status#" .. name)
end
local function waitForStatusChange(name)
    os.pullEvent("service_status#" .. name)
end

function services_api.waitUp(name)
    while instances[name] and instances[name].status == "starting" do
        waitForStatusChange(name)
    end
    local instance = instances[name]
    if not instance then
        error(name .. ": unknown service")
    elseif instance.status == "stopped" then
        error(name .. ": service stopped")
    elseif instance.status == "up" then
        return
    elseif instance.status == "failed" then
        error(name .. ": " .. instance.error)
    end
end

function services_api.waitDown(name)
    while true do
        local instance = instances[name]
        if not instance then
            error(name .. ": unknown service")
        elseif instance.status == "stopped" then
            return
        elseif instance.status == "failed" then
            error(name .. ": " .. instance.error)
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

-- The main logic of a service process.
local function run(config, ready)
    if config.type == "oneshot" then
        local ok, err = pcall(runHook, config.start)
        if not ok then
            local ok_stop, err_stop = pcall(runHook, config.stop)
            if not ok_stop then
                err = err .. "\nwhile stopping:\n" .. err_stop
            end
            error(err, 0)
        end
        ready()
        -- Keep alive to indicate an "up" status, waiting for an external signal to stop.
        os.pullEventRaw("terminate")
        runHook(config.stop)
    elseif config.type == "process" then
        -- Immediately signal "up" status. TODO: allow services to signal readiness explicitly.
        ready()
        local ok, err = pcall(env.execIsolated, table.unpack(config.command))
        if not ok then
            -- Log the error to screen, since the user won't be able to observe it without
            -- a working shell otherwise.
            printError(err)
            error(err, 0)
        end
    end
end

function services_api.start(name)
    -- Doing this early makes sure that the config exists and we won't get errors down below.
    local config = configs.getConfig(name)

    -- Don't bother starting the service if another thread is already working on that.
    local instance = instances[name]
    if instance and (instance.status == "starting" or instance.status == "up") then
        services_api.waitUp(name)
        return
    end

    local closures = {}
    for _, dependency in ipairs(config.requires or {}) do
        table.insert(closures, function() services_api.start(dependency) end)
    end
    parallel.waitForAll(table.unpack(closures))

    -- By the time the dependencies are started, the service might have already been started by
    -- another instance of `services.start`, so check again.
    instance = instances[name]
    if instance and (instance.status == "starting" or instance.status == "up") then
        services_api.waitUp(name)
        return
    end
    -- The config at this point might differ from the one we used to check dependencies. We can't
    -- detect this without deep comparison, and that's not possible for closures (if we don't want
    -- `svc reload` to break all ongoing `svc start` commands). For now we just use the old config
    -- for consistency.

    local function ready()
        instances[name].status = "up" -- don't drop `pid`
        notifyStatusChange(name)
    end

    local pid = proc.start("service " .. name, function()
        local ok, err = pcall(run, config, ready)
        if ok or err == "Terminated" then
            instances[name] = { status = "stopped" }
        else
            instances[name] = { status = "failed", error = err }
        end
        notifyStatusChange(name)
    end, function()
        instances[name] = { status = "failed", error = "Killed" }
        notifyStatusChange(name)
    end)

    instances[name] = { pid = pid, status = "starting" }
    notifyStatusChange(name)

    -- Oneshot services are not considered up until the process finishes.
    services_api.waitUp(name)
end

function services_api.stop(name)
    local instance = instances[name]
    if not instance then
        -- Allow stopping non-existent instances as long as they could exist (i.e. a config exists).
        configs.getConfig(name)
        return
    end
    -- Stopping a service doesn't require a working config, so don't validate it.

    if instance.status ~= "starting" and instance.status ~= "up" then
        return
    end

    -- Is there any running service that depends on this one?
    for name2, instance2 in pairs(instances) do
        if instance2.status == "starting" or instance2.status == "up" then
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

    proc.stop(instance.pid)
    -- `stop` throws an error into the running coroutine, which cleans everything up, so there's no
    -- need to run clean-up code or update the status here.
    services_api.waitDown(name)
end

function services_api.kill(name)
    -- Follows the logic in `services_api.stop`.
    local instance = instances[name]
    if not instance then
        configs.getConfig(name)
        return
    end
    if instance.status == "starting" or instance.status == "up" then
        proc.kill(instance.pid)
    end
end

function services_api.status(name)
    local instance = instances[name]
    local config_result = configs.tryGetConfig(name)
    if instance then
        -- Services that have been started, but whose configs have been deleted since, still exist.
        config_result = config_result or { error = "manifest deleted" }
    end
    if not config_result then
        return nil
    end

    local config = config_result.config
    if not config then
        return {
            status = "failed",
            error = config_result.error,
            requires = {},
            description = nil,
        }
    end

    -- A service that has never been started is effectively stopped.
    instance = instance or { status = "stopped" }

    return {
        status = instance.status,
        error = instance.error,
        requires = config.requires or {},
        description = config.description,
    }
end

function services_api.allStatus()
    -- Populate from both running instances and configs. Services whose configs have been deleted
    -- are exclusive to the former, services that have never been started are unique to the latter.
    local status = {}
    for name, _ in pairs(instances) do
        status[name] = services_api.status(name)
    end
    for _, name in ipairs(configs.getConfigList()) do
        if not status[name] then
            status[name] = services_api.status(name)
        end
    end
    return status
end

return services_api
