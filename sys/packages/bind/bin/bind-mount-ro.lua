local bind = require "bind"

local args = { ... }
if #args ~= 2 then
    print("Usage: bind-mount-ro <source> <destination>")
    return
end

local source = shell.resolve(args[1])
local destination = shell.resolve(args[2])
bind.mount(source, destination, true)
