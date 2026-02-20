dofile(fs.combine(shell.getRunningProgram(), "../../pkgs.lua"))
local named = require "named"

local PROTOCOL = "sylfn-nfs"
peripheral.find("modem", rednet.open)

local ROOT = "pub"
rednet.host(PROTOCOL, named.hostname())

local function wrapOne(func)
    return function(path, ...)
        return func(fs.combine(ROOT, path), ...)
    end
end

local function patchError(err)
    if type(err) == "string" and string.find(err, "/" .. ROOT) == 1 then
        return "/" .. string.sub(err, #ROOT + 2)
    end
    return err
end

local function readToString(path)
    local file, err = fs.open(path, "r")
    if file == nil then error(err) end
    local contents = file.readAll()
    file.close()
    return contents
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
    list = wrapOne(fs.list),
    getSize = wrapOne(fs.getSize),
    exists = wrapOne(fs.exists),
    isDir = wrapOne(fs.isDir),
    attributes = function(path)
        local attrs = fs.attributes(fs.combine(ROOT, path))
        attrs.isReadOnly = true
        return attrs
    end,
    read = function(path)
        return readToString(fs.combine(ROOT, path))
    end,

    -- internal funcitons
    _driver = function()
        local read = function(path) return readToString(fs.combine(fs.getDir(shell.getRunningProgram()), path)) end

        return string.format(
            'do %s end local nfs = (function() %s end)() fs._vfs.api.unmount("nfs") nfs.mount("nfs")', -- shell.run("nfs/startup.lua")
            read("../vfs/driver.lua"),
            read("driver.lua")
        )
    end,
}

while true do
    local computer, message = rednet.receive(PROTOCOL)
    if message == "driver" then
        rednet.send(computer, nfs._driver(), PROTOCOL)
    else
        local response = table.pack(pcall(function()
            return nfs[message[2]](table.unpack(message, 3, message.n))
        end))
        if response[1] == false then
            response[2] = patchError(response[2])
        end
        rednet.send(computer, response, PROTOCOL .. message[1])
    end
end
