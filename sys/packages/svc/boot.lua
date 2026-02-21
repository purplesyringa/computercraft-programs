local args = { ... }
local boot_path
if args[1] == "packages.svc.boot" and args[2] then
    -- If this file is `require`d, the first argument is the package name and the second argument is
    -- its file path, which is how we can verify this is the case.
    boot_path = args[2]
elseif arg and not args[1] then
    -- If this file is executed directly, the path should be in what is effectively `argv[0]`.
    boot_path = arg[0]
else
    -- If this file is `dofile`d, the environment will both lack `arg` and most likely have
    -- non-matching `args`, so we can detect this condition fairly consitently.
    error("svc/boot can only be called with `require` or as file")
end

if os._svc then
    error("system already booted")
end

print("Booting...")

settings.define("svc.target", {
    description = "Default target to reach",
    default = "base",
    type = "string",
})
local target = settings.get("svc.target")

local svc = {
    sysroot = fs.combine(boot_path, "..", "..", ".."),
}
os._svc = svc

function os.version()
    return "WOR 0.1"
end

-- Redefine `require` so that we have access to modules normally. This doesn't behave exactly like
-- normal modules, but it's close enough.
require, _ = require("cc.require").make(_ENV, fs.combine(svc.sysroot, "packages"))

-- VFS is so critical to running the system that it has to be started manually rather than as
-- a service, since otherwise we won't even be able to run programs.
require "vfs.install"

local env = require "svc.env"
local proc = require "svc.proc"
local targets = require "svc.targets"
local services = require "svc.services"

function svc.reload()
    services.reload()
    targets.reload()
end

svc.start = services.start
svc.stop = services.stop
svc.kill = services.kill
svc.reach = targets.reach

function svc.status()
    return {
        services = services.allStatus(),
        target = targets.currentStatus(),
    }
end

svc.serviceStatus = services.status
svc.targetStatus = targets.status

svc.makeNestedShell = env.makeNestedShell
svc._execWrapped = env.execWrapped

env.init()
svc.reload()

term.setCursorPos(1, 1)
term.clear()

proc.start(function()
    local ok, err = pcall(svc.reach, target)
    if not ok then
        printError(err)
    end
end)

proc.loop()
