local hardware = {}

-- Exported for the `hw` program.
function hardware._parseName(name)
    return name:match("([^.]+)%.(.+)")
end

function hardware.resolve(name)
    local group_name, subname = hardware._parseName(name)
    if not group_name then
        return nil
    end
    return hardware.resolveGroup(group_name)[subname]
end

function hardware.wrap(name)
    local native_name = hardware.resolve(name)
    if not native_name then
        return nil
    end
    return peripheral.wrap(native_name)
end

function hardware.resolveGroup(group_name)
    return settings.get("hardware.names", {})[group_name] or {}
end

function hardware.wrapGroup(group_name)
    local group = hardware.resolveGroup(group_name)
    for k, v in pairs(group) do
        group[k] = peripheral.wrap(v)
    end
    return group
end

function hardware.set(name, native_name)
    local group_name, subname = hardware._parseName(name)
    assert(group_name, name .. " is not a valid name")
    local groups = settings.get("hardware.names", {})
    if not groups[group_name] then
        groups[group_name] = {}
    end
    groups[group_name][subname] = native_name
    if not next(groups[group_name]) then
        groups[group_name] = nil
    end
    settings.set("hardware.names", groups)
    settings.save()
end

function hardware.listAll()
    local names = {}
    for group_name, subnames in pairs(settings.get("hardware.names", {})) do
        for subname, native_name in pairs(subnames) do
            names[group_name .. "." .. subname] = native_name
        end
    end
    return names
end

return hardware
