local core = require "core"
local services = require "svc.services"

local targets_api = {}

-- {
--     [name] = {
--         config? = ...,
--         config_error? = ...,
--     },
--     ...
-- }
local targets = {}
local current_target = nil

function targets_api.reload()
    targets = {}
    for _, path in pairs(fs.find(fs.combine(core.sysroot, "run", "targets", "*.lua"))) do
        local name = fs.getName(path):gsub("%.lua$", "")
        local ok, config_or_err = pcall(function()
            local module, err = loadfile(path, nil, {})
            if not module then
                error(err, 0)
            end
            return module()
        end)
        local target = {}
        if ok then
            target.config = config_or_err
        else
            target.config_error = config_or_err
        end
        targets[name] = target
    end
end

local function buildTargetBringUpPlan(name)
    local plan = {}
    local set = {}
    local errors = {}
    local function visitTarget(name)
        if set[name] then
            return
        end
        set[name] = true
        local target = targets[name]
        assert(target, name .. ": unknown target")
        if not target.config then
            error(name .. ": " .. target.config_error)
        end
        for _, service in pairs(target.config.services or {}) do
            services.populateBringUpPlan(plan, errors, service)
        end
        for _, dep in pairs(target.config.inherits or {}) do
            visitTarget(dep)
        end
    end
    visitTarget(name)
    return plan, errors
end

function targets_api.reach(name, force, persist)
    -- Build plans ahead of time so that errors are surfaced before we mutate the system.

    -- Errors are not handled here, as targets_api.status would surface them anyway.
    -- They're only used to keep old serivces running in case the target is broken in some way.
    local up_plan, errors = buildTargetBringUpPlan(name)
    local isolate_plan = services.buildIsolatePlan(up_plan)

    current_target = name

    -- Run the logic in a separate process, since if `svc.reach` is called from a service that is
    -- disabled in the new target, we might fail to complete it.
    core.startProcess("reach " .. name, function()
        parallel.waitForAll(
            -- Bring up new services.
            function()
                local ok = pcall(services.bringUpFromPlan, up_plan)
                if ok and persist then
                    settings.set("svc.target", name)
                    settings.save()
                end
            end,
            -- Tear down old services.
            function()
                if not next(errors) then
                    if force then
                        services.killAllExpect(up_plan)
                    else
                        services.isolateByPlan(isolate_plan)
                    end
                end
            end
        )
        os.queueEvent("target_reached")
    end, function()
        os.queueEvent("target_reached")
    end)

    os.pullEvent("target_reached")

    local status = targets_api.status(name) or {
        status = "degraded",
        error = "missing target definition"
    }
    if status.status == "degraded" then
        error(status.error, 0)
    end
end

function targets_api.status(name)
    local target = targets[name]
    if not target then
        return nil
    end
    if not target.config then
        return {
            status = "degraded",
            error = target.config_error,
        }
    end

    local services_by_status = {
        stopped = {},
        queued = {},
        starting = {},
        up = {},
        failed = {},
    }
    local plan, errors = buildTargetBringUpPlan(name)
    for dep, _ in pairs(errors) do
        plan[dep] = true -- collect dependencies with failed configs too
    end
    for service, _ in pairs(plan) do
        local status = services.status(service)
        table.insert(services_by_status[status.status], service)
    end

    local status
    local err = nil
    if next(services_by_status.failed) or next(services_by_status.stopped) then
        status = "degraded"
        local error_lines = {}
        for _, key in pairs({ "failed", "stopped" }) do
            local list = services_by_status[key]
            if next(list) then
                table.insert(error_lines, key .. " services: " .. table.concat(list, ", "))
            end
        end
        err = table.concat(error_lines, "\n")
    elseif next(services_by_status.queued) or next(services_by_status.starting) then
        status = "starting"
    else
        status = "up"
    end

    return {
        status = status,
        error = err,
    }
end

function targets_api.currentStatus()
    local status = targets_api.status(current_target) or {
        status = "degraded",
        error = "missing target definition",
    }
    status.name = current_target
    return status
end

return targets_api
