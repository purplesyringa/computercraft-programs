local vfs = require "vfs"

return {
    mount = function(origin, mountpoint, read_only)
        assert(origin ~= mountpoint, "bind-mounting over self is not supported")

        local function assert_rw(path, cond)
            if read_only and cond ~= true then
                error("/" .. path .. ": Read-only filesystem", 0)
            end
        end

        local function patchError(err)
            if type(err) == "string" and origin ~= "" and string.find(err, "/" .. origin) == 1 then
                return "/" .. string.sub(err, #origin + 2)
            end
            return err
        end

        local function wrap(func)
            return function(...)
                local result = table.pack(pcall(func, ...))
                if result[1] == false then
                    error(patchError(result[2]), 0)
                end
                return table.unpack(result, 2, result.n)
            end
        end

        vfs.mount(mountpoint, {
            description = ("bind://%s"):format(origin),
            drive = (read_only and "bind:ro") or "bind:rw",

            isReadOnly = wrap(function(path)
                return read_only or fs.isReadOnly(fs.combine(origin, path))
            end),

            list = wrap(function(path)
                return vfs.list(fs.combine(origin, path))
            end),

            attributes = wrap(function(path)
                return vfs.attributes(fs.combine(origin, path))
            end),

            find = wrap(function(path)
                local list = fs.find(fs.combine(origin, path))
                if origin ~= "" then
                    for key, _ in pairs(list) do
                        list[key] = string.sub(list[key], #origin + 2)
                    end
                end
                return list
            end),

            makeDir = wrap(function(path)
                assert_rw(path)
                fs.makeDir(fs.combine(origin, path))
            end),

            delete = wrap(function(path)
                assert(path ~= "", "/: Deleting mountpoint is not supported.")
                assert_rw(path)
                return fs.delete(fs.combine(origin, path))
            end),

            move = wrap(function(src, dst)
                assert_rw(path)
                return fs.move(fs.combine(origin, src), fs.combine(origin, dst))
            end),

            copy = wrap(function(src, dst)
                assert_rw(path)
                return fs.copy(fs.combine(origin, src), fs.combine(origin, dst))
            end),

            read = wrap(function(path)
                return vfs.read(fs.combine(origin, path))
            end),

            write = wrap(function(path, contents)
                assert_rw(path)
                vfs.write(fs.combine(origin, path), contents)
            end),

            open = wrap(function(path, mode)
                assert_rw(path, mode == "r" or mode == "rb")
                return vfs.open(fs.combine(origin, path), mode)
            end),
        })
    end,
}
