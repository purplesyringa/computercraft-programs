local vfs = require "vfs"

local function components(path)
    return string.gmatch(path, "([^/]+)")
end

return {
    mount = function(mountpoint, tree, read_only)
        read_only = (read_only and true) or false

        -- Entry type:
        -- {
        --     attributes? = { size?, isDir?, isReadOnly? true, created? 0, modified? created },
        --     -- if file:
        --     contents = "some text",
        --     -- if dir:
        --     entries = {
        --         -- filename = Entry
        --     },
        -- }

        local function mkdentry()
            local now = os.epoch("utc")
            return {
                attributes = {
                    isReadOnly = read_only,
                    created = now,
                    modified = now,
                },
                entries = {},
            }
        end

        local function mkfile()
            local now = os.epoch("utc")
            return {
                attributes = {
                    isReadOnly = read_only,
                    created = now,
                    modified = now,
                },
                contents = "",
            }
        end

        local function mkattrs(entry)
            if not entry then return nil end
            local attrs = entry.attributes or {}
            if not attrs.size then attrs.size = (entry.entries and 0) or #entry.contents end
            if not attrs.isDir then attrs.isDir = (entry.entries and true) or false end
            if not attrs.isReadOnly then attrs.isReadOnly = true end
            if not attrs.created then attrs.created = 0 end
            if not attrs.modified then attrs.modified = attrs.created end
            entry.attrs = attrs
            return attrs
        end

        local function clone(entry)
            if not entry then return end
            mkattrs(entry)

            if entry.contents then
                local copy = mkfile()
                copy.attributes.size = entry.attributes.size
                copy.attributes.modified = entry.attributes.modified
                copy.contents = entry.contents
                return copy
            end

            local copy = mkdentry()
            copy.attributes.modified = entry.attributes.modified
            for name, fentry in pairs(entry.entries) do
                copy.entries[name] = clone(fentry)
            end
            return copy
        end

        tree = tree or mkdentry()

        local function errorPath(path, message) error("/" .. path .. ": " .. message) end
        local function enotdir(path) errorPath(path, "Not a directory") end
        local function eisdir(path) errorPath(path, "Not a file") end
        local function enoent(path) errorPath(path, "No such file") end
        local function eexist(path) errorPath(path, "File exists") end
        local function assert_rw(entry, path) if read_only or mkattrs(entry).isReadOnly then errorPath(path, "Read-only filesystem") end end

        local function walk(path)
            local parent, entry, name = nil, tree, nil
            for component in components(path) do
                if not entry then enoent(path) end
                if not entry.entries then enotdir(path) end
                parent, entry, name = entry, entry.entries[component], component
            end
            return parent, entry, name
        end

        vfs.mount(mountpoint, {
            description = "tmpfs",
            drive = (read_only and "tmp:ro") or "tmp:rw",
            find = function()
                error("unimplemented! find")
            end,
            isReadOnly = function() return read_only end,
            getFreeSpace = function() return 0xFFFFFFFF end,
            getCapacity = function() return 0xFFFFFFFF end,

            list = function(path)
                local _, entry, _ = walk(path)
                if not entry then enoent(path) end
                if not entry.entries then enotdir(path) end
                local list = {}
                for name, fentry in pairs(entry.entries) do
                    table.insert(list, {
                        name = name,
                        attributes = mkattrs(fentry),
                    })
                end
                return list
            end,

            attributes = function(path)
                local entry = tree
                for component in components(path) do
                    entry = entry and entry.entries and entry.entries[component]
                end
                return mkattrs(entry)
            end,

            makeDir = function(path)
                local entry = tree
                for component in components(path) do
                    if not entry.entries[component] then
                        assert_rw(entry, path)
                        entry.attributes.modified = os.epoch("utc")
                        entry.entries[component] = mkdentry()
                    end
                    entry = entry.entries[component]
                    if not entry.entries then eexist(path) end
                end
            end,

            delete = function(path)
                assert(path ~= "", "/: Deleting mountpoint is not supported. Remount instead.")
                local dentry, _, name = walk(path)
                assert_rw(dentry, path)
                dentry.attributes.modified = os.epoch("utc")
                dentry.entries[name] = nil
            end,

            -- XXX: what if dst is a subdir of src or dst == src?
            -- XXX: this should be handled on vfs side (move, copy)
            move = function(src, dst)
                local src_d, src_f, src_fn = walk(src)
                local dst_d, dst_f, dst_fn = walk(dst)
                if not src_f then enoent(src) end
                if dst_f then eexist(dst) end
                assert_rw(src_d, src)
                assert_rw(dst_d, dst)
                src_d.attributes.modified = os.epoch("utc")
                src_d.entries[src_fn] = nil
                dst_d.attributes.modified = os.epoch("utc")
                dst_d.entries[dst_fn] = src_f
            end,

            copy = function(src, dst)
                local _, src_f, _ = walk(src)
                local dst_d, dst_f, dst_fn = walk(dst)
                if not src_f then enoent(src) end
                if dst_f then eexist(dst) end
                assert_rw(dst_d, dst)
                dst_d.attributes.modified = os.epoch("utc")
                dst_d.entries[dst_fn] = clone(src_f)
            end,

            read = function(path)
                local _, entry, _ = walk(path)
                if not entry then enoent(path) end
                if entry.entries then eisdir(path) end
                return entry.contents
            end,

            write = function(path, contents)
                if path == "" then eisdir("") end
                local dentry, _, name = walk(path)

                if not dentry.entries[name] then
                    assert_rw(dentry, path)
                    dentry.attributes.modified = os.epoch("utc")
                    dentry.entries[name] = mkfile()
                end

                local entry = dentry.entries[name]
                if entry.entries then eisdir(path) end
                assert_rw(entry, path)
                entry.attributes.size = #contents
                entry.attributes.modified = os.epoch("utc")
                entry.contents = contents
            end,
        })
    end,
}
