local env = require "svc.env"
local configs = require "svc.configs"
local proc = require "svc.proc"

-- Runtime service info. Services that never ran during the current boot are absent.
-- {
--     [name] = {
--         -- The logical state of the service.
--         status = "stopped" | "queued" | "starting" | "up" | "failed",
--         -- Present only if the status is `failed`.
--         error? = ...,
--         -- Present only if the service is active.
--         pid? = ...,
--         -- The ground-truth config for this service (i.e. possibly outdated compared to
--         -- `configs`). Present only if the service is active.
--         config? = ...,
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

local function isActive(instance)
    return instance and (
        instance.status == "queued"
        or instance.status == "starting"
        or instance.status == "up"
    )
end

local function waitUp(name)
    while instances[name].status == "queued" or instances[name].status == "starting" do
        waitForStatusChange(name)
    end
    local instance = instances[name]
    if instance.status == "stopped" then
        error(name .. ": service stopped")
    elseif instance.status == "failed" then
        error(name .. ": " .. instance.error)
    end
end

local function waitUpMultiple(names)
    for _, name in ipairs(names) do
        waitUp(name)
    end
    -- Make sure no service has failed or been stopped since it got up in the previous loop.
    for _, name in ipairs(names) do
        assert(instances[name].status == "up", name .. " is down")
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

function services_api.populateBringUpPlan(plan, name)
    -- Preload all configs before starting services, so that we have a consistent picture.
    if plan[name] then
        return
    end
    local config = configs.getConfig(name)
    plan[name] = config
    for _, dep in pairs(config.requires or {}) do
        services_api.populateBringUpPlan(plan, dep)
    end
end

local function runHook(hook)
    if hook then
        debug.setfenv(hook, env.make())
        hook()
    end
end

-- The main logic of a service process.
local function run(config, setStatus)
    -- Wait for dependencies to start.
    waitUpMultiple(config.requires or {})
    setStatus("starting")

    if config.type == "oneshot" then
        local ok, err = pcall(runHook, config.start)
        if not ok then
            local ok_stop, err_stop = pcall(runHook, config.stop)
            if not ok_stop then
                err = err .. "\nwhile stopping:\n" .. err_stop
            end
            error(err, 0)
        end
        setStatus("up")
        -- Keep alive to indicate an "up" status, waiting for an external signal to stop.
        os.pullEventRaw("terminate")
        runHook(config.stop)
    elseif config.type == "process" then
        -- Immediately signal "up" status. TODO: allow services to signal readiness explicitly.
        setStatus("up")
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
    local plan = {}
    services_api.populateBringUpPlan(plan, name)
    services_api.bringUpFromPlan(plan)
end

function services_api.bringUpFromPlan(plan)
    local names = {}
    for name, config in pairs(plan) do
        table.insert(names, name)
        if not isActive(instances[name]) then
            -- Start background threads for all services without yielding, so that the plan is
            -- enacted consistently even if this function is cancelled.
            local pid = proc.start("service " .. name, function()
                local ok, err = pcall(run, config, function(status)
                    instances[name].status = status -- don't drop `pid`
                    notifyStatusChange(name)
                end)
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
            -- New processes start after the current one yields, so all services will be `queued` or
            -- better by the time `run` is entered, and `waitUpMultiple` won't witness stale state.
            instances[name] = { status = "queued", pid = pid, config = config }
            notifyStatusChange(name)
        end
    end

    -- Wait for readiness.
    waitUpMultiple(names)
end

function services_api.stop(name)
    local instance = instances[name]
    if not instance then
        -- Allow stopping non-existent instances as long as they could exist (i.e. a config exists).
        configs.getConfig(name)
        return
    end
    -- Stopping a service doesn't require a working config, so don't validate it.

    if not isActive(instance) then
        return
    end

    -- Is there any active service that depends on this one?
    for name2, instance2 in pairs(instances) do
        if isActive(instance2) then
            for _, name3 in pairs(instance2.config.requires or {}) do
                if name3 == name then
                    error(name .. ": required by running service " .. name2)
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
    if isActive(instance) then
        proc.kill(instance.pid)
    end
end

function services_api.status(name)
    local config
    local instance = instances[name]
    if isActive(instance) then
        -- Active services don't care about on-disk configs.
        config = instance.config
    else
        local config_result = configs.tryGetConfig(name)
        if instance then
            -- Services that have at some point existed, but whose configs have been deleted since,
            -- still exist.
            config_result = config_result or { error = "manifest deleted" }
        end
        if not config_result then
            return nil
        end

        config = config_result.config
        if not config then
            return {
                status = "failed",
                error = config_result.error,
                requires = {},
                description = nil,
            }
        end
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
