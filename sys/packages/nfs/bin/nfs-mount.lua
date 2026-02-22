local nfs = require "nfs"

local args = { ... }
if #args == 0 then
    print("Usage: nfs-mount <mountpoint> [<hostname>]")
    print("The default hostname is 'fileserver'")
    return
end

nfs.mount(args[1], args[2])
