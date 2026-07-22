local Controller = require "getty.controller"

local args = { ... }
if #args < 2 then
    print("Usage: getty <seat> <command...>")
    print("Use 'default' as the seat to use the built-in monitor and keyboard.")
    return
end

Controller.new(args[1]):run(table.unpack(args, 2))
