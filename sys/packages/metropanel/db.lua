local vfs = require "vfs"

local function readFile(name)
    local ok, ans = pcall(function()
        return textutils.unserialize(vfs.read(name))
    end)
    if ok then
        return ans
    else
        return {}
    end
end

local db = readFile("metropanel.db")

local function writeFile(name, data)
    vfs.write(name, textutils.serialize(data))
end

return {
    get = function(key, default)
        if db[key] == nil then
            db[key] = default
        end
        return db[key]
    end,
    set = function(key, value)
        db[key] = value
    end,
    save = function()
        writeFile("metropanel.db", db)
    end,
}
