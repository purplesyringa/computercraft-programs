local nfs = require "nfs"

local args = { ... }
if #args == 0 then
    print("Usage: nfs-mount <mountpoint> [<hostname|id>]")
    print("The default hostname is 'fileserver'")
    return
end

local host = args[2]
local id = tonumber(host)
if id and id > 0 and id % 1 == 0 then
    host = id
end

nfs.mount(args[1], host)
