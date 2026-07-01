local bytesio = require "bytesio"
local impure = require "runfs.impure"
local svc = require "svc"
local vfs = require "vfs"

local runfs = {
    description = "dynamic environment",
    drive = "runfs",
}

-- Calls `func` with `root_path / rel_path`, removing the `root_path` prefix from occurring errors.
local function forward(func, root_path, rel_path, ...)
    local result = table.pack(pcall(func, fs.combine(root_path, rel_path), ...))
    if result[1] == false then
        local err = result[2]
        if type(err) == "string" and err:find("/" .. root_path .. "/") == 1 then
            err = err:sub(#root_path + 2)
        end
        error(err, 0)
    end
    return table.unpack(result, 2, result.n)
end

-- Calls `func` with the right root and error rewrites, where `rel_path` matches `packages/...`.
local function forwardPackage(func, rel_path, ...)
    local package_home = rel_path:match("^packages/[^/]*")
    local root_path = svc.sysroot
    if impure.get() and fs.exists(fs.combine("impure", package_home)) then
        root_path = "impure"
    end
    return forward(func, root_path, rel_path, ...)
end

local function makeBinaryWrapper(command)
    if command:find("/") or command:find("*") or command:find("?") then
        return nil
    end

    local sys_paths = fs.find(fs.combine(svc.sysroot, "packages", "*", "bin", command .. ".lua"))
    local impure_paths = fs.find(fs.combine("impure", "packages", "*", "bin", command .. ".lua"))

    local paths = {}
    if impure.get() then
        paths = { table.unpack(impure_paths) }
    end
    local overridden_package = nil
    for _, path in pairs(sys_paths) do
        -- Exclude paths from packages overridden by /impure, even if (especially if) the impure
        -- package doesn't contain a corresponding binary.
        local package_name = path:match("[^/]*/bin/[^/]*$"):match("[^/]*")
        if impure.get() and fs.exists(fs.combine("impure", "packages", package_name)) then
            overridden_package = package_name
        else
            table.insert(paths, path)
        end
    end

    if #paths > 1 then
        local error = ("Multiple binaries named '%s': %s"):format(command, table.concat(paths, ", "))
        return ("error(%q, 0)\n"):format(error)
    elseif #paths == 1 then
        return ("os._svc.execWrapped(_ENV, %q, ...)\n"):format(paths[1])
    elseif overridden_package then
        local s = "Package '%s' providing binary '%s' is overwritten by an impure package"
        local error = s:format(overridden_package, command)
        return ("error(%q, 0)\n"):format(error)
    elseif next(impure_paths) then
        local s = "Binary '%s' is provided by the impure environment, but it is disabled"
        local error = s:format(command)
        return ("error(%q, 0)\n"):format(error)
    else
        return nil
    end
end

-- Checks if `rel_path` is a file path directly within `targets`.
local function isTargetPath(rel_path)
    return rel_path:match("^targets/[^/]*$")
end

function runfs.list(rel_path)
    if rel_path == "" then
        return {
            { name = "bin", attributes = { isDir = true } },
            { name = "packages", attributes = { isDir = true } },
            { name = "targets", attributes = { isDir = true } },
        }
    elseif rel_path == "bin" then
        local added = {}
        local files = {}
        -- Include binaries from /impure unconditionally, since we create wrappers for them even if
        -- the impure environment is off to show human-friendly errors.
        for _, root_path in pairs({ svc.sysroot, "impure" }) do
            for _, path in pairs(fs.find(fs.combine(root_path, "packages", "*", "bin", "*.lua"))) do
                local name = fs.getName(path):gsub("%.lua$", "")
                if not added[name] then
                    added[name] = true
                    table.insert(files, {
                        name = name,
                        attributes = { isDir = false },
                    })
                end
            end
        end
        table.sort(files, function(a, b)
            return a.name < b.name
        end)
        return files
    elseif rel_path == "packages" or rel_path == "targets" then
        local entries_by_name = {}
        local function scanRoot(root_path)
            local ok, list = pcall(vfs.list, fs.combine(root_path, rel_path))
            if ok then
                for _, entry in pairs(list) do
                    -- `open` for targets falls back from `impure` to the sysroot without checking
                    -- if the failure occured because the file is a directory or because it's
                    -- absent, so for consistency we treat directory targets as absent.
                    if not (rel_path == "targets" and entry.isDir) then
                        entries_by_name[entry.name] = entry
                    end
                end
            end
        end
        scanRoot(svc.sysroot)
        if impure.get() then
            -- Impure packages and targets overrides the ones from sysroot.
            scanRoot("impure")
        end
        local unique_entries = {}
        for _, entry in pairs(entries_by_name) do
            table.insert(unique_entries, entry)
        end
        return unique_entries
    elseif rel_path:match("^packages/") then
        return forwardPackage(vfs.list, rel_path)
    elseif runfs.attributes(rel_path) then -- possibly a binary or a target file
        error("/" .. rel_path .. ": Not a directory", 0)
    end
    error("/" .. rel_path .. ": No such file", 0)
end

function runfs.attributes(rel_path)
    if rel_path == "" or rel_path == "bin" or rel_path == "packages" or rel_path == "targets" then
        return { isDir = true }
    elseif rel_path:match("^bin/") and makeBinaryWrapper(rel_path:sub(5)) then
        return { isDir = false }
    elseif rel_path:match("^packages/") then
        return forwardPackage(vfs.attributes, rel_path)
    elseif isTargetPath(rel_path) then
        local function scanRoot(root_path)
            local ok, attrs = pcall(fs.attributes, fs.combine(root_path, rel_path))
            if ok and not attrs.isDir then
                return attrs
            end
            return nil
        end
        return (impure.get() and scanRoot("impure")) or scanRoot(svc.sysroot)
    end
    return nil
end

function runfs.open(rel_path, mode)
    if rel_path == "" or rel_path == "bin" or rel_path == "packages" or rel_path == "targets" then
        error("/" .. rel_path .. ": Not a file", 0)
    elseif rel_path:match("^bin/") then
        local contents = makeBinaryWrapper(rel_path:sub(5))
        if not contents then
            error("/" .. rel_path .. ": No such file", 0)
        end
        -- `bytesio.open` returns two values, we want to return only one.
        local file, _ = bytesio.open(contents, mode)
        return file
    elseif rel_path:match("^packages/") then
        return forwardPackage(vfs.open, rel_path, mode)
    elseif isTargetPath(rel_path) then
        if impure.get() then
            local ok, handle = pcall(vfs.open, fs.combine("impure", rel_path), mode)
            if ok then
                return handle
            end
        end
        return forward(vfs.open, svc.sysroot, rel_path, mode)
    end
end

return runfs
