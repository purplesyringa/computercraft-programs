local bytesio = require "bytesio"

local old_vfs = fs._vfs
local ofs = fs
if old_vfs then
    ofs = old_vfs.original_fs
end

-- mount = {
--     -- Absolute path to the mountpoint.
--     root = ...,
--
--     -- Drive type, as visible by `getDrive`.
--     drive = ...,
--
--     -- String description of the mount.
--     description = ...,
--
--     -- Implementations directly mirroring `fs` methods.
--     find(rel_pattern),
--     isReadOnly(rel_path), -- defaults to true
--     getFreeSpace(rel_path), -- defaults to 0
--     getCapacity(rel_path), -- defaults to 0
--
--     -- Returns a list containing information about files in the given directory in the following
--     -- format: `{ name = ..., attributes = ... }`.
--     list(rel_path),
--
--     -- An implementation of `fs.attributes` returning `nil` for absent files.
--     attributes(rel_path),
--
--     -- If missing, throws the read-only error.
--     makeDir(rel_path),
--     delete(rel_path),
--
--     -- If missing, simulated with `read`, `write`, and (for `move`) `delete`.
--     move(src_rel_path, dst_rel_path),
--     copy(src_rel_path, dst_rel_path),
--
--     -- If missing, simulated with `read` and `write`.
--     open(rel_path, mode),
--
--     -- Read the entire file as a string.
--     read(rel_path),
--     -- Overwrite the entire file as a string. If missing, throws the read-only error.
--     write(rel_path, contents),
-- }
local root_mount = {
    root = "",
    drive = "root",
    description = "physical",
    find = ofs.find,
    isReadOnly = ofs.isReadOnly,
    getFreeSpace = ofs.getFreeSpace,
    getCapacity = ofs.getCapacity,
    list = function(rel_path)
        local list = ofs.list(rel_path)
        for i, name in ipairs(list) do
            list[i] = {
                name = name,
                attributes = ofs.attributes(ofs.combine(rel_path, name)),
            }
        end
        return list
    end,
    attributes = function(rel_path)
        if not ofs.exists(rel_path) then
            return nil
        end
        return ofs.attributes(rel_path)
    end,
    makeDir = ofs.makeDir,
    delete = ofs.delete,
    move = ofs.move,
    copy = ofs.copy,
    open = ofs.open,
    read = function(rel_path)
        local file = ofs.open(rel_path, "r")
        local contents = file.readAll()
        file.close()
        return contents
    end,
    write = function(rel_path, contents)
        local file = ofs.open(rel_path, "w")
        file.write(contents)
        file.close()
    end,
}

-- A list of mounts, sorted by the addition order. This typically means the most nested mount is
-- last, but if `a/b` is mounted and then `a` is mounted, the second mount shadows the first one.
-- The first element is always the FS root mount.
local mounts = { root_mount }
if old_vfs then
    -- Move over old mounts when reinitializing the VFS driver.
    table.move(old_vfs.mounts, 2, #old_vfs.mounts, 2, mounts)
end

local function startsWith(s, prefix)
    return string.sub(s, 1, #prefix) == prefix
end

-- Takes an absolute path. Returns `mount, rel_path`, where `mount` is the mount responsible for the
-- path, and `rel_path` is a path relative to the mount root. A path exactly matching a mount root
-- is considered to be located within the mount.
local function resolvePath(path)
    for i = #mounts, 1, -1 do
        local mount = mounts[i]
        if startsWith(path .. "/", mount.root .. "/") then
            return mount, string.sub(path, #mount.root + 2)
        end
    end
    return root_mount, path
end

-- Checks if the given absolute path is nested strictly within the mount and not any later mount.
local function isOwnedBy(path, mount)
    if mount.root ~= "" and not startsWith(path, mount.root .. "/") then
        return false
    end
    for i = #mounts, 1, -1 do
        local mount2 = mounts[i]
        if mount2 == mount then
            return true
        end
        if startsWith(path, mount2.root .. "/") then
            return false
        end
    end
    error("mount not in mount list")
end

local function isShadowed(mount)
    return mount.root ~= "" and not isOwnedBy(mount.root .. "/", mount)
end

local function assertOrReadOnly(condition, path)
    assert(condition, "/" .. ofs.combine(path) .. ": read-only filesystem")
end

local function callWithErr(mount, method, ...)
    local args = table.pack(...)
    local result = table.pack(pcall(function()
        return mount[method](table.unpack(args, 1, args.n))
    end))
    if result[1] then
        return table.unpack(result, 2, result.n)
    end
    local err = result[2]
    if err and startsWith(err, "/") and mount.root ~= "" then
        err = "/" .. mount.root .. err
    end
    error(err, 0)
end

local vfs = {}

local fs = {
    _vfs = {
        original_fs = ofs,
        mounts = mounts,
        api = vfs,
    },

    -- Pure functions.
    combine = ofs.combine,
    getName = ofs.getName,
    getDir = ofs.getDir,
}

function fs.complete(pattern, dir, ...)
    local pattern_dir, pattern_name = pattern:match("(.*)/(.*)")
    if pattern_dir == nil then
        pattern_dir, pattern_name = "", pattern
    end

    -- Completing a pattern starting with `/` ignores the base directory, even though `fs.combine`
    -- doesn't behave that way.
    if startsWith(pattern, "/") then
        dir = ofs.combine(pattern_dir)
    else
        dir = ofs.combine(dir, pattern_dir)
    end

    local mount, dir_rel_path = resolvePath(dir)
    local ok, files = pcall(function() return mount.list(dir_rel_path) end)
    if not ok then
        return {}
    end

    local args = { ... }
    local options
    if type(args[1]) == "table" then
        options = args[1]
    else
        options = {
            include_files = args[2],
            include_dirs = args[3],
        }
    end

    local res = {}

    -- CraftOS makes some questionable decisions here, but we copy its behavior for consistency.

    -- CraftOS completes `.` if the pattern is empty, but does not complete `./`, even though it
    -- does add both versions with and without slashes for normal directories. This only happens if
    -- `include_dirs` is set.
    if pattern == "" and options.include_dirs ~= false then
        table.insert(res, ".")
    end

    -- CraftOS completes `..` if `dir` is not a literal root and the pattern doesn't contain
    -- slashes. Disabling `include_dirs` replaces the completion with `../`, but does not complete
    -- the `..` pattern, only `.` and an empty one. Also notably, `dir = "a/.."` is not considered
    -- a root, only empty `dir` is.
    if dir ~= "" then
        if pattern == "" then
            if options.include_dirs ~= false then
                table.insert(res, "..")
            else
                table.insert(res, "../")
            end
        elseif pattern == "." then
            if options.include_dirs ~= false then
                table.insert(res, ".")
            else
                table.insert(res, "./")
            end
        end
    end

    for _, file in ipairs(files) do
        if (
            startsWith(file.name, pattern_name)
            and (
                not startsWith(file.name, ".")
                or options.include_hidden
                or startsWith(pattern_name, ".")
            )
        ) then
            local suffix = file.name:sub(#pattern_name + 1)
            if file.attributes.isDir then
                table.insert(res, suffix .. "/")
                if options.include_dirs ~= false and suffix ~= "" then
                    table.insert(res, suffix)
                end
            else
                if options.include_files ~= false and suffix ~= "" then
                    table.insert(res, suffix)
                end
            end
        end
    end

    return res
end

local function components(path)
    local list = {}
    for component in string.gmatch(path, "([^/]+)") do
        table.insert(list, component)
    end
    return list
end

local function globMatches(s, pattern)
    -- Copied from rom/apis/fs.lua verbatim to reproduce semantics.
    local find_escape = {
        ["^"] = "%^", ["$"] = "%$", ["("] = "%(", [")"] = "%)", ["%"] = "%%",
        ["."] = "%.", ["["] = "%[", ["]"] = "%]", ["+"] = "%+", ["-"] = "%-",
        ["*"] = ".*",
        ["?"] = ".",
    }
    return s:find("^" .. pattern:gsub(".", find_escape) .. "$") ~= nil
end

function fs.find(pattern)
    -- This doesn't make much sense semantically, but mirrors the behavior of the original `find`.
    pattern = ofs.combine(pattern)

    local result = {}
    local pattern_components = components(pattern)

    for _, mount in ipairs(mounts) do
        if isShadowed(mount) then
            goto ignore_mount
        end

        local root_components = components(mount.root)

        -- Check if matching paths can be nested strictly within this mount.
        if not (
            -- If the pattern is empty, we want to return the root as a single result. The root is
            -- not strictly nested within itself, so there's a bit of special-casing.
            (mount.root == "" or #pattern_components > #root_components)
            and globMatches(mount.root, table.concat(pattern_components, "/", 1, #root_components))
        ) then
            goto ignore_mount
        end

        local rel_pattern = table.concat(pattern_components, "/", #root_components + 1)

        -- ...and are not entirely nested within its submounts.
        local projected_pattern = ofs.combine(mount.root, rel_pattern)
        if not isOwnedBy(projected_pattern, mount) then
            goto ignore_mount
        end

        for _, rel_path in ipairs(mount.find(rel_pattern)) do
            local path = ofs.combine(mount.root, rel_path)

            -- Ignore paths nested within submounts.
            if isOwnedBy(path, mount) then
                table.insert(result, path)
            end
        end

        ::ignore_mount::
    end

    return result
end

local function wrapOne(func, default_value)
    return function(path)
        path = ofs.combine(path)
        local mount, rel_path = resolvePath(path)
        if not mount[func] then
            return default_value
        end
        return callWithErr(mount, func, rel_path)
    end
end

function fs.list(path)
    local mount, rel_path = resolvePath(ofs.combine(path))
    local list = mount.list(rel_path)
    for i, file in pairs(list) do
        list[i] = file.name
    end
    return list
end

function fs.getSize(path)
    return fs.attributes(path).size
end

-- The shell calls `exists`/`isDir` on completions, and if a filesystem doesn't respond, this can
-- cause issues even before entering the mountpoint. Hence handling `rel_path == ""` specially.
function fs.exists(path)
    local mount, rel_path = resolvePath(ofs.combine(path))
    return rel_path == "" or mount.attributes(rel_path) ~= nil
end

function fs.isDir(path)
    local mount, rel_path = resolvePath(ofs.combine(path))
    if rel_path == "" then
        return true
    end
    local attrs = mount.attributes(rel_path)
    return attrs ~= nil and attrs.isDir
end

fs.isReadOnly = wrapOne("isReadOnly", true)

function fs.makeDir(path)
    local mount, rel_path = resolvePath(ofs.combine(path))
    assertOrReadOnly(mount.makeDir, path)
    callWithErr(mount, "makeDir", rel_path)
end

local function copyRecursive(src, dst_mount, dst_rel_path)
    local src_mount, src_rel_path = resolvePath(ofs.combine(src))
    local attrs = src_mount.attributes(src_rel_path)
    if not attrs then
        return -- race condition
    end
    if attrs.isDir then
        callWithErr(dst_mount, "makeDir", dst_rel_path)
        for _, file in ipairs(callWithErr(src_mount, "list", src_rel_path)) do
            local name = file.name
            copyRecursive(ofs.combine(src, name), dst_mount, ofs.combine(dst_rel_path, name))
        end
    else
        local contents = callWithErr(src_mount, "read", src_rel_path)
        callWithErr(dst_mount, "write", dst_rel_path, contents)
    end
end

-- Takes an absolute path and asserts if it cannot be deleted.
local function assertDeletable(path)
    local mount, rel_path = resolvePath(path)
    assert(rel_path ~= "", "/" .. path .. ": cannot delete mount")
    for i = #mounts, 1, -1 do
        local mount2 = mounts[i]
        if mount2 == mount then
            break
        elseif startsWith(mount2.root, path .. "/") then
            error("/" .. path .. ": contains mount " .. mount2.root)
        end
    end
    assertOrReadOnly(mount.delete, path)
end

function fs.move(src, dst)
    local src_mount, src_rel_path = resolvePath(ofs.combine(src))
    local dst_mount, dst_rel_path = resolvePath(ofs.combine(dst))
    if src_mount == dst_mount and src_mount.move then
        callWithErr(src_mount, "move", src_rel_path, dst_rel_path)
        return
    end
    assert(not dst_mount.attributes(dst_rel_path), "/" .. ofs.combine(dst) .. ": File exists")
    assertOrReadOnly(not dst_mount.isReadOnly(dst_rel_path), dst)
    assertOrReadOnly(dst_mount.write, dst)
    assertDeletable(ofs.combine(src))
    copyRecursive(src, dst_mount, dst_rel_path)
    fs.delete(src)
end

function fs.copy(src, dst)
    local src_mount, src_rel_path = resolvePath(ofs.combine(src))
    local dst_mount, dst_rel_path = resolvePath(ofs.combine(dst))
    if src_mount == dst_mount and src_mount.copy then
        callWithErr(src_mount, "copy", src_rel_path, dst_rel_path)
        return
    end
    assert(not dst_mount.attributes(dst_rel_path), "/" .. ofs.combine(dst) .. ": File exists")
    assertOrReadOnly(not dst_mount.isReadOnly(dst_rel_path), dst)
    assertOrReadOnly(dst_mount.write, dst)
    copyRecursive(src, dst_mount, dst_rel_path)
end

function fs.delete(path)
    path = ofs.combine(path)
    assertDeletable(path)
    local mount, rel_path = resolvePath(path)
    callWithErr(mount, "delete", rel_path)
end

function fs.open(path, mode)
    local base_mode = mode:gsub("b$", "")
    if not ({ r = true, w = true, a = true, ["r+"] = true, ["w+"] = true })[base_mode] then
        error("Unsupported mode")
    end

    local mount, rel_path = resolvePath(ofs.combine(path))
    if mount.open then
        return mount.open(rel_path, mode)
    end

    if base_mode ~= "r" then
        assertOrReadOnly(not mount.isReadOnly(rel_path), path)
        assertOrReadOnly(mount.write, path)
    end

    local ok, contents = pcall(function() return callWithErr(mount, "read", rel_path) end)
    if not ok then
        return nil, contents
    end

    local handle, get_contents = bytesio.open(contents, mode)

    if base_mode ~= "r" then
        function handle.flush()
            callWithErr(mount, "write", rel_path, get_contents())
        end

        function handle.close()
            handle.flush()
            handle.close()
        end
    end

    return handle
end

function fs.getDrive(path)
    local mount, rel_path = resolvePath(ofs.combine(path))
    if mount == root_mount then
        return ofs.getDrive(rel_path)
    else
        return mount.drive
    end
end

function fs.isDriveRoot(path)
    local mount, rel_path = resolvePath(ofs.combine(path))
    return rel_path == "" or (mount == root_mount and ofs.isDriveRoot(rel_path))
end

fs.getFreeSpace = wrapOne("getFreeSpace", 0)
fs.getCapacity = wrapOne("getCapacity", 0)

function fs.attributes(path)
    path = ofs.combine(path)
    local mount, rel_path = resolvePath(path)
    local attrs = mount.attributes(rel_path)
    assert(attrs, "/" .. path .. ": No such file")
    attrs.modification = attrs.modified
    return attrs
end

function vfs.mount(root, handlers)
    root = ofs.combine(root)
    assert(root ~= "", "cannot mount over /")
    assert(fs.isDir(root), "/" .. root .. ": not a directory")
    local mount = setmetatable({ root = root }, { __index = handlers })
    table.insert(mounts, mount)
end

function vfs.unmount(root)
    root = ofs.combine(root)
    assert(root ~= "", "cannot unmount /")
    for i = #mounts, 1, -1 do
        local mount = mounts[i]
        if startsWith(mount.root, root .. "/") then
            error("/" .. root .. ": submount present at /" .. mounts[i].root)
        elseif mount.root == root then
            table.remove(mounts, i)
            return true
        end
    end
    return false
end

function vfs.list()
    local result = {}
    for _, mount in ipairs(mounts) do
        table.insert(result, {
            root = mount.root,
            drive = mount.drive,
            description = mount.description,
            shadowed = isShadowed(mount),
        })
    end
    return result
end

_G.fs = fs
