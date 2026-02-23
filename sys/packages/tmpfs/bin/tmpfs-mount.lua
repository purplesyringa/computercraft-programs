local tmpfs = require "tmpfs"

local args = { ... }
if #args == 0 then
    print("Usage: tmpfs-mount <mountpoint>")
    return
end

tmpfs.mount(args[1])
