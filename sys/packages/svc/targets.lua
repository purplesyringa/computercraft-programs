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

local function isSameCommand(a, b)
    a = a or {}
    b = b or {}
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

function targets_api.reach(name, force)
    local target = targets[name]
    assert(target, name .. ": unknown target")
    if not target.config then
        error(name .. ": " .. target.config_error)
    end

    current_target = name

    local closures = {}

    -- Bring up new services.
    for _, service in ipairs(target.config.services) do
        table.insert(closures, function() pcall(services.start, service) end)
    end

    -- Tear down old services.
    local all_status = services.allStatus()

    local goal_set = {}
    local function visit(service)
        if goal_set[service] or not all_status[service] then
            return
        end
        goal_set[service] = true
        for _, dependency in pairs(all_status[service].requires) do
            visit(dependency)
        end
    end
    for _, service in pairs(target.config.services) do
        visit(service)
    end
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
    for _, service in ipairs(target.config.services) do
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
