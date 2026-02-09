local pretty = require "cc.pretty"

local PROTOCOL = "sylfn-nfs"
local ROOT = "pub"
peripheral.find("modem", rednet.open)
rednet.host(PROTOCOL, "fileserver")

local function wrapOne(func)
    return function(path, ...)
        return func(fs.combine(ROOT, path), ...)
    end
end

local nfs = {
    complete = function(pattern, ...) return fs.complete(ROOT .. "/" .. pattern, "", ...) end,
    find = function(path)
        local list = fs.find(fs.combine(ROOT, path))
        for key, _ in pairs(list) do
            list[key] = string.sub(list[key], #ROOT + 1)
        end
        return list
    end,
    -- isDriveRoot (client)
    list = wrapOne(fs.list),
    -- combine, getName, getDir (client)
    getSize = wrapOne(fs.getSize),
    exists = wrapOne(fs.exists),
    isDir = wrapOne(fs.isDir),
    -- isReadOnly, makeDir, move, copy, delete, open, getDrive, getFreeSpace, getCapacity (client)
    attributes = function(path)
        local attrs = fs.attributes(fs.combine(ROOT, path))
        attrs.isReadOnly = true
        return attrs
    end,

    -- Internal functions
    _read = function(path)
        local file = fs.open(fs.combine(ROOT, path), "r")
        local contents = file.readAll()
        file.close()
        return contents
    end,
}

while true do
    local computer, message = rednet.receive(PROTOCOL)
    local response = table.pack(pcall(function()
        return nfs[message[2]](table.unpack(message, 3, message.n))
    end))
    rednet.send(computer, response, PROTOCOL .. message[1])
end
