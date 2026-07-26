local sysroot = os._svc.sysroot

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
    local glob = fs.combine(sysroot, "run", "packages", "*", "services", "*.lua")
    for _, path in pairs(fs.find(glob)) do
        local name = fs.getName(path):gsub("%.lua$", "")
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

    -- Keep deleted configs in the map, since there may be active services using them.
    for name, _ in pairs(configs) do
        if not name_to_paths[name] then
            configs[name] = { error = "Manifest deleted" }
        end
    end
end

function configs_api.tryGetConfig(name)
    return configs[name]
end

function configs_api.getConfig(name)
    assert(configs[name], name .. ": unknown service")
    if not configs[name].config then
        error(name .. ": " .. configs[name].error)
    end
    return configs[name].config
end

function configs_api.getConfigList()
    local names = {}
    for name, _ in pairs(configs) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

return configs_api
