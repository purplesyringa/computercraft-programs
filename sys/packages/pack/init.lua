local function loadModuleFromFile(modules, name)
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
end

local function populateDependenciesFromCode(modules, code)
    -- We don't exactly want to parse Lua code here. CC has a Lua parser under `cc.internal`, but
    -- it's not guaranteed to stay there, so I'd rather not use it. Pattern-matching is fine in the
    -- meantime for our own code.
    for dep in code:gmatch('require%s*%(?%s*"([^"]+)"') do
        if not modules[dep] then
            loadModuleFromFile(modules, dep)
            populateDependenciesFromCode(modules, modules[dep])
        end
    end
end

local function formatModules(modules)
    local out = "package.preload = {\n"
    for name, code in pairs(modules) do
        out = out .. ('\t[%q] = load(%q, %q, "t", _ENV),\n'):format(name, code, "=pack:" .. name)
    end
    out = out .. '}\n'
    return out
end

local function packString(code)
    local modules = {}
    populateDependenciesFromCode(modules, code)
    return formatModules(modules) .. code
end

return { packString = packString }
