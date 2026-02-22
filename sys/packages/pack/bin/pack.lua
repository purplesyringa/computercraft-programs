local function populate_dependencies(modules, name)
    if modules[name] then return end

    local path, err = package.searchpath(name, package.path)
    if not path then
        error("Could not find '" .. name .. "': " .. err)
    end
    if path:find("rom/") == 1 then
        return -- internal
    end
    local file
    file, err = fs.open(path, "r")
    if not file then
        error("Could not open '" .. path .. "' for '" .. name .. "': " .. err)
    end
    local code = file.readAll()
    file.close()
    modules[name] = code

    -- We don't exactly want to parse Lua code here. CC has a Lua parser under `cc.internal`, but
    -- it's not guaranteed to stay there, so I'd rather not use it. Pattern-matching is fine in the
    -- meantime for our own code.

    for dep in code:gmatch('require%s*%(?%s*"([^"]+)"') do
        populate_dependencies(modules, dep)
    end
end

local function pack(entry_name)
    local modules = {}
    populate_dependencies(modules, entry_name)

    local out = "package.preload = {\n"
    for name, code in pairs(modules) do
        out = out .. ('\t[%q] = load(%q, %q, "t", _ENV),\n'):format(name, code, "=pack:" .. name)
    end
    out = out .. '}\n'
    out = out .. ('require(%q)\n'):format(entry_name)

    return out
end

return { pack = pack }
