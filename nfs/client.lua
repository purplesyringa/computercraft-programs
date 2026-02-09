local pretty = require "cc.pretty"

local PROTOCOL = "sylfn-nfs"
local ROOT = "nfs"
local MANAGED_PATH = fs.combine(ROOT, ".managed")
local FD_PATH = fs.combine(ROOT, "fd")

if fs.exists(ROOT) and not fs.exists(MANAGED_PATH) then
    error("/nfs folder already exists. Why? Please don't.")
end
fs.makeDir(ROOT)
fs.open(MANAGED_PATH, "w").close()
fs.delete(FD_PATH)
local current_fd = 0
local ofs = (fs._ofs or fs)
local current_id = math.random(0, 0xFFFFFFFF)

peripheral.find("modem", function(name, modem)
    if modem.isWireless() then
        rednet.open(name)
    end
end)

local function nfscall(func, ...)
    local server = rednet.lookup(PROTOCOL, "fileserver")
    if server == nil then
        error("no nfs server")
    end
    local id = current_id
    current_id = (current_id + 1) % (0xFFFFFFFF + 1)
    rednet.send(server, table.pack(id, func, ...), PROTOCOL)
    local _, message = rednet.receive(PROTOCOL .. id)
    if message[1] then
        return table.unpack(message, 2, message.n)
    end
    error(table.unpack(message, 2, message.n))
end

local function tonfspath(...)
    local args = table.pack(...)
    local has_slash = string.match(args[args.n], "/$")
    local path = ofs.combine(...)
    if has_slash then path = path .. "/" end
    if string.find(path .. "/", ROOT .. "/") == 1 then
        return string.sub(path, #ROOT + 1)
    end
end

local function wrapOne(func, handler)
    return function(path, ...)
        local nfspath = tonfspath(path)
        if nfspath then
            if handler then
                return handler(nfspath, ...)
            else
                return nfscall(func, nfspath, ...)
            end
        end
        return ofs[func](path, ...)
    end
end

local function errornfsro(path)
    error(path .. ": read-only filesystem")
end

local function assertlocal(path)
    if tonfspath(path) then
        errornfsro(path)
    end
end

local function nfsdown(path)
    local fd = current_fd
    current_fd = current_fd + 1
    local local_path = fs.combine(FD_PATH, tostring(fd))

    local file = ofs.open(local_path, "w")
    file.write(nfscall("_read", path))
    file.close()

    return local_path
end

local function nfsopen(path, mode)
    path = nfsdown(path)

    local handle = ofs.open(path, mode)
    local orig_close = handle.close
    handle.close = function()
        ofs.delete(path)
        orig_close()
    end
    return handle
end

local function components(path)
    local list = {}
    for component in string.gmatch(path, "([^/]+)") do
        table.insert(list, component)
    end
    return list
end

local function extend(dst, src)
    table.move(src, 1, #src, #dst + 1, dst)
end

_G.fs = {
    complete = function(pattern, dir, ...)
        local nfspath
        if string.sub(pattern, 1, 1) == "/" then
            nfspath = tonfspath(pattern)
        else
            nfspath = tonfspath(dir, pattern)
        end
        if not nfspath or (nfspath == "" and pattern ~= "") then
            return ofs.complete(pattern, dir, ...)
        end
        nfspath = string.gsub(nfspath, "^/", "", 1)
        local res = {}
        if pattern == "" then
            res = {".", ".."}
        end
        extend(res, nfscall("complete", nfspath, ...))
        return res
    end,
    find = function(pattern)
        local filtered = {}
        for _, path in ipairs(ofs.find(pattern)) do
            if string.find(path, ROOT .. "/") ~= 1 then
                table.insert(filtered, path)
            end
        end
        local combined = ofs.combine(pattern)
        local root_components = components(ROOT)
        local pattern_components = components(combined)
        local root_pattern_prefix = table.concat(pattern_components, "/", 1, #root_components)
        local is_nfs = false
        for _, path in pairs(ofs.find(root_pattern_prefix)) do
            is_nfs = is_nfs or path == ROOT
        end
        if is_nfs and #pattern_components > #root_components then
            local relative_pattern = table.concat(pattern_components, "/", #root_components + 1)
            for path in nfscall("find", relative_pattern) do
                table.insert(filtered, ofs.combine(ROOT, path))
            end
        end
        return filtered
    end,
    isDriveRoot = wrapOne("isDriveRoot", function(path) return path == "" end),
    list = wrapOne("list"),
    combine = ofs.combine,
    getName = ofs.getName,
    getDir = ofs.getDir,
    getSize = wrapOne("getSize"),
    exists = wrapOne("exists", function(path) return path == "" or nfscall("exists", path) end),
    isDir = wrapOne("isDir", function(path) return path == "" or nfscall("isDir", path) end),
    isReadOnly = wrapOne("isReadOnly", function() return true end),
    makeDir = function(path)
        assertlocal(path)
        return ofs.makeDir(path)
    end,
    move = function(src, dst)
        assertlocal(src)
        assertlocal(dst)
        return ofs.move(src, dst)
    end,
    copy = function(src, dst)
        assertlocal(dst)
        local nfssrc = tonfspath(src)
        if nfssrc then return ofs.move(nfsdown(nfssrc), dst) end
        return ofs.copy(src, dst)
    end,
    delete = function(path)
        assertlocal(path)
        return ofs.delete(path)
    end,
    open = function(path, mode)
        local nfspath = tonfspath(path)
        if not nfspath then return ofs.open(path, mode) end
        if mode ~= "r" and mode ~= "r+" then errornfsro(path) end
        return nfsopen(nfspath, mode)
    end,
    getDrive = wrapOne("getDrive", function() return "nfs" end),
    getFreeSpace = wrapOne("getFreeSpace", function() return 0 end),
    getCapacity = wrapOne("getCapacity", function() return 0 end),
    attributes = wrapOne("attributes"),
    _nfs = PROTOCOL,
    _ofs = ofs,
}
