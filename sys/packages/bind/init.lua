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

            isReadOnly = function(path)
                return read_only or fs.isReadOnly(fs.combine(origin, path))
            end,

            list = function(path)
                return vfs.list(fs.combine(origin, path))
            end,

            attributes = function(path)
                return vfs.attributes(fs.combine(origin, path))
            end,

            find = function(path)
                return fs.find(fs.combine(origin, path))
            end,

            makeDir = function(path)
                assert_rw(path)
                fs.makeDir(fs.combine(origin, path))
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
                return vfs.read(fs.combine(origin, path))
            end,

            write = function(path, contents)
                assert_rw(path)
                vfs.write(fs.combine(origin, path), contents)
            end,

            open = function(path, mode)
                assert_rw(path, mode == "r" or mode == "rb")
                return fs.open(fs.combine(origin, path), mode)
            end,
        })
    end,
}
