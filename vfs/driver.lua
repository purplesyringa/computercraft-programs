local old_vfs = fs._vfs
local ofs = fs
if old_vfs then
    ofs = old_vfs.original_fs
end

local ROOT = ".vfs"
local MANAGED_PATH = ofs.combine(ROOT, ".managed")
local FD_PATH = ofs.combine(ROOT, "fd")

if ofs.exists(ROOT) and not ofs.exists(MANAGED_PATH) then
    error("/" .. ROOT .. " is not managed by the VFS driver.")
end
ofs.makeDir(ROOT)
ofs.open(MANAGED_PATH, "w").close()
ofs.delete(FD_PATH)
local next_fd = 0

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
--     -- An implementation of `fs.complete` for empty `dir`.
--     complete(rel_path, options),
--
--     -- Implementations directly mirroring `fs` methods.
--     find(rel_pattern),
--     list(rel_path),
--     getSize(rel_path),
--     exists(rel_path),
--     isDir(rel_path),
--     isReadOnly(rel_path),
--     getFreeSpace(rel_path),
--     getCapacity(rel_path),
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
    complete = function(rel_path, options)
        return ofs.complete(rel_path, "", options)
    end,
    find = ofs.find,
    list = ofs.list,
    getSize = ofs.getSize,
    exists = ofs.exists,
    isDir = ofs.isDir,
    isReadOnly = ofs.isReadOnly,
    getFreeSpace = ofs.getFreeSpace,
    getCapacity = ofs.getCapacity,
    attributes = ofs.attributes,
    makeDir = ofs.makeDir,
    move = ofs.move,
    copy = ofs.copy,
    delete = ofs.delete,
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

local function combineKeepingTrailingSlash(...)
    local args = table.pack(...)
    local has_slash = string.match(args[args.n], "/$")
    local path = ofs.combine(...)
    if has_slash then
        path = path .. "/"
    end
    return path
end

-- Takes an absolute path with an optional trailing slash. Returns `mount, rel_path`, where
-- `mount` is the mount containing the path, and `rel_path` is a path relative to the mount root.
--
-- If `match_root` is `true`, a path exactly matching the root is considered to be located within
-- the mount, otherwise it isn't. If the path ends with a slash, it's always considered to be within
-- the mount.
local function resolvePath(path, match_root)
    for i = #mounts, 1, -1 do
        local mount = mounts[i]
        if path == mount.root and match_root then
            return mount, ""
        elseif startsWith(path, mount.root .. "/") then
            return mount, string.sub(path, #mount.root + 2)
        end
    end
    return root_mount, path
end

-- Checks if the given absolute path is nested strictly within the mount and not any later mount.
local function isOwnedBy(path, mount)
    if not startsWith(path, mount.root .. "/") then
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
    return not isOwnedBy(mount.root .. "/", mount)
end

local function assertOrReadOnly(condition, path)
    assert(condition, "/" .. path .. ": read-only filesystem")
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
    local path
    if pattern == "" then
        -- Completing an empty pattern should list files within the base directory, rather than
        -- complete the filename of the base directory itself.
        path = combineKeepingTrailingSlash(dir, "/")
    elseif startsWith(pattern, "/") then
        -- Completing a path starting with `/` ignores the base directory, even though `fs.combine`
        -- doesn't behave that way.
        path = combineKeepingTrailingSlash(pattern)
    else
        path = combineKeepingTrailingSlash(dir, pattern)
    end

    -- If the pattern doesn't end with a trailing slash, we're supposed to complete the filename,
    -- even if there is a directory with a matching name, so `match_root` should be `false`.
    local mount, rel_path = resolvePath(path, false)
    if mount == root_mount then
        return ofs.complete(pattern, dir, ...)
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

    for _, completion in ipairs(mount.complete(rel_path, options)) do
        -- The `complete` implementation may offer `.` for empty patterns, make sure to ignore that.
        if rel_path == "" and completion ~= "." then
            table.insert(res, completion)
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
            local path = ofs.combine(pattern.root, rel_path)

            -- Ignore paths nested within submounts.
            if isOwnedBy(path, mount) then
                table.insert(result, path)
            end
        end

        ::ignore_mount::
    end

    return result
end

local function wrapOne(func)
    return function(path)
        local mount, rel_path = resolvePath(ofs.combine(path), true)
        return callWithErr(mount, func, rel_path)
    end
end

fs.list = wrapOne("list")
fs.getSize = wrapOne("getSize")

-- The shell calls `exists`/`isDir` on completions, and if a filesystem doesn't respond, this can
-- cause issues even before entering the mountpoint. Hence handling `rel_path == ""` specially.
function fs.exists(path)
    local mount, rel_path = resolvePath(ofs.combine(path), true)
    return rel_path == "" or mount.exists(rel_path)
end
function fs.isDir(path)
    local mount, rel_path = resolvePath(ofs.combine(path), true)
    return rel_path == "" or mount.isDir(rel_path)
end

fs.isReadOnly = wrapOne("isReadOnly")

function fs.makeDir(path)
    local mount, rel_path = resolvePath(ofs.combine(path), false)
    assertOrReadOnly(mount.makeDir, path)
    callWithErr(mount, "makeDir", rel_path)
end

local function copyAcrossMounts(src_mount, src_rel_path, dst_mount, dst_rel_path)
    assertOrReadOnly(not dst_mount.isReadOnly(dst_rel_path), dst)
    assertOrReadOnly(dst_mount.write, dst)

    local function doCopy(subpath)
        local src = ofs.combine(src_rel_path, subpath)
        local dst = ofs.combine(dst_rel_path, subpath)
        if src_mount.isDir(src) then
            callWithErr(dst_mount, "makeDir", dst)
            for _, name in ipairs(callWithErr(src_mount, "list", src)) do
                doCopy(ofs.combine(subpath, name))
            end
        else
            local contents = callWithErr(src_mount, "read", src_rel_path)
            callWithErr(dst_mount, "write", dst_rel_path, contents)
        end
    end

    doCopy("")
end

function fs.move(src, dst)
    local src_mount, src_rel_path = resolvePath(ofs.combine(src), true)
    local dst_mount, dst_rel_path = resolvePath(ofs.combine(dst), true)
    if src_mount == dst_mount and src_mount.move then
        callWithErr(src_mount, "move", src_rel_path, dst_rel_path)
        return
    end
    assertOrReadOnly(not src_mount.isReadOnly(src_rel_path), src)
    copyAcrossMounts(src_mount, src_rel_path, dst_mount, dst_rel_path)
    callWithErr(src_mount, "delete", src_rel_path)
end

function fs.copy(src, dst)
    local src_mount, src_rel_path = resolvePath(ofs.combine(src), true)
    local dst_mount, dst_rel_path = resolvePath(ofs.combine(dst), true)
    if src_mount == dst_mount and src_mount.copy then
        callWithErr(src_mount, "copy", src_rel_path, dst_rel_path)
        return
    end
    copyAcrossMounts(src_mount, src_rel_path, dst_mount, dst_rel_path)
end

function fs.delete(path)
    path = ofs.combine(path)
    local mount, rel_path = resolvePath(path, true)
    assert(rel_path ~= "", "/" .. path .. ": cannot delete mount")
    for i = #mounts, 1, -1 do
        local mount2 = mounts[i]
        if startsWith(mount2.root, path .. "/") then
            error("/" .. path .. ": contains mount " .. mount2.root)
        end
    end
    assertOrReadOnly(mount.delete, path)
    callWithErr(mount, "delete", rel_path)
end

function fs.open(path, mode)
    local base_mode = mode:gsub("b$", "")
    if not ({ r = true, w = true, a = true, ["r+"] = true, ["w+"] = true })[base_mode] then
        error("Unsupported mode")
    end

    local mount, rel_path = resolvePath(ofs.combine(path), false)
    if mount.open then
        return mount.open(rel_path, mode)
    end

    if base_mode ~= "r" then
        assertOrReadOnly(not mount.isReadOnly(rel_path), path)
        assertOrReadOnly(mount.write, path)
    end

    local ok, contents = pcall(function() callWithErr(mount, "read", rel_path) end)
    if not ok then
        return nil, contents
    end

    local fd = next_fd
    next_fd = next_fd + 1
    local local_path = ofs.combine(FD_PATH, tostring(fd))

    local file, err = ofs.open(local_path, "w+")
    if file == nil then
        return nil, err
    end
    ofs.delete(local_path)
    file.write(contents)

    local handle = {
        seek = file.seek,
        close = file.close,
    }

    if base_mode == "r" or base_mode == "r+" or base_mode == "w+" then
        handle.read = file.read
        handle.readAll = file.readAll
        handle.readLine = file.readLine
    end

    if base_mode ~= "r" then
        handle.write = file.write
        handle.writeLine = file.writeLine

        local function flush()
            local tell = file.seek("cur", 0)
            file.seek("set", 0)
            local contents = file.readAll()
            file.seek("set", tell)
            callWithErr(mount, "write", rel_path, contents)
        end

        -- No need to flush to the local file, since it's deleted after restart anyway.
        handle.flush = flush
        handle.close = function()
            flush()
            file.close()
        end
    end

    return handle
end

function fs.getDrive(path)
    local mount, rel_path = resolvePath(ofs.combine(path), false)
    if mount == root_mount then
        return ofs.getDrive(rel_path)
    else
        return mount.drive
    end
end

function fs.isDriveRoot(path)
    local mount, rel_path = resolvePath(ofs.combine(path), false)
    return rel_path == "" or (mount == root_mount and ofs.isDriveRoot(rel_path))
end

fs.getFreeSpace = wrapOne("getFreeSpace")
fs.getCapacity = wrapOne("getCapacity")
fs.attributes = wrapOne("attributes")

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
