local async = require "async"
local named = require "named"
local vfs = require "vfs"

local PROTOCOL = "sylfn-nfs"
peripheral.find("modem", rednet.open)

local args = { ... }
if #args == 0 then
    print("Usage: nfsd <path>")
    return
end

local root = fs.combine(args[1])

local function patchError(err)
    if type(err) == "string" and root ~= "" and string.find(err, "/" .. root) == 1 then
        return "/" .. string.sub(err, #root + 2)
    end
    return err
end

local nfs = {
    find = function(path)
        local list = fs.find(fs.combine(root, path))
        if root ~= "" then
            for key, _ in pairs(list) do
                list[key] = string.sub(list[key], #root + 2)
            end
        end
        return list
    end,
    list = function(path)
        return vfs.list(fs.combine(root, path))
    end,
    attributes = function(path)
        local attrs = vfs.attributes(path)
        if attrs then
            attrs.isReadOnly = true
        end
        return attrs
    end,
    read = function(path)
        return vfs.read(fs.combine(root, path))
    end,
}

local requests = async.newQueue()

async.spawn(function()
    while true do
        requests.put(rednet.receive(PROTOCOL))
    end
end)

local set = async.newTaskSet(32)

async.spawn(function()
    while true do
        local computer, message = requests.get()
        set.spawn(function()
            local response = table.pack(pcall(function()
                return nfs[message[2]](table.unpack(message, 3, message.n))
            end))
            if response[1] == false then
                response[2] = patchError(response[2])
            end
            rednet.send(computer, response, PROTOCOL .. message[1])
        end)
    end
end)

async.drive()
