local svc = require "svc"

local args = { ... }
if #args == 0 then
    printError("Usage:")
    printError("  wrap some.lua [args...]")
    return
end

local program = shell.resolve(args[1])
svc.execWrapped(_ENV, program, table.unpack(args, 2))
