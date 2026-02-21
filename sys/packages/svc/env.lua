local vfs = require "vfs"
local make_package = require("cc.require").make

local sysroot = os._svc.sysroot
local svc_setup_env = fs.combine(sysroot, "run", "bin", "svc-setup-env")

local env = {}

local function findProgram(command)
    if command == "" or command:find("/") or command:find("*") or command:find("?") then
        return nil
    end
    local paths = fs.find(fs.combine(sysroot, "packages", "*", "bin", command .. ".lua"))
    if not next(paths) then
        return nil
    end
    return paths
end

function env.getCombinedBinPath()
    return fs.combine(sysroot, "run", "bin")
end

function env.init()
    local bin_path = env.getCombinedBinPath()

    local function makeAttributes(isDir)
        return {
            created = 0,
            isDir = isDir,
            isReadOnly = true,
            modification = 0,
            modified = 0,
            size = 0,
        }
    end

    vfs.mount(bin_path, {
        description = "dynamic path",
        drive = "svcbin",
        find = function() return {} end, -- TODO
        list = function(rel_path)
            if rel_path ~= "" then
                error("/" .. rel_path .. ": not a directory", 0)
            end
            local added = {}
            local files = {}
            for _, path in pairs(fs.find(fs.combine(sysroot, "packages", "*", "bin", "*.lua"))) do
                local name = fs.getName(path):gsub(".lua$", "")
                if not added[name] then
                    added[name] = true
                    table.insert(files, {
                        name = name,
                        attributes = makeAttributes(false),
                    })
                end
            end
            table.sort(files, function(a, b)
                return a.name < b.name
            end)
            return files
        end,
        isReadOnly = function() return true end,
        attributes = function(rel_path)
            if rel_path == "" or findProgram(rel_path) then
                return makeAttributes(rel_path == "")
            end
            return nil
        end,
        read = function(rel_path)
            if rel_path == "" then
                error("/" .. rel_path .. ": not a file", 0)
            end
            local paths = findProgram(rel_path)
            if not paths then
                error("/" .. rel_path .. ": not found", 0)
            end
            if #paths > 1 then
                local error = "Multiple binaries named '" .. rel_path .. "': " .. table.concat(paths, ", ")
                return "error(" .. string.format("%q", error) .. ", 0)\n"
            end
            local path = paths[1]
            return "os._svc._execWrapped(_ENV, " .. string.format("%q", path) .. ", ...)\n"
        end,
    })

    shell.setPath("/" .. bin_path .. ":" .. shell.path())
end

function env.execWrapped(child_env, program, ...)
    if child_env.shell then
        -- This is not quite correct: if a program runs a different program with an identical name
        -- as a child, which can happen if the service directory is renamed, `getRunningProgram` can
        -- return the wrong path. There isn't much we can do about this and it should be rare.
        local old_get_running_program = child_env.shell.getRunningProgram
        local wrapper_program = old_get_running_program()
        child_env.shell.getRunningProgram = function()
            local running_program = old_get_running_program()
            if running_program == wrapper_program then
                return program
            else
                return running_program
            end
        end
    end

    -- Provide a `require`/`package` pair from scratch instead of patching the existing ones, since
    -- they may be absent if the wrapper is executed with `os.run` and it's easy to do.
    --
    -- We only patch this program's `package` -- if it runs subprocesses, their own wrappers are
    -- responsible for patching. This means that running `bin/*` programs by absolute path doesn't
    -- set up `package`, but that seems consistent with how other package managers work.
    child_env.require, child_env.package = make_package(child_env, "nonexistent")
    local new_path = (
        "/" .. fs.combine(sysroot, "packages", "?", "init.lua")
        .. ";/" .. fs.combine(sysroot, "packages", "?.lua")
    )
    for pattern in child_env.package.path:gmatch("[^;]+") do
        -- Remove relative paths from the search path, since that'd add two require paths for
        -- a single file and cause issues. Recommend using `<packagename>.<path...>` instead.
        if pattern:sub(1, 1) == "/" then
            new_path = new_path .. ";" .. pattern
        end
    end
    child_env.package.path = new_path

    -- `os.run` consumes errors, so we use `loadfile` directly. That makes sense anyway, since
    -- `os.run` does some extra setup, but the environment is already completely ready.
    local fn, err = loadfile(program, nil, child_env)
    if not fn then
        error(err, 0)
    end
    fn(...)
end

function env.make(base_env)
    -- Passing this lets the child shell inherit our path, aliases, and completion info, which we'd
    -- otherwise have to populate from `rom/startup`, which would get ugly quick.
    base_env = base_env or {
        shell = shell,
    }

    -- Run a nested `shell` to create a detached shell environment, so that services don't affect
    -- each other's working directories and program stacks.
    --
    -- We can't run programs by passing arguments to the shell directly, since
    -- a) it uses `shell.run` instead of `shell.execute`, breaking arguments,
    -- b) it ignores its return value, leaving us with no way to detect failures.
    -- So instead, we have a script save the `shell` instance somewhere where we can access it and
    -- then operate on that `shell` object.
    os.run(
        base_env,
        "rom/programs/shell.lua",
        -- Calling `svc-setup-env` might take some time due to FS operations possibly being
        -- asynchronous, but when it does load, it should set up the environment and quit instantly,
        -- so there's no race when reading `_setup_env`.
        svc_setup_env
    )
    return os._svc._setup_env
end

function env.makeNestedShell(base_env)
    return env.make(base_env).shell
end

function env.execIsolated(command, ...)
    -- `shell.execute` merges errors into a single boolean value, but we need to know if the program
    -- quit due to a `terminate` event (i.e. has been successfully stopped) or failed otherwise, so
    -- we reimplement `shell.execute`. This also allows us to remove one level of nesting (isolated
    -- requirements are already set up by the shell for `svc-setup-env`). We don't support shebangs
    -- for simplicity.
    local path = shell.resolveProgram(command)
    assert(path, "no program named '" .. command .. "'")

    local file, err = fs.open(path, "r")
    assert(file, err)
    local code = file.readAll()
    file.close()

    local isolated_env = env.make()

    -- Since the shell is set up for `svc-setup-env`, we need to change some properties depending on
    -- the executed command.

    -- Reinitialize `require`/`package` to load files from the correct directory.
    isolated_env.require, isolated_env.package = make_package(isolated_env, fs.getDir(path))

    -- Since `svc-setup-env` has already quit, the shell thinks there is no active program. This is
    -- easy to detect and fix.
    local old_get_running_program = isolated_env.shell.getRunningProgram
    isolated_env.shell.getRunningProgram = function()
        local running_program = old_get_running_program()
        if not running_program then
            return path
        else
            return running_program
        end
    end

    isolated_env.arg = { [0] = command, ... }

    local func, err = load(code, "@/" .. path, nil, isolated_env)
    assert(func, err)
    func(...)
end

return env

