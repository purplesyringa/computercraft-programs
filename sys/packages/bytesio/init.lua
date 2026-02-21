return {
    open = function(contents, mode)
        local base_mode = mode:gsub("b$", "")
        if not ({ r = true, w = true, a = true, ["r+"] = true, ["w+"] = true })[base_mode] then
            error("Unsupported mode")
        end

        local mode_binary = mode ~= base_mode
        local mode_read = ({ r = true, ["r+"] = true, ["w+"] = true })[base_mode]
        local mode_write = base_mode ~= "r"
        local mode_append = base_mode == 'a'
        local mode_truncate = ({ w = true, ["w+"] = true })[base_mode]

        local closed = false
        local seek = 0 -- ZERO INDEXED !!!
        if mode_truncate then contents = "" end
        if mode_append then seek = #contents end

        local handle = {}

        function handle.close()
            closed = true
        end

        function handle.seek(whence, off)
            assert(not closed, "file closed")
            if not whence then whence = "cur" end
            if not off then off = 0 end

            local newseek
            if whence == "set" then
                newseek = off
            elseif whence == "cur" then
                newseek = seek + off
            elseif whence == "end" then
                newseek = #contents + off
            else
                error("unknown seek whence: " .. whence)
            end

            assert(newseek >= 0, "rewound too far")
            seek = math.min(newseek, #contents) -- XXX: Should we support "holes" in contents?
            if seek ~= newseek then printError("fixme: seek past end??") end
            return seek
        end

        if mode_read then
            function handle.readAll()
                assert(not closed, "file closed")
                return contents:sub(1 + seek)
            end

            function handle.read(count)
                assert(not closed, "file closed")
                assert((count or 1) >= 0, "can't unread things")

                local sub = contents:sub(1 + seek, seek + (count or 1))
                seek = seek + #sub

                if mode_binary and not count then
                    return sub:byte()
                end
                return sub
            end

            function handle.readLine(withTrailing)
                assert(not closed, "file closed")
                if seek == #contents then return end
                local pos = contents:find('\n', 1 + seek, true)
                local sub = contents:sub(1 + seek, pos) -- if pos is nil, then reads to the end
                seek = seek + #sub
                if not withTrailing then
                    sub = sub:gsub("\r\n$", ""):gsub("\n$", "") -- there cant be two LFs
                end
                return sub
            end
        end

        if mode_write then
            function handle.flush()
                assert(not closed, "file closed")
            end

            function handle.write(part) -- string OR [charcode, if binary]
                assert(not closed, "file closed")
                if mode_binary and type(part) == "number" then
                    part = string.char(part)
                end
                part = tostring(part)

                local newseek = seek + #part
                local before = contents:sub(1, seek)
                local after = contents:sub(1 + newseek)
                contents = before .. part .. after
                seek = newseek
            end

            function handle.writeLine(text)
                handle.write(text .. "\n")
            end
        end

        return handle, function() return contents end
    end,
}
