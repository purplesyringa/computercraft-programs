local core = require "core"
local make_package = require("cc.require").make

local function setShellPath(shell)
    shell.setPath("/" .. fs.combine(core.sysroot, "run", "bin") .. ":" .. shell.path())
end

local function doMake(opts, command)
    local env = opts.env
    if not env then
        -- Run a nested `shell` to create a detached shell environment. We have a script exfiltrate
        -- the `shell` instance because there's no direct way to obtain it, and directly running
        -- programs via `shell <...>` mangles arguments and consumes errors.
        os.run(
            { shell = opts.base_shell or shell },
            "rom/programs/shell.lua",
            -- Calling `env-setup` might take some time due to FS operations possibly being
            -- asynchronous, but when it does load, it should set up the environment and quit
            -- instantly, so there's no race when reading `_setup_env`.
            fs.combine(core.sysroot, "run", "bin", "env-setup")
        )
        env = os._setup_env
        os._setup_env = nil
        assert(env, "failed to setup environment")
    end

    if opts.reload then
        -- When starting processes in a terminal redirect, we need to reinitialize the shell because
        -- PATH changes depending on whether the terminal is advanced. The ROM startup script is
        -- responsible for this, but it also runs MOTD and startup scripts from disks and the
        -- filesystem root, so we have to monkey-patch `settings.get` to disable that behavior.
        local overrides = {
            ["shell.allow_startup"] = false,
            ["shell.allow_disk_startup"] = false,
            ["motd.enable"] = false,
        }
        os.run({
            shell = env.shell,
            -- `startup.lua` requires various built-in modules; this is close enough.
            require = require,
            settings = setmetatable({
                get = function(name, ...)
                    if overrides[name] ~= nil then
                        return overrides[name]
                    end
                    return settings.get(name, ...)
                end,
            }, { __index = settings }),
        }, "rom/startup.lua")
        -- Since `startup.lua` overrides path, we have to inject the combined /bin back.
        setShellPath(env.shell)
    end

    -- Make sure to resolve the path after reloading the environment.
    local path = opts.path
    if not path and command then
        path = env.shell.resolveProgram(command)
        assert(path, "no program named '" .. command .. "'")
    end

    if opts.sysroot_require then
        -- This patch does not apply to nested programs, since `os.run` creates a new environment --
        -- their wrappers are responsible for patching. This means that running `bin/*` programs by
        -- absolute path doesn't set up `package`, but that seems consistent with how other package
        -- managers work.
        env.require, env.package = make_package(env, "nonexistent")
        local new_path = (
            "/" .. fs.combine(core.sysroot, "run", "packages", "?", "init.lua")
            .. ";/" .. fs.combine(core.sysroot, "run", "packages", "?.lua")
        )
        for pattern in env.package.path:gmatch("[^;]+") do
            -- Remove relative paths from the search path, since that'd add two require paths for
            -- a single file and cause issues. Recommend using `<packagename>.<path...>` instead.
            if pattern:sub(1, 1) == "/" then
                new_path = new_path .. ";" .. pattern
            end
        end
        env.package.path = new_path
    else
        if path then
            env.require, env.package = make_package(env, fs.getDir(path))
        else
            env.require, env.package = nil
        end
    end

    return env, path
end

local function make(opts)
    local env, _ = doMake(opts)
    return env
end

local function exec(opts, command, ...)
    local env, path = doMake(opts, command)

    -- The shell is assumed to be set up for `core-setup-env` or another wrapper, so patch the
    -- running program. (We can't change the real `shell` program stack directly.)
    --
    -- XXX: This is not quite correct: if a program runs a different program with an identical name
    -- as a child, which can happen if the service directory is renamed, `getRunningProgram` can
    -- return the wrong path. There isn't much we can do about this and it should be rare.
    local old_cb = env.shell.getRunningProgram
    local prev = old_cb()
    env.shell.getRunningProgram = function()
        local running_program = old_cb()
        if running_program == prev then
            return path
        else
            return running_program
        end
    end

    env.arg = { [0] = command, ... }

    -- We don't support shebangs for simplicity.
    local fn, err = loadfile(path, nil, env)
    assert(fn, err)
    return fn(...)
end

return {
    _setShellPath = setShellPath, -- used by `core` for initialization
    make = make,
    exec = exec,
}
