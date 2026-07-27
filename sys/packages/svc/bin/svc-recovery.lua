local args = { ... }

assert(args[1] == "-f", "svc-recovery cannot be run directly, press Alt-Terminate")

local svc = require "svc"
svc.reach("base")
svc.reach("shell")
