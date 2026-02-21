local vfs = require "vfs"

local PROTOCOL = "sylfn-nfs"
peripheral.find("modem", rednet.open)

return {
    mount = function(mountpoint, host) -- either hostname or computer id
        if host == nil then host = "fileserver" end
        local nfshostarg = host
        if type(host) == "string" then host = rednet.lookup(PROTOCOL, host) end
        assert(host ~= nil)

        local current_id = math.random(0, 0xFFFFFFFF)
        local function call(func)
            return function(...)
                local id = current_id
                current_id = (current_id + 1) % (0xFFFFFFFF + 1)
                rednet.send(host, table.pack(id, func, ...), PROTOCOL)
                local _, message = rednet.receive(PROTOCOL .. id)
                if message[1] then
                    return table.unpack(message, 2, message.n)
                end
                error(message[2])
            end
        end

        vfs.mount(mountpoint, {
            description = ("nfs://%s"):format(nfshostarg),
            drive = ("nfs:%d"):format(host),
            find = call("find"),
            list = call("list"),
            isReadOnly = function() return true end,
            attributes = call("attributes"),
            read = call("read"),
        })
    end,
}
