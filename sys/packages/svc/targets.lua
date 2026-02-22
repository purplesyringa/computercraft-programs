local env = require "svc.env"
local proc = require "svc.proc"
local services = require "svc.services"

local targets_api = {}

local sysroot = os._svc.sysroot

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
    for _, path in pairs(fs.find(fs.combine(sysroot, "targets", "*.lua"))) do
        local name = fs.getName(path):gsub(".lua$", "")
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

local function getTargetServiceSet(target)
    local service_statuses = services.allStatus()
    local service_set = {}
    local function visitService(name)
        if service_set[name] or not service_statuses[name] then
            return
        end
        service_set[name] = true
        for _, dependency in pairs(service_statuses[name].requires) do
            visitService(dependency)
        end
    end

    local target_set = {}
    local function visitTarget(name, is_main)
        if target_set[name] then
            return
        end
        target_set[name] = true
        local target = targets[name]
        assert(target, name .. ": unknown target")
        if not target.config then
            error(name .. ": " .. target.config_error)
        end
        for _, service in pairs(target.config.services or {}) do
            visitService(service)
        end
        if is_main then
            for _, service in pairs(target.config.inherent_services or {}) do
                visitService(service)
            end
        end
        for _, target in pairs(target.config.inherits or {}) do
            visitTarget(target, false)
        end
    end

    visitTarget(target, true)
    return service_set
end

function targets_api.reach(name, force)
    local goal_set = getTargetServiceSet(name)
    current_target = name

    local closures = {}

    -- Bring up new services.
    for service, _ in pairs(goal_set) do
        table.insert(closures, function() pcall(services.start, service) end)
    end

    -- Tear down old services.
    local all_status = services.allStatus()
    local dependents = {}
    for service, status in pairs(all_status) do
        for _, dependency in pairs(status.requires) do
            if not dependents[dependency] then
                dependents[dependency] = {}
            end
            table.insert(dependents[dependency], service)
        end
    end
    for service, status in pairs(all_status) do
        if status.up and not goal_set[service] then
            if force then
                services.kill(service)
            else
                table.insert(closures, function()
                    for _, dependent in pairs(dependents[service] or {}) do
                        -- Stopping the dependents will be triggered by other closures.
                        services.waitDown(dependent)
                    end
                    pcall(services.stop, service)
                end)
            end
        end
    end

    parallel.waitForAll(table.unpack(closures))
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

    local failed_services = {}
    for service, _ in pairs(getTargetServiceSet(name)) do
        local status = services.status(service)
        if not status or not status.up then
            table.insert(failed_services, service)
        end
    end

    if next(failed_services) then
        return {
            status = "degraded",
            error = "failed services: " .. table.concat(failed_services, ", "),
        }
    end

    return {
        status = "running",
        error = nil,
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
