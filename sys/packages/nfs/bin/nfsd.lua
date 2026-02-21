local named = require "named"

local PROTOCOL = "sylfn-nfs"
peripheral.find("modem", rednet.open)

local ROOT = "pub"
rednet.host(PROTOCOL, named.hostname())

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
    find = function(path)
        local list = fs.find(fs.combine(ROOT, path))
        for key, _ in pairs(list) do
            list[key] = string.sub(list[key], #ROOT + 1)
        end
        return list
    end,
    list = function(path)
        local list = fs.list(fs.combine(ROOT, path))
        for i, name in ipairs(list) do
            list[i] = {
                name = name,
                attributes = fs.attributes(fs.combine(ROOT, path, name)),
            }
        end
        return list
    end,
    attributes = function(path)
        path = fs.combine(ROOT, path)
        if not fs.exists(path) then
            return nil
        end
        local attrs = fs.attributes(path)
        attrs.isReadOnly = true
        return attrs
    end,
    read = function(path)
        return readToString(fs.combine(ROOT, path))
    end,
}

while true do
    local computer, message = rednet.receive(PROTOCOL)
    local response = table.pack(pcall(function()
        return nfs[message[2]](table.unpack(message, 3, message.n))
    end))
    if response[1] == false then
        response[2] = patchError(response[2])
    end
    rednet.send(computer, response, PROTOCOL .. message[1])
end
