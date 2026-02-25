local tmpfs = require "tmpfs"

local args = { ... }
if #args == 0 then
    print("Usage: tmpfs-mount <mountpoint> [<image> [<rw>]]")
    return
end

local mountpoint = args[1]
if #args == 1 then
    tmpfs.mount(mountpoint)
    return
end

local env = setmetatable({ mounting = true }, { __index = _G })
local image = loadfile(shell.resolve(args[2]), nil, env)()
local read_only = args[3] ~= "true"
tmpfs.mount(mountpoint, image, read_only)
