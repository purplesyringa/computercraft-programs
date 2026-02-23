local vfs = require "vfs"

return {
    mount = function(origin, mountpoint, read_only)
        assert(origin ~= mountpoint, "bind-mounting over self is not supported")

        local function assert_rw(path, cond)
            if read_only and cond ~= false then
                error("/" .. path .. ": Read-only filesystem")
            end
        end

        vfs.mount(mountpoint, {
            description = ("bind://%s"):format(origin),
            drive = (read_only and "bind:ro") or "bind:rw",
            find = function()
                error("unimplemented! find")
            end,
            isReadOnly = function() return read_only end,
            getFreeSpace = function() return 0xFFFFFFFF end,
            getCapacity = function() return 0xFFFFFFFF end,

            list = function(path)
                local realpath = fs.combine(origin, path)
                local list = {}
                for _, name in ipairs(fs.list(realpath)) do
                    table.insert(list, {
                        name = name,
                        attributes = fs.attributes(fs.combine(realpath, name)),
                    })
                end
                return list
            end,

            attributes = function(path)
                local realpath = fs.combine(origin, path)
                if not fs.exists(realpath) then
                    return nil
                end
                return fs.attributes(realpath)
            end,

            makeDir = function(path)
                assert_rw(path)
                return fs.makeDir(fs.combine(origin, path))
            end,

            delete = function(path)
                assert(path ~= "", "/: Deleting mountpoint is not supported.")
                assert_rw(path)
                return fs.delete(fs.combine(origin, path))
            end,

            move = function(src, dst)
                assert_rw(path)
                return fs.move(fs.combine(origin, src), fs.combine(origin, dst))
            end,

            copy = function(src, dst)
                assert_rw(path)
                return fs.copy(fs.combine(origin, src), fs.combine(origin, dst))
            end,

            read = function(path)
                local file = fs.open(fs.combine(origin, path), "r")
                local contents = file.readAll()
                file.close()
                return contents
            end,

            write = function(path, contents)
                assert_rw(path)
                local file = fs.open(fs.combine(origin, path), "w")
                file.write(contents)
                file.close()
            end,

            open = function(path, mode)
                assert_rw(path, mode == "r" or mode == "rb")
                return fs.open(fs.combine(origin, path), mode)
            end,
        })
    end,
}
