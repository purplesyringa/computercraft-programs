local args = { ... }
local boot_path
if args[1] == "packages.core.boot" and args[2] then
    -- If this file is `require`d, the first argument is the package name and the second argument is
    -- its file path, which is how we can verify this is the case.
    boot_path = args[2]
elseif arg and not args[1] then
    -- If this file is executed directly, the path should be in what is effectively `argv[0]`.
    boot_path = arg[0]
else
    -- If this file is `dofile`d, the environment will both lack `arg` and most likely have
    -- non-matching `args`, so we can detect this condition fairly consistently.
    error("core/boot can only be called with `require` or as file")
end

if os._core then
    error("system already booted")
end

print("Booting...")

if not os._timings then
    os._timings = {}
end
table.insert(os._timings, { "packages.core.boot", os.clock() })

local core = {
    sysroot = fs.combine(boot_path, "..", "..", ".."),
}
os._core = core

function os.version()
    return "WOR 0.1"
end

-- Redefine `require` so that we have access to modules normally. This doesn't behave exactly like
-- normal modules, but it's close enough. This doesn't include impure modules, but we don't want to
-- handle that complexity here.
require = require("cc.require").make(_ENV, fs.combine(core.sysroot, "packages"))

-- VFS is so critical to running the system that it has to be started manually rather than as
-- a service, since otherwise we won't even be able to run programs.
require "vfs.install"

local runfs = require "runfs"
runfs.mount(fs.combine(core.sysroot, "run"))

local proc = require "core.proc"
core.startProcess = proc.start
core.stopProcess = proc.stop
core.killProcess = proc.kill
core.listProcesses = proc.list
core.withImminentHandler = proc.withImminentHandler
proc.registerRebootShutdownHandlers()

local environ = require "environ"
-- Reexport because wrappers can't require `environ` directly, as they don't have `require` set up.
function core._execWrapped(env, path, command, ...)
    environ.exec({
        env = env,
        sysroot_require = true,
        path = path,
    }, command or path, ...)
end

environ._setShellPath(shell)

term.setCursorPos(1, 1)
term.clear()

proc.start("boot", function()
    local ok, err = pcall(environ.exec, {}, "svc-boot")
    table.insert(os._timings, { "booted", os.clock() })
    if not ok then
        printError(err)
    end
end)

proc.loop(function()
    proc.start("recovery", function()
        environ.exec({}, "svc-recovery", "-f")
    end)
end)
