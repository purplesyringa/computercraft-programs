local core = require "core"

-- On-disk configs, i.e. service templates. These have no relation to the runtime state.
-- {
--     [name] = {
--         config? = ...,
--         error? = ...,
--     },
--     ...
-- }
local configs = {}

local configs_api = {}

function configs_api.reload()
    local name_to_paths = {}
    local glob = fs.combine(core.sysroot, "run", "packages", "*", "services", "*.lua")
    for _, path in pairs(fs.find(glob)) do
        local name = fs.getName(path):gsub("%.lua$", "")
        if not name_to_paths[name] then
            name_to_paths[name] = {}
        end
        table.insert(name_to_paths[name], path)
    end

    configs = {}
    for name, paths in pairs(name_to_paths) do
        local ok, config_or_err = pcall(function()
            if #paths > 1 then
                error("Multiple manifests: " .. table.concat(paths, ", "), 0)
            end
            local module, err = loadfile(paths[1], nil, {})
            if not module then
                error(err, 0)
            end
            local config = module()
            assert(config, "Service config didn't return a value")
            return config
        end)
        if ok then
            configs[name] = { config = config_or_err }
        else
            configs[name] = { error = config_or_err }
        end
    end
end

-- returns (group, param) or (name)
local function splitServiceName(name)
    local group, param = name:match("([^@]+)@(.*)")
    if group then
        return group, param
    end
    return name
end

function configs_api.tryGetConfig(name)
    local group, param = splitServiceName(name)
    local config_group = configs[group]
    if config_group and type(config_group.config) == "function" then
        local ok, config_or_err = pcall(config_group.config, param)
        if ok then
            return { config = config_or_err }
        else
            return { error = config_or_err }
        end
    elseif config_group and type(config_group.config) == "table" and param then
        return { error = "not a template" }
    else
        return config_group
    end
end

function configs_api.getConfig(name)
    local config_or_err = configs_api.tryGetConfig(name)
    if not config_or_err then
        error(name .. ": unknown service", 0)
    end
    if not config_or_err.config then
        error(name .. ": " .. config_or_err.error, 0)
    end
    return config_or_err.config
end

function configs_api.getConfigList()
    local names = {}
    for name, _ in pairs(configs) do
        -- Parametrized services are excluded from config list
        if type(configs[name].config) ~= "function" then
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

return configs_api
