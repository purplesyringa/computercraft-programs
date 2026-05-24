local vfs = require "vfs"

local startup = {}

-- Replaces the active startup script with a new one, atomically.
function startup.setScript(code)
    -- This is weird because CC doesn't expose an atomic rename with overwrites, so we have to
    -- delete the old `startup.lua` manually, but then there could be a moment in time when neither
    -- the old nor the new version exists.
    --
    -- To prevent this, we place the temporary copy in the `startup` directory, which CC also treats
    -- as startup code, so that at least one of `startup/svc-new.lua` and `startup.lua` exist at
    -- every moment and thus the system is never bricked.
    --
    -- The creation of `startup/svc-new.lua` is not atomic, so if the system crashes at that point,
    -- we may get a syntax error. However, `startup.lua` takes precedence over that file, and it
    -- should still be intact at that point, so the error should never surface.

    -- Before we overwrite `startup/svc-new.lua`, make sure that it's not the sole startup file,
    -- otherwise two botched updates in a row could brick the system. This is a no-op if
    -- `startup.lua` already exists.
    pcall(fs.move, "startup/svc-new.lua", "startup.lua")

    vfs.write("startup/svc-new.lua", code)
    fs.delete("startup.lua") -- deleting a non-existent file is a no-op
    fs.move("startup/svc-new.lua", "startup.lua")
    if not next(fs.list("startup")) then
        fs.delete("startup")
    end
end

-- Retrieves the active startup script, or returns `nil` if none is found. This function takes into
-- account the race condition avoidance strategies used by `setScript`.
function startup.getScript()
    local ok, code = pcall(vfs.read, "startup.lua")
    if ok then
        return code
    end

    -- `setScript` crashed between `delete` and `move`.
    ok, code = pcall(vfs.read, "startup/svc-new.lua")
    if ok then
        return code
    end

    return nil
end

return startup
